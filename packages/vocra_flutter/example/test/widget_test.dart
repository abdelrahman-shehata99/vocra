import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocra_flutter/vocra_flutter.dart';

import 'package:vocra_flutter_example/key_entry_screen.dart';

/// In-memory [KeyStore] so widget tests never touch the real secure-storage
/// platform channel (which has no mock in the test environment).
class _FakeKeyStore implements KeyStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String name) async => _values[name];

  @override
  Future<void> write(String name, String value) async => _values[name] = value;

  @override
  Future<void> delete(String name) async => _values.remove(name);
}

void main() {
  testWidgets('renders the key-entry screen with Groq/Deepgram fields', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: KeyEntryScreen(keyStore: _FakeKeyStore())),
    );
    await tester.pump();

    expect(find.text('Groq API key'), findsOneWidget);
    expect(find.text('Deepgram API key'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Start conversation'),
      findsOneWidget,
    );
  });

  testWidgets('shows a validation message when starting without keys', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: KeyEntryScreen(keyStore: _FakeKeyStore())),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Start conversation'));
    await tester.pump();

    expect(find.text('Enter both a Groq and a Deepgram key.'), findsOneWidget);
  });
}
