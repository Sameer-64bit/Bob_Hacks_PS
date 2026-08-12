import 'package:flutter/material.dart';

import '../../data/branches.dart';
import '../../models/models.dart';
import '../../services/repository.dart';
import '../../services/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../board/board_screen.dart';
import '../landing.dart';

class TeacherDashboard extends StatefulWidget {
  final Teacher teacher;
  const TeacherDashboard({super.key, required this.teacher});

  @override
  State<TeacherDashboard> createState() => _TeacherDashboardState();
}

class _TeacherDashboardState extends State<TeacherDashboard> {
  List<ScheduleEntry> _schedule = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final schedule = await repo.teacherSchedule(widget.teacher.id);
      if (!mounted) return;
      setState(() {
        _schedule = schedule;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showError(context, e);
    }
  }

  Future<void> _logout() async {
    await SessionStore.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LandingScreen()), (_) => false);
  }

  Future<void> _addSlots() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AddSlotSheet(teacherId: widget.teacher.id),
    );
    if (created == true) _load();
  }

  Future<void> _deleteSlot(ScheduleEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove class?'),
        content: Text(
            '${entry.subject} on ${dayName(entry.dayOfWeek)}, ${entry.timeRange}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Palette.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await repo.deleteScheduleSlot(entry.id);
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Map<String, Classroom> get _classrooms {
    final map = <String, Classroom>{};
    for (final s in _schedule) {
      final c = s.classroom;
      if (c != null) map[c.id] = c;
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final classrooms = _classrooms.values.toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('Prof. ${widget.teacher.name.split(' ').first}'),
        actions: [
          IconButton(
              tooltip: 'Refresh',
              onPressed: _load,
              icon: const Icon(Icons.refresh)),
          IconButton(
              tooltip: 'Sign out',
              onPressed: _logout,
              icon: const Icon(Icons.logout)),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addSlots,
        backgroundColor: Palette.dark,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add class'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Palette.navy))
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: ListView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Palette.terracotta,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.teacher.name,
                              style:
                                  text.titleLarge?.copyWith(color: Colors.white)),
                          const SizedBox(height: 4),
                          Text(
                            'Employee ID ${widget.teacher.employeeId} · '
                            '${_schedule.length} classes / week',
                            style: text.bodyMedium?.copyWith(
                                color: Colors.white.withValues(alpha: 0.8)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (classrooms.isNotEmpty) ...[
                      const SectionTitle('Your classrooms'),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final c in classrooms)
                            _ClassroomChip(
                              classroom: c,
                              onOpenBoard: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          BoardScreen(classroom: c))),
                            ),
                        ],
                      ),
                      const SizedBox(height: 24),
                    ],
                    const SectionTitle('Weekly schedule'),
                    const SizedBox(height: 10),
                    if (_schedule.isEmpty)
                      const EmptyNote(
                        icon: Icons.calendar_month_outlined,
                        title: 'No classes yet',
                        body:
                            'Tap “Add class” to upload your week. Pick the days, '
                            'branch and time — the classroom is created for you '
                            'and students see it instantly.',
                      )
                    else
                      for (var day = 1; day <= 7; day++) ...[
                        if (_schedule.any((s) => s.dayOfWeek == day)) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 8),
                            child: Text(dayName(day), style: text.titleMedium),
                          ),
                          for (final entry in _schedule
                              .where((s) => s.dayOfWeek == day)) ...[
                            _SlotCard(
                                entry: entry,
                                onDelete: () => _deleteSlot(entry)),
                            const SizedBox(height: 8),
                          ],
                        ],
                      ],
                    const SizedBox(height: 90),
                  ],
                ),
              ),
            ),
    );
  }
}

class _ClassroomChip extends StatelessWidget {
  final Classroom classroom;
  final VoidCallback onOpenBoard;
  const _ClassroomChip({required this.classroom, required this.onOpenBoard});

  @override
  Widget build(BuildContext context) {
    final branch = branchByKey(classroom.branch);
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: Palette.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Palette.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${branch.short} · ${yearName(classroom.year)}',
                  style: text.titleMedium),
              const SizedBox(height: 4),
              CodeChip(code: classroom.code),
            ],
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Open smart board',
            onPressed: onOpenBoard,
            icon: const Icon(Icons.draw_outlined, color: Palette.slate),
          ),
        ],
      ),
    );
  }
}

