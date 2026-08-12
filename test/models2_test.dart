import 'package:flutter_test/flutter_test.dart';

import 'package:kaksha/data/languages.dart';
import 'package:kaksha/models/models2.dart';

void main() {
  group('v2 models', () {
    test('assignment parses with and without due date', () {
      final a = Assignment.fromMap({
        'id': 'a1',
        'classroom_id': 'c1',
        'teacher_id': 't1',
        'title': 'Linked lists',
        'description': 'Solve Q1-Q5',
        'due_at': '2026-08-20T18:29:00+00:00',
        'max_score': 50,
        'created_at': '2026-08-12T10:00:00+00:00',
      });
      expect(a.title, 'Linked lists');
      expect(a.maxScore, 50);
      expect(a.dueAt, isNotNull);

      final b = Assignment.fromMap({
        'id': 'a2',
        'classroom_id': 'c1',
        'teacher_id': 't1',
        'title': 'No deadline',
        'description': '',
        'due_at': null,
        'max_score': 100,
        'created_at': '2026-08-12T10:00:00+00:00',
      });
      expect(b.dueAt, isNull);
    });

    test('submission joins student info and knows evaluation state', () {
      final s = Submission.fromMap({
        'id': 's1',
        'assignment_id': 'a1',
        'student_id': 'st1',
        'content': 'my answer',
        'submitted_at': '2026-08-12T10:30:00+00:00',
        'score': null,
        'feedback': null,
        'students': {'name': 'Maheshwar', 'roll_no': 'R1'},
      });
      expect(s.evaluated, isFalse);
      expect(s.studentName, 'Maheshwar');

      final graded = Submission.fromMap({
        'id': 's2',
        'assignment_id': 'a1',
        'student_id': 'st1',
        'content': 'ans',
        'submitted_at': '2026-08-12T10:30:00+00:00',
        'score': 42,
      });
      expect(graded.evaluated, isTrue);
      expect(graded.score, 42);
    });

    test('ticket status flags', () {
      final t = Ticket.fromMap({
        'id': 't1',
        'classroom_id': 'c1',
        'student_id': 's1',
        'title': 'Recursion doubt',
        'status': 'open',
        'created_at': '2026-08-12T09:00:00+00:00',
        'students': {'name': 'Maheshwar'},
      });
      expect(t.isOpen, isTrue);
      expect(t.studentName, 'Maheshwar');
    });

    test('ticket message kinds parse', () {
      for (final kind in ['text', 'image', 'voice', 'meeting']) {
        final m = TicketMessage.fromMap({
          'id': 'm-$kind',
          'ticket_id': 't1',
          'sender_role': 'teacher',
          'sender_name': 'Shah Alam',
          'kind': kind,
          'body': 'hello',
          'media_path': kind == 'text' ? null : 'tickets/x.jpg',
          'created_at': '2026-08-12T09:05:00+00:00',
        });
        expect(m.kind, kind);
      }
    });

    test('class events carry slide index and student name', () {
      final e = ClassEvent.fromMap({
        'id': 'e1',
        'classroom_id': 'c1',
        'student_name': 'Maheshwar',
        'kind': 'hand',
        'slide_index': 2,
        'body': '',
        'created_at': '2026-08-12T09:10:00+00:00',
      });
      expect(e.kind, 'hand');
      expect(e.slideIndex, 2);
    });

    test('attendance record parses date', () {
      final r = AttendanceRecord.fromMap({
        'student_id': 's1',
        'day': '2026-08-10',
        'status': 'present',
      });
      expect(r.day.day, 10);
      expect(r.status, 'present');
    });

    test('shortWhen formats readable timestamps', () {
      expect(shortWhen(DateTime(2026, 8, 12, 14, 5)), '12 Aug, 2:05 PM');
      expect(shortWhen(DateTime(2026, 1, 3, 0, 0)), '3 Jan, 12:00 AM');
    });
  });

  group('languages', () {
    test('codes are unique and lookup falls back to English', () {
      final codes = kLanguages.map((l) => l.code).toSet();
      expect(codes.length, kLanguages.length);
      expect(languageByCode('hi').name, 'Hindi');
      expect(languageByCode('nope').code, 'en');
    });
  });
}
