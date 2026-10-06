import 'package:flutter/material.dart';

import 'src/project/project_open_screen.dart';

void main() {
  runApp(const EngineStudioApp());
}

/// Root of the level editor. Screens (project open, level view) are added in
/// later phase 3 items; this is the shell they mount into.
class EngineStudioApp extends StatelessWidget {
  const EngineStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Engine Studio',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: ProjectOpenScreen(onOpened: ProjectOpenScreen.openProject),
    );
  }
}
