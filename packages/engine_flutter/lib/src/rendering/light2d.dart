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
  /// [coneAngle] gives it a visibility-polygon edge to soften — softens
  /// the polygon's straight, faceted edges (an artifact of
  /// approximating a curve with [shadowRayCount] straight segments)
  /// and the hard line where a shadow cuts the light off, into a
  /// gradient instead of a sharp, unnatural-looking cutoff. `8` (the
  /// default) is sized to actually read as soft against a typical
  /// light radius (a few pixels of blur is imperceptible on a
  /// 100–300px-radius light); raise it further for a deliberately
  /// hazy/diffuse source, or set `0` for a fully hard, unblurred edge.
  /// Meaningless for a plain circular light, which has no polygon edge
  /// to soften in the first place — the falloff gradient already
  /// handles that case.
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

  /// `true` (default, matching the original flicker behavior): [radius]
  /// oscillates along with [intensity]. `false` pins [radius] exactly
  /// at [baseRadius] every tick while [intensity] still flickers
  /// normally — for a [castsShadows] light specifically, this matters
  /// far beyond a visual choice: [radius] is part of the shadow
  /// raycast geometry (and `Light2D.cacheShadowGeometry`'s own cache
  /// key), so a flickering shadow-casting light with this left `true`
  /// re-raycasts from scratch *every single tick* even while
  /// completely stationary, since its geometry input is constantly
  /// changing — `cacheShadowGeometry` can never get a cache hit.
  /// Setting this `false` keeps the geometry perfectly stable frame to
  /// frame for a light that doesn't move, so `cacheShadowGeometry` can
  /// actually skip the raycast sweep almost every tick — a real,
  /// measured fps win for something as common as a flickering torch
  /// mounted on a wall. Meaningless while [flickerSpeed] is `0`.
  bool flickerAffectsRadius;

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

  /// Restricts which `zIndex` layer(s) this light's reveal/tint/shadow
  /// affects — `null` (default, for both [minZIndex] and [maxZIndex])
  /// means no restriction at all, the original "one light affects the
  /// whole screen regardless of any zIndex" behavior. Set one or both to
  /// scope a light to a specific band, e.g. a ground-level torch
  /// (`minZIndex: 0, maxZIndex: 0`) that shouldn't dim or reveal a
  /// foreground overlay or background parallax layer sitting at a
  /// different `zIndex`, even though it's on screen at the same time.
  /// `EngineView` implements this by rendering in z-bands (split at
  /// every light's `minZIndex`/`maxZIndex` boundary) and compositing
  /// each band's own lighting pass in isolation before the next band is
  /// drawn on top — a game with no light using these fields never pays
  /// for the extra bands (they collapse back to the original single
  /// full-screen pass). Doesn't affect a shadow-casting light's raycast
  /// geometry itself (still computed against the full `TileMap`
  /// regardless of z), only which drawn content the resulting reveal is
  /// allowed to touch.
  int? minZIndex;
  int? maxZIndex;

  /// `false` (default) recomputes this light's shadow-casting visibility
  /// polygon (a `raycastTileMap` sweep of [shadowRayCount] rays) fresh
  /// every single frame — always correct, but real, measurable cost for
  /// a light that in practice never moves relative to the level's
  /// geometry (a torch mounted on a wall). `true` skips that sweep and
  /// reuses the previous frame's per-ray *world-space* hit distances
  /// whenever every input that could change them ([radius],
  /// [coneAngle], [coneDirection], [shadowRayCount],
  /// [blockOneWayPlatforms], [castsShadows], [openAirFalloffScale], and
  /// this light's own world `Position`) is bit-for-bit identical to
  /// last frame's — the
  /// re-projection into *screen* space (so the polygon still correctly
  /// follows `Camera` panning/zooming even while cached) always happens
  /// fresh regardless. Invalidates immediately and completely the
  /// instant any of those inputs changes, never blends/interpolates
  /// toward the new value — deliberately not the same idea as
  /// [shadowSmoothingSeconds] (which reads as the shadow visibly lagging
  /// into place, rejected live earlier for exactly that reason): a
  /// cache hit must look pixel-identical to the equivalent uncached
  /// frame, only cheaper. Does **not** detect the level's own `TileMap`
  /// geometry changing out from under a light that itself hasn't moved
  /// (destroying a wall, opening a door) — nothing in this engine
  /// versions `TileMap` mutations yet, so there's no cheap way to
  /// detect that case. A game whose level geometry can change under a
  /// stationary shadow-casting light must leave this `false` (the
  /// default), or invalidate the cache itself by nudging [radius] (or
  /// any other keyed field) to force a recompute right when the
  /// geometry actually changes.
  bool cacheShadowGeometry;

  /// Peak alpha (`0`–`1`) of an additional plain-white additive glow
  /// drawn on top of the brightness reveal — `0` (default) draws
  /// nothing extra, the original behavior. Distinct from [colorArgb]'s
  /// tint (which recolors, and is skipped entirely while transparent):
  /// the brightness-reveal pass alone can only ever erase darkness back
  /// to the scene's *original* brightness (an alpha-erase floors at
  /// "fully revealed," it can never go past it), so two overlapping
  /// lights' reveals can't make the shared area brighter than either
  /// manages alone — real light is additive, and two torches standing
  /// close together should visibly brighten the ground between them
  /// beyond what either does by itself. This pass exists purely to
  /// supply that: like [colorArgb]'s tint, it uses `BlendMode.plus`
  /// against the real scene colors underneath, so overlapping lights'
  /// glows genuinely stack instead of capping at one light's own
  /// strength. A typical value is small (`0.1`–`0.25`) — this is meant
  /// to read as "brighter," not to wash out or recolor the scene the
  /// way a strong [colorArgb] tint would.
  double overbrightIntensity;

  /// Scales down the reveal radius, but *only* along a shadow-casting
  /// ray that travels its full length without hitting anything —
  /// `1.0` (default) leaves every ray's real distance untouched, the
  /// original behavior. A ray that *does* hit a solid surface short of
  /// [radius] is never affected regardless of this value, so a light
  /// still fully illuminates whatever surface/wall it's actually next
  /// to — only genuinely open, unobstructed directions (open sky above
  /// an outdoor level, say) get pulled in, addressing "a light reveals
  /// open air, not just surfaces": real light does travel through open
  /// air the same way it does anywhere else, but a game level's open
  /// volumes are usually far bigger than what a torch would
  /// realistically brighten, so an unshortened full-radius reveal into
  /// empty space above the ground reads as an artificial floating disc
  /// rather than a light actually illuminating something. Meaningless
  /// unless [castsShadows] is also on — there's no per-ray hit data to
  /// distinguish "open" from "surface-adjacent" without it, so a plain
  /// circular light is unaffected regardless of this value.
  double openAirFalloffScale;

  /// Internal render-side cache for [cacheShadowGeometry] — the world-
  /// space per-ray hit distances from the last time this light's shadow
  /// geometry was actually recomputed, plus every input that produced
  /// them (so `EngineView` can tell in O(1) whether they're still
  /// valid). Not meant to be read or set from game code, and
  /// deliberately excluded from [toJson]/[fromJson] — same reasoning as
  /// [smoothedShadowDistances]: derived, per-frame rendering state, not
  /// anything meaningful to persist in a save or send over the
  /// agent-facing JSON API.
  List<double>? cachedShadowDistances;
  double? cachedShadowWorldX;
  double? cachedShadowWorldY;
  double? cachedShadowRadius;
  double? cachedShadowConeAngle;
  double? cachedShadowConeDirection;
  int? cachedShadowRayCount;
  bool? cachedShadowBlockOneWay;
  bool? cachedShadowCastsShadows;
  double? cachedShadowOpenAirFalloffScale;

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
    this.flickerAffectsRadius = true,
    double? baseIntensity,
    double? baseRadius,
    this.flickerElapsed = 0,
    this.shadowRayCount = 48,
    this.shadowSmoothingSeconds = 0,
    this.shadowEdgeSoftness = 8,
    this.minZIndex,
    this.maxZIndex,
    this.cacheShadowGeometry = false,
    this.overbrightIntensity = 0,
    this.openAirFalloffScale = 1.0,
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
        'flickerAffectsRadius': flickerAffectsRadius,
        'baseIntensity': baseIntensity,
        'baseRadius': baseRadius,
        'flickerElapsed': flickerElapsed,
        'shadowRayCount': shadowRayCount,
        'shadowSmoothingSeconds': shadowSmoothingSeconds,
        'shadowEdgeSoftness': shadowEdgeSoftness,
        if (minZIndex != null) 'minZIndex': minZIndex,
        if (maxZIndex != null) 'maxZIndex': maxZIndex,
        'cacheShadowGeometry': cacheShadowGeometry,
        'overbrightIntensity': overbrightIntensity,
        'openAirFalloffScale': openAirFalloffScale,
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
        flickerAffectsRadius: json['flickerAffectsRadius'] as bool? ?? true,
        baseIntensity: (json['baseIntensity'] as num?)?.toDouble(),
        baseRadius: (json['baseRadius'] as num?)?.toDouble(),
        flickerElapsed: (json['flickerElapsed'] as num?)?.toDouble() ?? 0,
        shadowRayCount: (json['shadowRayCount'] as num?)?.toInt() ?? 48,
        shadowSmoothingSeconds: (json['shadowSmoothingSeconds'] as num?)?.toDouble() ?? 0,
        shadowEdgeSoftness: (json['shadowEdgeSoftness'] as num?)?.toDouble() ?? 8,
        minZIndex: (json['minZIndex'] as num?)?.toInt(),
        maxZIndex: (json['maxZIndex'] as num?)?.toInt(),
        cacheShadowGeometry: json['cacheShadowGeometry'] as bool? ?? false,
        overbrightIntensity: (json['overbrightIntensity'] as num?)?.toDouble() ?? 0,
        openAirFalloffScale: (json['openAirFalloffScale'] as num?)?.toDouble() ?? 1.0,
      );
}
