import 'dart:ffi';
import 'dart:typed_data';
import '../native/rnnoise_ffi.dart';

/// Adapta chunks de tamaño variable (flutter_sound) al frame fijo de RNNoise
/// (480 muestras PCM16 = 960 bytes). Llama RNNoise por cada frame completo y
/// emite el audio limpio.
class RnnoiseProcessor {
  // 480 muestras × 2 bytes = 960 bytes por frame.
  static const int _bytesPerFrame = RnnoiseFfi.frameSize * 2;

  final RnnoiseFfi _ffi = RnnoiseFfi();
  // Residuo del chunk anterior (< 960 bytes). Uint8List evita boxing.
  Uint8List _residual = Uint8List(0);

  void init() => _ffi.init();

  /// Procesa [input] (PCM16 LE, 48 kHz, mono) y devuelve los bytes limpios.
  /// Si la .so no cargó (init falló), passthrough: audio sin supresión,
  /// pero la llamada sigue funcionando.
  Uint8List process(Uint8List input) {
    if (!_ffi.isInitialized) return input;
    // Combinar residuo con la entrada nueva.
    final Uint8List data;
    if (_residual.isEmpty) {
      data = input;
    } else {
      data = Uint8List(_residual.length + input.length)
        ..setRange(0, _residual.length, _residual)
        ..setRange(_residual.length, _residual.length + input.length, input);
    }

    final frames = data.length ~/ _bytesPerFrame;
    if (frames == 0) {
      _residual = data.sublist(0); // copia defensiva
      return Uint8List(0);
    }

    final output = BytesBuilder(copy: false);
    for (int f = 0; f < frames; f++) {
      output.add(_processFrame(data, f * _bytesPerFrame));
    }

    // Guardar residuo (< 960 bytes) para el siguiente chunk.
    final residualStart = frames * _bytesPerFrame;
    _residual = residualStart < data.length
        ? data.sublist(residualStart) // sublist crea copia
        : Uint8List(0);

    return output.toBytes();
  }

  // Lee un frame de [data] en [offset], lo procesa con RNNoise y devuelve PCM16.
  Uint8List _processFrame(Uint8List data, int offset) {
    final input = _ffi.inputBuf;
    for (int i = 0; i < RnnoiseFfi.frameSize; i++) {
      final lo = data[offset + i * 2];
      final hi = data[offset + i * 2 + 1];
      int sample = (hi << 8) | lo;
      if (sample >= 0x8000) sample -= 0x10000; // sign-extend
      (input + i).value = sample.toDouble();
    }

    _ffi.processFrame();

    final out = Uint8List(_bytesPerFrame);
    final outputBuf = _ffi.outputBuf;
    for (int i = 0; i < RnnoiseFfi.frameSize; i++) {
      int sample = (outputBuf + i).value.round().clamp(-32768, 32767);
      out[i * 2]     = sample & 0xFF;
      out[i * 2 + 1] = (sample >> 8) & 0xFF;
    }
    return out;
  }

  void dispose() {
    _ffi.dispose();
    _residual = Uint8List(0);
  }
}
