import 'package:flutter/material.dart';

import '../../data/branches.dart';
import '../../models/models.dart';
import '../../models/models2.dart';
import '../../services/repository.dart';
import '../../services/repository2.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../shared/ticket_thread.dart';

/// Teacher view of student doubt tickets, grouped per classroom.
class TeacherDoubtsTab extends StatefulWidget {
  final Teacher teacher;
  final List<Classroom> classrooms;

  const TeacherDoubtsTab(
      {super.key, required this.teacher, required this.classrooms});

  @override
  State<TeacherDoubtsTab> createState() => _TeacherDoubtsTabState();
}

class _TeacherDoubtsTabState extends State<TeacherDoubtsTab> {
  Classroom? _classroom;
  List<Ticket> _tickets = [];
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
      final list = await repo.classroomTickets(classroom.id);
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

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (widget.classrooms.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: EmptyNote(
            icon: Icons.help_outline,
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
            const SizedBox(height: 18),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(40),
                child:
                    Center(child: CircularProgressIndicator(color: Palette.navy)),
              )
            else if (_tickets.isEmpty)
              const EmptyNote(
                icon: Icons.mark_chat_read_outlined,
                title: 'No doubts raised',
                body:
                    'When a student raises a doubt in this classroom, the 1-to-1 thread appears here.',
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
                            asTeacher: true,
                            senderName: widget.teacher.name,
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
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: (ticket.isOpen
                                      ? Palette.marigold
                                      : Palette.sage)
                                  .withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              ticket.isOpen
                                  ? Icons.help_outline
                                  : Icons.check_circle_outline,
                              color: ticket.isOpen
                                  ? const Color(0xFF8A5A13)
                                  : Palette.sage,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(ticket.title, style: text.titleMedium),
                                const SizedBox(height: 2),
                                Text(
                                  '${ticket.studentName ?? 'Student'} · ${shortWhen(ticket.createdAt)}',
                                  style: text.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          PillBadge(
                            label: ticket.isOpen ? 'Open' : 'Resolved',
                            color: ticket.isOpen
                                ? const Color(0xFFFDF1DC)
                                : Palette.sage.withValues(alpha: 0.15),
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
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}
