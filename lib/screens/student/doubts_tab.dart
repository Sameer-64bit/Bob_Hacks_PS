import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../models/models2.dart';
import '../../services/repository.dart';
import '../../services/repository2.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../shared/ticket_thread.dart';

/// Student doubts: raise a 1-to-1 ticket and chat with the teacher.
class StudentDoubtsTab extends StatefulWidget {
  final Student student;
  const StudentDoubtsTab({super.key, required this.student});

  @override
  State<StudentDoubtsTab> createState() => _StudentDoubtsTabState();
}

class _StudentDoubtsTabState extends State<StudentDoubtsTab> {
  List<Ticket> _tickets = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await repo.studentTickets(widget.student.id);
      if (!mounted) return;
      setState(() {
        _tickets = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showError(context, e);
    }
  }

  Future<void> _raise() async {
    final classroomId = widget.student.classroomId;
    if (classroomId == null) return;
    final titleController = TextEditingController();
    final messageController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Raise a doubt'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    labelText: 'Topic', hintText: 'e.g. Stuck on recursion'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: messageController,
                minLines: 3,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    labelText: 'Describe your doubt',
                    alignLabelWithHint: true),
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
              child: const Text('Raise ticket')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (titleController.text.trim().isEmpty) {
      showError(context, 'Give your doubt a topic.');
      return;
    }
    try {
      final ticket = await repo.createTicket(
        classroomId: classroomId,
        studentId: widget.student.id,
        studentName: widget.student.name,
        title: titleController.text.trim(),
        firstMessage: messageController.text,
      );
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => TicketThreadScreen(
          ticket: ticket,
          asTeacher: false,
          senderName: widget.student.name,
        ),
      ));
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _raise,
        backgroundColor: Palette.dark,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.live_help_outlined),
        label: const Text('Raise a doubt'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Palette.navy))
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: ListView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  children: [
                    const SectionTitle('Your 1-to-1 doubt sessions'),
                    const SizedBox(height: 10),
                    if (_tickets.isEmpty)
                      const EmptyNote(
                        icon: Icons.live_help_outlined,
                        title: 'No doubts yet',
                        body:
                            'Stuck on something? Raise a doubt and your teacher '
                            'answers you 1-to-1 — with messages, images, voice '
                            'notes or a live video call.',
                      )
                    else
                      for (final ticket in _tickets) ...[
                        Material(
                          color: Palette.card,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => Navigator.of(context)
                                .push(MaterialPageRoute(
                                  builder: (_) => TicketThreadScreen(
                                    ticket: ticket,
                                    asTeacher: false,
                                    senderName: widget.student.name,
                                  ),
                                ))
                                .then((_) => _load()),
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
                                        Text(ticket.title,
                                            style: text.titleMedium),
                                        const SizedBox(height: 2),
                                        Text(shortWhen(ticket.createdAt),
                                            style: text.bodySmall),
                                      ],
                                    ),
                                  ),
                                  PillBadge(
                                    label:
                                        ticket.isOpen ? 'Open' : 'Resolved',
                                    color: ticket.isOpen
                                        ? const Color(0xFFFDF1DC)
                                        : Palette.sage
                                            .withValues(alpha: 0.15),
                                    textColor: ticket.isOpen
                                        ? const Color(0xFF8A5A13)
                                        : Palette.sage,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    const SizedBox(height: 90),
                  ],
                ),
              ),
            ),
    );
  }
}