class _SlotCard extends StatelessWidget {
  final ScheduleEntry entry;
  final VoidCallback onDelete;
  const _SlotCard({required this.entry, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final color = subjectColor(entry.subject);
    final classroom = entry.classroom;
    final label = classroom == null
        ? ''
        : '${branchByKey(classroom.branch).short} · ${yearName(classroom.year)}';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Palette.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Palette.line),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 46,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(4)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.subject, style: text.titleMedium),
                const SizedBox(height: 3),
                Text('$label · ${entry.timeRange}', style: text.bodySmall),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, size: 20, color: Palette.faint),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add-slot sheet: multi-day selection creates one slot per chosen day.
// ---------------------------------------------------------------------------

class _AddSlotSheet extends StatefulWidget {
  final String teacherId;
  const _AddSlotSheet({required this.teacherId});

  @override
  State<_AddSlotSheet> createState() => _AddSlotSheetState();
}

class _AddSlotSheetState extends State<_AddSlotSheet> {
  final _subject = TextEditingController();
  Branch _branch = kBranches.first;
  int _year = 1;
  final Set<int> _days = {};
  TimeOfDay _start = const TimeOfDay(hour: 14, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 15, minute: 0);
  bool _busy = false;

  @override
  void dispose() {
    _subject.dispose();
    super.dispose();
  }

  int _minutes(TimeOfDay t) => t.hour * 60 + t.minute;

  Future<void> _pickTime(bool start) async {
    final initial = start ? _start : _end;
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = picked;
        if (_minutes(_end) <= _minutes(_start)) {
          _end = TimeOfDay(hour: (picked.hour + 1) % 24, minute: picked.minute);
        }
      } else {
        _end = picked;
      }
    });
  }

  Future<void> _save() async {
    if (_subject.text.trim().isEmpty) {
      showError(context, 'Enter a subject name.');
      return;
    }
    if (_days.isEmpty) {
      showError(context, 'Pick at least one day.');
      return;
    }
    if (_minutes(_end) <= _minutes(_start)) {
      showError(context, 'End time must be after start time.');
      return;
    }
    setState(() => _busy = true);
    try {
      for (final day in _days.toList()..sort()) {
        await repo.addScheduleSlot(
          teacherId: widget.teacherId,
          branchKey: _branch.key,
          year: _year,
          subject: _subject.text.trim(),
          dayOfWeek: day,
          startMinutes: _minutes(_start),
          endMinutes: _minutes(_end),
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final years = List.generate(_branch.years, (i) => i + 1);
    const dayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 26,
        bottom: MediaQuery.of(context).viewInsets.bottom + 30,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add a class', style: text.headlineMedium),
            const SizedBox(height: 6),
            Text(
              'One entry can repeat on several days — pick them all below.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _subject,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'Subject', hintText: 'e.g. Data Structures'),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<Branch>(
                    initialValue: _branch,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Branch'),
                    items: [
                      for (final b in kBranches)
                        DropdownMenuItem(
                            value: b,
                            child: Text('${b.short} — ${b.name.split('— ').last}',
                                overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (b) => setState(() {
                      _branch = b!;
                      if (_year > _branch.years) _year = 1;
                    }),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<int>(
                    initialValue: _year,
                    decoration: const InputDecoration(labelText: 'Year'),
                    items: [
                      for (final y in years)
                        DropdownMenuItem(value: y, child: Text(yearName(y))),
                    ],
                    onChanged: (y) => setState(() => _year = y!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text('Days', style: text.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var d = 1; d <= 7; d++)
                  FilterChip(
                    label: Text(dayShort[d - 1]),
                    selected: _days.contains(d),
                    onSelected: (sel) => setState(() {
                      sel ? _days.add(d) : _days.remove(d);
                    }),
                    selectedColor: Palette.dark,
                    checkmarkColor: Colors.white,
                    labelStyle: TextStyle(
                      color: _days.contains(d) ? Colors.white : Palette.body,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    backgroundColor: Palette.paper,
                    side: const BorderSide(color: Palette.line),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _TimeField(
                      label: 'Starts',
                      value: _start,
                      onTap: () => _pickTime(true)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _TimeField(
                      label: 'Ends', value: _end, onTap: () => _pickTime(false)),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(_days.isEmpty
                        ? 'Add to schedule'
                        : 'Add ${_days.length} ${_days.length == 1 ? 'class' : 'classes'} to schedule'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  final String label;
  final TimeOfDay value;
  final VoidCallback onTap;
  const _TimeField(
      {required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.schedule, size: 18, color: Palette.faint),
        ),
        child: Text(
          value.format(context),
          style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w600, color: Palette.dark),
        ),
      ),
    );
  }
}
