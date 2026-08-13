import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:kaksha/services/repository5.dart';

void main() {
  test('media pack/unpack round-trips exactly', () {
    final original = Uint8List.fromList(
        List.generate(50000, (i) => (i * 31 + i ~/ 7) % 256));
    final packed = MediaCodec.pack(original);
    expect(packed.cipher, isNot(equals(original))); // actually encrypted
    final restored = MediaCodec.unpack(packed.cipher, packed.ivHex);
    expect(restored, equals(original));
  });

  test('ciphertext is unreadable without the right IV', () {
    final original = Uint8List.fromList(List.filled(1000, 65)); // "AAAA…"
    final packed = MediaCodec.pack(original);
    expect(
      () => MediaCodec.unpack(
          packed.cipher, '000102030405060708090a0b0c0d0e0f'),
      throwsA(anything), // gzip header won't survive a wrong-key decrypt
    );
  });

  test('compressible data really shrinks', () {
    final original = Uint8List.fromList(List.filled(100000, 42));
    final packed = MediaCodec.pack(original);
    expect(packed.cipher.length, lessThan(original.length ~/ 10));
  });
}
