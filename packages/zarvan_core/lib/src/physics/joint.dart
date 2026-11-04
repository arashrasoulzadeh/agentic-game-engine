import 'dart:math' as math;

import 'package:zarvan_schema/zarvan_schema.dart' show jointSchema;

import '../ecs/entity.dart';
import '../ecs/system.dart';
import '../ecs/world.dart';
import 'position.dart';
import 'velocity.dart';

/// How a [Joint] ties two points together.
enum JointKind {
  /// A spring pulling toward [Joint.length] both ways, with damping.
  spring,

  /// A rope: only pulls when stretched past [Joint.length]; slack otherwise.
  rope,

  /// A rigid rod: holds exactly [Joint.length] apart.
  rod,
}

/// Ties the entity that carries it to another entity ([other]) or to a fixed
/// world point ([anchorX], [anchorY]) by distance: a pendulum, a hanging
/// lantern, a tether, a swinging platform. Solved by [JointSystem].
///
/// Entities need a `Position`; a `Velocity` lets springs and ropes push them
/// (without one, an end is only moved by a rod's correction).
class Joint {
  Joint({
    this.kind = JointKind.spring,
    this.other,
    this.anchorX = 0,
    this.anchorY = 0,
    this.length = 50,
    this.stiffness = 40,
    this.damping = 4,
    this.breakDistance = 0,
  });

  JointKind kind;

  /// The entity at the other end, or null for a fixed point at
  /// ([anchorX], [anchorY]).
  EntityId? other;
  double anchorX;
  double anchorY;

  /// Rest length in world units.
  double length;

  /// Spring and rope strength: acceleration per unit of stretch (per second
  /// squared). Higher is stiffer; too high for the step size becomes unstable.
  double stiffness;

  /// How strongly motion along the joint is damped (per second).
  double damping;

  /// The joint snaps when the ends get farther apart than this (0 = never).
  double breakDistance;

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'other': other,
    'anchorX': anchorX,
    'anchorY': anchorY,
    'length': length,
    'stiffness': stiffness,
    'damping': damping,
    'breakDistance': breakDistance,
  };

  factory Joint.fromJson(Map<String, dynamic> json) => Joint(
    kind: JointKind.values.firstWhere(
      (k) => k.name == json['kind'],
      orElse: () => JointKind.spring,
    ),
    other: json['other'] as int?,
    anchorX: (json['anchorX'] as num?)?.toDouble() ?? 0,
    anchorY: (json['anchorY'] as num?)?.toDouble() ?? 0,
    length: (json['length'] as num?)?.toDouble() ?? 50,
    stiffness: (json['stiffness'] as num?)?.toDouble() ?? 40,
    damping: (json['damping'] as num?)?.toDouble() ?? 4,
    breakDistance: (json['breakDistance'] as num?)?.toDouble() ?? 0,
  );
}

/// Emitted when a [Joint] snaps past its `breakDistance` (the component is
/// removed).
class JointBroken {
  JointBroken({required this.entity, required this.other});

  final EntityId entity;
  final EntityId? other;
}

/// Solves every [Joint] each step. Register it **before** `MovementSystem`, so
/// the velocity changes it makes are integrated in the same step.
class JointSystem extends System {
  @override
  String get name => 'joint';

  @override
  void update(World world, double dt) {
    final joints = world.componentsOf<Joint>();
    if (joints.length == 0 || dt <= 0) return;
    final positions = world.componentsOf<Position>();
    final velocities = world.componentsOf<Velocity>();
    final broken = <EntityId>[];
    for (var i = 0; i < joints.length; i++) {
      final aId = joints.entityAt(i);
      final j = joints.denseAt(i);
      final a = positions.get(aId);
      if (a == null) continue;
      final bId = j.other;
      final b = bId == null ? null : positions.get(bId);
      if (bId != null && b == null) continue; // the other end is gone
      final bx = b?.x ?? j.anchorX;
      final by = b?.y ?? j.anchorY;
      final dx = bx - a.x;
      final dy = by - a.y;
      final dist = math.sqrt(dx * dx + dy * dy);
      if (j.breakDistance > 0 && dist > j.breakDistance) {
        broken.add(aId);
        continue;
      }
      if (dist < 1e-9) continue;
      final nx = dx / dist;
      final ny = dy / dist;
      final stretch = dist - j.length;
      final va = velocities.get(aId);
      final vb = bId == null ? null : velocities.get(bId);
      // An anchored joint moves only its own entity; between two entities the
      // work is shared equally.
      final share = bId == null ? 1.0 : 0.5;

      if (j.kind == JointKind.rod) {
        a.x += nx * stretch * share;
        a.y += ny * stretch * share;
        if (b != null) {
          b.x -= nx * stretch * share;
          b.y -= ny * stretch * share;
        }
        // Remove the speed that would stretch or compress the rod.
        final rel =
            ((vb?.x ?? 0) - (va?.x ?? 0)) * nx +
            ((vb?.y ?? 0) - (va?.y ?? 0)) * ny;
        if (va != null) {
          va.x += nx * rel * share;
          va.y += ny * rel * share;
        }
        if (vb != null) {
          vb.x -= nx * rel * share;
          vb.y -= ny * rel * share;
        }
        continue;
      }

      if (j.kind == JointKind.rope && stretch <= 0) continue;
      final rel =
          ((vb?.x ?? 0) - (va?.x ?? 0)) * nx +
          ((vb?.y ?? 0) - (va?.y ?? 0)) * ny;
      final accel = j.stiffness * stretch + j.damping * rel;
      if (va != null) {
        va.x += nx * accel * dt * share;
        va.y += ny * accel * dt * share;
      }
      if (vb != null) {
        vb.x -= nx * accel * dt * share;
        vb.y -= ny * accel * dt * share;
      }
    }
    for (final id in broken) {
      final other = joints.get(id)?.other;
      joints.remove(id);
      world.events.emit(JointBroken(entity: id, other: other));
    }
  }
}

/// Registers [Joint] so it serializes.
void registerJointComponents(World world) {
  if (world.components.isRegistered('joint')) return;
  world.components.register<Joint>(
    'joint',
    (j) => j.toJson(),
    Joint.fromJson,
    schema: jointSchema,
  );
}
