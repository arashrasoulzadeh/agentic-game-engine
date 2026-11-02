import 'system.dart';
import 'world.dart';
import 'world_query.dart';

/// A countdown that lives on an entity and survives save/load and snapshots,
/// unlike the closure timers of `world.after`: when it reaches zero a
/// [CountdownTimerFired] event is emitted for whoever cares.
///
/// One per entity; use a separate entity for each independent timer. Needs
/// [CountdownTimerSystem] in the world to count down.
class CountdownTimer {
  /// Identifies the timer in [CountdownTimerFired.name].
  String name;

  /// Seconds left until it fires.
  double remaining;

  /// If set, the timer restarts with this many seconds each time it fires
  /// and stays; if null it fires once and removes itself.
  double? interval;

  CountdownTimer(this.name, this.remaining, {this.interval});

  Map<String, dynamic> toJson() => {
    'name': name,
    'remaining': remaining,
    if (interval != null) 'interval': interval,
  };

  factory CountdownTimer.fromJson(Map<String, dynamic> json) => CountdownTimer(
    json['name'] as String,
    (json['remaining'] as num).toDouble(),
    interval: (json['interval'] as num?)?.toDouble(),
  );
}

/// Emitted when a [CountdownTimer] on [entity] reaches zero.
class CountdownTimerFired {
  final int entity;
  final String name;
  CountdownTimerFired(this.entity, this.name);
}

/// Counts every [CountdownTimer] down by `dt` and emits [CountdownTimerFired].
///
/// A repeating timer fires once per elapsed interval, so a long step loses no
/// beats. A one-shot timer is removed (through `world.commands`) after firing.
class CountdownTimerSystem implements System {
  @override
  String get name => 'countdownTimer';

  @override
  void update(World world, double dt) {
    const epsilon = 1e-9;
    for (final (entity, timer) in world.query<CountdownTimer>()) {
      timer.remaining -= dt;
      var guard = 0;
      while (timer.remaining <= epsilon) {
        world.events.emit(CountdownTimerFired(entity, timer.name));
        final interval = timer.interval;
        if (interval == null || interval <= 0) {
          world.commands.remove<CountdownTimer>(entity);
          break;
        }
        timer.remaining += interval;
        if (++guard > 10000) break;
      }
    }
  }
}
