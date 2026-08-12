/// Models for the v2 features: attendance, assignments, doubt tickets
/// and live classroom events.
library;

class AttendanceRecord {
  final String studentId;
  final DateTime day;
  final String status; // present | absent | late

  const AttendanceRecord(
      {required this.studentId, required this.day, required this.status});

  factory AttendanceRecord.fromMap(Map<String, dynamic> m) => AttendanceRecord(
        studentId: m['student_id'] as String,
        day: DateTime.parse(m['day'] as String),
        status: m['status'] as String? ?? 'present',
      );
}

class Assignment {
  final String id;
  final String classroomId;
  final String teacherId;
  final String title;
  final String description;
  final DateTime? dueAt;
  final int maxScore;
  final DateTime createdAt;

  const Assignment({
    required this.id,
    required this.classroomId,
    required this.teacherId,
    required this.title,
    required this.description,
    required this.dueAt,
    required this.maxScore,
    required this.createdAt,
  });

  factory Assignment.fromMap(Map<String, dynamic> m) => Assignment(
        id: m['id'] as String,
        classroomId: m['classroom_id'] as String,
        teacherId: m['teacher_id'] as String,
        title: m['title'] as String,
        description: m['description'] as String? ?? '',
        dueAt: m['due_at'] == null
            ? null
            : DateTime.parse(m['due_at'] as String).toLocal(),
        maxScore: (m['max_score'] as num?)?.toInt() ?? 100,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      );
}

class Submission {
  final String id;
  final String assignmentId;
  final String studentId;
  final String content;
  final DateTime submittedAt;
  final int? score; // null until evaluated
  final String? feedback;
  final String? studentName; // joined
  final String? studentRoll; // joined

  const Submission({
    required this.id,
    required this.assignmentId,
    required this.studentId,
    required this.content,
    required this.submittedAt,
    this.score,
    this.feedback,
    this.studentName,
    this.studentRoll,
  });

  bool get evaluated => score != null;

  factory Submission.fromMap(Map<String, dynamic> m) {
    final student = m['students'] as Map<String, dynamic>?;
    return Submission(
      id: m['id'] as String,
      assignmentId: m['assignment_id'] as String,
      studentId: m['student_id'] as String,
      content: m['content'] as String? ?? '',
      submittedAt: DateTime.parse(m['submitted_at'] as String).toLocal(),
      score: (m['score'] as num?)?.toInt(),
      feedback: m['feedback'] as String?,
      studentName: student?['name'] as String?,
      studentRoll: student?['roll_no'] as String?,
    );
  }
}

class Ticket {
  final String id;
  final String classroomId;
  final String studentId;
  final String title;
  final String status; // open | resolved
  final DateTime createdAt;
  final String? studentName; // joined

  const Ticket({
    required this.id,
    required this.classroomId,
    required this.studentId,
    required this.title,
    required this.status,
    required this.createdAt,
    this.studentName,
  });

  bool get isOpen => status == 'open';

  factory Ticket.fromMap(Map<String, dynamic> m) => Ticket(
        id: m['id'] as String,
        classroomId: m['classroom_id'] as String,
        studentId: m['student_id'] as String,
        title: m['title'] as String,
        status: m['status'] as String? ?? 'open',
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
        studentName:
            (m['students'] as Map<String, dynamic>?)?['name'] as String?,
      );
}

class TicketMessage {
  final String id;
  final String ticketId;
  final String senderRole; // student | teacher
  final String senderName;
  final String kind; // text | image | voice | meeting
  final String body;
  final String? mediaPath;
  final DateTime createdAt;

  const TicketMessage({
    required this.id,
    required this.ticketId,
    required this.senderRole,
    required this.senderName,
    required this.kind,
    required this.body,
    this.mediaPath,
    required this.createdAt,
  });

  factory TicketMessage.fromMap(Map<String, dynamic> m) => TicketMessage(
        id: m['id'] as String,
        ticketId: m['ticket_id'] as String,
        senderRole: m['sender_role'] as String,
        senderName: m['sender_name'] as String? ?? '',
        kind: m['kind'] as String? ?? 'text',
        body: m['body'] as String? ?? '',
        mediaPath: m['media_path'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      );
}

class ClassEvent {
  final String id;
  final String classroomId;
  final String studentName;
  final String kind; // hand | chat
  final int slideIndex;
  final String body;
  final DateTime createdAt;

  const ClassEvent({
    required this.id,
    required this.classroomId,
    required this.studentName,
    required this.kind,
    required this.slideIndex,
    required this.body,
    required this.createdAt,
  });

  factory ClassEvent.fromMap(Map<String, dynamic> m) => ClassEvent(
        id: m['id'] as String,
        classroomId: m['classroom_id'] as String,
        studentName: m['student_name'] as String? ?? 'Student',
        kind: m['kind'] as String,
        slideIndex: (m['slide_index'] as num?)?.toInt() ?? 0,
        body: m['body'] as String? ?? '',
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      );
}

/// "12 Aug, 2:05 PM" style short timestamp without intl.
String shortWhen(DateTime t) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final h24 = t.hour;
  final suffix = h24 >= 12 ? 'PM' : 'AM';
  var h = h24 % 12;
  if (h == 0) h = 12;
  final mm = t.minute.toString().padLeft(2, '0');
  return '${t.day} ${months[t.month - 1]}, $h:$mm $suffix';
}
