import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import '../models/models2.dart';
import 'repository.dart';

/// v2 data access: attendance, assignments, doubt tickets, live class
/// events and media uploads. Kept as an extension so the v1 file stays
/// untouched.
extension RepositoryV2 on Repository {
  SupabaseClient get _db => Supabase.instance.client;

  // ---------------------------------------------------------------- profile

  Future<void> setLanguage({
    required bool isTeacher,
    required String id,
    required String code,
  }) async {
    await _db
        .from(isTeacher ? 'teachers' : 'students')
        .update({'language': code}).eq('id', id);
  }

  Future<String> languageOf({required bool isTeacher, required String id}) async {
    final row = await _db
        .from(isTeacher ? 'teachers' : 'students')
        .select('language')
        .eq('id', id)
        .maybeSingle();
    return (row?['language'] as String?) ?? 'en';
  }

  // ------------------------------------------------------------- attendance

  Future<List<Student>> classroomStudents(String classroomId) async {
    final rows = await _db
        .from('students')
        .select()
        .eq('classroom_id', classroomId)
        .order('name');
    return [for (final r in rows) Student.fromMap(r)];
  }

  Future<List<AttendanceRecord>> classroomAttendance(String classroomId) async {
    final rows = await _db
        .from('attendance')
        .select('student_id, day, status')
        .eq('classroom_id', classroomId);
    return [for (final r in rows) AttendanceRecord.fromMap(r)];
  }

  // ------------------------------------------------------------ assignments

  Future<Assignment> createAssignment({
    required String classroomId,
    required String teacherId,
    required String title,
    required String description,
    DateTime? dueAt,
    required int maxScore,
  }) async {
    final row = await _db
        .from('assignments')
        .insert({
          'classroom_id': classroomId,
          'teacher_id': teacherId,
          'title': title,
          'description': description,
          'due_at': dueAt?.toUtc().toIso8601String(),
          'max_score': maxScore,
        })
        .select()
        .single();
    return Assignment.fromMap(row);
  }

  Future<void> deleteAssignment(String id) async {
    await _db.from('assignments').delete().eq('id', id);
  }

  /// Live list of a classroom's assignments — new ones appear without
  /// any refresh on the student dashboard.
  Stream<List<Assignment>> streamAssignments(String classroomId) {
    return _db
        .from('assignments')
        .stream(primaryKey: ['id'])
        .eq('classroom_id', classroomId)
        .order('created_at')
        .map((rows) => [for (final r in rows) Assignment.fromMap(r)]);
  }

  Future<List<Assignment>> classroomAssignments(String classroomId) async {
    final rows = await _db
        .from('assignments')
        .select()
        .eq('classroom_id', classroomId)
        .order('created_at', ascending: false);
    return [for (final r in rows) Assignment.fromMap(r)];
  }

  Future<List<Submission>> assignmentSubmissions(String assignmentId) async {
    final rows = await _db
        .from('submissions')
        .select('*, students(name, roll_no)')
        .eq('assignment_id', assignmentId)
        .order('submitted_at');
    return [for (final r in rows) Submission.fromMap(r)];
  }

  Future<Submission?> mySubmission(String assignmentId, String studentId) async {
    final row = await _db
        .from('submissions')
        .select()
        .eq('assignment_id', assignmentId)
        .eq('student_id', studentId)
        .maybeSingle();
    return row == null ? null : Submission.fromMap(row);
  }

