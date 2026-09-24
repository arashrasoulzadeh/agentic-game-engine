import 'package:engine_core/engine_core.dart';

import '../physics/platformer_controller.dart';

/// Parry/precise-deflect component. A short input-timing window that,
/// when an incoming hit lands inside it, negates the damage and instead
/// opens the attacker up (stuns them, marks them vulnerable, etc.).
///
/// Unlike [Health]'s invincibility window (which simply ignores damage),
/// a parry requires *timing* — the parry must be active when the hit
/// connects. The window is typically very short (e.g., 0.1-0.2s) and
/// started by a dedicated parry input (not the attack button).
///
/// [parryWindowSeconds] — how long the parry stays active after being
/// triggered. Default 0.15s.
///
/// [parryStunSeconds] — how long the *attacker* is stunned when parried.
/// Default 0.5s.
///
/// [parryCooldownSeconds] — minimum time between parry attempts. Prevents
/// spamming. Default 0.5s.
///
/// Managed by [ParrySystem] — call [requestParry] from input/AI to start
/// the window, the system counts down [parryTimer] and [parryCooldownTimer].
class Parry {
  /// Time remaining in the active parry window. > 0 means a hit now will be parried.
  double parryTimer;

  /// Cooldown before another parry can be requested.
  double parryCooldownTimer;

  /// How long the parry window stays open after request.
  final double parryWindowSeconds;

  /// How long the attacker is stunned on successful parry.
  final double parryStunSeconds;

  /// Minimum time between parry attempts.
  final double parryCooldownSeconds;

  /// Whether a parry is currently active (window open).
  bool get isParrying => parryTimer > 0;

  /// Whether a parry can be requested right now (not on cooldown).
  bool get canParry => parryCooldownTimer <= 0;

  Parry({
    this.parryTimer = 0,
    this.parryCooldownTimer = 0,
    this.parryWindowSeconds = 0.15,
    this.parryStunSeconds = 0.5,
    this.parryCooldownSeconds = 0.5,
  });

  /// Requests a parry attempt. Returns true if the parry window was started.
  /// Called from input system or AI behavior when parry button pressed.
  bool requestParry() {
    if (canParry) {
      parryTimer = parryWindowSeconds;
      parryCooldownTimer = parryCooldownSeconds;
      return true;
    }
    return false;
  }

  Map<String, dynamic> toJson() => {
        'parryTimer': parryTimer,
        'parryCooldownTimer': parryCooldownTimer,
        'parryWindowSeconds': parryWindowSeconds,
        'parryStunSeconds': parryStunSeconds,
        'parryCooldownSeconds': parryCooldownSeconds,
      };

  factory Parry.fromJson(Map<String, dynamic> json) => Parry(
        parryTimer: (json['parryTimer'] as num?)?.toDouble() ?? 0,
        parryCooldownTimer: (json['parryCooldownTimer'] as num?)?.toDouble() ?? 0,
        parryWindowSeconds: (json['parryWindowSeconds'] as num?)?.toDouble() ?? 0.15,
        parryStunSeconds: (json['parryStunSeconds'] as num?)?.toDouble() ?? 0.5,
        parryCooldownSeconds: (json['parryCooldownSeconds'] as num?)?.toDouble() ?? 0.5,
      );
}

/// Emitted when a parry successfully deflects an attack. The attacker
/// ([source]) is stunned for [Parry.parryStunSeconds] and made vulnerable.
class ParrySuccessEvent {
  final EntityId defender;
  final EntityId attacker;
  ParrySuccessEvent(this.defender, this.attacker);
}

/// System that counts down parry timers and handles parry logic on hit.
/// Also integrates with damageEntity to check for active parry.
class ParrySystem implements System {
  @override
  String get name => 'parry';

  @override
  void update(World world, double dt) {
    final parries = world.storeOf<Parry>();
    for (var i = 0; i < parries.length; i++) {
      final parry = parries.denseAt(i);
      if (parry.parryTimer > 0) {
        parry.parryTimer = (parry.parryTimer - dt).clamp(0, double.infinity);
      }
      if (parry.parryCooldownTimer > 0) {
        parry.parryCooldownTimer = (parry.parryCooldownTimer - dt).clamp(0, double.infinity);
      }
    }
  }
}

/// Extension on World to check/handle parry in damage flow.
/// Call this from your damage handling code (or modify damageEntity)
/// to integrate parry logic.
extension ParryWorld on World {
  /// Attempts to parry an incoming hit. If [target] has an active parry
  /// window, the hit is negated, attacker is stunned, and
  /// [ParrySuccessEvent] fires. Returns true if parried.
  bool tryParry(EntityId target, EntityId attacker) {
    final parry = storeOf<Parry>().get(target);
    if (parry != null && parry.isParrying) {
      // Successful parry!
      parry.parryTimer = 0; // Consume the parry window

      // Stun the attacker
      final attackerController = storeOf<PlatformerController>().get(attacker);
      if (attackerController != null) {
        attackerController.hitstunSeconds = parry.parryStunSeconds;
      }

      // Make attacker vulnerable (could add a "parried" flag component)
      events.emit(ParrySuccessEvent(target, attacker));
      return true;
    }
    return false;
  }
}