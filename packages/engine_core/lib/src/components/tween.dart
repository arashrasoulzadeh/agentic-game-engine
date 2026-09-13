/// A handful of easing curves for `Tween` — a plain enum (not a
/// `double Function(double)` closure) so `Tween` stays JSON-plain and
/// agent-authorable, the same reasoning `AIState.behaviorId` uses a
/// string id instead of embedding a `Behavior` instance directly.
enum EasingType { linear, easeInQuad, easeOutQuad, easeInOutQuad }

double _ease(EasingType type, double t) {
  switch (type) {
    case EasingType.linear:
      return t;
    case EasingType.easeInQuad:
      return t * t;
    case EasingType.easeOutQuad:
      return t * (2 - t);
    case EasingType.easeInOutQuad:
      return t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t;
  }
}

/// Interpolates a single `double` from [from] to [to] over [duration]
/// seconds, advanced by `TweenSystem`. Deliberately just a value holder,
/// not something that writes into another component itself — a game
/// reads `.value` each tick and applies it to whatever it's driving
/// (a `Position.x`, a `Sprite.scaleX`, a UI widget's opacity...), the
/// same "doesn't hide how it works" approach as the rest of this
/// engine. Use one `Tween` per animated value; drive several at once
/// (e.g. a screen-shake's x *and* y) with separate entities/components.
///
/// [loop] restarts from [from] every time it completes; [pingPong]
/// reverses direction instead of restarting (a back-and-forth wobble).
/// At most one of the two makes sense set at once — [pingPong] wins if
/// both are set. Neither ever fires `TweenCompleteEvent`, since neither
/// has a defined "done" state.
class Tween {
  double from;
  double to;
  double duration;
  double elapsed;
  bool loop;
  bool pingPong;
  EasingType easing;

  /// Ping-pong direction: `true` means currently animating from [to]
  /// back to [from]. Internal state, but serialized so a saved/reloaded
  /// tween resumes going the same direction rather than snapping back.
  bool reversed;

  Tween({
    required this.from,
    required this.to,
    required this.duration,
    this.elapsed = 0,
    this.loop = false,
    this.pingPong = false,
    this.easing = EasingType.linear,
    this.reversed = false,
  });

  double get rawProgress => duration <= 0 ? 1 : (elapsed / duration).clamp(0.0, 1.0);

  double get value {
    final t = _ease(easing, rawProgress);
    return reversed ? to + (from - to) * t : from + (to - from) * t;
  }

  bool get isComplete => !loop && !pingPong && elapsed >= duration;

  Map<String, dynamic> toJson() => {
        'from': from,
        'to': to,
        'duration': duration,
        'elapsed': elapsed,
        'loop': loop,
        'pingPong': pingPong,
        'easing': easing.name,
        'reversed': reversed,
      };

  factory Tween.fromJson(Map<String, dynamic> json) => Tween(
        from: (json['from'] as num).toDouble(),
        to: (json['to'] as num).toDouble(),
        duration: (json['duration'] as num).toDouble(),
        elapsed: (json['elapsed'] as num?)?.toDouble() ?? 0,
        loop: json['loop'] as bool? ?? false,
        pingPong: json['pingPong'] as bool? ?? false,
        easing: EasingType.values.firstWhere(
          (e) => e.name == json['easing'],
          orElse: () => EasingType.linear,
        ),
        reversed: json['reversed'] as bool? ?? false,
      );
}
