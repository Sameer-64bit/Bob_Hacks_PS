import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart' show compute;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models3.dart';
import 'ai.dart';
import 'repository.dart';
import 'repository2.dart';

/// Isolate entry: gzip+AES of a large file must not freeze the UI.
Map<String, dynamic> packMediaInIsolate(Uint8List bytes) {
  final packed = MediaCodec.pack(bytes);
  return {'cipher': packed.cipher, 'iv': packed.ivHex};
}

/// Compression + encryption for class media. Static so it's unit-testable
/// without a Supabase connection.
class MediaCodec {
  /// App-wide media key: the blob in storage is ciphertext, so downloading
  /// it outside the app yields noise. (Obfuscation-grade DRM — real DRM
  /// needs per-user keys and a licensed player.)
  static final enc.Key key = enc.Key.fromUtf8('kaksha-classroom-media-key-2026!');

  static ({Uint8List cipher, String ivHex}) pack(Uint8List bytes) {
    final compressed =
        Uint8List.fromList(GZipEncoder().encodeBytes(bytes, level: 6));
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter =
        enc.Encrypter(enc.AES(key, mode: enc.AESMode.ctr, padding: null));
    return (
      cipher: encrypter.encryptBytes(compressed, iv: iv).bytes,
      ivHex: iv.base16,
    );
  }

  static Uint8List unpack(Uint8List cipher, String ivHex) {
    final encrypter =
        enc.Encrypter(enc.AES(key, mode: enc.AESMode.ctr, padding: null));
    final compressed = encrypter.decryptBytes(
      enc.Encrypted(cipher),
      iv: enc.IV.fromBase16(ivHex),
    );
    return Uint8List.fromList(
        GZipDecoder().decodeBytes(Uint8List.fromList(compressed)));
  }
}

/// v7 data access: live lecture captions and encrypted class media.
extension RepositoryV7 on Repository {
  SupabaseClient get _db => Supabase.instance.client;

  // ------------------------------------------------------------ live captions

  /// Ships one recorded audio chunk to the AI proxy for live transcription.
  Future<void> sendLiveChunk({
    required String sessionId,
    required String classroomId,
    required int slideIndex,
    required int chunkIndex,
    required double offsetSeconds,
    required Uint8List audioBytes,
    required String audioExt,
  }) async {
    final server = await SlideAi.resolveServerUrl();
    await http
        .post(
          Uri.parse('$server/live_chunk'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'session_id': sessionId,
            'classroom_id': classroomId,
            'slide_index': slideIndex,
            'chunk_index': chunkIndex,
            'offset_s': offsetSeconds,
            'audio_b64': base64Encode(audioBytes),
            'audio_ext': audioExt,
          }),
        )
        .timeout(const Duration(seconds: 30));
  }

  /// Live caption rows for a session, ordered by lecture time.
  Stream<List<LiveCaption>> streamCaptions(String sessionId) {
    return _db
        .from('live_captions')
        .stream(primaryKey: ['id'])
        .eq('session_id', sessionId)
        .order('start_s', ascending: true)
        .map((rows) => [for (final r in rows) LiveCaption.fromMap(r)]
          ..sort((a, b) => a.startS.compareTo(b.startS)));
  }

  // ------------------------------------------------------- encrypted media

  /// Compress (gzip) + encrypt (AES-CTR) + upload, then record metadata.
  /// Returns the new media row's id.
  Future<String> uploadClassMedia({
    required String classroomId,
    required String teacherId,
    required String title,
    required String mime,
    required Uint8List bytes,
    String? sessionId,
    String transcriptStatus = 'none',
  }) async {
    // Off the UI thread — a 50 MB gzip+AES pass would otherwise freeze the
    // app and look like a hang.
    final packed = await compute(packMediaInIsolate, bytes);
    final cipher = packed['cipher'] as Uint8List;
    final ivHex = packed['iv'] as String;

    final path = await uploadMedia(
      bytes: cipher,
      extension: 'bin',
      contentType: 'application/octet-stream',
    );
    final row = await _db
        .from('class_media')
        .insert({
          'classroom_id': classroomId,
          'teacher_id': teacherId,
          if (sessionId != null) 'session_id': sessionId,
          'transcript_status': transcriptStatus,
          'title': title,
          'mime': mime,
          'bytes_original': bytes.length,
          'bytes_stored': cipher.length,
          'path': path,
          'iv': ivHex,
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  /// Subtitles for an uploaded lecture, ordered by playback time.
  Future<List<LiveCaption>> listMediaCaptions(String mediaId) async {
    final rows = await _db
        .from('media_captions')
        .select()
        .eq('media_id', mediaId)
        .order('start_s');
    return [
      for (final r in rows)
        LiveCaption(
          id: r['id'] as String,
          slideIndex: 0,
          startS: (r['start_s'] as num?)?.toDouble() ?? 0,
          endS: (r['end_s'] as num?)?.toDouble() ?? 0,
          text: r['text'] as String? ?? '',
        ),
    ];
  }

  /// Ships the raw lecture recording to the proxy: it transcribes once
  /// (player subtitles) and, when [noteId] is set, synthesises the class
  /// notes from that transcript + the session slides.
  Future<void> startLectureMediaJob({
    required String mediaId,
    String? noteId,
    required String language,
    required String title,
    required Uint8List mediaBytes,
    required String mediaExt,
    List<String> slidePngsB64 = const [],
    List<int> strokeCounts = const [],
    List<Map<String, dynamic>> slideMarks = const [],
  }) async {
    final server = await SlideAi.resolveServerUrl();
    final response = await http
        .post(
          Uri.parse('$server/lecture_media'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'media_id': mediaId,
            'note_id': noteId,
            'language': language,
            'title': title,
            'audio_b64': base64Encode(mediaBytes),
            'audio_ext': mediaExt,
            'slides': slidePngsB64,
            'stroke_counts': strokeCounts,
            'slide_marks': slideMarks,
          }),
        )
        .timeout(const Duration(minutes: 3));
    if (response.statusCode != 200) {
      throw Exception(
          'AI server rejected the lecture (HTTP ${response.statusCode}).');
    }
  }

  Future<List<ClassMedia>> listClassMedia(String classroomId) async {
    final rows = await _db
        .from('class_media')
        .select()
        .eq('classroom_id', classroomId)
        .order('created_at', ascending: false);
    return [for (final r in rows) ClassMedia.fromMap(r)];
  }

  Future<void> deleteClassMedia(String id) async {
    await _db.from('class_media').delete().eq('id', id);
  }

  /// Download + decrypt + decompress — returns the playable original bytes.
  Future<Uint8List> fetchClassMedia(ClassMedia media) async {
    final response = await http
        .get(Uri.parse(mediaUrl(media.path)))
        .timeout(const Duration(minutes: 3));
    if (response.statusCode != 200) {
      throw Exception('Could not download media (HTTP ${response.statusCode}).');
    }
    return MediaCodec.unpack(response.bodyBytes, media.iv);
  }
}
