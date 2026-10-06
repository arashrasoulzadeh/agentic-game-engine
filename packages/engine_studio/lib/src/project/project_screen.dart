import 'package:flutter/material.dart';

import '../level/level_screen.dart';
import 'studio_project.dart';

/// Lists a project's levels and opens one for editing. The first screen after a
/// project opens, so a designer can choose which level to work on.
class ProjectScreen extends StatelessWidget {
  final StudioProject project;

  const ProjectScreen({super.key, required this.project});

  @override
  Widget build(BuildContext context) {
    final levels = project.levelPaths();
    return Scaffold(
      appBar: AppBar(title: Text(project.root.split('/').last)),
      body: levels.isEmpty
          ? const Center(
              key: Key('no-levels'),
              child: Text('This project has no levels yet.'),
            )
          : ListView(
              children: [
                for (final relative in levels)
                  ListTile(
                    key: Key('level-$relative'),
                    leading: const Icon(Icons.map_outlined),
                    title: Text(relative.split('/').last),
                    subtitle: Text(relative),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => LevelScreen(
                          levelPath: '${project.root}/$relative',
                          projectRoot: project.root,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
