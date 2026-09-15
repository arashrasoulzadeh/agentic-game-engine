/// Weather conditions [DayNightCycle] blends into its ambient brightness/
/// tint -- see [DayNightCycle.weather].
enum Weather { clear, overcast, rain, fog }

/// Drives a looping day/night clock and current weather, computing the
/// ambient brightness/tint a renderer should wash the scene with each
/// frame. A plain mutable object the game owns and advances -- like
/// [Camera] (see `engine_flutter`), not an ECS component, since a world
/// has exactly one of these, not one per entity.
///
/// `EngineView.dayNightCycle` (`engine_flutter`) reads [ambientBrightness]/
/// [ambientColorArgb] each frame in place of the plain static
/// `EngineView.ambientBrightness` double, and calls [advance] once per
/// tick the same way it already calls `Camera.update`.
class DayNightCycle {
  DayNightCycle({
    this.hour = 12,
    this.dayLengthSeconds = 600,
    this.weather = Weather.clear,
    this.weatherIntensity = 1.0,
  });

  /// Current time of day, `0`-`24` (midnight to midnight), wrapping at
  /// `24`. Defaults to `12` (noon, full daylight) so a game that never
  /// touches this class renders exactly as it did before this existed.
  double hour;

  /// Real seconds for one full 24-hour cycle. `600` (10 minutes) by
  /// default -- fast enough to actually see change during a normal play
  /// session, slow enough not to feel frantic. `0` (or negative) freezes
  /// the clock -- [advance] becomes a no-op -- for a game that wants to
  /// drive [hour] itself (e.g. from a fixed in-game calendar/quest state
  /// instead of real elapsed time).
  double dayLengthSeconds;

  /// Current weather -- see [Weather].
  Weather weather;

  /// How strongly [weather] affects brightness/tint: `0` (no effect,
  /// identical to [Weather.clear]) to `1` (full effect). Lets a game
  /// fade weather in/out over a transition instead of switching
  /// instantly.
  double weatherIntensity;

  /// Advances [hour] by real elapsed seconds, wrapping at `24`. Call
  /// once per frame with the same `dt` driving everything else --
  /// mirrors `Camera.update(dt)`.
  void advance(double dt) {
    if (dayLengthSeconds <= 0) return;
    hour = (hour + dt / dayLengthSeconds * 24) % 24;
  }

  /// `0` (fully dark) to `1` (fully lit) from time of day alone, before
  /// [weather] is applied -- see [ambientBrightness] for the value a
  /// renderer actually uses. Night (22:00-05:00) sits at a dim floor
  /// rather than pure black so shapes stay legible; dawn (05:00-08:00)
  /// and dusk (18:00-22:00) ramp smoothly between the night floor and
  /// the daytime plateau (08:00-18:00).
  double get timeOfDayBrightness => _lerpStops(hour, _brightnessStops);

  /// [timeOfDayBrightness] further dimmed by [weather] (scaled by
  /// [weatherIntensity]) -- what a renderer should actually use each
  /// frame.
  double get ambientBrightness {
    final floor = switch (weather) {
      Weather.clear => 1.0,
      Weather.overcast => 0.6,
      Weather.rain => 0.5,
      Weather.fog => 0.7,
    };
    final multiplier = _lerp(1.0, floor, weatherIntensity.clamp(0, 1));
    return timeOfDayBrightness * multiplier;
  }

