import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../data/branches.dart';
import '../../data/languages.dart';
import '../../models/models.dart';
import '../../services/repository.dart';
import '../../services/repository2.dart';
import '../../services/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/language_picker.dart';
import '../board/live_board_view.dart';
import '../landing.dart';
import 'assignments_tab.dart';
import 'doubts_tab.dart';

class StudentDashboard extends StatefulWidget {
  final Student student;
  const StudentDashboard({super.key, required this.student});

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> {
  Classroom? _classroom;
  List<ScheduleEntry> _schedule = [];
  bool _loading = true;
  String? _error;
  int _tab = 0;
  String _language = 'en';

  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final classroomId = widget.student.classroomId;
      if (classroomId == null) {
        setState(() {
          _loading = false;
          _error = 'You are not enrolled in a classroom yet.';
        });
        return;
      }
      final classroom = await repo.classroomById(classroomId);
      final schedule = await repo.classroomSchedule(classroomId);
      String language = _language;
      try {
        language = await repo.languageOf(isTeacher: false, id: widget.student.id);
      } catch (_) {
        // language column arrives with schema_v2 — fall back quietly
      }
      if (!mounted) return;
      setState(() {
        _classroom = classroom;
        _schedule = schedule;
        _language = language;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your classes. Pull to retry.';
      });
    }
  }

  Future<void> _pickLanguage() async {
    final code = await showLanguagePicker(context, _language);
    if (code == null || code == _language) return;
    setState(() => _language = code);
    try {
      await repo.setLanguage(
          isTeacher: false, id: widget.student.id, code: code);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  List<ScheduleEntry> _classesOn(DateTime day) {
    final list =
        _schedule.where((s) => s.dayOfWeek == day.weekday).toList()
          ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    return list;
  }

  Future<void> _logout() async {
    await SessionStore.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LandingScreen()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Hi, ${widget.student.name.split(' ').first}'),
        actions: [
          IconButton(
            tooltip: 'Language · ${languageByCode(_language).native}',
            onPressed: _pickLanguage,
            icon: const Icon(Icons.translate),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
          const SizedBox(width: 8),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: Palette.card,
        indicatorColor: Palette.marigold.withValues(alpha: 0.25),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined), label: 'Calendar'),
          NavigationDestination(
              icon: Icon(Icons.assignment_outlined), label: 'Assignments'),
          NavigationDestination(
              icon: Icon(Icons.live_help_outlined), label: 'Doubts'),
        ],
      ),
      body: switch (_tab) {
        1 => StudentAssignmentsTab(student: widget.student),
        2 => StudentDoubtsTab(student: widget.student),
        _ => _buildCalendarTab(),
      },
    );
  }

  Widget _buildCalendarTab() {
    final text = Theme.of(context).textTheme;
    final branch = branchByKey(widget.student.branch);
    final dayClasses = _classesOn(_selectedDay);

    return _loading
          ? const Center(child: CircularProgressIndicator(color: Palette.navy))
          : RefreshIndicator(
              color: Palette.navy,
              onRefresh: _load,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    children: [
                      _HeaderCard(
                        branchName: branch.name,
                        year: yearName(widget.student.year),
                        rollNo: widget.student.rollNo,
                        classroom: _classroom,
                        onOpenBoard: _classroom == null
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) => LiveBoardView(
                                        classroom: _classroom!,
                                        student: widget.student))),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        EmptyNote(
                            icon: Icons.wifi_off,
                            title: 'Something went wrong',
                            body: _error!),
                      ],
                      const SizedBox(height: 24),
                      const SectionTitle('Your calendar'),
                      const SizedBox(height: 10),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: _buildCalendar(),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SectionTitle(
                        _titleForDay(_selectedDay),
                        trailing: dayClasses.isEmpty
                            ? null
                            : PillBadge(
                                label:
                                    '${dayClasses.length} ${dayClasses.length == 1 ? 'class' : 'classes'}'),
                      ),
                      const SizedBox(height: 10),
                      if (dayClasses.isEmpty)
                        EmptyNote(
                          icon: Icons.beach_access_outlined,
                          title: 'No classes',
                          body: _schedule.isEmpty
                              ? 'Your timetable appears here once a teacher uploads their schedule.'
                              : 'Nothing scheduled for this day.',
                        )
                      else
                        for (final entry in dayClasses) ...[
                          _ClassCard(
                              entry: entry,
                              onTap: () => _showClassSheet(entry)),
                          const SizedBox(height: 10),
                        ],
                      const SizedBox(height: 12),
                      if (_schedule.isNotEmpty)
                        Text(
                          'You have ${_schedule.length} classes a week from '
                          '${_teacherCount()} ${_teacherCount() == 1 ? 'teacher' : 'teachers'}.',
                          style: text.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            );
  }

  int _teacherCount() => _schedule.map((s) => s.teacherId).toSet().length;

  String _titleForDay(DateTime day) {
    final now = DateTime.now();
    if (isSameDay(day, now)) return 'Today';
    if (isSameDay(day, now.add(const Duration(days: 1)))) return 'Tomorrow';
    return '${dayName(day.weekday)}, ${day.day}/${day.month}';
  }

  Widget _buildCalendar() {
    return TableCalendar<ScheduleEntry>(
      firstDay: DateTime.now().subtract(const Duration(days: 365)),
      lastDay: DateTime.now().add(const Duration(days: 365)),
      focusedDay: _focusedDay,
      selectedDayPredicate: (d) => isSameDay(d, _selectedDay),
      onDaySelected: (selected, focused) => setState(() {
        _selectedDay = selected;
        _focusedDay = focused;
      }),
      eventLoader: _classesOn,
      startingDayOfWeek: StartingDayOfWeek.monday,
      availableCalendarFormats: const {CalendarFormat.month: 'Month'},
      headerStyle: const HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
        titleTextStyle: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w600, color: Palette.dark),
        leftChevronIcon: Icon(Icons.chevron_left, color: Palette.faint),
        rightChevronIcon: Icon(Icons.chevron_right, color: Palette.faint),
      ),
      daysOfWeekStyle: const DaysOfWeekStyle(
        weekdayStyle: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600, color: Palette.faint),
        weekendStyle: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600, color: Palette.terracotta),
      ),
      calendarStyle: CalendarStyle(
        outsideDaysVisible: false,
        defaultTextStyle: const TextStyle(color: Palette.body, fontSize: 14),
        weekendTextStyle:
            const TextStyle(color: Palette.terracotta, fontSize: 14),
        todayDecoration: BoxDecoration(
          color: Palette.marigold.withValues(alpha: 0.25),
          shape: BoxShape.circle,
        ),
        todayTextStyle: const TextStyle(
            color: Palette.dark, fontWeight: FontWeight.w700, fontSize: 14),
        selectedDecoration:
            const BoxDecoration(color: Palette.navy, shape: BoxShape.circle),
        selectedTextStyle:
            const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        markersMaxCount: 3,
        markerDecoration:
            const BoxDecoration(color: Palette.sage, shape: BoxShape.circle),
        markerSize: 5,
        markerMargin: const EdgeInsets.symmetric(horizontal: 1.2),
      ),
    );
  }

  void _showClassSheet(ScheduleEntry entry) {
    final text = Theme.of(context).textTheme;
    final color = subjectColor(entry.subject);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.menu_book_outlined, color: color, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.subject, style: text.titleLarge),
                      Text('${dayName(entry.dayOfWeek)} · ${entry.timeRange}',
                          style: text.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Icon(Icons.person_outline, size: 18, color: Palette.faint),
                const SizedBox(width: 8),
                Text(
                  entry.teacherName == null
                      ? 'Teacher'
                      : 'Taught by ${entry.teacherName}',
                  style: text.bodyLarge,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.repeat, size: 18, color: Palette.faint),
                const SizedBox(width: 8),
                Text('Every ${dayName(entry.dayOfWeek)}', style: text.bodyLarge),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Palette.paper,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Class notes, attendance and materials arrive here in the next '
                'update.',
                style: text.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final String branchName;
  final String year;
  final String rollNo;
  final Classroom? classroom;
  final VoidCallback? onOpenBoard;

  const _HeaderCard({
    required this.branchName,
    required this.year,
    required this.rollNo,
    required this.classroom,
    required this.onOpenBoard,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Palette.navy,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            branchName,
            style: text.titleLarge?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            '$year · Roll no. $rollNo',
            style: text.bodyMedium
                ?.copyWith(color: Colors.white.withValues(alpha: 0.75)),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (classroom != null) CodeChip(code: classroom!.code),
              const Spacer(),
              if (onOpenBoard != null)
                TextButton.icon(
                  onPressed: onOpenBoard,
                  style: TextButton.styleFrom(
                    foregroundColor: Palette.marigold,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  icon: const Icon(Icons.draw_outlined, size: 18),
                  label: const Text('Watch live'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ClassCard extends StatelessWidget {
  final ScheduleEntry entry;
  final VoidCallback onTap;
  const _ClassCard({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final color = subjectColor(entry.subject);
    return Material(
      color: Palette.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Palette.line),
          ),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 46,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.subject, style: text.titleMedium),
                    const SizedBox(height: 3),
                    Text(
                      entry.teacherName == null
                          ? entry.timeRange
                          : '${entry.teacherName} · ${entry.timeRange}',
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Palette.faint),
            ],
          ),
        ),
      ),
    );
  }
}
