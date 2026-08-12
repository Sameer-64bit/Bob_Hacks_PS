import 'package:flutter/material.dart';

import '../theme.dart';

/// Shown when lib/config.dart hasn't been filled in yet.
class SetupScreen extends StatelessWidget {
  const SetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Almost there', style: text.displayMedium),
                const SizedBox(height: 12),
                Text(
                  'Kaksha needs its Supabase project keys before it can run.',
                  style: text.bodyLarge,
                ),
                const SizedBox(height: 24),
                const _Step(n: '1', body: 'Create a free project at supabase.com'),
                const _Step(
                    n: '2',
                    body:
                        'Open SQL Editor and run the contents of supabase/schema.sql'),
                const _Step(
                    n: '3',
                    body:
                        'Copy the Project URL and anon key from Project Settings → API'),
                const _Step(
                    n: '4',
                    body: 'Paste both values into lib/config.dart and restart'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final String n;
  final String body;
  const _Step({required this.n, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Palette.dark,
              shape: BoxShape.circle,
            ),
            child: Text(n,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(body, style: Theme.of(context).textTheme.bodyLarge),
            ),
          ),
        ],
      ),
    );
  }
}
