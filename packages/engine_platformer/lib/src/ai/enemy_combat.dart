import 'package:engine_core/engine_core.dart';
import 'package:engine_platformer/engine_platformer.dart';

/// Combat state for an enemy with explicit telegraph/wind-up.
/// Follows the pattern: Idle → Patrol → Alert → Approach → Telegraph → Attack → Recovery → Reposition
/// Plus special states: Stagger, Guard, Retreat
enum EnemyCombatState {
  /// Standing still, unaware of player
  idle,
  /// Walking back and forth on patrol route
  patrol,
  /// Aware of player but not yet engaging (heard sound, saw movement)
  alert,
  /// Moving toward player to get in attack range
  approach,
  /// Winding up attack (telegraph) - player can see this and react (parry/dodge)
  telegraph,
  /// Active attack hitbox out
  attack,
  /// Recovering after attack (cooldown, vulnerable)
  recovery,
  /// Moving to a new position after attack
  reposition,
  /// Stunned from parry/guard break/heavy hit
  stagger,
  /// Actively guarding/blocking
  guard,
  /// Fleeing (low health, overwhelmed)
  retreat,
}

/// Component holding the enemy's combat AI state and configuration.
/// The state machine is driven by [EnemyCombatBehavior].
class EnemyCombat {
  /// Current combat state.
  EnemyCombatState state;

  /// Time remaining in current state (for timed states like telegraph, attack, recovery).
  double stateTimer;

  /// Target entity (usually the player) this enemy is focused on.
  EntityId? target;

  /// Configuration - all overridable per-entity via AIState.memory
  /// Detection range for entering Alert state
  final double detectionRange;
  /// Range at which enemy starts Approach toward target
  final double engageRange;
  /// Range at which enemy triggers Telegraph (wind-up)
  final double attackRange;
  /// How long Telegraph (wind-up) lasts before Attack fires
  final double telegraphDuration;
  /// How long Attack hitbox stays active
  final double attackDuration;
  /// Recovery time after attack before can act again
  final double recoveryDuration;
  /// Time to spend in Reposition before returning to Patrol/Approach
  final double repositionDuration;
  /// Stagger duration (set externally when parried/guard broken)
  final double staggerDuration;
  /// Guard duration when choosing to block
  final double guardDuration;
  /// Retreat trigger health fraction (0-1)
  final double retreatHealthFraction;
  /// Speed when approaching
  final double approachSpeed;
  /// Speed when repositioning
  final double repositionSpeed;
  /// Speed when retreating
  final double retreatSpeed;
  /// Patrol speed (when no target)
  final double patrolSpeed;
  /// Patrol min/max X (for idle/patrol states)
  final double? patrolMinX;
  final double? patrolMaxX;

  EnemyCombat({
    this.state = EnemyCombatState.idle,
    this.stateTimer = 0,
    this.target,
    this.detectionRange = 300,
    this.engageRange = 200,
    this.attackRange = 48,
    this.telegraphDuration = 0.5,
    this.attackDuration = 0.2,
    this.recoveryDuration = 0.5,
    this.repositionDuration = 1.0,
    this.staggerDuration = 1.0,
    this.guardDuration = 0.5,
    this.retreatHealthFraction = 0.25,
    this.approachSpeed = 80,
    this.repositionSpeed = 60,
    this.retreatSpeed = 100,
    this.patrolSpeed = 40,
    this.patrolMinX,
    this.patrolMaxX,
  });

  /// Transitions to a new state, resetting stateTimer.
  void changeState(EnemyCombatState newState, {double? timer}) {
    state = newState;
    stateTimer = timer ?? 0;
  }

  Map<String, dynamic> toJson() => {
        'state': state.name,
        'stateTimer': stateTimer,
        'target': target,
        'detectionRange': detectionRange,
        'engageRange': engageRange,
        'attackRange': attackRange,
        'telegraphDuration': telegraphDuration,
        'attackDuration': attackDuration,
        'recoveryDuration': recoveryDuration,
        'repositionDuration': repositionDuration,
        'staggerDuration': staggerDuration,
        'guardDuration': guardDuration,
        'retreatHealthFraction': retreatHealthFraction,
        'approachSpeed': approachSpeed,
        'repositionSpeed': repositionSpeed,
        'retreatSpeed': retreatSpeed,
        'patrolSpeed': patrolSpeed,
        if (patrolMinX != null) 'patrolMinX': patrolMinX,
        if (patrolMaxX != null) 'patrolMaxX': patrolMaxX,
      };

