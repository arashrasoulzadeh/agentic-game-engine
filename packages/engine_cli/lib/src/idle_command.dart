import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:engine_core/engine_core.dart';
import 'package:engine_core/engine_core_idle.dart';

/// `game_agent idle ...`: tools for idle / incremental games.
class IdleCommand extends Command<int> {
  IdleCommand({StringSink? out}) {
    addSubcommand(SimulateCommand(out: out));
    addSubcommand(ValidateIdleCommand(out: out));
  }

  @override
  final name = 'idle';
  @override
  final description = 'Tools for idle / incremental games.';
}

/// Plays an idle game definition with a deterministic greedy strategy and prints when it reaches
/// milestones, so cost curves can be tuned without playing.
class SimulateCommand extends Command<int> {
  SimulateCommand({StringSink? out}) : _out = out {
    argParser
      ..addOption(
        'days',
        defaultsTo: '3',
        help: 'How much game time to simulate.',
      )
      ..addOption(
        'prestige-at',
        help:
            'Prestige as soon as it would give this many times what is held (for example 2). '
            'Omit to never prestige.',
      );
  }

  final StringSink? _out;

  @override
  final name = 'simulate';
  @override
  final description =
      'Simulate an idle game definition (JSON) and report its pacing.';
  @override
  final invocation =
      'game_agent idle simulate <game.json> [--days N] [--prestige-at X]';

  @override
  Future<int> run() async {
    final args = argResults!;
    if (args.rest.isEmpty) usageException('Missing the game definition file.');
    final days = double.tryParse(args['days'] as String);
    if (days == null || days <= 0)
      usageException('--days must be a positive number.');
    final prestigeText = args['prestige-at'] as String?;
    final prestigeAt = prestigeText == null
        ? null
        : double.tryParse(prestigeText);
    if (prestigeText != null && prestigeAt == null) {
      usageException('--prestige-at must be a number.');
    }

    final file = File(args.rest.first);
    if (!file.existsSync()) {
      stderr.writeln('Error: ${file.path} does not exist.');
      return 1;
    }
    final Map<String, dynamic> json;
    try {
      json = (jsonDecode(file.readAsStringSync()) as Map)
          .cast<String, dynamic>();
    } on Object catch (e) {
      stderr.writeln('Error: ${file.path} is not a valid JSON object: $e');
      return 1;
    }
    final problems = validateIdleDefinition(json);
    if (problems.isNotEmpty) {
      stderr.writeln('${file.path} has problems:');
      for (final p in problems) {
        stderr.writeln('  $p');
      }
      return 1;
    }

    final world = World(width: 10, height: 10);
    registerCoreComponents(world);
    final game = loadIdleDefinition(world, json);
    final report = simulateIdle(
      world,
      game.wallet,
      limit: Duration(hours: (days * 24).round()),
      prestigeAt: prestigeAt,
    );
    (_out ?? stdout).write(describeSimulation(report));
    return 0;
  }
}

/// Checks an idle game definition and lists every problem with the path to it, without running anything.
/// Exits 0 when valid, 1 otherwise: the check an agent or CI runs after editing the JSON.
class ValidateIdleCommand extends Command<int> {
  ValidateIdleCommand({StringSink? out}) : _out = out;

  final StringSink? _out;

  @override
  final name = 'validate';
  @override
  final description =
      'Validate an idle game definition (JSON) and list every problem.';
  @override
  final invocation = 'game_agent idle validate <game.json>';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) usageException('Missing the game definition file.');
    final file = File(rest.first);
    if (!file.existsSync()) {
      stderr.writeln('Error: ${file.path} does not exist.');
      return 1;
    }
    final Map<String, dynamic> json;
    try {
      json = (jsonDecode(file.readAsStringSync()) as Map)
          .cast<String, dynamic>();
    } on Object catch (e) {
      stderr.writeln('Error: ${file.path} is not a valid JSON object: $e');
      return 1;
    }
    final problems = validateIdleDefinition(json);
    final out = _out ?? stdout;
    if (problems.isEmpty) {
      final generators = (json['generators'] as List?)?.length ?? 0;
      final upgrades = (json['upgrades'] as List?)?.length ?? 0;
      out.writeln(
        '${file.path}: OK ($generators generators, $upgrades upgrades)',
      );
      return 0;
    }
    for (final p in problems) {
      out.writeln('${file.path}: $p');
    }
    return 1;
  }
}
