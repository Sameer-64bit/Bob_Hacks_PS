import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:kaksha/data/branches.dart';
import 'package:kaksha/models/models.dart';
import 'package:kaksha/services/repository.dart';

void main() {
  group('time helpers', () {
    test('parses HH:MM:SS and HH:MM', () {
      expect(parseTimeToMinutes('14:05:00'), 14 * 60 + 5);
      expect(parseTimeToMinutes('09:30'), 9 * 60 + 30);
      expect(parseTimeToMinutes('00:00:00'), 0);
    });

    test('formats 12-hour times', () {
      expect(formatMinutes(0), '12:00 AM');
      expect(formatMinutes(9 * 60 + 5), '9:05 AM');
      expect(formatMinutes(12 * 60), '12:00 PM');
      expect(formatMinutes(14 * 60), '2:00 PM');
      expect(formatMinutes(23 * 60 + 59), '11:59 PM');
    });

    test('round-trips to SQL time', () {
      expect(minutesToSql(14 * 60 + 5), '14:05');
      expect(parseTimeToMinutes(minutesToSql(830)), 830);
    });
  });

  group('branches', () {
    test('every branch key is unique', () {
      final keys = kBranches.map((b) => b.key).toSet();
      expect(keys.length, kBranches.length);
    });

    test('lookup falls back safely', () {
      expect(branchByKey('btech_cse').short, 'CSE');
      expect(branchByKey('nonsense'), kBranches.first);
    });

    test('year names cover every programme length', () {
      final longest = kBranches.map((b) => b.years).reduce(max);
      expect(longest <= kYearNames.length, isTrue);
      expect(yearName(1), '1st Year');
      expect(yearName(4), '4th Year');
    });
  });

  group('classroom codes', () {
    test('follow SHORT+year-XXXX and avoid ambiguous characters', () {
      final rng = Random(7);
      for (final b in kBranches) {
        final code = classroomCode(b, 2, rng);
        expect(code, matches(RegExp('^${b.short}2-[A-Z2-9]{4}\$')));
        final tail = code.split('-').last;
        for (final ambiguous in ['O', 'I', '0', '1']) {
          expect(tail.contains(ambiguous), isFalse,
              reason: '$code tail should not contain $ambiguous');
        }
      }
    });
  });

  group('schedule entries', () {
    test('parse joined rows from supabase', () {
      final entry = ScheduleEntry.fromMap({
        'id': 'e1',
        'teacher_id': 't1',
        'classroom_id': 'c1',
        'subject': 'Data Structures',
        'day_of_week': 1,
        'start_time': '14:00:00',
        'end_time': '15:00:00',
        'teachers': {'name': 'Shah Alam'},
        'classrooms': {
          'id': 'c1',
          'code': 'CSE1-ABCD',
          'branch': 'btech_cse',
          'year': 1,
        },
      });
      expect(entry.teacherName, 'Shah Alam');
      expect(entry.classroom!.code, 'CSE1-ABCD');
      expect(entry.timeRange, '2:00 PM – 3:00 PM');
      expect(dayName(entry.dayOfWeek), 'Monday');
    });
  });

  group('strokes', () {
    test('JSON round-trip preserves geometry and style', () {
      final s = Stroke(
        id: 'abc',
        color: 0xFF16324F,
        width: 4,
        tool: 'pen',
        points: const [Offset(1.5, 2.25), Offset(10, 20), Offset(-3, 0.5)],
      );
      final back = Stroke.fromJson(s.toJson());
      expect(back.id, s.id);
      expect(back.color, s.color);
      expect(back.width, s.width);
      expect(back.tool, s.tool);
      expect(back.points, s.points);
    });

    test('bounds cover all points', () {
      final s = Stroke(
        id: 'b',
        color: 0,
        width: 1,
        tool: 'pen',
        points: const [Offset(10, 5), Offset(-2, 40), Offset(7, 7)],
      );
      expect(s.bounds, const Rect.fromLTRB(-2, 5, 10, 40));
    });

    test('translation moves every point', () {
      final s = Stroke(
        id: 't',
        color: 0,
        width: 1,
        tool: 'pen',
        points: const [Offset(0, 0), Offset(5, 5)],
      );
      final moved = s.translated(const Offset(10, -2));
      expect(moved.points, const [Offset(10, -2), Offset(15, 3)]);
    });
  });
}
