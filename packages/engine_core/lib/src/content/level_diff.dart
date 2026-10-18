import 'dart:convert';

import 'level_document.dart';

/// One component of a named entity that differs between two levels.
class ComponentChange {
  ComponentChange(this.component, this.before, this.after);

  final String component;

  /// The component before / after; null when it was added / removed.
  final Map<String, dynamic>? before;
  final Map<String, dynamic>? after;

  bool get isAdded => before == null;
  bool get isRemoved => after == null;

  /// Field names whose value differs (all of them for an added or removed component).
  List<String> get fields => [
        for (final f in {...?before?.keys, ...?after?.keys}.toList()..sort())
          if (_canon(before?[f]) != _canon(after?[f])) f,
      ];
}

/// A named entity present in both levels whose components differ.
class EntityChange {
  EntityChange(this.name, this.components);
  final String name;
  final List<ComponentChange> components;
}

/// What differs between two levels, at the level a designer reads: entities added, entities
/// removed, and per-component changes to entities that exist in both.
///
/// Entities are matched by **name**. An entity with no name cannot be followed across an edit,
/// so an unnamed entity that is not byte-for-byte identical to one on the other side shows up
/// as removed plus added rather than changed; name the entities that matter.
class LevelDiff {
  LevelDiff(this.added, this.removed, this.changed);

  final List<LevelEntity> added;
  final List<LevelEntity> removed;
  final List<EntityChange> changed;

  bool get isEmpty => added.isEmpty && removed.isEmpty && changed.isEmpty;

  /// A plain-text summary, one line per change, for terminals and code review.
  String format() {
    if (isEmpty) return 'No differences.';
    final out = StringBuffer();
    String label(LevelEntity e) => e.name ?? '(unnamed ${e.components.keys.join(', ')})';
    for (final e in removed) {
      out.writeln('- ${label(e)}');
    }
    for (final e in added) {
      out.writeln('+ ${label(e)}');
    }
    for (final c in changed) {
      for (final comp in c.components) {
        if (comp.isAdded) {
          out.writeln('+ ${c.name}.${comp.component} ${jsonEncode(comp.after)}');
        } else if (comp.isRemoved) {
          out.writeln('- ${c.name}.${comp.component}');
        } else {
          for (final f in comp.fields) {
            out.writeln(
              '~ ${c.name}.${comp.component}.$f: ${jsonEncode(comp.before![f])} -> ${jsonEncode(comp.after![f])}',
            );
          }
        }
      }
    }
    return out.toString().trimRight();
  }

  Map<String, dynamic> toJson() => {
        'added': [for (final e in added) e.toJson()],
        'removed': [for (final e in removed) e.toJson()],
        'changed': [
          for (final c in changed)
            {
              'name': c.name,
              'components': [
                for (final comp in c.components)
                  {'component': comp.component, 'before': comp.before, 'after': comp.after},
              ],
            },
        ],
      };
}

/// Compares two levels. See [LevelDiff] for how entities are matched.
LevelDiff diffLevels(LevelDocument before, LevelDocument after) {
  final added = <LevelEntity>[];
  final removed = <LevelEntity>[];
  final changed = <EntityChange>[];

  final afterNamed = {for (final e in after.entities) if (e.name != null) e.name!: e};
  final beforeNamed = {for (final e in before.entities) if (e.name != null) e.name!: e};

  for (final e in before.entities) {
    if (e.name == null) continue;
    final other = afterNamed[e.name];
    if (other == null) {
      removed.add(e);
      continue;
    }
    final comps = <ComponentChange>[];
    for (final c in {...e.components.keys, ...other.components.keys}.toList()..sort()) {
      if (_canon(e.components[c]) != _canon(other.components[c])) {
        comps.add(ComponentChange(c, e.components[c], other.components[c]));
      }
    }
    if (comps.isNotEmpty) changed.add(EntityChange(e.name!, comps));
  }
  for (final e in after.entities) {
    if (e.name != null && !beforeNamed.containsKey(e.name)) added.add(e);
  }

  // Unnamed entities: pair off identical ones; whatever is left over was removed or added.
  final leftover = <String, List<LevelEntity>>{};
  for (final e in before.entities.where((e) => e.name == null)) {
    (leftover[_canon(e.components)] ??= []).add(e);
  }
  for (final e in after.entities.where((e) => e.name == null)) {
    final same = leftover[_canon(e.components)];
    if (same != null && same.isNotEmpty) {
      same.removeLast();
    } else {
      added.add(e);
    }
  }
  removed.addAll(leftover.values.expand((l) => l));

  return LevelDiff(added, removed, changed);
}

/// A place where both sides changed the same thing differently.
class MergeConflict {
  MergeConflict(this.entity, this.component, this.base, this.ours, this.theirs);

  /// The entity's name; unnamed entities never conflict (they are merged as sets).
  final String entity;

