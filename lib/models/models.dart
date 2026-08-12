import 'dart:ui';

class Classroom {
  final String id;
  final String code;
  final String branch;
  final int year;

  const Classroom({
    required this.id,
    required this.code,
    required this.branch,
    required this.year,
  });

  factory Classroom.fromMap(Map<String, dynamic> m) => Classroom(
        id: m['id'] as String,
        code: m['code'] as String,
        branch: m['branch'] as String,
        year: (m['year'] as num).toInt(),
      );
}

class Student {
  final String id;
  final String name;
  final String rollNo;
  final String branch;
  final int year;
  final String? classroomId;

  const Student({
    required this.id,
    required this.name,
    required this.rollNo,
    required this.branch,
    required this.year,
    this.classroomId,
  });

  factory Student.fromMap(Map<String, dynamic> m) => Student(
        id: m['id'] as String,
        name: m['name'] as String,
        rollNo: m['roll_no'] as String,
        branch: m['branch'] as String,
        year: (m['year'] as num).toInt(),
        classroomId: m['classroom_id'] as String?,
      );
}

class Teacher {
  final String id;
  final String name;
  final String employeeId;

  const Teacher({required this.id, required this.name, required this.employeeId});

  factory Teacher.fromMap(Map<String, dynamic> m) => Teacher(
        id: m['id'] as String,
        name: m['name'] as String,
        employeeId: m['employee_id'] as String,
      );
}

/// A weekly recurring class slot. [dayOfWeek]: 1 = Monday … 7 = Sunday,
/// matching [DateTime.weekday]. Times are minutes from midnight.
class ScheduleEntry {
  final String id;
  final String teacherId;
  final String classroomId;
  final String subject;
  final int dayOfWeek;
  final int startMinutes;
  final int endMinutes;
  final String? teacherName;
  final Classroom? classroom;

  const ScheduleEntry({
    required this.id,
    required this.teacherId,
    required this.classroomId,
    required this.subject,
    required this.dayOfWeek,
    required this.startMinutes,
    required this.endMinutes,
    this.teacherName,
    this.classroom,
  });

  factory ScheduleEntry.fromMap(Map<String, dynamic> m) => ScheduleEntry(
        id: m['id'] as String,
        teacherId: m['teacher_id'] as String,
        classroomId: m['classroom_id'] as String,
        subject: m['subject'] as String,
        dayOfWeek: (m['day_of_week'] as num).toInt(),
        startMinutes: parseTimeToMinutes(m['start_time'] as String),
        endMinutes: parseTimeToMinutes(m['end_time'] as String),
        teacherName: (m['teachers'] as Map<String, dynamic>?)?['name'] as String?,
        classroom: m['classrooms'] is Map<String, dynamic>
            ? Classroom.fromMap(m['classrooms'] as Map<String, dynamic>)
            : null,
      );

  String get timeRange =>
      '${formatMinutes(startMinutes)} – ${formatMinutes(endMinutes)}';
}

/// Parses "14:05:00" / "14:05" into minutes from midnight.
int parseTimeToMinutes(String t) {
  final parts = t.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

/// 830 -> "1:50 PM" (12-hour clock without an intl dependency).
String formatMinutes(int minutes) {
  final h24 = minutes ~/ 60;
  final m = minutes % 60;
  final suffix = h24 >= 12 ? 'PM' : 'AM';
  var h = h24 % 12;
  if (h == 0) h = 12;
  final mm = m.toString().padLeft(2, '0');
  return '$h:$mm $suffix';
}

/// Minutes -> "HH:MM" for Postgres `time`.
String minutesToSql(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

const List<String> kDayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String dayName(int dayOfWeek) => kDayNames[(dayOfWeek - 1).clamp(0, 6)];

// ---------------------------------------------------------------------------
// Smart board models
// ---------------------------------------------------------------------------

class Stroke {
  final String id;
  final int color; // ARGB
  final double width;
  final String tool; // 'pen' | 'highlighter'
  final List<Offset> points;

  const Stroke({
    required this.id,
    required this.color,
    required this.width,
    required this.tool,
    required this.points,
  });

  Stroke copyWith({String? id, List<Offset>? points}) => Stroke(
        id: id ?? this.id,
        color: color,
        width: width,
        tool: tool,
        points: points ?? this.points,
      );

  Stroke translated(Offset delta) =>
      copyWith(points: [for (final p in points) p + delta]);

  Map<String, dynamic> toJson() => {
        'id': id,
        'color': color,
        'width': width,
        'tool': tool,
        'points': [
          for (final p in points) ...[
            double.parse(p.dx.toStringAsFixed(2)),
            double.parse(p.dy.toStringAsFixed(2)),
          ]
        ],
      };

  factory Stroke.fromJson(Map<String, dynamic> m) {
    final raw = (m['points'] as List).cast<num>();
    return Stroke(
      id: m['id'] as String,
      color: (m['color'] as num).toInt(),
      width: (m['width'] as num).toDouble(),
      tool: m['tool'] as String? ?? 'pen',
      points: [
        for (var i = 0; i + 1 < raw.length; i += 2)
          Offset(raw[i].toDouble(), raw[i + 1].toDouble()),
      ],
    );
  }

  Rect get bounds {
    if (points.isEmpty) return Rect.zero;
    var minX = points.first.dx, maxX = points.first.dx;
    var minY = points.first.dy, maxY = points.first.dy;
    for (final p in points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }
}

class BoardSlide {
  final String? dbId;
  int index;
  List<Stroke> strokes;

  BoardSlide({this.dbId, required this.index, List<Stroke>? strokes})
      : strokes = strokes ?? [];

  List<Map<String, dynamic>> strokesJson() =>
      [for (final s in strokes) s.toJson()];
}
