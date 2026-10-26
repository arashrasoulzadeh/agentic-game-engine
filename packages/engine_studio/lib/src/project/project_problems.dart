import 'dart:convert';
import 'dart:io';

import 'package:engine_core/engine_core.dart';
import 'package:engine_schema/engine_schema.dart';
import 'package:path/path.dart' as p;

import '../graph/graph_editor.dart';
import 'studio_project.dart';

/// One problem found in a project file, from either a level or a graph, so the two
/// can be listed together and a click can open the right file.
class ProjectProblem {
  /// Path relative to the project root.
  final String file;
  final String message;
  final bool isError;

  /// Which kind of file it came from.
  final ProblemSource source;

  /// For level problems, the entity index; for graph problems, -1.
  final int entityIndex;

  /// For graph problems, the offending node id.
  final String? nodeId;

  const ProjectProblem({
    required this.file,
    required this.message,
    required this.isError,
    required this.source,
    this.entityIndex = -1,
    this.nodeId,
  });

  @override
  String toString() => '$file: $message';
}

enum ProblemSource { level, graph }

/// Validates every level and graph in [project] and returns all problems, levels
/// first and each group in path order.
///
/// A file that can't be read or isn't valid JSON is itself reported as an error
/// rather than crashing the scan - the point of the list is to find broken files.
List<ProjectProblem> collectProjectProblems(StudioProject project) {
  final problems = <ProjectProblem>[];
  final validator = LevelValidator.forSchemas(allComponentSchemas);

  for (final relative in project.levelPaths()) {
    final decoded = _decode(project.root, relative);
    if (decoded is String) {
      problems.add(
        ProjectProblem(
          file: relative,
          message: decoded,
          isError: true,
          source: ProblemSource.level,
        ),
      );
      continue;
    }
    // Custom game JSON under assets/levels/ (no entities list) is not an
    // engine LevelDocument — skip rather than reporting a false "missing
    // entities" error for every Mobarez-style wave file.
    if (!Level.looksLikeDocument(decoded)) continue;
    try {
      for (final issue in validator.validate(
        LevelDocument.fromJson(decoded as Map<String, dynamic>),
      )) {
        problems.add(
          ProjectProblem(
            file: relative,
            message: issue.toString(),
            isError: issue.severity == IssueSeverity.error,
            source: ProblemSource.level,
            entityIndex: issue.entityIndex,
          ),
        );
      }
    } on Object catch (e) {
      problems.add(
        ProjectProblem(
          file: relative,
          message: 'not a valid level: $e',
          isError: true,
          source: ProblemSource.level,
        ),
      );
    }
  }

  for (final relative in project.graphPaths()) {
    final decoded = _decode(project.root, relative);
    if (decoded is String) {
      problems.add(
        ProjectProblem(
          file: relative,
          message: decoded,
          isError: true,
          source: ProblemSource.graph,
        ),
      );
      continue;
    }
    try {
      final editor = GraphEditor.fromDocument(
        GraphDocument.fromJson(decoded as Map<String, dynamic>),
      );
      for (final issue in editor.validate()) {
        problems.add(
          ProjectProblem(
            file: relative,
            message: issue.toString(),
            isError: issue.kind != GraphIssueKind.unreachableNode,
            source: ProblemSource.graph,
            nodeId: issue.nodeId,
          ),
        );
      }
    } on Object catch (e) {
      problems.add(
        ProjectProblem(
          file: relative,
          message: 'not a valid graph: $e',
          isError: true,
          source: ProblemSource.graph,
        ),
      );
    }
  }
  return problems;
}

/// The decoded JSON of [relative], or an error message string when it can't be
/// read or parsed.
Object _decode(String root, String relative) {
  try {
    final text = File(p.join(root, relative)).readAsStringSync();
    final json = jsonDecode(text);
    return json is Map<String, dynamic>
        ? json
        : 'the file is not a JSON object';
  } on FormatException catch (e) {
    return 'is not valid JSON (${e.message})';
  } on FileSystemException catch (e) {
    return 'could not be read (${e.message})';
  }
}
