// Balance simulator: plays an idle game definition with a greedy strategy and prints when it reaches
// milestones. The same thing as `game_agent idle simulate`, without installing the CLI.
//
//   dart run tool/simulate.dart path/to/game.json [--days 3] [--prestige-at 2.0]
//
// Deterministic: the same definition and options always print the same report.
import 'dart:convert';
import 'dart:io';

import 'package:engine_core/engine_core.dart';
import 'package:engine_idle/engine_idle_logic.dart';

int main(List<String> args) {
  final path = args.where((a) => !a.startsWith('--')).firstOrNull;
  if (path == null) {
    stderr.writeln(
      'usage: dart run tool/simulate.dart <game.json> [--days N] [--prestige-at X]',
    );
    return 64;
  }
  double? option(String name) {
    final i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? double.tryParse(args[i + 1]) : null;
  }

  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('No such file: $path');
    return 66;
  }
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final problems = validateIdleDefinition(json);
  if (problems.isNotEmpty) {
    stderr.writeln('The definition has problems:');
    for (final p in problems) {
      stderr.writeln('  $p');
    }
    return 65;
  }

  final world = World(width: 10, height: 10);
  registerCoreComponents(world);
  final game = loadIdleDefinition(world, json);
  final report = simulateIdle(
    world,
    game.wallet,
    limit: Duration(hours: ((option('--days') ?? 3) * 24).round()),
    prestigeAt: option('--prestige-at'),
  );
  stdout.write(describeSimulation(report));
  return 0;
}
