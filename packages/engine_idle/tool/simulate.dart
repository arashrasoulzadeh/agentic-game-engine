// Balance simulator: plays an idle game definition with a greedy strategy and prints when it reaches
// milestones.
//
//   dart run tool/simulate.dart path/to/game.json [--days 3] [--prestige-at 2.0]
//
// Deterministic: the same definition and options always print the same report.
import 'dart:convert';
import 'dart:io';

import 'package:engine_core/engine_core.dart';
import 'package:engine_idle/engine_idle_logic.dart';

String _fmt(Duration d) {
  final days = d.inDays,
      h = d.inHours % 24,
      m = d.inMinutes % 60,
      s = d.inSeconds % 60;
  return [
    if (days > 0) '${days}d',
    if (days > 0 || h > 0) '${h}h',
    if (d.inHours < 24) '${m}m',
    if (d.inMinutes < 10) '${s}s',
  ].join(' ');
}

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

  stdout.writeln(
    'Simulated ${_fmt(report.elapsed)}, ${report.purchases} purchases'
    '${report.stalled ? ' (stalled: ${report.stallReason})' : ''}.',
  );
  for (final m in report.milestones) {
    stdout.writeln('  ${_fmt(m.at).padRight(10)} ${m.label}');
  }
  stdout.writeln('Final income:');
  for (final e in report.finalIncome.entries) {
    stdout.writeln('  ${formatBigNumber(e.value)} ${e.key}/s');
  }
  return 0;
}
