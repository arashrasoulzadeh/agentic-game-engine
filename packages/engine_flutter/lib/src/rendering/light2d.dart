/// A point (or cone) light for `EngineView`'s ambient-darkness lighting
/// pass (see `EngineView.ambientBrightness`) — a torch glow, a
/// flashlight highlight, an explosion flash. Reveals the already-drawn
/// scene through the darkness rather than recoloring it by default:
/// brightness/falloff is the core effect, with [colorArgb] as an
/// optional additive tint layered on top (see its own doc comment) and
/// [castsShadows] as an optional real-occlusion mode — every field
/// beyond [radius]/[intensity] is opt-in and off by default, so a plain
/// `Light2D()` behaves exactly like the very first version of this
/// component.
class Light2D {
  double radius;

  /// How fully this light reveals the scene at its center, `0`
  /// (invisible — no reveal at all) to `1` (fully revealed, the
  /// scene's true colors), falling off smoothly to `0` again at
  /// [radius]'s edge.
  double intensity;

  /// Additive color tint layered on top of the brightness reveal,
  /// strongest at the center and fading to nothing at [radius]'s edge
  /// — a warm torch glow, a cold blue moonlight patch. The **alpha**
  /// channel of this color is the tint's strength; alpha `0` (the
  /// default, `0x00FFFFFF`) means no tint pass runs at all — the exact
  /// original brightness-only behavior, at no extra draw cost. An
  /// opaque-ish color (e.g. `0xAAFF6600` for orange) makes the tint
  /// visible; RGB is the hue, alpha is "how strong."
  int colorArgb;

  /// `null` (default) is a full 360° point light. Set together with
  /// [coneDirection] for a flashlight/directional-beam shape instead —
  /// the reveal (and, if [castsShadows] is on, the shadow raycasting)
  /// is then limited to this angular width in radians, centered on
  /// [coneDirection].
  double? coneAngle;

  /// Radians, `0` pointing along the positive x-axis (screen/world
  /// "right"), increasing clockwise — which way [coneAngle] points.
  /// Meaningless (and ignored) while [coneAngle] is `null`.
  double coneDirection;

  /// `false` (default) reveals a plain circle (or cone), the original
  /// behavior — no awareness of level geometry at all, so a light
  /// shines straight through a wall. `true` casts real rays (via
  /// `raycastTileMap`, the same primitive AI line-of-sight already
  /// uses) out to [radius] and reveals only up to whatever solid tile
  /// each ray first hits, so `TileMap` walls actually block light.
  /// Meaningfully more expensive than the plain-circle path (one
  /// raycast per sampled angle per light per frame) — opt in per light
  /// that's actually near occluding geometry, not globally.
  bool castsShadows;

  /// `false` (default, matching `raycastTileMap`'s own default) means
  /// a one-way tile (landable from above only) never blocks this
  /// light, same as `WorldView.hasLineOfSight`'s default — a one-way
  /// platform is usually meant to be seen/shot through from below.
  /// Set `true` for a light where that reads wrong: a one-way platform
  /// still *renders* as an opaque-looking surface, so a torch placed
  /// underneath one would otherwise visibly shine straight through
  /// something that looks solid. Meaningless unless [castsShadows] or
  /// [coneAngle] is also set — there's no raycasting to affect
  /// otherwise.
  bool blockOneWayPlatforms;

  /// Blur radius (logical pixels, pre-`Camera.zoom`) `EngineView`
  /// applies to this light's reveal/tint paints when [castsShadows] or
  /// [coneAngle] gives it a visibility-polygon edge to soften — `3`
  /// (the default) softens the polygon's straight, faceted edges (an
  /// artifact of approximating a curve with [shadowRayCount] straight
  /// segments) into a gentler gradient instead of a hard, jagged
  /// cutoff. Raise it for a deliberately soft/diffuse light source (a
  /// hazy torch, moonlight through leaves); `0` gives a fully hard,
  /// unblurred polygon edge. Meaningless for a plain circular light,
  /// which has no polygon edge to soften in the first place — the
  /// gradient's own falloff already handles that case.
  double shadowEdgeSoftness;

  /// Hz-ish oscillation speed for a flickering/guttering effect (a
  /// torch, a failing warning light) — `0` (default) disables
  /// flickering entirely, [intensity]/[radius] stay exactly as set.
  /// When `> 0`, `LightFlickerSystem` varies [intensity]/[radius]
  /// around [baseIntensity]/[baseRadius] each tick; read/write
  /// [intensity]/[radius] directly for a *steady* light, and
  /// [baseIntensity]/[baseRadius] instead once flickering (changing
  /// [intensity] directly would just be overwritten next tick).
  double flickerSpeed;

  /// How far [intensity]/[radius] swing from their base values while
  /// flickering, as a fraction (`0`–`1`) — `0.3` means each oscillates
  /// roughly ±30%. Meaningless while [flickerSpeed] is `0`.
  double flickerAmount;

  /// The steady values `LightFlickerSystem` oscillates [intensity]/
  /// [radius] around. Defaulted from the constructor's `intensity`/
  /// `radius` arguments so a game enabling flicker on an existing
  /// light doesn't have to specify these separately.
  double baseIntensity;
  double baseRadius;

  /// Seconds of flicker oscillation elapsed — advanced by
  /// `LightFlickerSystem`, not meant to be set from game code.
  double flickerElapsed;

