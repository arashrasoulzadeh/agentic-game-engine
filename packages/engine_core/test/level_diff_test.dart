import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

LevelEntity _e(String? name, Map<String, Map<String, dynamic>> c) => LevelEntity(name: name, components: c);

LevelDocument _doc(List<LevelEntity> es) => LevelDocument(entities: es);

Map<String, dynamic> _pos(num x, num y) => {'x': x, 'y': y};

void main() {
  group('diffLevels', () {
    test('identical levels have no differences, whatever the key order', () {
      final a = _doc([_e('p', {'position': _pos(1, 2)})]);
      final b = _doc([_e('p', {'position': {'y': 2, 'x': 1}})]);
      expect(diffLevels(a, b).isEmpty, isTrue);
      expect(diffLevels(a, b).format(), 'No differences.');
    });

    test('reports added, removed, and field-level changes by entity name', () {
      final before = _doc([
        _e('player', {'position': _pos(1, 2), 'health': {'current': 5, 'max': 5}}),
        _e('door', {'position': _pos(9, 9)}),
      ]);
      final after = _doc([
        _e('player', {'position': _pos(1, 7), 'health': {'current': 5, 'max': 5}, 'collider': {'radius': 4}}),
        _e('key', {'position': _pos(3, 3)}),
      ]);
      final d = diffLevels(before, after);
      expect(d.removed.map((e) => e.name), ['door']);
      expect(d.added.map((e) => e.name), ['key']);
      expect(d.changed.single.name, 'player');
      final byComp = {for (final c in d.changed.single.components) c.component: c};
      expect(byComp['position']!.fields, ['y']);
      expect(byComp['collider']!.isAdded, isTrue);
      expect(byComp.containsKey('health'), isFalse);
      expect(d.format().split('\n'), [
        '- door',
        '+ key',
        '+ player.collider {"radius":4}',
        '~ player.position.y: 2 -> 7',
      ]);
    });

    test('a removed component is reported', () {
      final d = diffLevels(
        _doc([_e('a', {'position': _pos(0, 0), 'health': {'current': 1, 'max': 1}})]),
        _doc([_e('a', {'position': _pos(0, 0)})]),
      );
      expect(d.changed.single.components.single.isRemoved, isTrue);
      expect(d.format(), '- a.health');
    });

    test('unnamed entities: identical ones cancel, different ones are removed + added', () {
      final same = diffLevels(
        _doc([_e(null, {'position': _pos(1, 1)}), _e(null, {'position': _pos(1, 1)})]),
        _doc([_e(null, {'position': _pos(1, 1)}), _e(null, {'position': _pos(1, 1)})]),
      );
      expect(same.isEmpty, isTrue);

      final moved = diffLevels(
        _doc([_e(null, {'position': _pos(1, 1)})]),
        _doc([_e(null, {'position': _pos(2, 1)})]),
      );
      expect((moved.added.length, moved.removed.length, moved.changed.length), (1, 1, 0));
    });

    test('toJson carries the same information', () {
      final d = diffLevels(
        _doc([_e('a', {'position': _pos(0, 0)})]),
        _doc([_e('a', {'position': _pos(5, 0)})]),
      );
      final j = d.toJson();
      expect((j['changed'] as List).single['name'], 'a');
    });
  });

  group('mergeLevels', () {
    final base = _doc([
      _e('player', {'position': _pos(0, 0), 'health': {'current': 5, 'max': 5}}),
      _e('door', {'position': _pos(9, 9)}),
    ]);

    test('non-overlapping edits from both sides are both kept', () {
      final ours = _doc([
        _e('player', {'position': _pos(1, 0), 'health': {'current': 5, 'max': 5}}),
        _e('door', {'position': _pos(9, 9)}),
      ]);
      final theirs = _doc([
        _e('player', {'position': _pos(0, 0), 'health': {'current': 9, 'max': 9}}),
        _e('door', {'position': _pos(9, 9)}),
      ]);
      final m = mergeLevels(base, ours, theirs);
      expect(m.hasConflicts, isFalse);
      final p = m.merged.entityNamed('player')!;
      expect(p.components['position'], _pos(1, 0), reason: 'ours moved it');
      expect(p.components['health'], {'current': 9, 'max': 9}, reason: 'theirs changed health');
    });

    test('the same change on both sides applies once, without a conflict', () {
      final edit = _doc([
        _e('player', {'position': _pos(4, 4), 'health': {'current': 5, 'max': 5}}),
        _e('door', {'position': _pos(9, 9)}),
      ]);
      final m = mergeLevels(base, edit, edit);
      expect(m.hasConflicts, isFalse);
      expect(m.merged.entityNamed('player')!.components['position'], _pos(4, 4));
    });

    test('both sides changing the same component differently conflicts and keeps ours', () {
      LevelDocument at(num x) => _doc([
            _e('player', {'position': _pos(x, 0), 'health': {'current': 5, 'max': 5}}),
            _e('door', {'position': _pos(9, 9)}),
          ]);
      final m = mergeLevels(base, at(1), at(2));
      expect(m.conflicts.single.entity, 'player');
      expect(m.conflicts.single.component, 'position');
      expect(m.merged.entityNamed('player')!.components['position'], _pos(1, 0));
    });

    test('additions from both sides are kept; one-sided deletion of an untouched entity wins', () {
      final ours = _doc([
        _e('player', base.entityNamed('player')!.components),
        _e('door', {'position': _pos(9, 9)}),
        _e('torch', {'position': _pos(1, 1)}),
      ]);
      final theirs = _doc([
        _e('player', base.entityNamed('player')!.components),
        _e('chest', {'position': _pos(2, 2)}),
      ]); // theirs deleted the door
      final m = mergeLevels(base, ours, theirs);
      expect(m.hasConflicts, isFalse);
      expect(m.merged.entities.map((e) => e.name), ['player', 'torch', 'chest']);
    });

    test('deleting an entity the other side edited is a conflict (ours kept)', () {
      final ours = _doc([_e('player', base.entityNamed('player')!.components)]); // deleted door
      final theirs = _doc([
        _e('player', base.entityNamed('player')!.components),
        _e('door', {'position': _pos(1, 1)}), // edited door
      ]);
      final m = mergeLevels(base, ours, theirs);
      expect(m.conflicts.single.entity, 'door');
      expect(m.conflicts.single.component, isNull);
      expect(m.merged.entityNamed('door'), isNull, reason: 'ours deleted it, ours is kept');
    });

    test('unnamed entities merge as sets: additions and removals from either side apply', () {
      final a = _e(null, {'position': _pos(1, 1)});
      final b = _e(null, {'position': _pos(2, 2)});
      final c = _e(null, {'position': _pos(3, 3)});
      final d = _e(null, {'position': _pos(4, 4)});
      final baseU = _doc([a, b]);
      final ours = _doc([a, b, c]); // added c
      final theirs = _doc([b, d]); // removed a, added d
      final m = mergeLevels(baseU, ours, theirs);
      final xs = m.merged.entities.map((e) => (e.components['position']!['x'] as num).toInt()).toList()..sort();
      expect(xs, [2, 3, 4]);
      expect(m.hasConflicts, isFalse);
    });

    test('merging with no changes returns the base unchanged', () {
      final m = mergeLevels(base, base, base);
      expect(diffLevels(base, m.merged).isEmpty, isTrue);
    });
  });
}
