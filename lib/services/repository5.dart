import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models3.dart';
import 'ai.dart';
import 'repository.dart';
import 'repository2.dart';

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
  Future<void> uploadClassMedia({
    required String classroomId,
    required String teacherId,
    required String title,
    required String mime,
    required Uint8List bytes,
  }) async {
    final packed = MediaCodec.pack(bytes);
    final cipher = packed.cipher;

    final path = await uploadMedia(
      bytes: cipher,
      extension: 'bin',
      contentType: 'application/octet-stream',
    );
    await _db.from('class_media').insert({
      'classroom_id': classroomId,
      'teacher_id': teacherId,
      'title': title,
      'mime': mime,
      'bytes_original': bytes.length,
      'bytes_stored': cipher.length,
      'path': path,
      'iv': packed.ivHex,
    });
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
