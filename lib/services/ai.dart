import 'dart:convert';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/languages.dart';
import '../models/models.dart';
import '../screens/board/board_controller.dart';
import '../screens/board/board_painter.dart';
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

  /// Renders a slide's strokes to a PNG (half canvas resolution keeps the
  /// payload small while staying readable).
  static Future<String> renderSlideBase64(BoardSlide slide) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    const scale = 0.5;
    canvas.scale(scale);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, kCanvasSize.width, kCanvasSize.height),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    for (final stroke in slide.strokes) {
      paintStroke(canvas, stroke);
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (kCanvasSize.width * scale).round(),
      (kCanvasSize.height * scale).round(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return base64Encode(bytes!.buffer.asUint8List());
  }

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
