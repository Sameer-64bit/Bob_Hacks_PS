import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../models/models2.dart';
import '../../services/repository.dart';
import '../../services/repository2.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Student assignments — the list streams straight from Supabase, so a new
/// assignment published by the teacher pops in without any refresh.
class StudentAssignmentsTab extends StatelessWidget {
  final Student student;
  const StudentAssignmentsTab({super.key, required this.student});

  @override
  Widget build(BuildContext context) {
    final classroomId = student.classroomId;
    if (classroomId == null) {
      return const Center(
        child: EmptyNote(
          icon: Icons.assignment_outlined,
          title: 'Not enrolled yet',
          body: 'Join a classroom to receive assignments.',
        ),
      );
    }
    return StreamBuilder<List<Assignment>>(
      stream: repo.streamAssignments(classroomId),
      builder: (context, assignmentSnap) {
        return StreamBuilder<List<Submission>>(
          stream: repo.streamMySubmissions(student.id),
          builder: (context, submissionSnap) {
            if (!assignmentSnap.hasData) {
              return const Center(
                  child: CircularProgressIndicator(color: Palette.navy));
            }
            final assignments = assignmentSnap.data!.reversed.toList();
            final submissions = {
              for (final s in submissionSnap.data ?? <Submission>[])
                s.assignmentId: s,
            };
            if (assignments.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: EmptyNote(
                    icon: Icons.assignment_outlined,
                    title: 'No assignments yet',
                    body:
                        'New assignments from your teachers appear here instantly.',
                  ),
                ),
              );
            }
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: ListView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  children: [
                    Row(
                      children: [
                        const Expanded(child: SectionTitle('Assignments')),
                        PillBadge(
                          label: 'LIVE',
                          icon: Icons.bolt,
                          color: Palette.sage.withValues(alpha: 0.15),
                          textColor: Palette.sage,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    for (final a in assignments) ...[
                      _AssignmentTile(
                        assignment: a,
                        submission: submissions[a.id],
                        student: student,
                      ),
                      const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _AssignmentTile extends StatelessWidget {
  final Assignment assignment;
  final Submission? submission;
  final Student student;

  const _AssignmentTile({
    required this.assignment,
    required this.submission,
    required this.student,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final s = submission;

    final Widget status;
    if (s == null) {
      status = const PillBadge(label: 'Attempt');
    } else if (s.evaluated) {
      status = PillBadge(
        label: '${s.score}/${assignment.maxScore}',
        icon: Icons.grade_outlined,
        color: Palette.sage.withValues(alpha: 0.15),
        textColor: Palette.sage,
      );
    } else {
      status = PillBadge(
        label: 'Submitted',
        color: Palette.navy.withValues(alpha: 0.08),
        textColor: Palette.navy,
      );
    }

    return Material(
      color: Palette.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          builder: (_) => _AssignmentSheet(
              assignment: assignment, submission: s, student: student),
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Palette.line),
          ),
          child: Row(
            children: [
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
              status,
            ],
          ),
        ),
      ),
    );
  }
}

class _AssignmentSheet extends StatefulWidget {
  final Assignment assignment;
  final Submission? submission;
  final Student student;

  const _AssignmentSheet(
      {required this.assignment, required this.submission, required this.student});

  @override
  State<_AssignmentSheet> createState() => _AssignmentSheetState();
}

class _AssignmentSheetState extends State<_AssignmentSheet> {
  late final TextEditingController _answer =
      TextEditingController(text: widget.submission?.content ?? '');
  bool _busy = false;

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_answer.text.trim().isEmpty) {
      showError(context, 'Write your answer first.');
      return;
    }
    setState(() => _busy = true);
    try {
      await repo.submitAssignment(
        assignmentId: widget.assignment.id,
        studentId: widget.student.id,
        content: _answer.text.trim(),
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Submitted! Your teacher can now score it.')));
      }
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
    final a = widget.assignment;
    final s = widget.submission;
    final evaluated = s?.evaluated == true;

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
            Text(a.title, style: text.headlineMedium),
            const SizedBox(height: 4),
            Text(
              a.dueAt == null
                  ? '${a.maxScore} marks'
                  : 'Due ${shortWhen(a.dueAt!)} · ${a.maxScore} marks',
              style: text.bodySmall,
            ),
            if (a.description.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Palette.paper,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(a.description, style: text.bodyLarge),
              ),
            ],
            const SizedBox(height: 16),
            if (evaluated) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Palette.sage.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Score: ${s!.score} / ${a.maxScore}',
                        style: text.titleLarge?.copyWith(color: Palette.sage)),
                    if ((s.feedback ?? '').isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text('“${s.feedback}”', style: text.bodyLarge),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text('Your answer', style: text.titleMedium),
              const SizedBox(height: 6),
              Text(s.content, style: text.bodyLarge),
            ] else ...[
              TextField(
                controller: _answer,
                minLines: 4,
                maxLines: 10,
                decoration: const InputDecoration(
                  labelText: 'Your answer',
                  hintText: 'Type your solution here…',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(s == null ? 'Submit' : 'Update submission'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
