import 'package:engine_core/engine_core.dart';

import 'health.dart';

/// One health-threshold transition in a boss fight. [healthFraction]
/// (in `(0, 1]`) is `Health.current / Health.max` at or below which
/// this phase activates — [patternId] is opaque to the engine (a game
/// reads it off `BossPhaseChangedEvent` to switch its own AI/attack
/// pattern, the same "reference by id, game owns the meaning" pattern
/// `AIState`/`TriggerZone` already use elsewhere in this engine).
///
/// [cinematicSteps], if given, is called fresh each time this phase
/// triggers to build a one-shot `CinematicStep` list played via an
/// internal `CinematicSystem` — a *factory*, not a list, because a
/// `CinematicStep` holds its own mutable progress state and can't be
/// replayed once consumed (same reason `TweenStep`/`WaitStep` are
/// built fresh per cutscene today).
class BossPhase {
  final double healthFraction;
  final String patternId;
  final List<CinematicStep> Function()? cinematicSteps;

  BossPhase({
    required this.healthFraction,
    required this.patternId,
    this.cinematicSteps,
  });
}

/// Fired the tick a boss's `Health` first crosses at or below a
/// `BossPhase.healthFraction` — a game's cue to switch attack
/// patterns/behavior for [entity] to whatever [patternId] means to it.
/// Fires once per phase, never repeats for the same phase even if
/// health fluctuates back up and down again (healing mid-fight isn't
/// modeled as "un-triggering" a phase).
class BossPhaseChangedEvent {
  final EntityId entity;
  final String patternId;
  final int phaseIndex;
  BossPhaseChangedEvent(this.entity, this.patternId, this.phaseIndex);
}

/// Ties `CinematicSystem` (a scripted one-shot sequence) and
/// `Health`/`damageEntity` (generic combat) together for the exact gap
/// TODO.md called out: "at 50% health, play this cinematic beat and
/// switch attack patterns" had no platformer-specific helper, so every
/// boss fight had to hand-roll that state machine from scratch.
///
/// Watches [entity]'s `Health.current / Health.max` each tick against
/// [phases], which must be given in **descending** `healthFraction`
/// order (validated in the constructor — phase 0 is the first to
/// trigger as health drops, matching how a fight is naturally
/// authored top-to-bottom). The tick the fraction first drops to or
/// below a not-yet-triggered phase's threshold, this emits
/// `BossPhaseChangedEvent` and, if that phase has [BossPhase.cinematicSteps],
/// starts playing it via an internal `CinematicSystem` instance — not
/// registered on `World` itself, just driven directly from this
/// system's own `update`, so a boss fight's cutscene beats don't need
/// a separate system add/remove dance as they start and finish.
///
/// A single large hit that crosses more than one threshold in the same
/// tick fires every crossed phase's event, in order — only the last
/// one's cinematic (if any) actually plays; an earlier phase's beat is
/// skipped rather than queued, since a boss taking burst damage past
/// an intermediate phase generally wants the *current* phase's intro,
/// not a queue of every phase it blew through.
class BossPhaseSystem implements System {
  final EntityId entity;
  final List<BossPhase> phases;
  int _nextPhaseIndex = 0;
  CinematicSystem? _activeCinematic;

  BossPhaseSystem(this.entity, this.phases) {
    for (var i = 1; i < phases.length; i++) {
      if (phases[i].healthFraction > phases[i - 1].healthFraction) {
        throw ArgumentError(
            'BossPhaseSystem.phases must be given in descending healthFraction '
            'order (phase $i has ${phases[i].healthFraction}, phase ${i - 1} has '
            '${phases[i - 1].healthFraction})');
      }
    }
  }

  @override
  String get name => 'bossPhase';

  /// Whether a phase's cinematic beat is currently playing — a game
  /// can check this the same way it checks `CinematicSystem.isPlaying`
  /// to gate input/AI during the beat.
  bool get isInCinematic => _activeCinematic?.isPlaying ?? false;

  @override
  void update(World world, double dt) {
    if (_activeCinematic != null) {
      _activeCinematic!.update(world, dt);
      if (!_activeCinematic!.isPlaying) _activeCinematic = null;
    }

    final health = world.storeOf<Health>().get(entity);
    if (health == null || health.max <= 0) return;
    final fraction = health.current / health.max;

    while (_nextPhaseIndex < phases.length &&
        fraction <= phases[_nextPhaseIndex].healthFraction) {
      final phase = phases[_nextPhaseIndex];
      final phaseIndex = _nextPhaseIndex;
      _nextPhaseIndex++;
      world.events.emit(BossPhaseChangedEvent(entity, phase.patternId, phaseIndex));

      final steps = phase.cinematicSteps?.call();
      if (steps != null && steps.isNotEmpty) {
        _activeCinematic = CinematicSystem(steps);
      }
    }
  }
}
