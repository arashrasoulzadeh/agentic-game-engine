import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:engine_strategy/engine_strategy.dart';
import 'package:flutter_test/flutter_test.dart';

World _world() {
  final w = World(width: 10, height: 10);
  registerCoreComponents(w);
  registerFlutterComponents(w);
  return w;
}

TurnGame _game(World w, {Map<String, TurnAI> ai = const {}}) => TurnGame.setup(
  w,
  navigator: GridNavigator(cols: 8, rows: 8, terrainCost: (_, _) => 1),
  cellSize: 32,
  teams: ['red', 'blue'],
  aiTeams: ai,
);

void main() {
  test('a unit moves on its own turn only, and turns rotate', () {
    final w = _world();
    final game = _game(w);
    final red = game.spawnUnit('red', 1, 1);
    final blue = game.spawnUnit('blue', 6, 6);
    expect(() => game.activeTeam, throwsStateError, reason: 'not started');
    game.start();
    expect([game.activeTeam, game.round], ['red', 1]);

    expect(game.moveTo(blue, 5, 6), isFalse, reason: 'not blue\'s turn');
    expect(game.moveTo(red, 3, 1), isTrue);
    w.step(0.1);
    expect(w.componentsOf<GridPosition>().get(red)!.col, 3);

    expect(game.endTurn(), isTrue);
    expect(game.activeTeam, 'blue');
    expect(game.moveTo(red, 4, 1), isFalse);
    game.endTurn();
    expect([game.activeTeam, game.round], ['red', 2]);
  });

  test('attack, winner and callbacks', () {
    final w = _world();
    final game = _game(w);
    final red = game.spawnUnit('red', 1, 1, attack: 99);
    final blue = game.spawnUnit('blue', 2, 1, maxHp: 5);
    game.start();
    expect(game.attack(red, blue), isTrue);
    w.step(0.1);
    w.step(0.1);
    expect(game.winner, 'red');
    expect(game.endTurn(), isFalse, reason: 'game over');
  });

  test('turn callbacks fire from the event flush with team and round', () {
    final w = _world();
    final game = _game(w);
    game.spawnUnit('red', 0, 0);
    game.spawnUnit('blue', 7, 7);
    final log = <String>[];
    final sub = game.onTurnStarted((t, r) => log.add('start $t $r'));
    game.onTurnEnded((t, r) => log.add('end $t $r'));
    game.start();
    w.step(0.1);
    game.endTurn();
    w.step(0.1);
    expect(log, ['start red 1', 'end red 1', 'start blue 1']);
    sub.cancel();
    game.endTurn();
    w.step(0.1);
    expect(
      log.last,
      'end blue 1',
      reason: 'start was cancelled, end still logs',
    );
    expect(log.where((e) => e.startsWith('start')).length, 2);
  });

  test('select and commandSelected go through the active team', () {
    final w = _world();
    final game = _game(w);
    final a = game.spawnUnit('red', 0, 0);
    final b = game.spawnUnit('red', 0, 1);
    game.spawnUnit('blue', 7, 7);
    game.start();
    expect(game.select(7, 7), isNull, reason: 'enemy unit is not selectable');
    expect(game.selectAll([a, b]), 2);
    expect(game.commandSelected(4, 4), 2);
    w.step(0.1);
    expect(w.componentsOf<GridPosition>().get(a)!.col, isNot(0));
  });

  test('setup and spawn validate their arguments', () {
    final w = _world();
    final game = _game(w);
    expect(() => game.spawnUnit('green', 0, 0), throwsArgumentError);
    game.spawnUnit('red', 0, 0);
    game.start();
    expect(game.start, throwsStateError);
    expect(
      () => TurnGame.setup(
        _world(),
        navigator: GridNavigator(cols: 1, rows: 1, terrainCost: (_, _) => 1),
        cellSize: 1,
        teams: [],
      ),
      throwsArgumentError,
    );
  });
}
