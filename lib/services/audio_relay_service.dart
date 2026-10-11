import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'rnnoise_processor.dart';

/// Cola de reproducción con tope: si se acumula más audio que [maxBytes],
/// descarta lo más viejo para que la latencia no crezca sin límite (deriva de
/// reloj entre teléfonos, ráfagas de TCP tras una pérdida).
/// También realinea a muestras PCM16: TCP no respeta límites de mensaje y un
/// chunk puede traer un número impar de bytes.
class PlaybackQueue {
  final int maxBytes;
  PlaybackQueue(this.maxBytes);

  final _chunks = Queue<Uint8List>();
  int _bytes = 0;
  int? _oddByte;

  int get bytes => _bytes;
  bool get isEmpty => _chunks.isEmpty;

  void add(Uint8List data) {
    if (_oddByte != null) {
      final joined = Uint8List(data.length + 1)
        ..[0] = _oddByte!
        ..setRange(1, data.length + 1, data);
      data = joined;
      _oddByte = null;
    }
    if (data.length.isOdd) {
      _oddByte = data.last;
      data = Uint8List.sublistView(data, 0, data.length - 1);
    }
    if (data.isEmpty) return;
    _chunks.add(data);
    _bytes += data.length;
    // Se descartan chunks enteros (siempre de longitud par): no desalinea.
    while (_bytes > maxBytes && _chunks.length > 1) {
      _bytes -= _chunks.removeFirst().length;
    }
  }

  Uint8List removeFirst() {
    final c = _chunks.removeFirst();
    _bytes -= c.length;
    return c;
  }

  void clear() {
    _chunks.clear();
    _bytes = 0;
    _oddByte = null;
  }
}

class AudioRelayService {
  // 48 kHz: frecuencia nativa de RNNoise (frame de 480 muestras = 10 ms).
  // A 16 kHz el modelo ve la voz con el espectro deformado y la suprime.
  static const int _sampleRate = 48000;
  static const int _numChannels = 1;
  static const int _bufferSize = 4096;
  static const int _maxQueuedBytes = _sampleRate * 2 * 200 ~/ 1000; // 200 ms
  // Siempre llega audio (silenciar manda ceros), así que este tiempo sin datos
  // significa conexión muerta aunque TCP todavía no lo haya notado.
  static const _peerTimeout = Duration(seconds: 3);
  static const _retryDelay = Duration(seconds: 2);

  static const _channel = MethodChannel('com.motovox.motovox/app');

  final _rnnoise = RnnoiseProcessor();
  final _recorder = FlutterSoundRecorder();
  final _player = FlutterSoundPlayer();
  final _queue = PlaybackQueue(_maxQueuedBytes);

  ServerSocket? _serverSocket;
  Socket? _socket;
  StreamController<Uint8List>? _recorderStream;
  Timer? _watchdog;
  DateTime _lastRx = DateTime.now();
  Future<void> _stopping = Future.value();
  bool _pumping = false;
  bool _muted = false;
  bool _disposed = false;

  // Cliente: destino guardado para reconectar solo tras una caída.
  String? _hostIp;
  int? _hostPort;

  int _actualPort = 0;
  int get actualPort => _actualPort;

  final _stateController = StreamController<bool>.broadcast();
  Stream<bool> get connectionState => _stateController.stream;

  Future<void> init() async {
    await _recorder.openRecorder();
    await _player.openPlayer();
    try {
      _rnnoise.init();
    } catch (_) {
      // La app sigue funcionando sin supresión de ruido si la .so no carga.
    }
    // Foreground service: sin él Android corta el micrófono con la pantalla
    // apagada. Si falla, la llamada sigue mientras la pantalla esté encendida.
    try { await _channel.invokeMethod('startCallService'); } catch (_) {}
  }

  Future<void> startHost() async {
    _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    _actualPort = _serverSocket!.port;
    _serverSocket!.listen(
      (socket) async {
        // ponytail: scope 1-a-1 — se rechaza una segunda conexión mientras
        // hay una activa. Upgrade: multi-cliente para grupos de motos.
        if (_socket != null || _disposed) {
          socket.destroy();
          return;
        }
        socket.setOption(SocketOption.tcpNoDelay, true);
        _socket = socket;
        await _startAudio(socket);
      },
      onError: (_) {},
    );
  }

  Future<bool> connectToHost(String hostIp, {required int port}) async {
    final ok = await _connect(hostIp, port, const Duration(seconds: 15));
    if (ok) {
      _hostIp = hostIp;
      _hostPort = port;
    }
    return ok;
  }

