import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Small rounded label, e.g. the classroom code chip.
class PillBadge extends StatelessWidget {
  final String label;
  final Color color;
  final Color? textColor;
  final IconData? icon;

  const PillBadge({
    super.key,
    required this.label,
    this.color = const Color(0xFFEFEAE0),
    this.textColor,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final fg = textColor ?? Palette.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Classroom code chip that copies itself on tap.
class CodeChip extends StatelessWidget {
  final String code;
  const CodeChip({super.key, required this.code});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Tap to copy',
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () {
          Clipboard.setData(ClipboardData(text: code));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Classroom code $code copied')),
          );
        },
        child: PillBadge(
          label: code,
          icon: Icons.tag,
          color: const Color(0xFFFDF1DC),
          textColor: const Color(0xFF8A5A13),
        ),
      ),
    );
  }
}

/// Section heading with the small overline style used across dashboards.
class SectionTitle extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const SectionTitle(this.title, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              color: Palette.faint,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Deterministic accent color per subject so a subject keeps its color
/// everywhere in the app.
Color subjectColor(String subject) {
  const palette = [
    Palette.navy,
    Palette.sage,
    Palette.terracotta,
    Color(0xFF7A5C9E),
    Color(0xFF2F6F6D),
    Color(0xFFA9713B),
    Palette.slate,
  ];
  var h = 0;
  for (final c in subject.toLowerCase().codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return palette[h % palette.length];
}

/// Standard error snack.
void showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: Palette.red,
      content: Text(error.toString().replaceFirst('Exception: ', '')),
    ),
  );
}

/// Empty-state placeholder used in lists.
class EmptyNote extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const EmptyNote(
      {super.key, required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Palette.line),
      ),
      child: Column(
        children: [
          Icon(icon, size: 30, color: Palette.faint),
          const SizedBox(height: 10),
          Text(title, style: text.titleMedium),
          const SizedBox(height: 4),
          Text(body, style: text.bodySmall, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
