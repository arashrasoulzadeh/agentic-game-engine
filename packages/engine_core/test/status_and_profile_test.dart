import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

World _world({bool approach = false}) {
  final w = World(width: 20, height: 20);
  registerCoreComponents(w);
  w.addSystem(OrderSystem(approachTargets: approach));
  installCombat(w);
  return w;
}

EntityId _unit(World w, String team, int c, int r,
    {int ap = 4, int hp = 20, int atk = 4, int def = 0}) {
  final e = w.spawn();
  w.storeOf<Team>().set(e, Team(team));
  w.storeOf<ActionPoints>().set(e, ActionPoints(ap, current: 0));
  w.storeOf<GridPosition>().set(e, GridPosition(c, r));
  w.storeOf<UnitStats>().set(e, UnitStats(maxHp: hp, attack: atk, defense: def));
  return e;
}

void main() {
  group('AttackProfile', () {
    test('a ranged unit hits from a distance without moving; melee still cannot', () {
      final w = _world();
      final archer = _unit(w, 'red', 0, 0);
      final knight = _unit(w, 'red', 0, 1);
      final target = _unit(w, 'blue', 3, 0);
      w.storeOf<AttackProfile>().set(archer, AttackProfile(range: 3));
      startTurnBasedGame(w, ['red', 'blue']);
      final failed = <OrderFailedEvent>[];
      w.events.on<OrderFailedEvent>(failed.add);

      submitOrder(w, archer, AttackOrder(target));
      submitOrder(w, knight, AttackOrder(target));
      w.step(0.1);
      expect(w.storeOf<UnitStats>().get(target)!.hp, 16);
      expect(w.storeOf<GridPosition>().get(archer)!.col, 0);
      expect(failed.single.entity, knight);
      expect(failed.single.reason, OrderFailure.outOfRange);
    });

    test('a per-unit cost overrides the global one', () {
      final w = _world();
      final mage = _unit(w, 'red', 0, 0, ap: 3);
      final target = _unit(w, 'blue', 1, 0);
      w.storeOf<AttackProfile>().set(mage, AttackProfile(range: 1, cost: 3));
      startTurnBasedGame(w, ['red', 'blue']);
      submitOrder(w, mage, AttackOrder(target));
      w.step(0.1);
      expect(w.storeOf<ActionPoints>().get(mage)!.current, 0);
      expect(w.storeOf<UnitStats>().get(target)!.hp, 16);
    });

    test('approaching stops at the unit\'s own reach, not the global one', () {
      final w = _world(approach: true);
      final archer = _unit(w, 'red', 0, 0);
      final target = _unit(w, 'blue', 6, 0);
      w.storeOf<AttackProfile>().set(archer, AttackProfile(range: 3));
      startTurnBasedGame(w, ['red', 'blue']);
      submitOrder(w, archer, AttackOrder(target));
      w.step(0.1);
      expect(w.storeOf<GridPosition>().get(archer)!.col, 3);
      expect(w.storeOf<UnitStats>().get(target)!.hp, 16);
    });

    test('JSON round trip and defaults', () {
      final back = AttackProfile.fromJson(AttackProfile(range: 4, cost: 2).toJson());
      expect((back.range, back.cost), (4, 2));
      final d = AttackProfile.fromJson({});
      expect((d.range, d.cost), (1, 1));
    });
  });

  group('StatusEffects', () {
    test('sums modifiers, finds by id, round-trips JSON', () {
      final s = StatusEffects([
        StatusEffect('rally', attack: 2),
        StatusEffect('stone', defense: 3, turns: 2),
      ]);
      expect(s.attackBonus, 2);
      expect(s.defenseBonus, 3);
      expect(s.has('rally'), isTrue);
      expect(s.has('nope'), isFalse);
      final back = StatusEffects.fromJson(s.toJson());
      expect(back.effects[1].turns, 2);
      expect(back.defenseBonus, 3);
    });

    test('bonuses change combat damage', () {
      expect(damageFor(UnitStats(maxHp: 1, attack: 4), UnitStats(maxHp: 1, defense: 1)), 3);
      expect(
        damageFor(UnitStats(maxHp: 1, attack: 4), UnitStats(maxHp: 1, defense: 1),
            attackBonus: 2, defenseBonus: 3),
        2,
      );
    });

    test('a status buffs the attack that lands', () {
      final w = _world();
      final a = _unit(w, 'red', 0, 0, atk: 4);
      final b = _unit(w, 'blue', 1, 0, def: 1);
      applyStatus(w, a, StatusEffect('rally', attack: 3, turns: 2));
      startTurnBasedGame(w, ['red', 'blue']);
      submitOrder(w, a, AttackOrder(b));
      w.step(0.1);
      expect(w.storeOf<UnitStats>().get(b)!.hp, 20 - (4 + 3 - 1));
    });

    test('applying the same id refreshes instead of stacking, and announces it', () {
      final w = _world();
      final a = _unit(w, 'red', 0, 0);
      final seen = <String>[];
      w.events.on<StatusAppliedEvent>((e) => seen.add(e.id));
      applyStatus(w, a, StatusEffect('x', defense: 1));
      applyStatus(w, a, StatusEffect('x', defense: 5));
      w.events.flush();
      expect(w.storeOf<StatusEffects>().get(a)!.effects, hasLength(1));
      expect(w.storeOf<StatusEffects>().get(a)!.defenseBonus, 5);
      expect(seen, ['x', 'x']);
    });

    test('effects tick on their owner\'s turn start and expire with an event', () {
      final w = _world();
      final red = _unit(w, 'red', 0, 0);
      final blue = _unit(w, 'blue', 5, 5);
      applyStatus(w, red, StatusEffect('short', turns: 1, defense: 1));
      applyStatus(w, red, StatusEffect('long', turns: 2, defense: 1));
      applyStatus(w, blue, StatusEffect('theirs', turns: 1));
      final expired = <String>[];
      w.events.on<StatusExpiredEvent>((e) => expired.add('${e.entity}:${e.id}'));

      startTurnBasedGame(w, ['red', 'blue']); // red's turn 1 starts: short 1->0, long 2->1
      w.events.flush();
      expect(expired, ['$red:short']);
      expect(w.storeOf<StatusEffects>().get(red)!.has('long'), isTrue);
      expect(w.storeOf<StatusEffects>().get(blue)!.has('theirs'), isTrue, reason: 'not blue\'s turn yet');

      endTurn(w); // blue's turn
      endTurn(w); // red again: long 1->0
      w.events.flush();
      expect(expired, contains('$red:long'));
      expect(expired, contains('$blue:theirs'));
      expect(w.storeOf<StatusEffects>().get(red)!.effects, isEmpty);
    });
  });

  group('DefendOrder', () {
    test('spends all remaining points and hardens the unit through the enemy\'s turn', () {
      final w = _world();
      final red = _unit(w, 'red', 0, 0, ap: 3, def: 0);
      final blue = _unit(w, 'blue', 1, 0, atk: 5);
      startTurnBasedGame(w, ['red', 'blue']);
      submitOrder(w, red, const DefendOrder());
      w.step(0.1);
      expect(w.storeOf<ActionPoints>().get(red)!.current, 0);
      expect(w.storeOf<StatusEffects>().get(red)!.has('defending'), isTrue);

      endTurn(w);
      submitOrder(w, blue, AttackOrder(red));
      w.step(0.1);
      expect(w.storeOf<UnitStats>().get(red)!.hp, 20 - (5 - 2), reason: 'defense 0 + 2 from defending');

      endTurn(w); // red's turn again: defending (turns 1) expires
      expect(w.storeOf<StatusEffects>().get(red)!.has('defending'), isFalse);
    });

    test('the bonus is configurable and JSON round-trips', () {
      expect(Order.fromJson(const DefendOrder().toJson()), isA<DefendOrder>());
      final w = World(width: 5, height: 5);
      registerCoreComponents(w);
      w.addSystem(OrderSystem(defendBonus: 4));
      final u = _unit(w, 'red', 0, 0);
      _unit(w, 'blue', 4, 4);
      startTurnBasedGame(w, ['red', 'blue']);
      submitOrder(w, u, const DefendOrder());
      w.step(0.1);
      expect(w.storeOf<StatusEffects>().get(u)!.defenseBonus, 4);
    });

    test('with no points left it waits and resumes next turn', () {
      final w = _world();
      final red = _unit(w, 'red', 0, 0, ap: 2);
      _unit(w, 'blue', 4, 4);
      startTurnBasedGame(w, ['red', 'blue']);
      trySpendActionPoints(w, red, 2);
      submitOrder(w, red, const DefendOrder());
      w.step(0.1);
      expect(w.storeOf<StatusEffects>().has(red), isFalse);
      expect(w.storeOf<OrderQueue>().get(red)!.orders, hasLength(1));
      endTurn(w);
      endTurn(w);
      w.step(0.1);
      expect(w.storeOf<StatusEffects>().get(red)!.has('defending'), isTrue);
      expect(w.storeOf<OrderQueue>().get(red)!.orders, isEmpty);
    });

    test('a unit without ActionPoints cannot defend', () {
      final w = _world();
      final e = _unit(w, 'red', 0, 0);
      w.storeOf<ActionPoints>().remove(e);
      _unit(w, 'blue', 4, 4);
      startTurnBasedGame(w, ['red', 'blue']);
      final failed = <OrderFailedEvent>[];
      w.events.on<OrderFailedEvent>(failed.add);
      w.storeOf<OrderQueue>().set(e, OrderQueue([const DefendOrder()]));
      w.step(0.1);
      expect(failed.single.reason, OrderFailure.invalidTarget);
    });
  });
}
