import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:motovox/services/audio_relay_service.dart';

Uint8List bytes(List<int> b) => Uint8List.fromList(b);

void main() {
  test('realinea chunks impares sin perder bytes', () {
    final q = PlaybackQueue(1000)
      ..add(bytes([1, 2, 3]))
      ..add(bytes([4, 5, 6]));
    expect(q.removeFirst(), [1, 2]);
    expect(q.removeFirst(), [3, 4, 5, 6]);
    expect(q.isEmpty, isTrue);
  });

  test('un solo byte queda pendiente hasta completar la muestra', () {
    final q = PlaybackQueue(1000)..add(bytes([9]));
    expect(q.isEmpty, isTrue);
    q.add(bytes([8]));
    expect(q.removeFirst(), [9, 8]);
  });

  test('descarta lo más viejo al pasar el tope, siempre en chunks pares', () {
    final q = PlaybackQueue(4)
      ..add(bytes([1, 1]))
      ..add(bytes([2, 2]))
      ..add(bytes([3, 3]));
    expect(q.bytes, 4);
    expect(q.removeFirst(), [2, 2]);
    expect(q.removeFirst(), [3, 3]);
  });

  test('nunca descarta el único chunk aunque supere el tope', () {
    final q = PlaybackQueue(2)..add(bytes([1, 2, 3, 4]));
    expect(q.bytes, 4);
  });

  test('clear también olvida el byte pendiente', () {
    final q = PlaybackQueue(100)
      ..add(bytes([7]))
      ..clear()
      ..add(bytes([1, 2]));
    expect(q.removeFirst(), [1, 2]);
  });
}
