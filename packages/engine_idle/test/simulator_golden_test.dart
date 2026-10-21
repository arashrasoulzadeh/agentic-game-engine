import 'dart:convert';
import 'dart:io';

import 'package:engine_core/engine_core.dart';
import 'package:engine_idle/engine_idle_logic.dart';
import 'package:flutter_test/flutter_test.dart';

/// The report as text, one line per milestone. Pinned in `test/golden/` so a change to the economy that
/// shifts the sample game's pacing shows up as a reviewable diff instead of passing silently.
String reportText(SimulationReport r) {
  final b = StringBuffer(
    'elapsed ${r.elapsed.inSeconds}s, ${r.purchases} purchases, stalled ${r.stalled}\n',
  );
  for (final m in r.milestones) {
    b.writeln('${m.at.inSeconds}s ${m.label}');
  }
  for (final e in r.finalIncome.entries) {
    b.writeln('income ${e.key} ${formatBigNumber(e.value)}/s');
  }
  return b.toString();
}

void main() {
  test('the sample game plays out exactly as the golden report says '
      '(rerun with UPDATE_GOLDEN=1 to accept a deliberate change)', () {
    final world = World(width: 10, height: 10);
    registerCoreComponents(world);
    final json =
        jsonDecode(File('example/cookie_clicker.json').readAsStringSync())
            as Map<String, dynamic>;
    final game = loadIdleDefinition(world, json);
    final actual = reportText(
      simulateIdle(
        world,
        game.wallet,
        limit: const Duration(days: 2),
        prestigeAt: 2,
      ),
    );

    final golden = File('test/golden/cookie_clicker_report.txt');
    if (Platform.environment['UPDATE_GOLDEN'] == '1' || !golden.existsSync()) {
      golden.writeAsStringSync(actual);
    }
    expect(actual, golden.readAsStringSync());
  });
}
