import 'package:flutter/material.dart';

import '../data/languages.dart';
import '../theme.dart';

/// Bottom sheet to pick the user's default language. Returns the code.
Future<String?> showLanguagePicker(BuildContext context, String current) {
  return showModalBottomSheet<String>(
    context: context,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Default language',
                    style: Theme.of(ctx).textTheme.headlineMedium),
                const SizedBox(height: 4),
                Text(
                  'Slide translations and descriptions use this language.',
                  style: Theme.of(ctx).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final lang in kLanguages)
                  ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 24),
                    leading: Icon(
                      lang.code == current
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: lang.code == current
                          ? Palette.navy
                          : Palette.faint,
                      size: 20,
                    ),
                    title: Text('${lang.native}  ·  ${lang.name}'),
                    onTap: () => Navigator.of(ctx).pop(lang.code),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
}