  /// The component, or null when one side deleted the whole entity and the other edited it
  /// (then [base], [ours] and [theirs] are null: compare the entities themselves).
  final String? component;
  final Map<String, dynamic>? base;
  final Map<String, dynamic>? ours;
  final Map<String, dynamic>? theirs;
}

/// The result of [mergeLevels].
class LevelMerge {
  LevelMerge(this.merged, this.conflicts);

  /// The merged level. Where there is a conflict it holds **ours**.
  final LevelDocument merged;
  final List<MergeConflict> conflicts;

  bool get hasConflicts => conflicts.isNotEmpty;
}

/// Three-way merge of two edits ([ours], [theirs]) of a common [base] - what a git merge
/// driver for level files does.
///
/// Per named entity, per component: if only one side changed it, that change wins; if both
/// made the *same* change it applies once; if they changed it differently it is a
/// [MergeConflict] and ours is kept. An entity one side deleted and the other edited is a
/// conflict too. Unnamed entities merge as sets: removals and additions from either side are
/// applied. Entity order follows [ours], with entities only [theirs] added appended.
LevelMerge mergeLevels(LevelDocument base, LevelDocument ours, LevelDocument theirs) {
  final conflicts = <MergeConflict>[];
  final entities = <LevelEntity>[];

  LevelEntity copy(LevelEntity e) => LevelEntity.fromJson(jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>);

  Map<String, LevelEntity> named(LevelDocument d) => {for (final e in d.entities) if (e.name != null) e.name!: e};
  final b = named(base), o = named(ours), t = named(theirs);

  // Named entities, in ours' order, then theirs-only.
  final order = [...o.keys, ...t.keys.where((k) => !o.containsKey(k))];
  for (final name in order) {
    final be = b[name], oe = o[name], te = t[name];
    if (oe != null && te != null) {
      final comps = <String, Map<String, dynamic>>{};
      for (final c in {...oe.components.keys, ...te.components.keys, ...?be?.components.keys}) {
        final bc = be?.components[c], oc = oe.components[c], tc = te.components[c];
        final pick = _merge3(bc, oc, tc);
        if (pick.conflict) conflicts.add(MergeConflict(name, c, bc, oc, tc));
        final value = pick.value;
        if (value != null) comps[c] = (jsonDecode(jsonEncode(value)) as Map).cast<String, dynamic>();
      }
      entities.add(LevelEntity(name: name, components: comps));
    } else if (oe != null) {
      // theirs does not have it.
      if (be == null) {
        entities.add(copy(oe)); // ours added it
      } else if (_canon(be.components) == _canon(oe.components)) {
        // theirs deleted it, ours left it alone: deletion wins.
      } else {
        conflicts.add(MergeConflict(name, null, null, null, null));
        entities.add(copy(oe));
      }
    } else if (te != null) {
      if (be == null) {
        entities.add(copy(te)); // theirs added it
      } else if (_canon(be.components) == _canon(te.components)) {
        // ours deleted it, theirs left it alone: deletion wins.
      } else {
        conflicts.add(MergeConflict(name, null, null, null, null));
        // ours deleted it: ours is kept, i.e. it stays deleted.
      }
    }
  }

  // Unnamed entities as multisets keyed by content.
  Map<String, List<LevelEntity>> bag(LevelDocument d) {
    final m = <String, List<LevelEntity>>{};
    for (final e in d.entities.where((e) => e.name == null)) {
      (m[_canon(e.components)] ??= []).add(e);
    }
    return m;
  }

  final bb = bag(base), ob = bag(ours), tb = bag(theirs);
  for (final key in {...bb.keys, ...ob.keys, ...tb.keys}) {
    final nb = bb[key]?.length ?? 0, no = ob[key]?.length ?? 0, nt = tb[key]?.length ?? 0;
    // Each side's net change from the base, applied to the base count.
    final count = (no + nt - nb).clamp(0, 1 << 20);
    final sample = (ob[key] ?? tb[key] ?? bb[key])!.first;
    for (var i = 0; i < count; i++) {
      entities.add(copy(sample));
    }
  }

  return LevelMerge(LevelDocument(entities: entities), conflicts);
}

({Map<String, dynamic>? value, bool conflict}) _merge3(
  Map<String, dynamic>? base,
  Map<String, dynamic>? ours,
  Map<String, dynamic>? theirs,
) {
  final b = _canon(base), o = _canon(ours), t = _canon(theirs);
  if (o == t) return (value: ours, conflict: false);
  if (o == b) return (value: theirs, conflict: false);
  if (t == b) return (value: ours, conflict: false);
  return (value: ours, conflict: true);
}

/// Key-order-independent text for comparing JSON values.
String _canon(Object? v) => jsonEncode(_sorted(v));

Object? _sorted(Object? v) {
  if (v is Map) {
    final keys = v.keys.map((k) => '$k').toList()..sort();
    return {for (final k in keys) k: _sorted(v[k])};
  }
  if (v is List) return v.map(_sorted).toList();
  return v;
}
