import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/branches.dart';
import '../models/models.dart';

/// Thrown with a human-readable message the UI can show directly.
class RepoException implements Exception {
  final String message;
  RepoException(this.message);
  @override
  String toString() => message;
}

/// Generates a join code like `CSE1-7KQ2` (no 0/O/1/I to keep it readable
/// when typed on a smart board).
String classroomCode(Branch branch, int year, [Random? rng]) {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final r = rng ?? Random();
  final tail =
      List.generate(4, (_) => alphabet[r.nextInt(alphabet.length)]).join();
  return '${branch.short}$year-$tail';
}

class Repository {
  SupabaseClient get _db => Supabase.instance.client;

  // ---------------------------------------------------------------- students

  Future<(Student, Classroom)> registerStudent({
    required String name,
    required String rollNo,
    required String branchKey,
    required int year,
  }) async {
    final existing = await _db
        .from('students')
        .select()
        .eq('roll_no', rollNo)
        .maybeSingle();
    if (existing != null) {
      throw RepoException(
          'Roll number $rollNo is already registered. Use “Already registered?” to sign in.');
    }
    final classroom = await findOrCreateClassroom(branchKey, year);
    final row = await _db
        .from('students')
        .insert({
          'name': name,
          'roll_no': rollNo,
          'branch': branchKey,
          'year': year,
          'classroom_id': classroom.id,
        })
        .select()
        .single();
    return (Student.fromMap(row), classroom);
  }

  Future<Student?> studentByRoll(String rollNo) async {
    final row =
        await _db.from('students').select().eq('roll_no', rollNo).maybeSingle();
    return row == null ? null : Student.fromMap(row);
  }

  Future<Student?> studentById(String id) async {
    final row = await _db.from('students').select().eq('id', id).maybeSingle();
    return row == null ? null : Student.fromMap(row);
  }

  // ---------------------------------------------------------------- teachers

  Future<Teacher> registerTeacher({
    required String name,
    required String employeeId,
  }) async {
    final existing = await _db
        .from('teachers')
        .select()
        .eq('employee_id', employeeId)
        .maybeSingle();
    if (existing != null) {
      throw RepoException(
          'Employee ID $employeeId is already registered. Use “Already registered?” to sign in.');
    }
    final row = await _db
        .from('teachers')
        .insert({'name': name, 'employee_id': employeeId})
        .select()
        .single();
    return Teacher.fromMap(row);
  }

  Future<Teacher?> teacherByEmployeeId(String employeeId) async {
    final row = await _db
        .from('teachers')
        .select()
        .eq('employee_id', employeeId)
        .maybeSingle();
    return row == null ? null : Teacher.fromMap(row);
  }

  Future<Teacher?> teacherById(String id) async {
    final row = await _db.from('teachers').select().eq('id', id).maybeSingle();
    return row == null ? null : Teacher.fromMap(row);
  }

  // -------------------------------------------------------------- classrooms

  /// One classroom exists per (branch, year); whoever registers first
  /// creates it and everyone after joins it.
  Future<Classroom> findOrCreateClassroom(String branchKey, int year) async {
    final found = await _db
        .from('classrooms')
        .select()
        .eq('branch', branchKey)
        .eq('year', year)
        .maybeSingle();
    if (found != null) return Classroom.fromMap(found);

    final branch = branchByKey(branchKey);
    try {
      final row = await _db
          .from('classrooms')
          .insert({
            'code': classroomCode(branch, year),
            'branch': branchKey,
            'year': year,
          })
          .select()
          .single();
      return Classroom.fromMap(row);
    } on PostgrestException {
      // Someone else created it in between — fetch theirs.
      final row = await _db
          .from('classrooms')
          .select()
          .eq('branch', branchKey)
          .eq('year', year)
          .single();
      return Classroom.fromMap(row);
    }
  }

  Future<Classroom?> classroomById(String id) async {
    final row =
        await _db.from('classrooms').select().eq('id', id).maybeSingle();
    return row == null ? null : Classroom.fromMap(row);
  }

  Future<Classroom?> classroomByCode(String code) async {
    final row = await _db
        .from('classrooms')
        .select()
        .eq('code', code.trim().toUpperCase())
        .maybeSingle();
    return row == null ? null : Classroom.fromMap(row);
  }

  // --------------------------------------------------------------- schedules

  Future<ScheduleEntry> addScheduleSlot({
    required String teacherId,
    required String branchKey,
    required int year,
    required String subject,
    required int dayOfWeek,
    required int startMinutes,
    required int endMinutes,
  }) async {
    final classroom = await findOrCreateClassroom(branchKey, year);
    final row = await _db
        .from('schedules')
        .insert({
          'teacher_id': teacherId,
          'classroom_id': classroom.id,
          'subject': subject,
          'day_of_week': dayOfWeek,
          'start_time': minutesToSql(startMinutes),
          'end_time': minutesToSql(endMinutes),
        })
        .select('*, classrooms(*)')
        .single();
    return ScheduleEntry.fromMap(row);
  }

  Future<void> deleteScheduleSlot(String id) async {
    await _db.from('schedules').delete().eq('id', id);
  }

  /// All slots taught by a teacher, with classroom info.
  Future<List<ScheduleEntry>> teacherSchedule(String teacherId) async {
    final rows = await _db
        .from('schedules')
        .select('*, classrooms(*)')
        .eq('teacher_id', teacherId)
        .order('day_of_week')
        .order('start_time');
    return [for (final r in rows) ScheduleEntry.fromMap(r)];
  }

  /// All slots for a classroom, with the teacher's name.
  Future<List<ScheduleEntry>> classroomSchedule(String classroomId) async {
    final rows = await _db
        .from('schedules')
        .select('*, teachers(name)')
        .eq('classroom_id', classroomId)
        .order('day_of_week')
        .order('start_time');
    return [for (final r in rows) ScheduleEntry.fromMap(r)];
  }

  // ------------------------------------------------------------- smart board

  Future<List<BoardSlide>> loadSlides(String classroomId) async {
    final rows = await _db
        .from('board_slides')
        .select()
        .eq('classroom_id', classroomId)
        .order('slide_index');
    return [
      for (final r in rows)
        BoardSlide(
          dbId: r['id'] as String,
          index: (r['slide_index'] as num).toInt(),
          backgroundUrl: r['background_url'] as String?,
          strokes: [
            for (final s in (r['strokes'] as List))
              Stroke.fromJson(Map<String, dynamic>.from(s as Map)),
          ],
        ),
    ]..sort((a, b) => a.index.compareTo(b.index));
  }

  Future<void> saveSlide(String classroomId, BoardSlide slide) async {
    await _db.from('board_slides').upsert(
      {
        'classroom_id': classroomId,
        'slide_index': slide.index,
        'strokes': slide.strokesJson(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'classroom_id,slide_index',
    );
  }

  Future<void> deleteSlide(String classroomId, int index) async {
    await _db
        .from('board_slides')
        .delete()
        .eq('classroom_id', classroomId)
        .eq('slide_index', index);
  }
}

final repo = Repository();
