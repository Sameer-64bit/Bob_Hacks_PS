import 'package:flutter_test/flutter_test.dart';

import 'package:kaksha/services/translator.dart';

void main() {
  group('Translator.chunkText', () {
    test('short text is a single chunk', () {
      expect(Translator.chunkText('Hello world'), ['Hello world']);
    });

    test('keeps every chunk under the limit', () {
      final long = List.generate(40, (i) => 'Sentence number $i is here.').join(' ');
      final chunks = Translator.chunkText(long, maxLen: 100);
      expect(chunks.length, greaterThan(1));
      for (final c in chunks) {
        expect(c.length, lessThanOrEqualTo(100));
      }
      // No content is lost.
      expect(chunks.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim(),
          long.replaceAll(RegExp(r'\s+'), ' ').trim());
    });

    test('splits on newlines first', () {
      final chunks =
          Translator.chunkText('line one\nline two\nline three', maxLen: 12);
      expect(chunks, ['line one', 'line two', 'line three']);
    });

    test('hard-cuts a single word longer than the limit', () {
      final chunks = Translator.chunkText('a' * 950, maxLen: 450);
      expect(chunks.length, greaterThanOrEqualTo(2));
      for (final c in chunks) {
        expect(c.length, lessThanOrEqualTo(450));
      }
    });

    test('drops empty chunks', () {
      expect(Translator.chunkText('\n\n  \nhi\n\n'), ['hi']);
    });
  });
}
