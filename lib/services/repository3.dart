import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models3.dart';
import 'ai.dart';
import 'repository.dart';
import 'repository2.dart';

/// v4 data access: the class-notes flow around the "End class" button.
extension RepositoryV4 on Repository {
  SupabaseClient get _db => Supabase.instance.client;

  /// Creates the notes row the proxy will fill in. Returns its id.
  Future<String> createClassNotes({
    required String classroomId,
    required String language,
    String? sessionId,
  }) async {
    final row = await _db
        .from('class_notes')
        .insert({
          'classroom_id': classroomId,
          if (sessionId != null) 'session_id': sessionId,
          'language': language,
          'stage': 'Uploading the class…',
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  /// Live view of the newest notes row for a classroom (progress included).
  Stream<ClassNotes?> streamLatestClassNotes(String classroomId) {
    return _db
        .from('class_notes')
        .stream(primaryKey: ['id'])
        .eq('classroom_id', classroomId)
        .order('created_at', ascending: false)
        .limit(1)
        .map((rows) => rows.isEmpty ? null : ClassNotes.fromMap(rows.first));
  }

  Future<void> markClassNotesFailed(String noteId, String message) async {
    await _db.from('class_notes').update({
      'status': 'failed',
      'stage': 'Failed',
      'error': message,
    }).eq('id', noteId);
  }

  /// Uploads the lecture recording and returns its public URL.
  Future<String> uploadLectureAudio(Uint8List bytes, String extension) async {
    final path = await uploadMedia(
      bytes: bytes,
      extension: extension,
      contentType: extension == 'm4a' ? 'audio/mp4' : 'audio/webm',
    );
    return mediaUrl(path);
  }

  /// Kicks off the notes pipeline on the AI proxy.
  Future<void> startClassNotesJob({
    required String noteId,
    required String language,
    required String title,
    required List<String> slidePngsB64,
    required List<int> strokeCounts,
    required List<Map<String, dynamic>> slideMarks,
    String? audioUrl,
    String audioExt = 'webm',
  }) async {
    final server = await SlideAi.resolveServerUrl();
    final response = await http
        .post(
          Uri.parse('$server/end_class'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'note_id': noteId,
            'language': language,
            'title': title,
            'slides': slidePngsB64,
            'stroke_counts': strokeCounts,
            'slide_marks': slideMarks,
            'audio_url': audioUrl,
            'audio_ext': audioExt,
          }),
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) {
      throw Exception(
          'AI server rejected the job (HTTP ${response.statusCode}).');
    }
  }
}