  factory EnemyCombat.fromJson(Map<String, dynamic> json) => EnemyCombat(
        state: EnemyCombatState.values.firstWhere(
          (s) => s.name == json['state'],
          orElse: () => EnemyCombatState.idle,
        ),
        stateTimer: (json['stateTimer'] as num?)?.toDouble() ?? 0,
        target: json['target'] != null ? (json['target'] as int) : null,
        detectionRange: (json['detectionRange'] as num?)?.toDouble() ?? 300,
        engageRange: (json['engageRange'] as num?)?.toDouble() ?? 200,
        attackRange: (json['attackRange'] as num?)?.toDouble() ?? 48,
        telegraphDuration: (json['telegraphDuration'] as num?)?.toDouble() ?? 0.5,
        attackDuration: (json['attackDuration'] as num?)?.toDouble() ?? 0.2,
        recoveryDuration: (json['recoveryDuration'] as num?)?.toDouble() ?? 0.5,
        repositionDuration: (json['repositionDuration'] as num?)?.toDouble() ?? 1.0,
        staggerDuration: (json['staggerDuration'] as num?)?.toDouble() ?? 1.0,
        guardDuration: (json['guardDuration'] as num?)?.toDouble() ?? 0.5,
        retreatHealthFraction: (json['retreatHealthFraction'] as num?)?.toDouble() ?? 0.25,
        approachSpeed: (json['approachSpeed'] as num?)?.toDouble() ?? 80,
        repositionSpeed: (json['repositionSpeed'] as num?)?.toDouble() ?? 60,
        retreatSpeed: (json['retreatSpeed'] as num?)?.toDouble() ?? 100,
        patrolSpeed: (json['patrolSpeed'] as num?)?.toDouble() ?? 40,
        patrolMinX: (json['patrolMinX'] as num?)?.toDouble(),
        patrolMaxX: (json['patrolMaxX'] as num?)?.toDouble(),
      );
}

/// Emitted when an enemy enters Telegraph state - the "wind-up" before
/// an attack. Game code can listen for this to show visual telegraph
/// (flash, particle, animation) so player can parry/dodge.
class EnemyTelegraphEvent {
  final EntityId enemy;
  final EnemyCombatState previousState;
  final double telegraphDuration;
  EnemyTelegraphEvent(this.enemy, this.previousState, this.telegraphDuration);
}

/// Emitted when an enemy starts its Attack (hitbox active).
class EnemyAttackEvent {
  final EntityId enemy;
  final double attackDuration;
  EnemyAttackEvent(this.enemy, this.attackDuration);
}

/// Behavior implementing the full enemy combat state machine with telegraph.
/// Reads/writes EnemyCombat component and AIState.memory for per-entity config.
class EnemyCombatBehavior implements Behavior {
  EnemyCombatBehavior();