  /// How many rays `EngineView` samples around this light when building
  /// its visibility polygon — only meaningful while [castsShadows] is
  /// on or [coneAngle] is set (the plain-circle fast path ignores it
  /// entirely). `48` (the default, and this feature's original fixed
  /// value) is a reasonable middle ground; raise it for one big,
  /// prominent shadow-casting light where faceted polygon edges would
  /// actually be visible, or lower it to cut cost when a level has many
  /// small shadow-casting lights on screen at once (each ray is one
  /// `raycastTileMap` call). Clamped to at least `3` when used — fewer
  /// rays than that can't describe a closed polygon.
  int shadowRayCount;

  /// Time constant (seconds) `EngineView` exponentially smooths each
  /// sampled shadow ray's hit distance toward its freshly-raycast value
  /// by, instead of snapping to it every frame. `0` (default) disables
  /// smoothing entirely — every ray uses its raw distance immediately,
  /// the original behavior. A light attached to a moving entity
  /// re-raycasts fresh from scratch every frame; as the entity crosses
  /// a tile boundary, some rays' hit tile (and so their distance) can
  /// change in a small, discrete jump rather than a smooth continuous
  /// change, which reads as the shadow polygon's edge visibly popping/
  /// flickering while the light moves — smoothing turns that jump into
  /// a brief, smooth transition instead. Smaller values track the raw
  /// value more closely (snappier, less smoothing); larger values lag
  /// more but hide jumps more thoroughly. `0.08`–`0.15` is a reasonable
  /// starting point for a light following a walking character.
  /// Meaningless unless [castsShadows] or [coneAngle] is set — there's
  /// no raycasting to smooth otherwise.
  double shadowSmoothingSeconds;

  /// Per-ray smoothed distances from the last frame `EngineView`
  /// rendered this light — internal render-side cache maintained
  /// entirely by `EngineView`, not meant to be read or set from game
  /// code, and deliberately **not** included in [toJson]/[fromJson]:
  /// it's sized to [shadowRayCount] and holds derived, per-frame
  /// rendering state, not anything meaningful to persist in a save or
  /// send over the agent-facing JSON API. Starts empty; `EngineView`
  /// (re)allocates it (filled with [radius], i.e. "fully lit," so the
  /// first frame doesn't smooth in *from* a shadowed state) the first
  /// time it renders this light, or whenever [shadowRayCount] changes.
  List<double> smoothedShadowDistances = <double>[];

  Light2D({
    this.radius = 100,
    this.intensity = 1,
    this.colorArgb = 0x00FFFFFF,
    this.coneAngle,
    this.coneDirection = 0,
    this.castsShadows = false,
    this.blockOneWayPlatforms = false,
    this.flickerSpeed = 0,
    this.flickerAmount = 0.3,
    double? baseIntensity,
    double? baseRadius,
    this.flickerElapsed = 0,
    this.shadowRayCount = 48,
    this.shadowSmoothingSeconds = 0,
    this.shadowEdgeSoftness = 3,
  })  : baseIntensity = baseIntensity ?? intensity,
        baseRadius = baseRadius ?? radius;

  Map<String, dynamic> toJson() => {
        'radius': radius,
        'intensity': intensity,
        'colorArgb': colorArgb,
        if (coneAngle != null) 'coneAngle': coneAngle,
        'coneDirection': coneDirection,
        'castsShadows': castsShadows,
        'blockOneWayPlatforms': blockOneWayPlatforms,
        'flickerSpeed': flickerSpeed,
        'flickerAmount': flickerAmount,
        'baseIntensity': baseIntensity,
        'baseRadius': baseRadius,
        'flickerElapsed': flickerElapsed,
        'shadowRayCount': shadowRayCount,
        'shadowSmoothingSeconds': shadowSmoothingSeconds,
        'shadowEdgeSoftness': shadowEdgeSoftness,
      };

  factory Light2D.fromJson(Map<String, dynamic> json) => Light2D(
        radius: (json['radius'] as num?)?.toDouble() ?? 100,
        intensity: (json['intensity'] as num?)?.toDouble() ?? 1,
        colorArgb: (json['colorArgb'] as num?)?.toInt() ?? 0x00FFFFFF,
        coneAngle: (json['coneAngle'] as num?)?.toDouble(),
        coneDirection: (json['coneDirection'] as num?)?.toDouble() ?? 0,
        castsShadows: json['castsShadows'] as bool? ?? false,
        blockOneWayPlatforms: json['blockOneWayPlatforms'] as bool? ?? false,
        flickerSpeed: (json['flickerSpeed'] as num?)?.toDouble() ?? 0,
        flickerAmount: (json['flickerAmount'] as num?)?.toDouble() ?? 0.3,
        baseIntensity: (json['baseIntensity'] as num?)?.toDouble(),
        baseRadius: (json['baseRadius'] as num?)?.toDouble(),
        flickerElapsed: (json['flickerElapsed'] as num?)?.toDouble() ?? 0,
        shadowRayCount: (json['shadowRayCount'] as num?)?.toInt() ?? 48,
        shadowSmoothingSeconds: (json['shadowSmoothingSeconds'] as num?)?.toDouble() ?? 0,
        shadowEdgeSoftness: (json['shadowEdgeSoftness'] as num?)?.toDouble() ?? 3,
      );
}
