import 'dart:convert';
import 'dart:io';

import 'package:engine_core/engine_core.dart';
import 'package:engine_idle/engine_idle.dart';
import 'package:flutter_test/flutter_test.dart';

BigNumber n(String s) => BigNumber.parse(s);

/// A save written by the first released save format (v1). Keep one fixture per released version and make
/// sure the current build still loads every one: that is the promise that a game update never wipes a
/// player. When the format changes, add `save_v2.json` here from the build that introduces it.
IdleController _fresh() {
  final w = World(width: 10, height: 10);
  registerCoreComponents(w);
  registerIdleComponents(w);
  w.storeOf<BigTreasury>().set(w.spawn(), BigTreasury());
  w.storeOf<IdleModifiers>().set(w.spawn(), IdleModifiers());
  w.storeOf<IdleStats>().set(w.spawn(), IdleStats());
  w.storeOf<Generator>().set(
    w.spawn(),
    Generator(
      id: 'cursor',
      cost: GeometricCost(base: n('10'), growth: 1.1),
      output: {'coins': n('1')},
    ),
  );
  w.addSystem(IdleSystem());
  return IdleController(world: w);
}

void main() {
  final fixtures = Directory('test/fixtures')
      .listSync()
      .whereType<File>()
      .where((f) => RegExp(r'save_v\d+\.json$').hasMatch(f.path))
      .toList();

  test('there is a fixture for every save version up to the current one', () {
    final versions = {
      for (final f in fixtures)
        int.parse(RegExp(r'save_v(\d+)').firstMatch(f.path)!.group(1)!),
    };
    final current = SaveMigrator(currentVersion: 1).currentVersion;
    expect(versions, containsAll([for (var v = 1; v <= current; v++) v]));
  });

  for (final f in fixtures) {
    test('${f.uri.pathSegments.last} still loads with its contents intact', () {
      final store = MemorySaveStore()
        ..value = (jsonDecode(f.readAsStringSync()) as Map)
            .cast<String, dynamic>();
      final c = _fresh();
      final summary = IdleSession(
        controller: c,
        store: store,
        clock: () => DateTime.utc(2026, 1, 1, 15),
      ).load();

      expect(c.world.storeOf<Generator>().denseAt(0).owned, 12);
      expect(c.wallet.of('gems'), n('3'));
      expect(c.world.storeOf<IdleStats>().denseAt(0).prestigeCount, 1);
      expect(summary, isNotNull, reason: 'three hours passed since the save');
      c.stop();
    });
  }
}