  /// ARGB tint for the ambient wash -- warm amber at dawn/dusk, deep
  /// blue at night, neutral white (no visible tint) at midday, then
  /// further desaturated toward grey/blue-grey by [weather].
  ///
  /// [_colorStops] hold pure *hues* (a dawn/dusk stop can be a full-
  /// brightness amber, not a hand-darkened one) -- this getter scales
  /// that hue's own magnitude toward black by [timeOfDayBrightness]
  /// before anything else touches it. That scaling is what keeps color
  /// and brightness from ever desyncing: without it, a hue stop timed
  /// independently of the brightness curve could still read as *bright*
  /// at an hour where the ambient overlay's alpha is already high (very
  /// dark) -- e.g. hour 19 sits only halfway through the 18-22 dusk
  /// *color* ramp (still ~50% white) while the *brightness* ramp is
  /// already well past its own halfway point, so the resulting overlay
  /// was a fairly bright warm wash composited at high alpha. On an
  /// unlit background that wash could end up visibly *brighter* than an
  /// area a light had actually revealed back to the scene's true (but
  /// comparatively dim) colors -- a real on-screen report of a player
  /// light that appeared to darken the scene relative to its unlit
  /// surroundings, caught by a real `EngineView` pixel-sampling test
  /// (`engine_flutter`'s `day_night_cycle_view_test.dart`). Scaling by
  /// [timeOfDayBrightness] instead means the tint can never be brighter
  /// than "how lit this hour already is," so it can't have this
  /// inversion regardless of exactly how the hue stops happen to be
  /// timed.
  int get ambientColorArgb {
    final hue = _lerpColorStops(hour, _colorStops);
    final timeColor = _lerpColor(0xFF000000, hue, timeOfDayBrightness.clamp(0, 1));
    final weatherTarget = switch (weather) {
      Weather.clear => null,
      Weather.overcast => 0xFF8A8A8A,
      Weather.rain => 0xFF5A6B7A,
      Weather.fog => 0xFFC8C8C8,
    };
    if (weatherTarget == null) return timeColor;
    // Fog washes out color most aggressively (real fog scatters light
    // evenly regardless of time of day); rain/overcast blend partially
    // so a night rainstorm still reads as darker-blue, not grey.
    final blend = weather == Weather.fog
        ? weatherIntensity.clamp(0, 1) * 0.8
        : weatherIntensity.clamp(0, 1) * 0.6;
    return _lerpColor(timeColor, weatherTarget, blend);
  }

  static const _brightnessStops = <(double, double)>[
    (0, 0.18),
    (5, 0.18),
    (8, 1.0),
    (18, 1.0),
    (22, 0.18),
    (24, 0.18),
  ];

  // Pure hues -- a full-brightness amber/blue is fine here even though
  // they represent dawn/dusk/night, because [ambientColorArgb] always
  // scales whatever this resolves to by [timeOfDayBrightness] before
  // using it. See that getter's own doc comment for why the scaling
  // (not hand-picking already-dark stop colors) is what actually keeps
  // color and brightness from desyncing.
  static const _colorStops = <(double, int)>[
    (0, 0xFF3A5580), // night -- moonlight blue hue
    (5, 0xFF3A5580),
    (6.5, 0xFFFFAA55), // dawn -- warm amber hue
    (8, 0xFFFFFFFF), // full daylight, no tint
    (18, 0xFFFFFFFF),
    (20, 0xFFFFAA55), // dusk -- same warm amber hue
    (22, 0xFF3A5580),
    (24, 0xFF3A5580),
  ];

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  static double _lerpStops(double x, List<(double, double)> stops) {
    for (var i = 0; i < stops.length - 1; i++) {
      final (x0, y0) = stops[i];
      final (x1, y1) = stops[i + 1];
      if (x >= x0 && x <= x1) {
        final t = x1 == x0 ? 0.0 : (x - x0) / (x1 - x0);
        return _lerp(y0, y1, t);
      }
    }
    return stops.last.$2;
  }

  static int _lerpColor(int a, int b, double t) {
    final aA = (a >> 24) & 0xFF, aR = (a >> 16) & 0xFF, aG = (a >> 8) & 0xFF, aB = a & 0xFF;
    final bA = (b >> 24) & 0xFF, bR = (b >> 16) & 0xFF, bG = (b >> 8) & 0xFF, bB = b & 0xFF;
    final rA = _lerp(aA.toDouble(), bA.toDouble(), t).round().clamp(0, 255);
    final rR = _lerp(aR.toDouble(), bR.toDouble(), t).round().clamp(0, 255);
    final rG = _lerp(aG.toDouble(), bG.toDouble(), t).round().clamp(0, 255);
    final rB = _lerp(aB.toDouble(), bB.toDouble(), t).round().clamp(0, 255);
    return (rA << 24) | (rR << 16) | (rG << 8) | rB;
  }

  static int _lerpColorStops(double x, List<(double, int)> stops) {
    for (var i = 0; i < stops.length - 1; i++) {
      final (x0, c0) = stops[i];
      final (x1, c1) = stops[i + 1];
      if (x >= x0 && x <= x1) {
        final t = x1 == x0 ? 0.0 : (x - x0) / (x1 - x0);
        return _lerpColor(c0, c1, t);
      }
    }
    return stops.last.$2;
  }
}
