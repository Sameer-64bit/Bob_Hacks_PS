import 'package:flutter/material.dart';

import '../theme.dart';
import 'board/board_join.dart';
import 'student/student_register.dart';
import 'teacher/teacher_register.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Palette.dark,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text('क',
                            style: TextStyle(
                                color: Color(0xFFE8A33D),
                                fontSize: 24,
                                fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Kaksha', style: text.headlineMedium),
                          Text('CSJM University · Kanpur',
                              style: text.bodySmall),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 44),
                  Text('One classroom,\nevery screen.',
                      style: text.displayLarge),
                  const SizedBox(height: 12),
                  Text(
                    'Timetables that build themselves, and a smart board that '
                    'joins the class with a single code.',
                    style: text.bodyLarge,
                  ),
                  const SizedBox(height: 36),
                  _RoleCard(
                    color: Palette.sage,
                    icon: Icons.school_outlined,
                    title: "I'm a student",
                    subtitle:
                        'Register with your roll number and see your week on a calendar.',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const StudentRegisterScreen())),
                  ),
                  const SizedBox(height: 14),
                  _RoleCard(
                    color: Palette.terracotta,
                    icon: Icons.co_present_outlined,
                    title: "I'm a teacher",
                    subtitle:
                        'Upload your weekly schedule — classrooms are created for you.',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const TeacherRegisterScreen())),
                  ),
                  const SizedBox(height: 14),
                  _RoleCard(
                    color: Palette.slate,
                    icon: Icons.draw_outlined,
                    title: 'Smart board',
                    subtitle:
                        'Enter a classroom code and start teaching on the big screen.',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const BoardJoinScreen())),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _RoleCard({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Material(
      color: Palette.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Palette.line),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: text.titleLarge),
                    const SizedBox(height: 3),
                    Text(subtitle, style: text.bodyMedium),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward, size: 20, color: Palette.faint),
            ],
          ),
        ),
      ),
    );
  }
}