  Future<bool> _connect(String ip, int port, Duration timeout) async {
    try {
      final socket = await Socket.connect(ip, port, timeout: timeout);
      if (_disposed) {
        socket.destroy();
        return false;
      }
      socket.setOption(SocketOption.tcpNoDelay, true);
      _socket = socket;
      await _startAudio(socket);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _reconnect() async {
    while (!_disposed && _socket == null) {
      await Future.delayed(_retryDelay);
      if (_disposed || _socket != null) return;
      if (await _connect(_hostIp!, _hostPort!, const Duration(seconds: 3))) {
        return;
      }
    }
  }

  Future<void> _startAudio(Socket socket) async {
    await _stopping;
    _lastRx = DateTime.now();
    // Errores de escritura llegan por done; sin handler serían no capturados.
    socket.done.then((_) {}, onError: (_) {});

    await _player.startPlayerFromStream(
      codec: Codec.pcm16,
      interleaved: true, // mono: da igual, pero feedUint8FromStream lo exige
      numChannels: _numChannels,
      sampleRate: _sampleRate,
      bufferSize: _bufferSize,
    );

    socket.listen(
      (data) {
        _lastRx = DateTime.now();
        _queue.add(data);
        if (!_pumping) _pump();
      },
      onDone: () => _onDisconnected(socket),
      onError: (_) => _onDisconnected(socket),
      cancelOnError: true,
    );

    _recorderStream = StreamController<Uint8List>();
    _recorderStream!.stream.listen((data) {
      // Silenciado manda ceros en vez de cortar el flujo: así el otro lado
      // distingue "silenciado" de "conexión caída".
      final out = _muted ? Uint8List(data.length) : _rnnoise.process(data);
      try { socket.add(out); } catch (_) {}
    });

    await _recorder.startRecorder(
      toStream: _recorderStream!.sink,
      codec: Codec.pcm16,
      numChannels: _numChannels,
      sampleRate: _sampleRate,
      bufferSize: _bufferSize,
      audioSource: AudioSource.voice_communication,
      // NS y voice processing del hardware apagados: RNNoise hace la
      // supresión y apilar dos supresores degrada la voz. AEC se mantiene,
      // es esencial en una llamada bidireccional.
      enableVoiceProcessing: false,
      enableNoiseSuppression: false,
      enableEchoCancellation: true,
    );

    _watchdog = Timer.periodic(const Duration(seconds: 1), (_) {
      if (DateTime.now().difference(_lastRx) > _peerTimeout) {
        _onDisconnected(socket);
      }
    });

    if (!_stateController.isClosed) _stateController.add(true);
  }

  // Alimenta el player con backpressure: cada feed espera a que el dispositivo
  // acepte el chunk, así lo pendiente queda en [_queue], que tiene tope.
  Future<void> _pump() async {
    _pumping = true;
    try {
      while (!_queue.isEmpty && !_player.isStopped) {
        await _player.feedUint8FromStream(_queue.removeFirst());
      }
    } catch (_) {
    } finally {
      _pumping = false;
    }
  }

  void _onDisconnected(Socket socket) {
    // onDone, onError y el watchdog pueden dispararse para el mismo socket.
    if (!identical(socket, _socket)) return;
    _socket = null;
    socket.destroy();
    if (!_stateController.isClosed) _stateController.add(false);
    // Libera el slot: el host vuelve a aceptar y el cliente reintenta solo.
    _stopAudio().then((_) {
      if (_hostIp != null && !_disposed) _reconnect();
    });
  }

  Future<void> _stopAudio() => _stopping = () async {
        _watchdog?.cancel();
        _watchdog = null;
        // Recorder antes que el stream: si no, escribe en un sink cerrado.
        try { await _recorder.stopRecorder(); } catch (_) {}
        try { await _player.stopPlayer(); } catch (_) {}
        final rs = _recorderStream;
        _recorderStream = null;
        try { await rs?.close(); } catch (_) {}
        _queue.clear();
      }();

  void setMuted(bool mute) => _muted = mute;

  Future<void> dispose() async {
    _disposed = true;
    _socket?.destroy();
    _socket = null;
    await _stopAudio();
    try { await _recorder.closeRecorder(); } catch (_) {}
    try { await _player.closePlayer(); } catch (_) {}
    try { await _serverSocket?.close(); } catch (_) {}
    _rnnoise.dispose();
    try { await _channel.invokeMethod('stopCallService'); } catch (_) {}
    if (!_stateController.isClosed) await _stateController.close();
  }
}
