import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/languages.dart';
import '../models/models.dart';
import 'slide_raster.dart';
import 'translator.dart';

/// Slide AI backed by the SmolVLM proxy (vlm_server.py) running somewhere on
/// the network. The proxy announces its current address to the `ai_servers`
/// table every few seconds, so the app finds it no matter which IP the wifi
/// hands out — nothing is hardcoded.
///
/// The small VLM only reads and writes English reliably, so "translate" is a
/// two-step pipeline: SmolVLM transcribes the slide, then a free translation
/// service (MyMemory) converts the text into the student's language.
class SlideAi {
  /// Optional override: flutter run --dart-define=AI_SERVER_URL=http://ip:5000
  static const String _envServerUrl = String.fromEnvironment('AI_SERVER_URL');

  /// Last address the proxy announced before this build shipped — used only
  /// if discovery fails (e.g. no row yet).
  static const String _fallbackServerUrl = 'http://172.18.7.129:5000';

  static String? _cachedUrl;
  static DateTime _cachedAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Public entry for other services that need the proxy address
  /// (e.g. the class-notes job started by "End class").
  static Future<String> resolveServerUrl() => _serverUrl();

  /// Looks up the proxy's current address from Supabase (cached for 15 s).
  static Future<String> _serverUrl() async {
    if (_envServerUrl.isNotEmpty) return _envServerUrl;
    final cached = _cachedUrl;
    if (cached != null &&
        DateTime.now().difference(_cachedAt).inSeconds < 15) {
      return cached;
    }
    try {
      final row = await Supabase.instance.client
          .from('ai_servers')
          .select('url, updated_at')
          .eq('id', 'default')
          .maybeSingle();
      final url = (row?['url'] as String?)?.trim();
      if (url != null && url.isNotEmpty) {
        _cachedUrl = url;
        _cachedAt = DateTime.now();
        return url;
      }
    } catch (_) {
      // fall through to the last known address
    }
    return _cachedUrl ?? _fallbackServerUrl;
  }

  /// Renders a slide (background image included) to a PNG at half canvas
  /// resolution — small payload, still readable for the VLM.
  static Future<String> renderSlideBase64(BoardSlide slide) =>
      SlideRaster.pngBase64(slide, scale: 0.5);

  /// The raw HTTP call to the proxy — reusable for translation, description…
  static Future<String> _ask(BoardSlide slide, String prompt) async {
    final imageB64 = await renderSlideBase64(slide);
    final body = jsonEncode({'image_b64': imageB64, 'prompt': prompt});

    http.Response response;
    var attempt = 0;
    do {
      final endpoint = '${await _serverUrl()}/generate';
      try {
        response = await http
            .post(
              Uri.parse(endpoint),
              headers: {'content-type': 'application/json'},
              body: body,
            )
            .timeout(const Duration(seconds: 90));
      } catch (_) {
        // Server unreachable — drop the cache so the next attempt re-resolves
        // the address (it may have moved to a new IP).
        _cachedUrl = null;
        attempt++;
        if (attempt <= 2) {
          await Future.delayed(Duration(seconds: attempt));
          continue;
        }
        throw Exception(
            'Could not reach the AI server. Is vlm_server.py running?');
      }
      if (response.statusCode == 200) break;
      attempt++;
      if (attempt <= 2 && response.statusCode >= 500) {
        await Future.delayed(Duration(seconds: 2 * attempt));
        continue;
      }
      throw Exception(
          'AI server error (${response.statusCode}): ${response.body}');
    } while (true);

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final text = (data['text'] as String? ?? '').trim();
    if (text.isEmpty) throw Exception('The AI returned no answer — try again.');
    return text;
  }

  /// Lecture Q&A on the proxy's dedicated chat LLM (/chat): the server
  /// retrieves the question-relevant parts of the transcript + notes and
  /// answers with a proper instruct model — grounded, not generic. The
  /// answer is then translated to the student's language.
  static Future<String> askLecture({
    required String transcript,
    required String question,
    required AppLanguage target,
    String notesContext = '',
    List<Map<String, String>> history = const [],
  }) async {
    final body = jsonEncode({
      'question': question,
      'transcript': transcript,
      'notes': notesContext,
      'history': history,
    });
    http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('${await _serverUrl()}/chat'),
            headers: {'content-type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 120));
    } catch (_) {
      _cachedUrl = null;
      throw Exception('Could not reach the AI server.');
    }
    if (response.statusCode == 404) {
      throw Exception(
          'The AI server needs a restart to enable the new chatbot.');
    }
    if (response.statusCode != 200) {
      throw Exception('AI server error (${response.statusCode}).');
    }
    final answer =
        ((jsonDecode(response.body) as Map)['text'] as String? ?? '').trim();
    if (answer.isEmpty) throw Exception('No answer — try rephrasing.');
    return Translator.translate(answer, target.code);
  }

  /// Reads the slide with the VLM, then translates the transcription into
  /// the student's language with the free translator.
  static Future<String> translate(BoardSlide slide, AppLanguage target) async {
    final transcription = await _ask(
      slide,
      'Read and transcribe ALL text written on this whiteboard slide, '
      'exactly as written. Keep line breaks, lists and formulas. Reply with '
      'ONLY the transcribed text. If there is no readable text, reply with: '
      'No readable text on this slide.',
    );
    return Translator.translate(transcription, target.code);
  }

  /// Describes the slide in English with the VLM, then translates the
  /// description when the student's language is not English.
  static Future<String> describe(BoardSlide slide, AppLanguage target) async {
    final description = await _ask(
      slide,
      'This is a classroom whiteboard slide. Describe clearly for a student '
      'what is drawn and written on it — the topic, any diagrams, and the '
      'key points. Be concise (under 150 words). Reply in English.',
    );
    return Translator.translate(description, target.code);
  }
}