  @override
  Action decide(WorldView view, EntityId self) {
    final combat = view.component<EnemyCombat>(self);
    final aiState = view.component<AIState>(self);
    final pos = view.component<Position>(self);
    final health = view.component<Health>(self);
    final controller = view.component<PlatformerController>(self);
    final weapon = view.component<Weapon>(self);

    if (combat == null || aiState == null || pos == null) {
      return const NoOpAction();
    }

    // Apply per-entity memory overrides
    final detectionRange = (aiState.memory['detectionRange'] as num?)?.toDouble() ?? combat.detectionRange;
    final engageRange = (aiState.memory['engageRange'] as num?)?.toDouble() ?? combat.engageRange;
    final attackRange = (aiState.memory['attackRange'] as num?)?.toDouble() ?? combat.attackRange;
    final telegraphDuration = (aiState.memory['telegraphDuration'] as num?)?.toDouble() ?? combat.telegraphDuration;
    final attackDuration = (aiState.memory['attackDuration'] as num?)?.toDouble() ?? combat.attackDuration;
    final recoveryDuration = (aiState.memory['recoveryDuration'] as num?)?.toDouble() ?? combat.recoveryDuration;
    final repositionDuration = (aiState.memory['repositionDuration'] as num?)?.toDouble() ?? combat.repositionDuration;
    final approachSpeed = (aiState.memory['approachSpeed'] as num?)?.toDouble() ?? combat.approachSpeed;
    final repositionSpeed = (aiState.memory['repositionSpeed'] as num?)?.toDouble() ?? combat.repositionSpeed;
    final retreatSpeed = (aiState.memory['retreatSpeed'] as num?)?.toDouble() ?? combat.retreatSpeed;
    final patrolSpeed = (aiState.memory['patrolSpeed'] as num?)?.toDouble() ?? combat.patrolSpeed;
    final patrolMinX = (aiState.memory['patrolMinX'] as num?)?.toDouble() ?? combat.patrolMinX;
    final patrolMaxX = (aiState.memory['patrolMaxX'] as num?)?.toDouble() ?? combat.patrolMaxX;
    final retreatHealthFraction = (aiState.memory['retreatHealthFraction'] as num?)?.toDouble() ?? combat.retreatHealthFraction;

    // Count down state timer
    if (combat.stateTimer > 0) {
      return _CountdownAction(self, combat);
    }

    // Find target (player) if not set
    if (combat.target == null) {
      combat.target = _findTarget(view, self, detectionRange);
    }

    final target = combat.target;
    final hasTarget = target != null;
    final targetPos = hasTarget ? view.component<Position>(target!) : null;
    final distToTarget = (hasTarget && targetPos != null)
        ? (pos.x - targetPos.x).abs()
        : double.infinity;

    // Check health for retreat
    final shouldRetreat = health != null &&
        health.current > 0 &&
        health.current / health.max <= retreatHealthFraction;

    // State machine
    switch (combat.state) {
      case EnemyCombatState.idle:
        if (hasTarget && distToTarget <= detectionRange) {
          combat.changeState(EnemyCombatState.alert);
          return const NoOpAction(); // Will process alert next tick
        }
        if (patrolMinX != null && patrolMaxX != null) {
          combat.changeState(EnemyCombatState.patrol);
        }
        return const NoOpAction();

      case EnemyCombatState.patrol:
        if (hasTarget && distToTarget <= detectionRange) {
          combat.changeState(EnemyCombatState.alert);
          return const NoOpAction();
        }
        return _patrolAction(self, pos, aiState, patrolSpeed, patrolMinX, patrolMaxX);

      case EnemyCombatState.alert:
        if (!hasTarget || targetPos == null) {
          combat.changeState(EnemyCombatState.idle);
          return const NoOpAction();
        }
        if (distToTarget <= engageRange) {
          combat.changeState(EnemyCombatState.approach);
          return const NoOpAction();
        }
        // Face target while alert
        return _faceTargetAction(self, pos, targetPos, controller);

      case EnemyCombatState.approach:
        if (!hasTarget || targetPos == null) {
          combat.changeState(EnemyCombatState.idle);
          return const NoOpAction();
        }
        if (shouldRetreat) {
          combat.changeState(EnemyCombatState.retreat);
          return const NoOpAction();
        }
        if (distToTarget <= attackRange) {
          combat.changeState(EnemyCombatState.telegraph, timer: telegraphDuration);
          return _EmitTelegraphEventAction(self, EnemyCombatState.approach, telegraphDuration);
        }
        return _approachAction(self, pos, targetPos, controller, approachSpeed);

      case EnemyCombatState.telegraph:
        // Wind-up - just face target, timer counts down
        if (!hasTarget || targetPos == null) {
          combat.changeState(EnemyCombatState.idle);
          return const NoOpAction();
        }
        if (shouldRetreat) {
          combat.changeState(EnemyCombatState.retreat);
          return const NoOpAction();
        }
        return _faceTargetAction(self, pos, targetPos, controller);

      case EnemyCombatState.attack:
        // Attack hitbox active - handled by AttackSystem via Weapon.attackRequested
        if (weapon != null) {
          weapon.attackRequested = true;
        }
        combat.changeState(EnemyCombatState.recovery, timer: recoveryDuration);
        return _EmitAttackEventAction(self, attackDuration);

      case EnemyCombatState.recovery:
        // Vulnerable after attack
        if (shouldRetreat) {
          combat.changeState(EnemyCombatState.retreat);
          return const NoOpAction();
        }
        combat.changeState(EnemyCombatState.reposition, timer: repositionDuration);
        return const NoOpAction();

      case EnemyCombatState.reposition:
        if (!hasTarget || targetPos == null) {
          combat.changeState(patrolMinX != null ? EnemyCombatState.patrol : EnemyCombatState.idle);
          return const NoOpAction();
        }
        if (shouldRetreat) {
          combat.changeState(EnemyCombatState.retreat);
          return const NoOpAction();
        }
        return _repositionAction(self, pos, targetPos, controller, repositionSpeed);

      case EnemyCombatState.stagger:
        // Stunned - cannot act, timer counts down externally
        return const NoOpAction();

      case EnemyCombatState.guard:
        // Actively blocking - handled by Health.isGuarding
        if (health != null) {
          health.isGuarding = true;
        }
        combat.changeState(EnemyCombatState.recovery, timer: recoveryDuration);
        return const NoOpAction();

      case EnemyCombatState.retreat:
        if (!hasTarget || targetPos == null) {
          combat.changeState(EnemyCombatState.idle);
          return const NoOpAction();
        }
        return _retreatAction(self, pos, targetPos, controller, retreatSpeed);
    }
  }

