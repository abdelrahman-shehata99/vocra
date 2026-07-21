import 'package:flutter/material.dart';

import 'key_entry_screen.dart';

void main() {
  runApp(const VoiceDemoApp());
}

class VoiceDemoApp extends StatelessWidget {
  const VoiceDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vocra SDK Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: KeyEntryScreen(),
    );
  }
}
