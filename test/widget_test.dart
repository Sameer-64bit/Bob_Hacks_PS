import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kaksha/screens/landing.dart';
import 'package:kaksha/screens/setup_screen.dart';
import 'package:kaksha/theme.dart';

Widget _wrap(Widget child) => MaterialApp(theme: buildTheme(), home: child);

void main() {
  testWidgets('landing screen shows all three roles', (tester) async {
    await tester.pumpWidget(_wrap(const LandingScreen()));
    expect(find.text("I'm a student"), findsOneWidget);
    expect(find.text("I'm a teacher"), findsOneWidget);
    expect(find.text('Smart board'), findsOneWidget);
    expect(find.text('Kaksha'), findsOneWidget);
  });

  testWidgets('setup screen lists configuration steps', (tester) async {
    await tester.pumpWidget(_wrap(const SetupScreen()));
    expect(find.text('Almost there'), findsOneWidget);
    expect(find.textContaining('supabase/schema.sql'), findsOneWidget);
    expect(find.textContaining('lib/config.dart'), findsOneWidget);
  });
}
