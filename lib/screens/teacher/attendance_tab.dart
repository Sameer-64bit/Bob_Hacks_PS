import 'package:flutter/material.dart';

import '../../data/branches.dart';
import '../../models/models.dart';
import '../../models/models2.dart';
import '../../services/repository.dart';
import '../../services/repository2.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Teacher view of student attendance per classroom. The attendance rows
/// themselves arrive from an external source (biometric / RFID / manual
/// import) — this screen only reads and summarises them.
class TeacherAttendanceTab extends StatefulWidget {
  final List<Classroom> classrooms;
  const TeacherAttendanceTab({super.key, required this.classrooms});

  @override
  State<TeacherAttendanceTab> createState() => _TeacherAttendanceTabState();
}

class _TeacherAttendanceTabState extends State<TeacherAttendanceTab> {
  Classroom? _classroom;
  List<Student> _students = [];
  List<AttendanceRecord> _records = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.classrooms.isNotEmpty) {
      _classroom = widget.classrooms.first;
      _load();
    }
  }

  Future<void> _load() async {
    final classroom = _classroom;
    if (classroom == null) return;
    setState(() => _loading = true);
    try {
      final students = await repo.classroomStudents(classroom.id);
      final records = await repo.classroomAttendance(classroom.id);
      if (!mounted) return;
      setState(() {
        _students = students;
        _records = records;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showError(context, e);
    }
  }

  ({int present, int total}) _statsFor(String studentId) {
    final mine = _records.where((r) => r.studentId == studentId);
    final present =
        mine.where((r) => r.status == 'present' || r.status == 'late').length;
    return (present: present, total: mine.length);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (widget.classrooms.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: EmptyNote(
            icon: Icons.fact_check_outlined,
            title: 'No classrooms yet',
            body: 'Add classes to your weekly schedule first.',
          ),
        ),
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<Classroom>(
                    // ignore: deprecated_member_use
                    value: _classroom,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Classroom'),
                    items: [
                      for (final c in widget.classrooms)
                        DropdownMenuItem(
                          value: c,
                          child: Text(
                              '${branchByKey(c.branch).short} · ${yearName(c.year)} · ${c.code}',
                              overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (c) {
                      setState(() => _classroom = c);
                      _load();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                    tooltip: 'Refresh',
                    onPressed: _load,
                    icon: const Icon(Icons.refresh)),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Palette.navy.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Attendance is synced from the college attendance system — '
                'this view is read-only.',
                style: text.bodySmall,
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(40),
                child:
                    Center(child: CircularProgressIndicator(color: Palette.navy)),
              )
            else if (_students.isEmpty)
              const EmptyNote(
                icon: Icons.people_outline,
                title: 'No students enrolled',
                body: 'Students appear here once they register for this batch.',
              )
            else
              for (final student in _students) ...[
                _AttendanceRow(student: student, stats: _statsFor(student.id)),
                const SizedBox(height: 10),
              ],
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

class _AttendanceRow extends StatelessWidget {
  final Student student;
  final ({int present, int total}) stats;
  const _AttendanceRow({required this.student, required this.stats});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final hasData = stats.total > 0;
    final ratio = hasData ? stats.present / stats.total : 0.0;
    final percent = (ratio * 100).round();
    final color = !hasData
        ? Palette.faint
        : percent >= 75
            ? Palette.sage
            : percent >= 60
                ? const Color(0xFF8A5A13)
                : Palette.red;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Palette.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Palette.line),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Palette.navy.withValues(alpha: 0.08),
            child: Text(
              student.name.isEmpty ? '?' : student.name[0].toUpperCase(),
              style: const TextStyle(
                  color: Palette.navy, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(student.name, style: text.titleMedium),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: hasData ? ratio : 0,
                    minHeight: 5,
                    backgroundColor: Palette.paper,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                hasData ? '$percent%' : '—',
                style: text.titleMedium?.copyWith(color: color),
              ),
              Text(
                hasData
                    ? '${stats.present}/${stats.total} days'
                    : 'no data yet',
                style: text.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