  EntityId? _findTarget(WorldView view, EntityId self, double range) {
    // Find nearest entity with Health and Position (player-like)
    EntityId? nearest;
    double nearestDist = double.infinity;
    for (final entity in view.entitiesWith<Health>()) {
      if (entity == self) continue;
      final pos = view.component<Position>(entity);
      final health = view.component<Health>(entity);
      if (pos == null || health == null || health.isDead) continue;
      final dx = pos.x - (view.component<Position>(self)?.x ?? 0);
      final dist = dx.abs();
      if (dist <= range && dist < nearestDist) {
        nearestDist = dist;
        nearest = entity;
      }
    }
    return nearest;
  }

  Action _patrolAction(EntityId self, Position pos, AIState aiState, double speed, double? minX, double? maxX) {
    if (minX == null || maxX == null) return const NoOpAction();
    final dir = (aiState.memory['dir'] as num?)?.toDouble() ?? 1.0;
    var shouldFlip = (dir > 0 && pos.x >= maxX) || (dir < 0 && pos.x <= minX);
    final newDir = shouldFlip ? -dir : dir;
    return _PatrolStepAction(self, newDir * speed, shouldFlip ? newDir : null);
  }

  Action _faceTargetAction(EntityId self, Position pos, Position targetPos, PlatformerController? controller) {
    final dir = targetPos.x > pos.x ? 1.0 : -1.0;
    if (controller != null) {
      return _SetFacingAction(self, dir);
    }
    return const NoOpAction();
  }

  Action _approachAction(EntityId self, Position pos, Position targetPos, PlatformerController? controller, double speed) {
    final dir = targetPos.x > pos.x ? 1.0 : -1.0;
    if (controller != null) {
      return _SetFacingAndVelocityAction(self, dir, speed);
    }
    return const NoOpAction();
  }

  Action _repositionAction(EntityId self, Position pos, Position targetPos, PlatformerController? controller, double speed) {
    // Move away from target to create spacing
    final dir = targetPos.x > pos.x ? -1.0 : 1.0;
    if (controller != null) {
      return _SetFacingAndVelocityAction(self, dir, speed);
    }
    return const NoOpAction();
  }

  Action _retreatAction(EntityId self, Position pos, Position targetPos, PlatformerController? controller, double speed) {
    // Run away from target
    final dir = targetPos.x > pos.x ? -1.0 : 1.0;
    if (controller != null) {
      return _SetFacingAndVelocityAction(self, dir, speed);
    }
    return const NoOpAction();
  }
}

class _CountdownAction implements Action {
  final EntityId entity;
  final EnemyCombat combat;
  _CountdownAction(this.entity, this.combat);

  @override
  void apply(World world) {
    final combat = world.storeOf<EnemyCombat>().get(entity);
    if (combat != null && combat.stateTimer > 0) {
      // Timer is counted down by the behavior's decide, not here
      // This action exists to consume the tick while timer counts
    }
  }
}

class _PatrolStepAction implements Action {
  final EntityId entity;
  final double vx;
  final double? newDirection;
  _PatrolStepAction(this.entity, this.vx, this.newDirection);

  @override
  void apply(World world) {
    world.storeOf<Velocity>().set(entity, Velocity(vx, 0));
    if (newDirection != null) {
      world.storeOf<AIState>().get(entity)?.memory['dir'] = newDirection;
    }
  }
}

class _SetFacingAction implements Action {
  final EntityId entity;
  final double facing;
  _SetFacingAction(this.entity, this.facing);

  @override
  void apply(World world) {
    world.storeOf<PlatformerController>().get(entity)?.facingSign = facing;
  }
}

class _SetFacingAndVelocityAction implements Action {
  final EntityId entity;
  final double facing;
  final double speed;
  _SetFacingAndVelocityAction(this.entity, this.facing, this.speed);

  @override
  void apply(World world) {
    final controller = world.storeOf<PlatformerController>().get(entity);
    if (controller != null) {
      controller.facingSign = facing;
    }
    world.storeOf<Velocity>().set(entity, Velocity(facing * speed, 0));
  }
}

class _EmitTelegraphEventAction implements Action {
  final EntityId enemy;
  final EnemyCombatState previousState;
  final double telegraphDuration;
  _EmitTelegraphEventAction(this.enemy, this.previousState, this.telegraphDuration);

  @override
  void apply(World world) {
    world.events.emit(EnemyTelegraphEvent(enemy, previousState, telegraphDuration));
  }
}

class _EmitAttackEventAction implements Action {
  final EntityId enemy;
  final double attackDuration;
  _EmitAttackEventAction(this.enemy, this.attackDuration);

  @override
  void apply(World world) {
    world.events.emit(EnemyAttackEvent(enemy, attackDuration));
  }
}