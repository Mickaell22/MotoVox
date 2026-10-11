import 'dart:ffi';
import 'package:ffi/ffi.dart';

// ── C signatures ──────────────────────────────────────────────────────────────

typedef _CreateC  = Pointer<Void> Function(Pointer<Void>);
typedef _DestroyC = Void Function(Pointer<Void>);
typedef _ProcessC = Float Function(Pointer<Void>, Pointer<Float>, Pointer<Float>);

// ── RnnoiseFfi ────────────────────────────────────────────────────────────────

/// Wrapper liviano sobre librnnoise.so.
/// Un solo estado por instancia; no es thread-safe — usar desde un único isolate.
class RnnoiseFfi {
  // 480 muestras = 10 ms a 48 kHz (constante fija del modelo; exige audio a 48 kHz).
  static const int frameSize = 480;

  late final Pointer<Void> Function(Pointer<Void>)                           _create;
  late final void Function(Pointer<Void>)                                     _destroy;
  late final double Function(Pointer<Void>, Pointer<Float>, Pointer<Float>) _process;

  late final Pointer<Void>  _state;

  /// Buffers reutilizables — Phase 3 los accede directamente para evitar copias.
  late final Pointer<Float> inputBuf;
  late final Pointer<Float> outputBuf;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  void init() {
    if (_initialized) return;

    final lib = DynamicLibrary.open('librnnoise.so');

    _create  = lib.lookupFunction<_CreateC,  Pointer<Void> Function(Pointer<Void>)>('rnnoise_create');
    _destroy = lib.lookupFunction<_DestroyC, void Function(Pointer<Void>)>('rnnoise_destroy');
    _process = lib.lookupFunction<_ProcessC,
        double Function(Pointer<Void>, Pointer<Float>, Pointer<Float>)>('rnnoise_process_frame');

    _state    = _create(nullptr);
    inputBuf  = calloc<Float>(frameSize);
    outputBuf = calloc<Float>(frameSize);

    _initialized = true;
  }

  /// Procesa [frameSize] muestras que ya están en [inputBuf].
  /// Escribe el resultado en [outputBuf].
  /// Retorna la probabilidad VAD: 1.0 = voz detectada, 0.0 = solo ruido.
  double processFrame() {
    assert(_initialized, 'Llamar init() antes de processFrame()');
    return _process(_state, outputBuf, inputBuf);
  }

  void dispose() {
    if (!_initialized) return;
    _destroy(_state);
    calloc.free(inputBuf);
    calloc.free(outputBuf);
    _initialized = false;
  }
}
