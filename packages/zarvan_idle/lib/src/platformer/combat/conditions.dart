import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_platformer/zarvan_platformer.dart' show Health;

/// A lasting condition on a fighter.
enum ConditionKind {
  /// Damage over time, one stack.
  bleed,

  /// Damage over time that stacks.
  poison,

  /// Cannot attack while it lasts.
  stun,
}

/// One active condition: [dpsFraction] of max health per second for each of
/// [stacks], until [remaining] seconds run out.
class StatusEffect {
  StatusEffect({
    required this.kind,
    required this.remaining,
    this.stacks = 1,
    this.dpsFraction = 0,
  });

  final ConditionKind kind;
  double remaining;
  int stacks;
  final double dpsFraction;

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'remaining': remaining,
    'stacks': stacks,
    'dpsFraction': dpsFraction,
  };

  factory StatusEffect.fromJson(Map<String, dynamic> json) => StatusEffect(
    kind: ConditionKind.values.firstWhere((k) => k.name == json['kind']),
    remaining: (json['remaining'] as num).toDouble(),
    stacks: (json['stacks'] as num?)?.toInt() ?? 1,
    dpsFraction: (json['dpsFraction'] as num?)?.toDouble() ?? 0,
  );
}

/// The conditions on one fighter.
class Conditions {
  Conditions([List<StatusEffect>? active]) : active = active ?? [];

  final List<StatusEffect> active;

  bool get stunned => active.any((e) => e.kind == ConditionKind.stun);

  /// Applies a condition: a repeat of the same kind refreshes its duration
  /// and, for stackable kinds, adds a stack up to [maxStacks].
  void apply(
    ConditionKind kind, {
    required double seconds,
    double dpsFraction = 0,
    int maxStacks = 1,
  }) {
    for (final e in active) {
      if (e.kind != kind) continue;
      e.remaining = seconds;
      if (e.stacks < maxStacks) e.stacks++;
      return;
    }
    active.add(
      StatusEffect(kind: kind, remaining: seconds, dpsFraction: dpsFraction),
    );
  }

  /// A short readable line, e.g. `Bleed 2s · Poison x2 4s`.
  String describe() => active
      .map(
        (e) =>
            '${e.kind.name[0].toUpperCase()}${e.kind.name.substring(1)}'
            '${e.stacks > 1 ? ' x${e.stacks}' : ''} ${e.remaining.ceil()}s',
      )
      .join(' · ');

  Map<String, dynamic> toJson() => {
    'active': [for (final e in active) e.toJson()],
  };

  factory Conditions.fromJson(Map<String, dynamic> json) => Conditions([
    for (final e in (json['active'] as List? ?? const []))
      StatusEffect.fromJson((e as Map).cast<String, dynamic>()),
  ]);
}

/// A damage-over-time tick landed (batched about twice a second).
class ConditionTick {
  ConditionTick({
    required this.entity,
    required this.kind,
    required this.damage,
  });

  final EntityId entity;
  final ConditionKind kind;
  final double damage;
}

/// Runs every fighter's [Conditions]: damage over time, expiry.
class ConditionSystem extends System {
  /// How often accumulated damage is reported as a [ConditionTick].
  static const _reportEvery = 0.5;

  final Map<(EntityId, ConditionKind), double> _pending = {};
  final Map<(EntityId, ConditionKind), double> _sinceReport = {};

  @override
  String get name => 'conditions';

  @override
  void update(World world, double dt) {
    final all = world.componentsOf<Conditions>();
    final health = world.componentsOf<Health>();
    for (var i = 0; i < all.length; i++) {
      final id = all.entityAt(i);
      final fx = all.denseAt(i);
      final hp = health.get(id);
      for (final e in fx.active) {
        e.remaining -= dt;
        if (hp == null || hp.current <= 0 || e.dpsFraction <= 0) continue;
        final key = (id, e.kind);
        final damage = hp.max * e.dpsFraction * e.stacks * dt;
        hp.current = (hp.current - damage).clamp(0, hp.max);
        _pending[key] = (_pending[key] ?? 0) + damage;
        final since = (_sinceReport[key] ?? 0) + dt;
        if (since >= _reportEvery) {
          world.events.emit(
            ConditionTick(entity: id, kind: e.kind, damage: _pending[key]!),
          );
          _pending.remove(key);
          _sinceReport.remove(key);
        } else {
          _sinceReport[key] = since;
        }
      }
      fx.active.removeWhere((e) => e.remaining <= 0);
    }
  }
}

/// Registers [Conditions] so it serializes.
void registerConditionComponents(World world) {
  if (world.components.isRegistered('conditions')) return;
  world.components.register<Conditions>(
    'conditions',
    (c) => c.toJson(),
    Conditions.fromJson,
  );
}
