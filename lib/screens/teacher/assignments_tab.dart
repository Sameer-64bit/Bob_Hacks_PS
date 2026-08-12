import 'package:flutter/material.dart';

import '../../data/branches.dart';
import '../../models/models.dart';
import '../../models/models2.dart';
import '../../services/repository.dart';
import '../../services/repository2.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Teacher view: create assignments per classroom, see who attempted,
/// open each submission and score it.
class TeacherAssignmentsTab extends StatefulWidget {
  final Teacher teacher;
  final List<Classroom> classrooms;

  const TeacherAssignmentsTab(
      {super.key, required this.teacher, required this.classrooms});

  @override
  State<TeacherAssignmentsTab> createState() => _TeacherAssignmentsTabState();
}

class _TeacherAssignmentsTabState extends State<TeacherAssignmentsTab> {
  Classroom? _classroom;
  List<Assignment> _assignments = [];
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
      final list = await repo.classroomAssignments(classroom.id);
      if (!mounted) return;
      setState(() {
        _assignments = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showError(context, e);
    }
  }

  Future<void> _create() async {
    final classroom = _classroom;
    if (classroom == null) return;
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) =>
          _NewAssignmentSheet(teacherId: widget.teacher.id, classroom: classroom),
    );
    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.classrooms.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: EmptyNote(
            icon: Icons.assignment_outlined,
            title: 'No classrooms yet',
            body:
                'Add classes to your weekly schedule first — assignments are given per classroom.',
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
                Expanded(child: _ClassroomDropdown(
                  classrooms: widget.classrooms,
                  value: _classroom,
                  onChanged: (c) {
                    setState(() => _classroom = c);
                    _load();
                  },
                )),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: _create,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(40),
                child:
                    Center(child: CircularProgressIndicator(color: Palette.navy)),
              )
            else if (_assignments.isEmpty)
              const EmptyNote(
                icon: Icons.assignment_outlined,
                title: 'No assignments yet',
                body:
                    'Create one — students in this classroom see it instantly, no refresh needed.',
              )
            else
              for (final a in _assignments) ...[
                _AssignmentCard(
                  assignment: a,
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(
                          builder: (_) => SubmissionsScreen(assignment: a)))
                      .then((_) => _load()),
                  onDelete: () async {
                    try {
                      await repo.deleteAssignment(a.id);
                      _load();
                    } catch (e) {
                      if (context.mounted) showError(context, e);
                    }
                  },
                ),
                const SizedBox(height: 10),
              ],
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

class _ClassroomDropdown extends StatelessWidget {
  final List<Classroom> classrooms;
  final Classroom? value;
  final ValueChanged<Classroom> onChanged;

