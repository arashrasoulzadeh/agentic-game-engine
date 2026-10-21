// The samples in docs/concepts/idle-games.md, executed so the guide cannot drift.
import 'dart:convert';
import 'dart:io';

import 'package:engine_core/engine_core.dart';
import 'package:engine_idle/engine_idle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('load a game from JSON, buy, and watch income', () {
    final json =
        jsonDecode(File('example/cookie_clicker.json').readAsStringSync())
            as Map<String, dynamic>;
    final world = World(width: 10, height: 10);
    registerCoreComponents(world);
    final game = loadIdleDefinition(
      world,
      json,
    ); // throws with every problem if the JSON is wrong
    world.addSystem(IdleSystem()); // accrues income each step

    final cursor = world.storeOf<Generator>().entityAt(0);
    expect(buyGenerator(world, game.wallet, cursor).ok, isTrue); // x1
    game.wallet.add('coins', BigNumber.from(1000));
    final r = buyGenerator(
      world,
      game.wallet,
      cursor,
      count: null,
    ); // as many as affordable
    expect(r.bought, greaterThan(5));
    expect(game.wallet.rateOf('coins') > BigNumber.zero, isTrue);
  });

  test('prestige, achievements and saving through a session', () {
    final json =
        jsonDecode(File('example/cookie_clicker.json').readAsStringSync())
            as Map<String, dynamic>;
    final world = World(width: 10, height: 10);
    registerCoreComponents(world);
    loadIdleDefinition(world, json);
    final controller = IdleController(world: world);

    controller.wallet.add('coins', BigNumber.parse('5e6'));
    world.storeOf<IdleStats>().denseAt(0).credit({
      'coins': BigNumber.parse('4e6'),
    });
    expect(controller.prestige(), BigNumber.from(2)); // floor(sqrt(4e6 / 1e6))

    final store = MemorySaveStore();
    final session = IdleSession(controller: controller, store: store);
    session.save();
    expect(store.read(), isNotNull);

    final code = session.exportCode(); // copyable text
    expect(code, startsWith('GSAVE1.'));
  });
}
