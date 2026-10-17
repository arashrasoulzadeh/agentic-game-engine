import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

GridNavigator _nav() => GridNavigator(cols: 20, rows: 20, terrainCost: (c, r) => 1);

World _turnWorld() {
  final w = World(width: 20, height: 20);
  registerCoreComponents(w);
  w.addSystem(OrderSystem.withNavigator(_nav()));
  w.addSystem(WinConditionSystem());
  installCombat(w);
  return w;
}

EntityId _unit(World w, String team, int c, int r, {int ap = 6, int hp = 10, int atk = 3}) {
  final e = w.spawn();
  w.storeOf<Team>().set(e, Team(team));
  w.storeOf<ActionPoints>().set(e, ActionPoints(ap, current: 0));
  w.storeOf<GridPosition>().set(e, GridPosition(c, r));
  w.storeOf<UnitStats>().set(e, UnitStats(maxHp: hp, attack: atk));
  return e;
}

EntityId _flag(World w, String id, String home, int c, int r) {
  final e = w.spawn();
  w.storeOf<Flag>().set(e, Flag(id, home, c, r));
  return e;
}

EntityId _zone(World w, String team, int c, int r) {
  final e = w.spawn();
  w.storeOf<DeliveryZone>().set(e, DeliveryZone(team, c, r));
  return e;
}