  const _ClassroomDropdown(
      {required this.classrooms, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<Classroom>(
      // ignore: deprecated_member_use
      value: value,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Classroom'),
      items: [
        for (final c in classrooms)
          DropdownMenuItem(
            value: c,
            child: Text(
                '${branchByKey(c.branch).short} · ${yearName(c.year)} · ${c.code}',
                overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (c) => c == null ? null : onChanged(c),
    );
  }
}

class _AssignmentCard extends StatelessWidget {
  final Assignment assignment;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _AssignmentCard(
      {required this.assignment, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Material(
      color: Palette.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Palette.line),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Palette.navy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.assignment_outlined,
                    color: Palette.navy, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(assignment.title, style: text.titleMedium),
                    const SizedBox(height: 3),
                    Text(
                      assignment.dueAt == null
                          ? 'No due date · ${assignment.maxScore} marks'
                          : 'Due ${shortWhen(assignment.dueAt!)} · ${assignment.maxScore} marks',
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Delete',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline,
                    size: 20, color: Palette.faint),
              ),
              const Icon(Icons.chevron_right, color: Palette.faint),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Create sheet
// ---------------------------------------------------------------------------

class _NewAssignmentSheet extends StatefulWidget {
  final String teacherId;
  final Classroom classroom;
  const _NewAssignmentSheet({required this.teacherId, required this.classroom});

  @override
  State<_NewAssignmentSheet> createState() => _NewAssignmentSheetState();
}

class _NewAssignmentSheetState extends State<_NewAssignmentSheet> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _maxScore = TextEditingController(text: '100');
  DateTime? _dueAt;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _maxScore.dispose();
    super.dispose();
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
        context: context, initialTime: const TimeOfDay(hour: 23, minute: 59));
    if (time == null) return;
    setState(() =>
        _dueAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      showError(context, 'Give the assignment a title.');
      return;
    }
    setState(() => _busy = true);
    try {
      await repo.createAssignment(
        classroomId: widget.classroom.id,
        teacherId: widget.teacherId,
        title: _title.text.trim(),
        description: _description.text.trim(),
        dueAt: _dueAt,
        maxScore: int.tryParse(_maxScore.text.trim()) ?? 100,
      );
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
            Text('New assignment', style: text.headlineMedium),
            const SizedBox(height: 6),
            Text(
              'For ${branchByKey(widget.classroom.branch).short} · ${yearName(widget.classroom.year)} — students see it live.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'Title', hintText: 'e.g. Linked List problems'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _description,
              minLines: 3,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'Instructions',
                  hintText: 'What should students do?'),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _pickDue,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Due (optional)',
                        suffixIcon: Icon(Icons.event, size: 18),
                      ),
                      child: Text(
                        _dueAt == null ? 'No due date' : shortWhen(_dueAt!),
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _maxScore,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Max marks'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
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
                    : const Text('Publish assignment'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Submissions + grading
// ---------------------------------------------------------------------------

class SubmissionsScreen extends StatefulWidget {
  final Assignment assignment;
  const SubmissionsScreen({super.key, required this.assignment});

  @override
  State<SubmissionsScreen> createState() => _SubmissionsScreenState();
}

class _SubmissionsScreenState extends State<SubmissionsScreen> {
  List<Submission> _submissions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await repo.assignmentSubmissions(widget.assignment.id);
      if (!mounted) return;
      setState(() {
        _submissions = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showError(context, e);
    }
  }

  Future<void> _grade(Submission s) async {
    final scoreController =
        TextEditingController(text: s.score?.toString() ?? '');
    final feedbackController = TextEditingController(text: s.feedback ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(s.studentName ?? 'Submission'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 220),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Palette.paper,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SingleChildScrollView(
                  child: Text(s.content.isEmpty ? '(empty answer)' : s.content),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: scoreController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                    labelText: 'Score out of ${widget.assignment.maxScore}'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: feedbackController,
                minLines: 2,
                maxLines: 4,
                decoration:
                    const InputDecoration(labelText: 'Feedback (optional)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Save score')),
        ],
      ),
    );
    if (saved != true) return;
    final score = int.tryParse(scoreController.text.trim());
    if (score == null) {
      if (mounted) showError(context, 'Enter a numeric score.');
      return;
    }
    try {
      await repo.gradeSubmission(
        submissionId: s.id,
        score: score.clamp(0, widget.assignment.maxScore),
        feedback: feedbackController.text.trim().isEmpty
            ? null
            : feedbackController.text.trim(),
      );
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final attempted = _submissions.length;
    final graded = _submissions.where((s) => s.evaluated).length;

    return Scaffold(
      appBar: AppBar(title: Text(widget.assignment.title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Palette.navy))
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: ListView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  children: [
                    Row(
                      children: [
                        PillBadge(
                            label: '$attempted attempted',
                            icon: Icons.people_outline),
                        const SizedBox(width: 8),
                        PillBadge(
                          label: '$graded scored',
                          icon: Icons.grading,
                          color: Palette.sage.withValues(alpha: 0.15),
                          textColor: Palette.sage,
                        ),
                        const Spacer(),
                        IconButton(
                            tooltip: 'Refresh',
                            onPressed: _load,
                            icon: const Icon(Icons.refresh)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (_submissions.isEmpty)
                      const EmptyNote(
                        icon: Icons.hourglass_empty,
                        title: 'No attempts yet',
                        body:
                            'Submissions appear here as soon as students attempt the assignment.',
                      )
                    else
                      for (final s in _submissions) ...[
                        Material(
                          color: Palette.card,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => _grade(s),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Palette.line),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(s.studentName ?? 'Student',
                                            style: text.titleMedium),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${s.studentRoll ?? ''} · submitted ${shortWhen(s.submittedAt)}',
                                          style: text.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  s.evaluated
                                      ? PillBadge(
                                          label:
                                              '${s.score}/${widget.assignment.maxScore}',
                                          color: Palette.sage
                                              .withValues(alpha: 0.15),
                                          textColor: Palette.sage,
                                        )
                                      : const PillBadge(label: 'Score it'),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                  ],
                ),
              ),
            ),
    );
  }
}
