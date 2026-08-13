import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai.dart';

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

  /// Local NLLB model on the AI proxy — no quota, no rate limits. Returns
  /// null when the proxy can't be reached (caller falls back to MyMemory).
  static Future<List<String>?> _proxyTranslate(
      List<String> texts, String targetCode) async {
    try {
      final server = await SlideAi.resolveServerUrl();
      final response = await http
          .post(
            Uri.parse('$server/translate'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'texts': texts, 'target': targetCode}),
          )
          .timeout(const Duration(seconds: 120));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final out = (data['translations'] as List).cast<String>();
      return out.length == texts.length ? out : null;
    } catch (_) {
      return null;
    }
  }

  /// Translates [text] from English into [targetCode] (e.g. 'hi').
  /// Local NLLB on the proxy first (fast, unlimited); the free MyMemory
  /// web API only as a fallback when the proxy is unreachable.
  static Future<String> translate(String text, String targetCode) async {
    if (targetCode == 'en' || text.trim().isEmpty) return text;
    final local = await _proxyTranslate([text], targetCode);
    if (local != null && local.first.trim().isNotEmpty) return local.first;
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

  /// Batch translation: ONE request to the proxy's local model translates
  /// the whole page at once. Falls back to bounded-concurrency MyMemory
  /// only when the proxy is down.
  static Future<List<String>> translateAll(
      List<String> texts, String targetCode,
      {int concurrency = 3}) async {
    if (targetCode == 'en') return texts;
    final local = await _proxyTranslate(texts, targetCode);
    if (local != null) {
      // Keep originals for any empty translations.
      return [
        for (var i = 0; i < texts.length; i++)
          local[i].trim().isEmpty ? texts[i] : local[i],
      ];
    }
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