void main() {
  group('Vip', () {
    test('losing the Vip loses the game even with units left', () {
      final w = _turnWorld();
      final vip = _unit(w, 'red', 0, 0, hp: 3);
      w.storeOf<Vip>().set(vip, const Vip());
      _unit(w, 'red', 5, 5);
      _unit(w, 'red', 6, 5);
      final hunter = _unit(w, 'blue', 1, 0, atk: 9);
      startTurnBasedGame(w, ['red', 'blue']);
      w.step(0.1);
      endTurn(w);
      submitOrder(w, hunter, AttackOrder(vip));
      w.step(0.1);
      w.step(0.1);
      expect(w.entities.isAlive(vip), isFalse);
      expect(turnStateOf(w)!.winner, 'blue');
      expect(turnStateOf(w)!.eliminated, contains('red'));
    });

    test('a team without a Vip is unaffected: it needs all units dead as before', () {
      final w = _turnWorld();
      final a = _unit(w, 'red', 0, 0, hp: 3);
      _unit(w, 'red', 5, 5);
      final hunter = _unit(w, 'blue', 1, 0, atk: 9);
      startTurnBasedGame(w, ['red', 'blue']);
      w.step(0.1);
      endTurn(w);
      submitOrder(w, hunter, AttackOrder(a));
      w.step(0.1);
      w.step(0.1);
      expect(turnStateOf(w)!.winner, isNull);
    });

    test('the real-time rule honours a Vip too', () {
      final w = World(width: 10, height: 10);
      registerCoreComponents(w);
      final sys = LastTeamStandingSystem();
      w.addSystem(sys);
      final vip = spawnRealtimeUnit(w, team: 'red', col: 0, row: 0);
      w.storeOf<Vip>().set(vip, const Vip());
      spawnRealtimeUnit(w, team: 'red', col: 1, row: 0);
      spawnRealtimeUnit(w, team: 'blue', col: 5, row: 5);
      w.step(0.1);
      expect(sys.winner, isNull);
      w.destroy(vip);
      w.step(0.1);
      expect(sys.winner, 'blue');
    });

    test('Vip round-trips JSON', () {
      expect(Vip.fromJson(const Vip().toJson()), isA<Vip>());
    });
  });

  group('Flag', () {
    test('an enemy walking onto it picks it up; its own team cannot', () {
      final w = _turnWorld();
      final flag = _flag(w, 'red flag', 'red', 5, 0);
      final own = _unit(w, 'red', 4, 0);
      final raider = _unit(w, 'blue', 5, 3);
      final events = <FlagPickedUpEvent>[];
      w.events.on<FlagPickedUpEvent>(events.add);
      startTurnBasedGame(w, ['red', 'blue']);
      submitOrder(w, own, const MoveOrder(5, 0));
      submitOrder(w, own, const MoveOrder(3, 3)); // steps off so the raider can enter
      w.step(0.1);
      expect(w.storeOf<Flag>().get(flag)!.carrier, isNull, reason: 'its own team never picks up its own flag');

      endTurn(w);
      submitOrder(w, raider, const MoveOrder(5, 0));
      w.step(0.1);
      w.events.flush();
      expect(w.storeOf<Flag>().get(flag)!.carrier, raider);
      expect(events.single.carrier, raider);
    });

    test('the flag rides along with its carrier', () {
      final w = _turnWorld();
      final flag = _flag(w, 'f', 'red', 5, 5);
      final raider = _unit(w, 'blue', 5, 7, ap: 8);
      startTurnBasedGame(w, ['red', 'blue']);
      endTurn(w);
      submitOrder(w, raider, const MoveOrder(5, 5));
      submitOrder(w, raider, const MoveOrder(9, 9));
      w.step(0.1);
      final f = w.storeOf<Flag>().get(flag)!;
      expect(f.carrier, raider);
      expect((f.col, f.row), (9, 9));
    });

    test('a unit carries at most one flag', () {
      final w = _turnWorld();
      final f1 = _flag(w, 'a', 'red', 5, 5);
      final f2 = _flag(w, 'b', 'red', 6, 5);
      final raider = _unit(w, 'blue', 4, 5);
      startTurnBasedGame(w, ['red', 'blue']);
      endTurn(w);
      // One order per cell: A* may take any equal-cost diagonal, so a single
      // MoveOrder(7, 5) is not guaranteed to step on either flag.
      submitOrder(w, raider, const MoveOrder(5, 5));
      submitOrder(w, raider, const MoveOrder(6, 5));
      submitOrder(w, raider, const MoveOrder(7, 5));
      w.step(0.1);
      final carriers = [w.storeOf<Flag>().get(f1)!.carrier, w.storeOf<Flag>().get(f2)!.carrier];
      expect(carriers.where((c) => c == raider), hasLength(1));
    });

    test('delivering to your own zone scores, resets the flag, and enough captures win', () {
      final w = _turnWorld();
      final flag = _flag(w, 'red flag', 'red', 10, 0);
      _zone(w, 'blue', 0, 10);
      w.storeOf<FlagRules>().set(w.spawn(), FlagRules(capturesToWin: 1));
      final raider = _unit(w, 'blue', 10, 2, ap: 20);
      _unit(w, 'red', 15, 15);
      final captured = <FlagCapturedEvent>[];
      w.events.on<FlagCapturedEvent>(captured.add);
      startTurnBasedGame(w, ['red', 'blue']);
      endTurn(w);
      submitOrder(w, raider, const MoveOrder(10, 0));
      submitOrder(w, raider, const MoveOrder(0, 10));
      w.step(0.1);
      w.events.flush();

      expect(captured.single.team, 'blue');
      expect(captured.single.total, 1);
      final f = w.storeOf<Flag>().get(flag)!;
      expect(f.carrier, isNull);
      expect((f.col, f.row), (10, 0), reason: 'back at home');
      expect(turnStateOf(w)!.winner, 'blue');
    });

    test('capturesToWin above one needs repeated deliveries; passing the zone empty-handed scores nothing', () {
      final w = _turnWorld();
      _flag(w, 'f', 'red', 5, 5);
      _zone(w, 'blue', 0, 0);
      final rules = FlagRules(capturesToWin: 2);
      w.storeOf<FlagRules>().set(w.spawn(), rules);
      final raider = _unit(w, 'blue', 1, 0, ap: 40);
      _unit(w, 'red', 15, 15);
      startTurnBasedGame(w, ['red', 'blue']);
      endTurn(w);
      submitOrder(w, raider, const MoveOrder(0, 0));
      w.step(0.1);
      expect(rules.captures['blue'], isNull, reason: 'no flag in hand');

      submitOrder(w, raider, const MoveOrder(5, 5));
      submitOrder(w, raider, const MoveOrder(0, 0));
      w.step(0.1);
      expect(rules.captures['blue'], 1);
      expect(turnStateOf(w)!.winner, isNull);
    });

    test('killing the carrier drops the flag where it fell, and a new raider can take it', () {
      final w = _turnWorld();
      final flag = _flag(w, 'f', 'red', 5, 5);
      final carrier = _unit(w, 'blue', 5, 5, hp: 3);
      final defender = _unit(w, 'red', 5, 6, atk: 9);
      final second = _unit(w, 'blue', 5, 9, ap: 6);
      final dropped = <FlagDroppedEvent>[];
      w.events.on<FlagDroppedEvent>(dropped.add);
      startTurnBasedGame(w, ['red', 'blue']);
      endTurn(w);
      w.storeOf<Flag>().get(flag)!.carrier = carrier;
      endTurn(w);
      submitOrder(w, defender, AttackOrder(carrier));
      w.step(0.1);
      w.events.flush();
      expect(w.entities.isAlive(carrier), isFalse);
      expect(w.storeOf<Flag>().get(flag)!.carrier, isNull);
      expect(dropped.single.formerCarrier, carrier);
      expect((w.storeOf<Flag>().get(flag)!.col, w.storeOf<Flag>().get(flag)!.row), (5, 5));

      endTurn(w);
      submitOrder(w, second, const MoveOrder(5, 5));
      w.step(0.1);
      expect(w.storeOf<Flag>().get(flag)!.carrier, second);
    });

    test('flags work in real time too', () {
      final w = World(width: 20, height: 20);
      registerCoreComponents(w);
      final cache = FlowFieldCache(_nav());
      w.addSystem(RealtimeOrderSystem(fields: cache, autoEngage: false));
      final flag = _flag(w, 'f', 'red', 8, 0);
      _zone(w, 'blue', 0, 0);
      w.storeOf<FlagRules>().set(w.spawn(), FlagRules(capturesToWin: 5));
      final raider = spawnRealtimeUnit(w, team: 'blue', col: 0, row: 0, speed: 8);
      submitOrder(w, raider, const MoveOrder(8, 0));
      submitOrder(w, raider, const MoveOrder(0, 0));
      final captured = <FlagCapturedEvent>[];
      w.events.on<FlagCapturedEvent>(captured.add);
      for (var i = 0; i < 80; i++) {
        w.step(0.05);
      }
      expect(captured, hasLength(1));
      expect(w.storeOf<Flag>().get(flag)!.carrier, isNull);
    });

    test('flag, zone and rules round-trip JSON', () {
      final f = Flag.fromJson(Flag('x', 'red', 1, 2, carrier: 7, col: 3, row: 4).toJson());
      expect((f.id, f.homeTeam, f.homeCol, f.homeRow, f.carrier, f.col, f.row), ('x', 'red', 1, 2, 7, 3, 4));
      expect(Flag.fromJson(Flag('y', 'blue', 5, 6).toJson()).carrier, isNull);
      final z = DeliveryZone.fromJson(const DeliveryZone('blue', 2, 3).toJson());
      expect((z.team, z.col, z.row), ('blue', 2, 3));
      final r = FlagRules.fromJson(FlagRules(capturesToWin: 3, captures: {'red': 1}).toJson());
      expect((r.capturesToWin, r.captures['red']), (3, 1));
    });

    test('a flag does not block movement or selection, because it is not a grid unit', () {
      final w = _turnWorld();
      _flag(w, 'f', 'blue', 3, 0); // blue flag: red walks over it as the raider
      final red = _unit(w, 'red', 0, 0);
      startTurnBasedGame(w, ['red', 'blue']);
      submitOrder(w, red, const MoveOrder(6, 0));
      w.step(0.1);
      expect(w.storeOf<GridPosition>().get(red)!.col, 6);
      expect(selectAtCell(w, 3, 0), isNull);
    });
  });
}
