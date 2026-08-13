import 'dart:convert';

import 'package:http/http.dart' as http;

/// Free text translation via the MyMemory API (no key needed, CORS-friendly,
/// works from web builds). The small VLM only reads/writes English well, so
/// its output is piped through this to reach the student's language.
class Translator {
  static const _endpoint = 'https://api.mymemory.translated.net/get';

  /// MyMemory rejects queries longer than ~500 bytes, so long slide text is
  /// split into chunks at line/sentence boundaries and re-joined.
  static List<String> chunkText(String text, {int maxLen = 450}) {
    final chunks = <String>[];
    var buffer = StringBuffer();

    void flush() {
      if (buffer.isNotEmpty) {
        chunks.add(buffer.toString());
        buffer = StringBuffer();
      }
    }

    // Prefer newline boundaries, then sentence boundaries, then hard cuts.
    for (final line in text.split('\n')) {
      final pieces = line.length <= maxLen
          ? [line]
          : line
              .split(RegExp(r'(?<=[.!?])\s+'))
              .expand((s) sync* {
                for (var i = 0; i < s.length; i += maxLen) {
                  yield s.substring(
                      i, i + maxLen > s.length ? s.length : i + maxLen);
                }
              })
              .toList();
      for (final piece in pieces) {
        if (buffer.length + piece.length + 1 > maxLen) flush();
        if (buffer.isNotEmpty) {
          buffer.write(piece == pieces.first && line != piece ? ' ' : '\n');
        }
        buffer.write(piece);
      }
      flush(); // keep original line structure
    }
    flush();
    return chunks.where((c) => c.trim().isNotEmpty).toList();
  }

  /// Translates [text] from English into [targetCode] (e.g. 'hi').
  /// Returns the input untouched when the target is English.
  /// Retries each chunk once — the free tier throws sporadic 429s.
  static Future<String> translate(String text, String targetCode) async {
    if (targetCode == 'en' || text.trim().isEmpty) return text;
    final results = <String>[];
    for (final chunk in chunkText(text)) {
      results.add(await _translateChunk(chunk, targetCode, retriesLeft: 2));
    }
    return results.join('\n');
  }

  static Future<String> _translateChunk(String chunk, String targetCode,
      {required int retriesLeft}) async {
    try {
      final uri = Uri.parse(_endpoint).replace(queryParameters: {
        'q': chunk,
        'langpair': 'en|$targetCode',
      });
      final response =
          await http.get(uri).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw Exception(
            'Translation service unavailable (HTTP ${response.statusCode}).');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final translated =
          data['responseData']?['translatedText'] as String? ?? '';
      if (translated.isEmpty ||
          (data['responseStatus'] != 200 &&
              data['responseStatus'] != '200')) {
        throw Exception('Translation failed — try again in a moment.');
      }
      return translated;
    } catch (_) {
      if (retriesLeft > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        return _translateChunk(chunk, targetCode,
            retriesLeft: retriesLeft - 1);
      }
      rethrow;
    }
  }

  /// Like [translate] but NEVER throws — falls back to the original text.
  /// Use for big batches where one failed field shouldn't kill the rest.
  static Future<String> translateSafe(String text, String targetCode) async {
    try {
      return await translate(text, targetCode);
    } catch (_) {
      return text;
    }
  }

  /// Runs translation jobs with bounded concurrency (the free API rate-
  /// limits aggressive parallel bursts, which silently broke whole pages).
  static Future<List<String>> translateAll(
      List<String> texts, String targetCode,
      {int concurrency = 3}) async {
    final results = List<String>.filled(texts.length, '');
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= texts.length) return;
        results[i] = await translateSafe(texts[i], targetCode);
      }
    }

    await Future.wait([for (var w = 0; w < concurrency; w++) worker()]);
    return results;
  }
}