  Future<Submission> submitAssignment({
    required String assignmentId,
    required String studentId,
    required String content,
  }) async {
    final row = await _db
        .from('submissions')
        .upsert({
          'assignment_id': assignmentId,
          'student_id': studentId,
          'content': content,
          'submitted_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'assignment_id,student_id')
        .select()
        .single();
    return Submission.fromMap(row);
  }

  Future<void> gradeSubmission({
    required String submissionId,
    required int score,
    String? feedback,
  }) async {
    await _db.from('submissions').update({
      'score': score,
      'feedback': feedback,
    }).eq('id', submissionId);
  }

  /// Student's submissions across assignments (to show scores).
  Stream<List<Submission>> streamMySubmissions(String studentId) {
    return _db
        .from('submissions')
        .stream(primaryKey: ['id'])
        .eq('student_id', studentId)
        .map((rows) => [for (final r in rows) Submission.fromMap(r)]);
  }

  // ---------------------------------------------------------------- tickets

  Future<Ticket> createTicket({
    required String classroomId,
    required String studentId,
    required String studentName,
    required String title,
    required String firstMessage,
  }) async {
    final row = await _db
        .from('tickets')
        .insert({
          'classroom_id': classroomId,
          'student_id': studentId,
          'title': title,
        })
        .select()
        .single();
    final ticket = Ticket.fromMap(row);
    if (firstMessage.trim().isNotEmpty) {
      await sendTicketMessage(
        ticketId: ticket.id,
        senderRole: 'student',
        senderName: studentName,
        kind: 'text',
        body: firstMessage.trim(),
      );
    }
    return ticket;
  }

  Future<List<Ticket>> classroomTickets(String classroomId) async {
    final rows = await _db
        .from('tickets')
        .select('*, students(name)')
        .eq('classroom_id', classroomId)
        .order('status', ascending: false) // open first
        .order('created_at', ascending: false);
    return [for (final r in rows) Ticket.fromMap(r)];
  }

  Future<List<Ticket>> studentTickets(String studentId) async {
    final rows = await _db
        .from('tickets')
        .select()
        .eq('student_id', studentId)
        .order('created_at', ascending: false);
    return [for (final r in rows) Ticket.fromMap(r)];
  }

  Future<void> setTicketStatus(String ticketId, String status) async {
    await _db.from('tickets').update({'status': status}).eq('id', ticketId);
  }

  Stream<List<TicketMessage>> streamTicketMessages(String ticketId) {
    return _db
        .from('ticket_messages')
        .stream(primaryKey: ['id'])
        .eq('ticket_id', ticketId)
        .order('created_at', ascending: true)
        .map((rows) => [for (final r in rows) TicketMessage.fromMap(r)]);
  }

  Future<void> sendTicketMessage({
    required String ticketId,
    required String senderRole,
    required String senderName,
    required String kind,
    required String body,
    String? mediaPath,
  }) async {
    await _db.from('ticket_messages').insert({
      'ticket_id': ticketId,
      'sender_role': senderRole,
      'sender_name': senderName,
      'kind': kind,
      'body': body,
      'media_path': mediaPath,
    });
  }

  /// Creates the meeting row and drops a `meeting` card into the thread.
  Future<void> scheduleMeeting({
    required String ticketId,
    required DateTime at,
    required String teacherName,
  }) async {
    final slug = ticketId.replaceAll('-', '').substring(0, 12);
    final url = 'https://meet.jit.si/kaksha-doubt-$slug';
    await _db.from('meetings').insert({
      'ticket_id': ticketId,
      'scheduled_at': at.toUtc().toIso8601String(),
      'url': url,
    });
    await sendTicketMessage(
      ticketId: ticketId,
      senderRole: 'teacher',
      senderName: teacherName,
      kind: 'meeting',
      body: jsonEncode({'url': url, 'at': at.toUtc().toIso8601String()}),
    );
  }

  // ------------------------------------------------------------------ media

  /// Uploads bytes to the public `media` bucket, returns the storage path.
  Future<String> uploadMedia({
    required Uint8List bytes,
    required String extension,
    required String contentType,
  }) async {
    final name =
        '${DateTime.now().millisecondsSinceEpoch}-${bytes.length}.$extension';
    final path = 'tickets/$name';
    await _db.storage.from('media').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType),
        );
    return path;
  }

  String mediaUrl(String path) =>
      _db.storage.from('media').getPublicUrl(path);

  // ----------------------------------------------------------- live class

  Future<void> sendClassEvent({
    required String classroomId,
    String? studentId,
    required String studentName,
    required String kind, // hand | chat
    required int slideIndex,
    String body = '',
  }) async {
    await _db.from('class_events').insert({
      'classroom_id': classroomId,
      'student_id': studentId,
      'student_name': studentName,
      'kind': kind,
      'slide_index': slideIndex,
      'body': body,
    });
  }

  Stream<List<ClassEvent>> streamClassEvents(String classroomId) {
    return _db
        .from('class_events')
        .stream(primaryKey: ['id'])
        .eq('classroom_id', classroomId)
        .order('created_at', ascending: true)
        .map((rows) => [for (final r in rows) ClassEvent.fromMap(r)]);
  }

  /// Live slides for the read-only student view of the board.
  Stream<List<BoardSlide>> streamSlides(String classroomId) {
    return _db
        .from('board_slides')
        .stream(primaryKey: ['id'])
        .eq('classroom_id', classroomId)
        .order('slide_index', ascending: true)
        .map((rows) => [
              for (final r in rows)
                BoardSlide(
                  dbId: r['id'] as String,
                  index: (r['slide_index'] as num).toInt(),
                  strokes: [
                    for (final s in (r['strokes'] as List))
                      Stroke.fromJson(Map<String, dynamic>.from(s as Map)),
                  ],
                ),
            ]);
  }
}
