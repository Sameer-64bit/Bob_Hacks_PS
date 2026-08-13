import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import '../models/models3.dart';
import 'repository.dart';

/// v5 data access: board sessions — one whiteboard per teaching period,
/// tied to date and time, with full history per classroom.
extension RepositoryV5 on Repository {
  SupabaseClient get _db => Supabase.instance.client;

  /// The open session for a classroom, creating one when none exists.
  Future<BoardSession> activeSession(String classroomId) async {
    final row = await _db
        .from('board_sessions')
        .select()
        .eq('classroom_id', classroomId)
        .isFilter('ended_at', null)
        .order('started_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (row != null) return BoardSession.fromMap(row);
    final created = await _db
        .from('board_sessions')
        .insert({'classroom_id': classroomId})
        .select()
        .single();
    return BoardSession.fromMap(created);
  }

  Future<BoardSession> newSession(String classroomId) async {
    final created = await _db
        .from('board_sessions')
        .insert({'classroom_id': classroomId})
        .select()
        .single();
    return BoardSession.fromMap(created);
  }

  Future<void> endSession(String sessionId) async {
    await _db.from('board_sessions').update(
        {'ended_at': DateTime.now().toUtc().toIso8601String()}).eq('id', sessionId);
  }

  /// Every session of a classroom, newest first — the board history.
  Future<List<BoardSession>> classroomSessions(String classroomId) async {
    final rows = await _db
        .from('board_sessions')
        .select()
        .eq('classroom_id', classroomId)
        .order('started_at', ascending: false);
    return [for (final r in rows) BoardSession.fromMap(r)];
  }

  /// Latest session (open or ended) as a live stream — the student's live
  /// view follows this, so a "New board" appears for them instantly.
  Stream<BoardSession?> streamLatestSession(String classroomId) {
    return _db
        .from('board_sessions')
        .stream(primaryKey: ['id'])
        .eq('classroom_id', classroomId)
        .order('started_at', ascending: false)
        .limit(1)
        .map((rows) => rows.isEmpty ? null : BoardSession.fromMap(rows.first));
  }

  // ---------------------------------------------------- session-aware slides

  BoardSlide _slideFromRow(Map<String, dynamic> r) => BoardSlide(
        dbId: r['id'] as String,
        index: (r['slide_index'] as num).toInt(),
        backgroundUrl: r['background_url'] as String?,
        strokes: [
          for (final s in (r['strokes'] as List))
            Stroke.fromJson(Map<String, dynamic>.from(s as Map)),
        ],
      );

  Future<List<BoardSlide>> loadSessionSlides(String sessionId) async {
    final rows = await _db
        .from('board_slides')
        .select()
        .eq('session_id', sessionId)
        .order('slide_index');
    return [for (final r in rows) _slideFromRow(r)]
      ..sort((a, b) => a.index.compareTo(b.index));
  }

  Future<void> saveSessionSlide(
      String classroomId, String sessionId, BoardSlide slide) async {
    await _db.from('board_slides').upsert(
      {
        'classroom_id': classroomId,
        'session_id': sessionId,
        'slide_index': slide.index,
        'strokes': slide.strokesJson(),
        'background_url': slide.backgroundUrl,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'session_id,slide_index',
    );
  }

  Future<void> deleteSessionSlide(String sessionId, int index) async {
    await _db
        .from('board_slides')
        .delete()
        .eq('session_id', sessionId)
        .eq('slide_index', index);
  }

  Stream<List<BoardSlide>> streamSessionSlides(String sessionId) {
    return _db
        .from('board_slides')
        .stream(primaryKey: ['id'])
        .eq('session_id', sessionId)
        .order('slide_index', ascending: true)
        // Realtime updates can arrive out of order — sort every emission so
        // students always see slides in exactly the teacher's arrangement.
        .map((rows) => [for (final r in rows) _slideFromRow(r)]
          ..sort((a, b) => a.index.compareTo(b.index)));
  }

  // ----------------------------------------------------------- notes history

  /// Every notes row of a classroom, newest first ("notes from which date").
  Future<List<ClassNotes>> classroomNotesHistory(String classroomId) async {
    final rows = await _db
        .from('class_notes')
        .select()
        .eq('classroom_id', classroomId)
        .order('created_at', ascending: false);
    return [for (final r in rows) ClassNotes.fromMap(r)];
  }
}
