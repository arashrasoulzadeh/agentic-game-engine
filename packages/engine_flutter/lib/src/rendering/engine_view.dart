import 'dart:math' show cos, exp, sin, pi;
import 'dart:ui' as ui;

import 'package:engine_core/engine_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/scheduler.dart';

import 'camera.dart';
import 'parallax_layer.dart';
import 'sprite.dart';
// Aliased -- `Text` collides with Flutter's own widget of the same
// name, which `package:flutter/widgets.dart` (imported above) already
// brings into scope.
import 'animation_transition.dart';
import 'hud_bar.dart';
import 'light2d.dart';
import 'nine_slice_sprite.dart';
import 'text.dart' as txt;
import 'debug_memory.dart';
import '../input/input.dart';
import 'sprite_atlas.dart';

/// The Flutter shell: owns the game loop (Ticker -> `world.step(dt)`),
/// forwards keyboard input, and paints sprites. Contains zero gameplay
/// logic — everything it reads comes from `World` component stores, so a
/// game built on this never has to hand-roll ticker/painter boilerplate
/// (previously duplicated in the CLI template and the stress-test app).
class EngineView extends StatefulWidget {
  final World world;
  final AtlasRegistry atlasRegistry;
  final Camera camera;
  final InputController? inputController;
  final EntityId? cameraFollowEntity;
  final Color backgroundColor;
  final bool paused;

  /// Shows a top-left debug panel: fps, tick count, live entity/sprite/
  /// particle counts, and resident memory (where available — not on
  /// web, `dart:io` has no memory API there, so that line is omitted).
  final bool showFpsOverlay;

  /// Draws collision debug outlines on top of everything else: a
  /// stroked circle for every `Collider` (green), and a stroked border
  /// per solid (red)/one-way (blue)/slope (orange) `TileMap` tile —
  /// "does my hitbox actually match what's drawn," the question this
  /// session's own physics debugging kept answering by hand-deriving
  /// coordinates instead. Doesn't draw `PlatformBody` rectangles —
  /// that's an `engine_platformer` concept `EngineView` (`engine_core`
  /// + Flutter only) can't reference without a backward dependency; a
  /// game using `PlatformBody` walls would need its own overlay for
  /// those specifically.
  final bool showColliderDebug;

  /// Called with the tap/click position converted to world coordinates
  /// via `camera.screenToWorld` — how a `Scene.handleTap` implementation
  /// (an ECS menu button, a door tapped in-world) learns where the
  /// player tapped without touching screen coordinates itself. Null (the
  /// default) disables tap handling entirely, so a game with no
  /// tap-driven UI pays nothing for it.
  final void Function(Offset worldPosition)? onWorldTap;

  /// When set, decouples simulation from display refresh rate: instead
  /// of calling `world.step(dt)` once per rendered frame with whatever
  /// `dt` that frame happened to take (so physics behavior subtly
  /// differs between e.g. 30fps and 144fps — the same gravity constant
  /// integrated over a bigger or smaller `dt` each tick), real elapsed
  /// time accumulates and `world.step(fixedTimestepSeconds)` runs
  /// however many whole steps fit (capped at 5 per rendered frame, so a
  /// long pause/tab-switch can't spiral into simulating an ever-growing
  /// backlog), each with the exact same `dt` regardless of frame rate.
  /// The leftover fractional step is used to interpolate `Position` for
  /// `Sprite`/`Particle` rendering between the last two simulated
  /// states, so motion still looks smooth at a display rate faster than
  /// the fixed step (60Hz simulation on a 120Hz display, say) instead
  /// of visibly stepping. `null` (default) keeps the original variable-
  /// timestep-per-frame behavior exactly as it was before this existed.
  /// A typical value is `1 / 60`.
  final double? fixedTimestepSeconds;

  /// `1.0` (default) disables the ambient-darkness lighting pass
  /// entirely — the scene renders exactly as before this existed, at
  /// no per-frame cost beyond one comparison. A lower value darkens
  /// the whole scene by that fraction (`0.0` is fully black), with
  /// every `Light2D` entity punching a soft, falling-off-to-nothing
  /// hole back through to the scene's true colors at its `Position` —
  /// see `Light2D`'s doc comment for what this basic version does and
  /// deliberately doesn't do (no colored tint, no shadow casting).
  final double ambientBrightness;

  /// Caps how often a tick (world step + repaint) actually runs, in
  /// frames per second — `null` (default) runs one tick per raw
  /// display callback, whatever the platform's actual refresh rate is
  /// (60Hz, 120Hz, uncapped on some web/desktop configurations). A
  /// ticker callback that arrives sooner than `1 / maxFps` since the
  /// last *processed* one is skipped outright (no world step, no
  /// repaint, negligible cost) rather than accumulated/batched, so
  /// this is a ceiling on frequency, not a guarantee of exactly that
  /// rate on a slower device. Set `60` for a stable, platform-
  /// independent simulation/render rate instead of however fast the
  /// display happens to run.
  final int? maxFps;

  const EngineView({
    super.key,
    required this.world,
    required this.atlasRegistry,
    required this.camera,
    this.inputController,
    this.cameraFollowEntity,
    this.backgroundColor = const Color(0xFF000000),
    this.paused = false,
    this.showFpsOverlay = false,
    this.showColliderDebug = false,
    this.onWorldTap,
    this.fixedTimestepSeconds,
    this.ambientBrightness = 1.0,
    this.maxFps,
  });

  @override
  State<EngineView> createState() => _EngineViewState();
}

class _EngineViewState extends State<EngineView>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  final FocusNode _focusNode = FocusNode();
  double _fps = 0;
  int? _memoryBytes;
  int _memorySampleCounter = 0;
  final List<double> _recentDts = [];
  double _lastDt = 0;

  // Fixed-timestep bookkeeping -- unused (stays at defaults, at no
  // per-frame cost beyond a null check) when `fixedTimestepSeconds` is
  // null.
  double _accumulator = 0;
  Map<EntityId, Position> _previousPositions = const {};
  double _interpolationAlpha = 1;

  static const _maxStepsPerFrame = 5;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    // maxFps caps how often a raw display callback is actually turned
    // into a world step + repaint -- a callback arriving sooner than
    // 1/maxFps since the last *processed* one (not the last raw
    // callback) is skipped outright, so a 120Hz display capped to 60
    // does half the simulation/render work instead of stepping with a
    // half-sized dt every callback. `_lastTick` deliberately isn't
    // updated on a skipped callback, so the eventual processed frame's
    // dt still reflects real elapsed time since the last one that did
    // anything.
    final maxFps = widget.maxFps;
    if (maxFps != null && maxFps > 0 && _lastTick != Duration.zero) {
      final minInterval = Duration(microseconds: (1e6 / maxFps).round());
      if (elapsed - _lastTick < minInterval) return;
    }
    final dt = _lastTick == Duration.zero
        ? 0.0
        : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (dt <= 0 || dt > 0.25) return;
    _lastDt = dt;
    if (widget.paused) return;

    final fixedDt = widget.fixedTimestepSeconds;
    if (fixedDt == null || fixedDt <= 0) {
      widget.world.step(dt);
      _interpolationAlpha = 1;
    } else {
      _accumulator += dt;
      var steps = 0;
      while (_accumulator >= fixedDt && steps < _maxStepsPerFrame) {
        _previousPositions = _snapshotPositions();
        widget.world.step(fixedDt);
        _accumulator -= fixedDt;
        steps++;
      }
      // A frame slow enough to hit the cap drops the excess backlog
      // rather than trying to catch up every subsequent frame too --
      // the alternative (never clamping) is the classic "spiral of
      // death" where a slow frame causes more simulation work, which
      // causes the next frame to be slower still.
      if (steps == _maxStepsPerFrame) _accumulator = 0;
      _interpolationAlpha = (_accumulator / fixedDt).clamp(0, 1);
    }
    // Decays/recomputes any active Camera.shake() offset -- called
    // unconditionally (not just when cameraFollowEntity is set), since
    // a static camera still needs to shake on e.g. an explosion.
    widget.camera.update(dt);

    if (widget.showFpsOverlay) {
      _recentDts.add(dt);
      if (_recentDts.length > 30) _recentDts.removeAt(0);
      final avgDt = _recentDts.reduce((a, b) => a + b) / _recentDts.length;
      _fps = avgDt > 0 ? 1 / avgDt : 0;

      // Sampling every ~30 ticks (not every frame) since reading RSS
      // is comparatively expensive and this is a debug readout, not
      // something the render loop should pay full cost for.
      _memorySampleCounter++;
      if (_memorySampleCounter >= 30) {
        _memorySampleCounter = 0;
        _memoryBytes = currentMemoryUsageBytes();
      }
    }

    final followId = widget.cameraFollowEntity;
    if (followId != null) {
      final pos = widget.world.storeOf<Position>().get(followId);
      if (pos != null) {
        final box = context.findRenderObject() as RenderBox?;
        widget.camera.follow(
          pos.x,
          pos.y,
          viewportSize: box?.size,
          worldWidth: widget.world.width,
          worldHeight: widget.world.height,
        );
      }
    }

    setState(() {});
  }

  /// A plain copy of every entity's current `Position` (value fields,
  /// not references — a `Position` is mutated in place by systems like
  /// `MovementSystem`, so keeping the same instance would make this
  /// "snapshot" silently track the live value instead of the moment it
  /// was taken). Only fixed-timestep mode calls this.
  Map<EntityId, Position> _snapshotPositions() {
    final positions = widget.world.storeOf<Position>();
    final snapshot = <EntityId, Position>{};
    for (var i = 0; i < positions.length; i++) {
      final entity = positions.entityAt(i);
      final p = positions.denseAt(i);
      snapshot[entity] = Position(p.x, p.y);
    }
    return snapshot;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// fps/tick/entity-sprite-particle counts, plus memory where
  /// available (not on web — see `debug_memory.dart`). Reads
  /// `storeOf<TileMap>`/`storeOf<Particle>` the same as the painter
  /// does, so it assumes the same `registerCoreComponents`/
  /// `registerFlutterComponents` precondition `EngineView` already has.
  String _debugText() {
    final world = widget.world;
    return [
      'fps: ${_fps.toStringAsFixed(0)}',
      'tick: ${world.tick}',
      'entities: ${world.entities.count}',
      'sprites: ${world.storeOf<Sprite>().length}',
      'particles: ${world.storeOf<Particle>().length}',
      if (_memoryBytes case final mem?) 'mem: ${(mem / (1024 * 1024)).toStringAsFixed(1)} MB',
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.inputController;
    final painter = _EnginePainter(
      world: widget.world,
      atlasRegistry: widget.atlasRegistry,
      camera: widget.camera,
      backgroundColor: widget.backgroundColor,
      showColliderDebug: widget.showColliderDebug,
      previousPositions: _previousPositions,
      interpolationAlpha: _interpolationAlpha,
      ambientBrightness: widget.ambientBrightness,
      frameDtSeconds: _lastDt,
    );

    Widget child = CustomPaint(painter: painter, size: Size.infinite);

    if (widget.showFpsOverlay) {
      child = Stack(
        children: [
          child,
          Positioned(
            left: 4,
            top: 4,
            child: Text(
              _debugText(),
              style: const TextStyle(
                color: Color(0xFF00FF00),
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      );
    }

    if (controller != null) {
      child = Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: (node, event) => controller.handleKeyEvent(event),
        child: child,
      );
    }

    final onWorldTap = widget.onWorldTap;
    if (onWorldTap == null) return child;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapUp: (details) {
        final box = context.findRenderObject() as RenderBox?;
        onWorldTap(widget.camera.screenToWorld(details.localPosition, box?.size ?? Size.zero));
      },
      child: child,
    );
  }
}

class _EnginePainter extends CustomPainter {
  final World world;
  final AtlasRegistry atlasRegistry;
  final Camera camera;
  final Color backgroundColor;
  final bool showColliderDebug;

  /// Positions as of just before the most recently simulated fixed
  /// step — empty (the default) when `EngineView.fixedTimestepSeconds`
  /// is null, in which case [interpolationAlpha] is always `1` and
  /// [_interpolated] is exactly equivalent to reading `Position`
  /// directly. See `EngineView.fixedTimestepSeconds`'s doc comment.
  final Map<EntityId, Position> previousPositions;
  final double interpolationAlpha;
  final double ambientBrightness;

  /// Real wall-clock seconds since the last rendered frame — used only
  /// to advance `Light2D.shadowSmoothingSeconds`' exponential smoothing
  /// at the actual render frame rate (not the simulation's fixed/
  /// variable tick rate, which can differ). `0` (the default) makes
  /// every smoothed ray jump straight to its raw value the first time
  /// it's read, same as smoothing being off.
  final double frameDtSeconds;

  _EnginePainter({
    required this.world,
    required this.atlasRegistry,
    required this.camera,
    required this.backgroundColor,
    this.showColliderDebug = false,
    this.previousPositions = const {},
    this.interpolationAlpha = 1,
    this.ambientBrightness = 1.0,
    this.frameDtSeconds = 0,
  }) : super(repaint: null);

  /// [current]'s position blended with wherever that entity was just
  /// before the last fixed step, by [interpolationAlpha] — smooths
  /// motion between simulated states when rendering happens more often
  /// than the fixed step runs. Falls back to [current] outright for an
  /// entity with no recorded previous position (just spawned this
  /// frame, or fixed-timestep mode isn't in use at all).
  Offset _interpolated(EntityId entity, Position current) {
    final prev = previousPositions[entity];
    if (prev == null) return Offset(current.x, current.y);
    return Offset(
      prev.x + (current.x - prev.x) * interpolationAlpha,
      prev.y + (current.y - prev.y) * interpolationAlpha,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = backgroundColor);

    final positions = world.storeOf<Position>();
    final items = <_DrawItem>[];
    var order = 0;
    order = _collectParallaxItems(items, order, size, positions);
    order = _collectTileMapItems(items, order, size, positions);
    order = _collectAnimationTransitionItems(items, order, size, positions);
    order = _collectSpriteItems(items, order, size, positions);
    order = _collectParticleItems(items, order, size, positions);
    order = _collectTextItems(items, order, size, positions);
    order = _collectHudBarItems(items, order, positions);
    _collectNineSliceItems(items, order, positions);

    // Stable by construction (`order` is a strictly increasing
    // tie-breaker assigned in the engine's original draw order --
    // parallax, then tiles, then sprites, then particles, each in
    // ComponentStore order) -- ties at the same zIndex (the default:
    // everything at 0) reproduce that original order exactly.
    items.sort((a, b) {
      final byZ = a.zIndex.compareTo(b.zIndex);
      return byZ != 0 ? byZ : a.order.compareTo(b.order);
    });

    for (final item in items) {
      item.paint(canvas);
    }

    if (ambientBrightness < 1.0) {
      _drawLighting(canvas, size, positions);
    }

    // Drawn last (on top of everything else) and outside the z-sorted
    // item list entirely -- debug outlines are diagnostic, not part of
    // the game's actual draw order, so they always win regardless of
    // any zIndex a real renderable happens to have.
    if (showColliderDebug) {
      _drawColliderDebug(canvas, size, positions);
      _drawTileMapDebug(canvas, size, positions);
    }
  }

  /// Ambient-darkness lighting pass (see `EngineView.ambientBrightness`
  /// and `Light2D`'s doc comments) — drawn as its own layer entirely on
  /// top of the already-composited scene rather than woven into the
  /// z-sorted item list, since it darkens *everything* underneath it
  /// regardless of that content's own zIndex, which a z-sorted item
  /// can't express. `saveLayer` isolates the darkness rect + light
  /// holes from the rest of the canvas so `BlendMode.dstOut` only
  /// erases within this layer (the black rect just drawn), not
  /// anything drawn before `paint` even started this pass; `restore`
  /// then composites the resulting mask (opaque black where dark,
  /// transparent where a light reached) back over the real scene with
  /// normal alpha blending, which is what actually darkens it.
  void _drawLighting(Canvas canvas, Size size, ComponentStore<Position> positions) {
    final lights = world.storeOf<Light2D>();
    final fullRect = Offset.zero & size;

    // Computed once per light, reused for both the darkness-reveal
    // pass and the (optional) color-tint pass below, so a
    // shadow-casting light's raycasts don't run twice.
    final infos = <_LightRenderInfo>[];
    for (var i = 0; i < lights.length; i++) {
      final entity = lights.entityAt(i);
      final light = lights.denseAt(i);
      final worldPos = positions.get(entity);
      if (worldPos == null) continue;
      if (light.radius <= 0) continue;

      final screenPos = camera.worldToScreen(worldPos.x, worldPos.y, size);
      final screenRadius = light.radius * camera.zoom;
      // Viewport culling: a light whose screen-space circle doesn't
      // reach the visible rect at all can't affect anything on screen
      // this frame, so skip it before the expensive part -- shadow
      // casting is a raycastTileMap call per sampled ray, and with
      // several shadow-casting lights in a level only a few of which
      // are ever on screen at once, this is a real cost avoided, not
      // just a micro-optimization (same reasoning as
      // _collectTileMapItems's tile culling above).
      if (!_circleIntersectsRect(screenPos, screenRadius, fullRect)) continue;
      final clipPath = _lightClipPath(light, worldPos, size);
      infos.add(_LightRenderInfo(light, screenPos, screenRadius, clipPath));
    }

    canvas.saveLayer(fullRect, Paint());
    canvas.drawRect(
      fullRect,
      Paint()..color = Color.fromRGBO(0, 0, 0, (1 - ambientBrightness).clamp(0, 1)),
    );

    for (final info in infos) {
      final intensity = info.light.intensity.clamp(0.0, 1.0);
      final revealPaint = Paint()
        ..blendMode = BlendMode.dstOut
        ..shader = ui.Gradient.radial(
          info.screenPos,
          info.screenRadius,
          _falloffColors(Color.fromRGBO(255, 255, 255, intensity)),
          _falloffStops,
        )
        ..maskFilter = _shadowEdgeMaskFilter(info);
      if (info.clipPath == null) {
        canvas.drawCircle(info.screenPos, info.screenRadius, revealPaint);
      } else {
        canvas.save();
        canvas.clipPath(info.clipPath!);
        canvas.drawCircle(info.screenPos, info.screenRadius, revealPaint);
        canvas.restore();
      }
    }

    canvas.restore();

    // Color tint: additive, drawn *after* the darkness mask is
    // composited back onto the real scene (BlendMode.plus needs the
    // scene's actual colors underneath it, not the black mask) --
    // skipped per-light whenever colorArgb's alpha is 0 (the default),
    // so a game that never sets a tint pays nothing for this pass.
    for (final info in infos) {
      final tintColor = Color(info.light.colorArgb);
      if (tintColor.a == 0) continue;

      final tintPaint = Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(
          info.screenPos,
          info.screenRadius,
          _falloffColors(tintColor),
          _falloffStops,
        )
        ..maskFilter = _shadowEdgeMaskFilter(info);
      if (info.clipPath == null) {
        canvas.drawCircle(info.screenPos, info.screenRadius, tintPaint);
      } else {
        canvas.save();
        canvas.clipPath(info.clipPath!);
        canvas.drawCircle(info.screenPos, info.screenRadius, tintPaint);
        canvas.restore();
      }
    }
  }

  /// Radial-gradient stop positions shared by the reveal and tint
  /// passes, paired with [_falloffFractions] (that stop's alpha as a
  /// fraction of the center's) to approximate a physically-inspired
  /// inverse-square-*like* falloff — `alpha(t) ≈ (1 - t)²` sampled at
  /// each stop — instead of either the original flat 2-stop linear dim
  /// (uniform brightness loss, read as artificial) or an earlier
  /// attempt at a softer curve that over-corrected into a large,
  /// uniformly-bright "glowing disc" look (read as cartoonish — too
  /// much of the radius stayed near-full-intensity before falling off).
  /// A quadratic-ish curve drops off quickly from a small, genuinely
  /// bright core and fades gradually through a long dim tail, closer
  /// to how a real point light actually looks. `ui.Gradient.radial`
  /// only interpolates linearly *between* stops, so approximating a
  /// curve at all means sampling it at several points, not just one
  /// middle stop — six points is enough to read as smooth without a
  /// visible piecewise-linear kink.
  static const List<double> _falloffStops = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0];
  static const List<double> _falloffFractions = [1.0, 0.64, 0.36, 0.16, 0.04, 0.0];

  /// Builds the gradient color list for [_falloffStops] from [peak] (the
  /// color at the light's exact center, alpha included) — each stop's
  /// alpha is `peak`'s own alpha scaled by that stop's
  /// [_falloffFractions] entry, so the *hue* stays constant across the
  /// gradient (only how much of it shows through varies) while the
  /// *shape* follows the shared falloff curve. Used for both the reveal
  /// pass (`peak` = opaque-ish white scaled by `intensity`) and the
  /// tint pass (`peak` = the light's own `colorArgb`), so a recolor of
  /// either never has to touch the falloff math itself.
  List<Color> _falloffColors(Color peak) => [
        for (final fraction in _falloffFractions) peak.withValues(alpha: peak.a * fraction),
      ];

  /// A blur on shadow-casting/cone lights' reveal and tint paints
  /// softens the visibility polygon's straight, faceted edges (a
  /// side effect of approximating a curve with `shadowRayCount`
  /// straight segments) into a gentler gradient instead of a hard,
  /// jagged cutoff — purely cosmetic, applied once per light per frame
  /// (not per sampled ray), so it doesn't scale with `shadowRayCount`
  /// the way the raycasting itself does. Blur radius comes from
  /// `Light2D.shadowEdgeSoftness` (scaled by `Camera.zoom`, so it stays
  /// a consistent *screen*-space softness regardless of zoom level);
  /// `null` (no blur at all) for a plain circular light, which has no
  /// polygon edge to soften, or a light with `shadowEdgeSoftness <= 0`
  /// (a deliberately hard edge).
  ui.MaskFilter? _shadowEdgeMaskFilter(_LightRenderInfo info) {
    if (info.clipPath == null) return null;
    final softness = info.light.shadowEdgeSoftness * camera.zoom;
    if (softness <= 0) return null;
    return ui.MaskFilter.blur(ui.BlurStyle.normal, softness);
  }

  /// `null` for a plain full-circle light (the fast path — no
  /// cone, no shadow casting: the gradient's own falloff already does
  /// all the work `drawCircle` needs). Otherwise, a fan-shaped `Path`
  /// from the light's screen position out to `rayCount` sampled points
  /// around its `coneAngle` (or the full circle, if shadow-casting with
  /// no cone) — each point at [Light2D.radius] normally, or wherever a
  /// `raycastTileMap` hit stops it short when [Light2D.castsShadows] is
  /// on, giving a real (if coarsely sampled) visibility polygon instead
  /// of a light shining through walls.
  ///
  /// When `light.shadowSmoothingSeconds > 0`, each ray's raw distance
  /// is exponentially smoothed toward `light.smoothedShadowDistances`
  /// (that light's own persisted per-ray cache, reused frame to frame)
  /// instead of used directly — see `Light2D.shadowSmoothingSeconds`'s
  /// doc comment for why: a light re-raycasting from scratch every
  /// frame as it moves can have a ray's hit tile change in a small
  /// discrete jump right as the light crosses a tile boundary, which
  /// otherwise reads as the polygon's edge visibly popping.
  Path? _lightClipPath(Light2D light, Position worldPos, Size size) {
    final hasCone = light.coneAngle != null;
    if (!hasCone && !light.castsShadows) return null;

    final rayCount = light.shadowRayCount < 3 ? 3 : light.shadowRayCount;
    final sweep = hasCone ? light.coneAngle! : 2 * pi;
    final startAngle = hasCone ? light.coneDirection - sweep / 2 : 0.0;

    final smoothingSeconds = light.shadowSmoothingSeconds;
    final smoothing = smoothingSeconds > 0 && frameDtSeconds > 0;
    if (smoothing && light.smoothedShadowDistances.length != rayCount + 1) {
      light.smoothedShadowDistances = List<double>.filled(rayCount + 1, light.radius);
    }
    // 1 - e^(-dt/tau): the fraction of the gap to the raw value closed
    // this frame, framerate-independent (a slow frame catches up
    // proportionally more than a fast one, instead of a fixed
    // per-frame blend factor that would smooth more at high framerates
    // and less at low ones for the same tau).
    final smoothingAlpha = smoothing ? 1 - exp(-frameDtSeconds / smoothingSeconds) : 1.0;

    final path = Path();
    final centerScreen = camera.worldToScreen(worldPos.x, worldPos.y, size);
    path.moveTo(centerScreen.dx, centerScreen.dy);

    for (var i = 0; i <= rayCount; i++) {
      final angle = startAngle + sweep * i / rayCount;
      final rawDist = light.castsShadows
          ? _raycastLightDistance(worldPos, angle, light.radius, light.blockOneWayPlatforms)
          : light.radius;
      double dist;
      if (smoothing) {
        final prev = light.smoothedShadowDistances[i];
        dist = prev + (rawDist - prev) * smoothingAlpha;
        light.smoothedShadowDistances[i] = dist;
      } else {
        dist = rawDist;
      }
      final worldPointX = worldPos.x + cos(angle) * dist;
      final worldPointY = worldPos.y + sin(angle) * dist;
      final screenPoint = camera.worldToScreen(worldPointX, worldPointY, size);
      path.lineTo(screenPoint.dx, screenPoint.dy);
    }
    path.close();
    return path;
  }

  /// How far a light at [worldPos] can see along [angle] before the
  /// nearest solid tile in any `TileMap` blocks it (via `raycastTileMap`
  /// — the same primitive AI line-of-sight already uses), capped at
  /// [maxRadius] when nothing blocks it at all. [blockOneWay] forwards
  /// straight to `raycastTileMap`'s own parameter of the same name
  /// (see `Light2D.blockOneWayPlatforms`'s doc comment for why a light
  /// would want this on).
  double _raycastLightDistance(
    Position worldPos,
    double angle,
    double maxRadius,
    bool blockOneWay,
  ) {
    final toX = worldPos.x + cos(angle) * maxRadius;
    final toY = worldPos.y + sin(angle) * maxRadius;
    var nearest = maxRadius;

    final tileMaps = world.storeOf<TileMap>();
    final mapPositions = world.storeOf<Position>();
    for (var m = 0; m < tileMaps.length; m++) {
      final mapEntity = tileMaps.entityAt(m);
      final map = tileMaps.denseAt(m);
      final origin = mapPositions.get(mapEntity) ?? Position(0, 0);
      final hit = raycastTileMap(map, origin, worldPos.x, worldPos.y, toX, toY,
          blockOneWay: blockOneWay);
      if (hit != null && hit.distance < nearest) {
        nearest = hit.distance;
      }
    }
    return nearest;
  }

  /// Whether a circle at [center] with [radius] overlaps [rect] at all
  /// — the closest point on the (clamped) rect to [center] is within
  /// [radius]. Used to cull a `Light2D` whose screen-space circle
  /// can't reach the visible viewport before doing any of the more
  /// expensive per-light work (shadow raycasting in particular).
  bool _circleIntersectsRect(Offset center, double radius, Rect rect) {
    final closestX = center.dx.clamp(rect.left, rect.right);
    final closestY = center.dy.clamp(rect.top, rect.bottom);
    final dx = center.dx - closestX;
    final dy = center.dy - closestY;
    return dx * dx + dy * dy <= radius * radius;
  }

  /// A stroked circle at every `Collider`'s actual radius — see
  /// `EngineView.showColliderDebug`'s doc comment for why (and what
  /// this deliberately doesn't cover).
  void _drawColliderDebug(Canvas canvas, Size size, ComponentStore<Position> positions) {
    final colliders = world.storeOf<Collider>();
    final paint = Paint()
      ..color = const Color(0xFF00FF00)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (var i = 0; i < colliders.length; i++) {
      final entity = colliders.entityAt(i);
      final pos = positions.get(entity);
      if (pos == null) continue;
      final screenPos = camera.worldToScreen(pos.x, pos.y, size);
      canvas.drawCircle(screenPos, colliders.denseAt(i).radius * camera.zoom, paint);
    }
  }

  /// A stroked border per solid (red)/one-way (blue)/slope (orange)
  /// tile, on top of `_collectTileMapItems`'s filled color — makes a
  /// tile's exact collision boundary unambiguous even when its fill
  /// color is hard to tell apart from a neighboring tile at a glance.
  void _drawTileMapDebug(Canvas canvas, Size size, ComponentStore<Position> positions) {
    final tileMaps = world.storeOf<TileMap>();
    for (var m = 0; m < tileMaps.length; m++) {
      final mapEntity = tileMaps.entityAt(m);
      final map = tileMaps.denseAt(m);
      final origin = positions.get(mapEntity) ?? Position(0, 0);

      for (var row = 0; row < map.rows; row++) {
        for (var col = 0; col < map.cols; col++) {
          final tileId = map.tileAt(col, row);
          if (tileId == 0) continue;

          final isSolid = map.solidTileIds.contains(tileId);
          final isOneWay = map.oneWayTileIds.contains(tileId);
          final isSlope = map.slopeUpRightTileIds.contains(tileId) || map.slopeUpLeftTileIds.contains(tileId);
          if (!isSolid && !isOneWay && !isSlope) continue;

          final left = origin.x + col * map.tileWidth;
          final top = origin.y + row * map.tileHeight;
          final screenPos = camera.worldToScreen(left, top, size);
          final color = isSolid
              ? const Color(0xFFFF3B30)
              : isOneWay
                  ? const Color(0xFF3B82F6)
                  : const Color(0xFFFF9500);

          canvas.drawRect(
            Rect.fromLTWH(
              screenPos.dx,
              screenPos.dy,
              map.tileWidth * camera.zoom,
              map.tileHeight * camera.zoom,
            ),
            Paint()
              ..color = color
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _EnginePainter oldDelegate) => true;

  /// Collects one `_DrawItem` per shared-atlas batch (plus one per
  /// non-batchable fallback sprite), grouped by `Sprite.zIndex` first so
  /// items land in the right slot once `paint()` sorts everything —
  /// batching only ever combines sprites that already share both a
  /// `zIndex` and an atlas, so it can't smear a sprite across the wrong
  /// z-slot.
  ///
  /// Batching itself: `Canvas.drawAtlas` draws many sprites from one
  /// source image in a single call with no per-sprite canvas state
  /// changes — meaningfully cheaper than a `save`/`translate`/`scale`/
  /// `drawImageRect`/`restore` sequence per sprite at sprite-heavy
  /// scenes. `RSTransform` (what `drawAtlas` takes per sprite) only
  /// supports one *positive, uniform* scale factor, not independent X/Y
  /// scale — so a sprite with `scaleX != scaleY`, or a negative one (the
  /// standard way `FacingSystem` flips a sprite horizontally), can't be
  /// expressed that way and falls back to the original per-sprite
  /// `drawImageRect` path instead.
  int _collectSpriteItems(
    List<_DrawItem> items,
    int order,
    Size size,
    ComponentStore<Position> positions,
  ) {
    final sprites = world.storeOf<Sprite>();
    if (sprites.length == 0) return order;

    final indicesByZ = <int, List<int>>{};
    for (var i = 0; i < sprites.length; i++) {
      final entity = sprites.entityAt(i);
      final sprite = sprites.denseAt(i);
      final pos = positions.get(entity);
      if (pos == null || !atlasRegistry.has(sprite.atlasId)) continue;
      (indicesByZ[sprite.zIndex] ??= []).add(i);
    }

    for (final zEntry in indicesByZ.entries) {
      final z = zEntry.key;
      final batchesByImage = <ui.Image, _SpriteBatch>{};
      final fallbackIndices = <int>[];

      for (final i in zEntry.value) {
        final entity = sprites.entityAt(i);
        final sprite = sprites.denseAt(i);
        if (sprite.scaleX != sprite.scaleY || sprite.scaleX <= 0) {
          fallbackIndices.add(i);
          continue;
        }

        final pos = positions.get(entity)!;
        final atlas = atlasRegistry.resolve(sprite.atlasId);
        final srcRect = atlas.regionFor(sprite.region);
        final worldPos = _interpolated(entity, pos);
        final screenPos = camera.worldToScreen(worldPos.dx, worldPos.dy, size);

        final batch = batchesByImage.putIfAbsent(atlas.image, () => _SpriteBatch());
        batch.transforms.add(RSTransform.fromComponents(
          rotation: sprite.rotation,
          scale: sprite.scaleX * camera.zoom,
          anchorX: srcRect.width / 2,
          anchorY: srcRect.height / 2,
          translateX: screenPos.dx,
          translateY: screenPos.dy,
        ));
        batch.rects.add(srcRect);
      }

      if (batchesByImage.isNotEmpty) {
        items.add(_DrawItem(z, order++, (canvas) {
          final paint = Paint();
          for (final entry in batchesByImage.entries) {
            canvas.drawAtlas(entry.key, entry.value.transforms, entry.value.rects, null, null, null, paint);
          }
        }));
      }
      for (final i in fallbackIndices) {
        items.add(_DrawItem(
          z,
          order++,
          (canvas) => _paintSpriteIndividually(canvas, size, positions, sprites, i),
        ));
      }
    }
    return order;
  }

  void _paintSpriteIndividually(
    Canvas canvas,
    Size size,
    ComponentStore<Position> positions,
    ComponentStore<Sprite> sprites,
    int i,
  ) {
    final entity = sprites.entityAt(i);
    final sprite = sprites.denseAt(i);
    final pos = positions.get(entity)!;
    final atlas = atlasRegistry.resolve(sprite.atlasId);
    final srcRect = atlas.regionFor(sprite.region);
    final worldPos = _interpolated(entity, pos);
    final screenPos = camera.worldToScreen(worldPos.dx, worldPos.dy, size);

    canvas.save();
    canvas.translate(screenPos.dx, screenPos.dy);
    if (sprite.rotation != 0) canvas.rotate(sprite.rotation);
    canvas.scale(
      sprite.scaleX * camera.zoom,
      sprite.scaleY * camera.zoom,
    );
    final destRect = ui.Rect.fromCenter(
      center: Offset.zero,
      width: srcRect.width,
      height: srcRect.height,
    );
    canvas.drawImageRect(atlas.image, srcRect, destRect, Paint());
    canvas.restore();
  }

  /// Collects one `_DrawItem` per `AnimationTransition` — the frozen
  /// outgoing frame of a crossfading animation (see
  /// `AnimationState.crossfadeSeconds`), drawn at the same world
  /// `Position` fading out via `alpha`. Collected (and thus drawn)
  /// *before* `_collectSpriteItems` so the incoming, real `Sprite`
  /// lands on top of the fading-out ghost within their shared default
  /// zIndex, without needing this to be batched — one instance per
  /// crossfading entity for a brief window is nowhere near the volume
  /// `_collectSpriteItems`'s `drawAtlas` batching exists for.
  int _collectAnimationTransitionItems(
    List<_DrawItem> items,
    int order,
    Size size,
    ComponentStore<Position> positions,
  ) {
    final transitions = world.storeOf<AnimationTransition>();
    for (var i = 0; i < transitions.length; i++) {
      final entity = transitions.entityAt(i);
      final transition = transitions.denseAt(i);
      final pos = positions.get(entity);
      if (pos == null || !atlasRegistry.has(transition.atlasId)) continue;

      items.add(_DrawItem(transition.zIndex, order++, (canvas) {
        final atlas = atlasRegistry.resolve(transition.atlasId);
        final srcRect = atlas.regionFor(transition.region);
        final screenPos = camera.worldToScreen(pos.x, pos.y, size);

        canvas.save();
        canvas.translate(screenPos.dx, screenPos.dy);
        if (transition.rotation != 0) canvas.rotate(transition.rotation);
        canvas.scale(
          transition.scaleX * camera.zoom,
          transition.scaleY * camera.zoom,
        );
        final destRect = ui.Rect.fromCenter(
          center: Offset.zero,
          width: srcRect.width,
          height: srcRect.height,
        );
        canvas.drawImageRect(
          atlas.image,
          srcRect,
          destRect,
          Paint()..color = Color.fromRGBO(255, 255, 255, transition.alpha),
        );
        canvas.restore();
      }));
    }
    return order;
  }

  /// Collects one `_DrawItem` per `Particle` (from `ParticleSystem`),
  /// grouped by `Particle.zIndex` — defaults land after sprites, the
  /// common case for hit sparks/dust/collect flair sitting above
  /// gameplay art rather than under it. A particle with its own
  /// `Sprite` component (the game attached one for a textured look)
  /// draws that region scaled by `Particle.scale`; otherwise a plain
  /// circle of `Particle.colorArgb`. Both fade via `Particle.alpha` —
  /// for the sprite case that relies on the paint's alpha channel
  /// modulating the whole `drawImageRect` call, the standard Flutter
  /// trick for compositing an image at partial opacity without a
  /// `saveLayer` per particle.
  int _collectParticleItems(
    List<_DrawItem> items,
    int order,
    Size size,
    ComponentStore<Position> positions,
  ) {
    final particles = world.storeOf<Particle>();
    if (particles.length == 0) return order;

    final sprites = world.storeOf<Sprite>();
    for (var i = 0; i < particles.length; i++) {
      final entity = particles.entityAt(i);
      final particle = particles.denseAt(i);
      final pos = positions.get(entity);
      if (pos == null) continue;

      final alpha = particle.alpha.clamp(0.0, 1.0);
      if (alpha <= 0 || particle.scale <= 0) continue;

      items.add(_DrawItem(particle.zIndex, order++, (canvas) {
        final worldPos = _interpolated(entity, pos);
        final screenPos = camera.worldToScreen(worldPos.dx, worldPos.dy, size);
        final sprite = sprites.get(entity);
        if (sprite != null && atlasRegistry.has(sprite.atlasId)) {
          final atlas = atlasRegistry.resolve(sprite.atlasId);
          final srcRect = atlas.regionFor(sprite.region);
          final destRect = ui.Rect.fromCenter(
            center: screenPos,
            width: srcRect.width * particle.scale * camera.zoom,
            height: srcRect.height * particle.scale * camera.zoom,
          );
          canvas.drawImageRect(
            atlas.image,
            srcRect,
            destRect,
            Paint()..color = Color.fromRGBO(255, 255, 255, alpha),
          );
        } else {
          final base = Color(particle.colorArgb);
          canvas.drawCircle(
            screenPos,
            4 * particle.scale * camera.zoom,
            Paint()..color = base.withValues(alpha: alpha * base.a),
          );
        }
      }));
    }
    return order;
  }

  /// Collects one `_DrawItem` per `ParallaxLayer`, defaulting to before
  /// tiles/sprites/particles (see `Sprite.zIndex`). Each layer's screen
  /// anchor scales the camera by `scrollFactorX`/`Y` instead of using it
  /// 1:1 like `worldToScreen` does for regular sprites — that scaled-
  /// down camera movement is the entire parallax effect. `tileX`/`tileY`
  /// repeat the region across the viewport by drawing it at every
  /// `_tileStarts` offset instead of once, so one authored strip covers
  /// arbitrarily wide/tall scrolling.
  int _collectParallaxItems(
    List<_DrawItem> items,
    int order,
    Size size,
    ComponentStore<Position> positions,
  ) {
    final layers = world.storeOf<ParallaxLayer>();
    if (layers.length == 0) return order;

    for (var i = 0; i < layers.length; i++) {
      final entity = layers.entityAt(i);
      final layer = layers.denseAt(i);
      if (!atlasRegistry.has(layer.atlasId)) continue;

      items.add(_DrawItem(layer.zIndex, order++, (canvas) {
        final atlas = atlasRegistry.resolve(layer.atlasId);
        final srcRect = atlas.regionFor(layer.region);
        final tileWidth = srcRect.width * camera.zoom;
        final tileHeight = srcRect.height * camera.zoom;
        if (tileWidth <= 0 || tileHeight <= 0) return;

        final pos = positions.get(entity) ?? Position(0, 0);
        final anchorX =
            (pos.x - camera.x * layer.scrollFactorX) * camera.zoom + size.width / 2;
        final anchorY =
            (pos.y - camera.y * layer.scrollFactorY) * camera.zoom + size.height / 2;

        final xs = layer.tileX ? _tileStarts(anchorX, tileWidth, size.width) : [anchorX];
        final ys = layer.tileY ? _tileStarts(anchorY, tileHeight, size.height) : [anchorY];

        final paint = Paint();
        for (final y in ys) {
          for (final x in xs) {
            canvas.drawImageRect(
              atlas.image,
              srcRect,
              Rect.fromLTWH(x, y, tileWidth, tileHeight),
              paint,
            );
          }
        }
      }));
    }
    return order;
  }

  /// Every `tileSize`-spaced offset from at-or-before 0 up to
  /// [viewportSize], starting from [anchor] — i.e. the set of positions
  /// to draw one tile at so the whole viewport is covered with no gaps,
  /// regardless of how far [anchor] has scrolled. Dart's `%` is floored
  /// (always non-negative for a positive divisor), so this works the
  /// same for a negative [anchor] as a positive one.
  List<double> _tileStarts(double anchor, double tileSize, double viewportSize) {
    var start = anchor % tileSize;
    if (start > 0) start -= tileSize;
    return [for (var x = start; x < viewportSize; x += tileSize) x];
  }

  /// Collects one `_DrawItem` per `TileMap`, grouped by `TileMap.zIndex`
  /// (defaults to before sprites/particles, same as before this became
  /// z-sortable). Each tile id with an entry in `TileMap.regionByTileId`
  /// (and a loaded `TileMap.atlasId`) draws that atlas region as its
  /// actual texture via `drawImageRect` — the same region-in-an-atlas
  /// mechanism `Sprite` uses, just applied per grid cell instead of per
  /// entity. Any tile id without one (including every tile in a level
  /// that never sets `atlasId` at all, i.e. every level before this
  /// existed) falls back to one placeholder color per collision kind —
  /// solid (opaque dark gray, the default/fallback), one-way
  /// (translucent blue), slope (orange), and ladder (translucent tan,
  /// so a non-solid, walk-through ladder doesn't visually read as a
  /// wall the player can't actually pass through) — so a level can mix
  /// textured and flat-color tiles freely (texture the visible terrain,
  /// leave an invisible trigger-marker id as plain color) rather than
  /// needing to texture every tile id or none.
  int _collectTileMapItems(
    List<_DrawItem> items,
    int order,
    Size size,
    ComponentStore<Position> positions,
  ) {
    final tileMaps = world.storeOf<TileMap>();
    for (var m = 0; m < tileMaps.length; m++) {
      final mapEntity = tileMaps.entityAt(m);
      final map = tileMaps.denseAt(m);

      items.add(_DrawItem(map.zIndex, order++, (canvas) {
        if (map.cols == 0 || map.rows == 0) return; // degenerate empty map

        final origin = positions.get(mapEntity) ?? Position(0, 0);

        // Cull to the tiles actually on screen -- a map far bigger than
        // the viewport (the common case once a level has any real
        // size) would otherwise walk every single tile every frame
        // regardless of how few are visible. `screenToWorld` gives the
        // world-space rect the viewport currently shows; converting
        // that into tile-grid indices (with a 1-tile margin so a tile
        // straddling the edge still gets drawn, and clamped to the
        // map's actual bounds) turns an O(rows*cols) walk into
        // O(visible tiles).
        final topLeftWorld = camera.screenToWorld(Offset.zero, size);
        final bottomRightWorld = camera.screenToWorld(Offset(size.width, size.height), size);
        final minCol = (((topLeftWorld.dx - origin.x) / map.tileWidth).floor() - 1)
            .clamp(0, map.cols - 1);
        final maxCol = (((bottomRightWorld.dx - origin.x) / map.tileWidth).ceil() + 1)
            .clamp(0, map.cols - 1);
        final minRow = (((topLeftWorld.dy - origin.y) / map.tileHeight).floor() - 1)
            .clamp(0, map.rows - 1);
        final maxRow = (((bottomRightWorld.dy - origin.y) / map.tileHeight).ceil() + 1)
            .clamp(0, map.rows - 1);

        // Resolved once per TileMap (not per tile) -- a missing/
        // not-yet-loaded atlas just means every tile in this map falls
        // back to its flat debug color, same as a level authored with
        // no atlasId at all.
        final atlas = map.atlasId != null && atlasRegistry.has(map.atlasId!)
            ? atlasRegistry.resolve(map.atlasId!)
            : null;

        for (var row = minRow; row <= maxRow; row++) {
          for (var col = minCol; col <= maxCol; col++) {
            final tileId = map.tileAt(col, row);
            if (tileId == 0) continue;

            final left = origin.x + col * map.tileWidth;
            final top = origin.y + row * map.tileHeight;
            final screenPos = camera.worldToScreen(left, top, size);
            final destRect = Rect.fromLTWH(
              screenPos.dx,
              screenPos.dy,
              map.tileWidth * camera.zoom,
              map.tileHeight * camera.zoom,
            );

            // A tile id with a real, loaded atlas region draws the
            // actual texture; anything else (no atlasId set on this
            // TileMap at all, the atlas hasn't loaded yet, or this
            // particular tile id just has no region entry) falls back
            // to the original flat debug color, so a level using
            // textures for most tiles can still leave some ids
            // (an invisible trigger marker, say) as plain color.
            final regionName = map.regionByTileId[tileId];
            final region = atlas != null && regionName != null
                ? atlas.regions[regionName]
                : null;
            if (region != null) {
              canvas.drawImageRect(atlas!.image, region, destRect, Paint());
              continue;
            }

            final color = map.oneWayTileIds.contains(tileId)
                ? const Color(0x8899CCFF)
                : (map.slopeUpRightTileIds.contains(tileId) || map.slopeUpLeftTileIds.contains(tileId))
                    ? const Color(0xFFC08040)
                    : map.ladderTileIds.contains(tileId)
                        ? const Color(0x88C09050)
                        : const Color(0xFF4A4A4A);

            canvas.drawRect(destRect, Paint()..color = color);
          }
        }
      }));
    }
    return order;
  }

  /// Collects one `_DrawItem` per `Text` — drawn fresh every frame via
  /// `TextPainter`, not batched (unlike sprites), since text doesn't
  /// share a source image the way atlas-based sprites do. `screenSpace`
  /// text skips the camera transform entirely (`Position` is already in
  /// viewport pixels); world-space text goes through `camera.worldToScreen`
  /// like a `Sprite`, so it scrolls/zooms with everything else.
  int _collectTextItems(
    List<_DrawItem> items,
    int order,
    Size size,
    ComponentStore<Position> positions,
  ) {
    final texts = world.storeOf<txt.Text>();
    for (var i = 0; i < texts.length; i++) {
      final entity = texts.entityAt(i);
      final text = texts.denseAt(i);
      final pos = positions.get(entity);
      if (pos == null) continue;

      items.add(_DrawItem(text.zIndex, order++, (canvas) {
        final screenPos =
            text.screenSpace ? Offset(pos.x, pos.y) : camera.worldToScreen(pos.x, pos.y, size);
        final scale = text.screenSpace ? 1.0 : camera.zoom;
        final painter = TextPainter(
          text: TextSpan(
            text: text.text,
            style: TextStyle(
              color: Color(text.colorArgb),
              fontSize: text.fontSize * scale,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: text.maxWidth == null ? double.infinity : text.maxWidth! * scale);

        final dx = switch (text.align) {
          txt.TextAlignment.left => 0.0,
          txt.TextAlignment.center => -painter.width / 2,
          txt.TextAlignment.right => -painter.width,
        };
        painter.paint(canvas, Offset(screenPos.dx + dx, screenPos.dy - painter.height / 2));
      }));
    }
    return order;
  }

  /// Collects one `_DrawItem` per `HudBar` — always screen space
  /// (`Position` is viewport pixels, never transformed by the camera;
  /// see `HudBar`'s doc comment for why), a background rect at [HudBar.width]/
  /// `.height` plus a foreground rect scaled to `HudBar.fraction`.
  int _collectHudBarItems(
    List<_DrawItem> items,
    int order,
    ComponentStore<Position> positions,
  ) {
    final bars = world.storeOf<HudBar>();
    for (var i = 0; i < bars.length; i++) {
      final entity = bars.entityAt(i);
      final bar = bars.denseAt(i);
      final pos = positions.get(entity);
      if (pos == null) continue;

      items.add(_DrawItem(bar.zIndex, order++, (canvas) {
        final rect = Rect.fromLTWH(pos.x, pos.y, bar.width, bar.height);
        canvas.drawRect(rect, Paint()..color = Color(bar.backgroundColorArgb));
        final fillRect = Rect.fromLTWH(pos.x, pos.y, bar.width * bar.fraction, bar.height);
        canvas.drawRect(fillRect, Paint()..color = Color(bar.fillColorArgb));
      }));
    }
    return order;
  }

  /// Collects one `_DrawItem` per `NineSliceSprite` — always screen
  /// space, same reasoning as `HudBar`. Draws 9 `drawImageRect` calls
  /// (corners at native size, edges/center stretched) rather than
  /// `Canvas.drawImageNine`, since that method always nine-slices the
  /// *whole* source image with no sub-rect parameter — useless against
  /// a shared atlas where the region is one packed rect within a much
  /// bigger image. A destination cell that would come out zero or
  /// negative size (e.g. `width`/`height` smaller than the insets sum
  /// to) is skipped rather than handed to `drawImageRect`.
  int _collectNineSliceItems(
    List<_DrawItem> items,
    int order,
    ComponentStore<Position> positions,
  ) {
    final sprites = world.storeOf<NineSliceSprite>();
    for (var i = 0; i < sprites.length; i++) {
      final entity = sprites.entityAt(i);
      final nine = sprites.denseAt(i);
      final pos = positions.get(entity);
      if (pos == null || !atlasRegistry.has(nine.atlasId)) continue;

      items.add(_DrawItem(nine.zIndex, order++, (canvas) {
        final atlas = atlasRegistry.resolve(nine.atlasId);
        final src = atlas.regionFor(nine.region);

        final srcXs = [src.left, src.left + nine.insetLeft, src.right - nine.insetRight, src.right];
        final srcYs = [src.top, src.top + nine.insetTop, src.bottom - nine.insetBottom, src.bottom];
        final dstXs = [
          pos.x,
          pos.x + nine.insetLeft,
          pos.x + nine.width - nine.insetRight,
          pos.x + nine.width,
        ];
        final dstYs = [
          pos.y,
          pos.y + nine.insetTop,
          pos.y + nine.height - nine.insetBottom,
          pos.y + nine.height,
        ];

        final paint = Paint();
        for (var col = 0; col < 3; col++) {
          for (var row = 0; row < 3; row++) {
            final srcRect = Rect.fromLTRB(srcXs[col], srcYs[row], srcXs[col + 1], srcYs[row + 1]);
            final dstRect = Rect.fromLTRB(dstXs[col], dstYs[row], dstXs[col + 1], dstYs[row + 1]);
            if (dstRect.width <= 0 || dstRect.height <= 0) continue;
            canvas.drawImageRect(atlas.image, srcRect, dstRect, paint);
          }
        }
      }));
    }
    return order;
  }
}

/// One item in the z-sorted draw list `_EnginePainter.paint` builds —
/// see its doc comment and `Sprite.zIndex` for the full ordering rule.
/// [order] is a tie-breaker for items sharing the same [zIndex],
/// assigned in the engine's original fixed draw order (parallax, tiles,
/// sprites, particles) so the common case (everything at the default
/// zIndex 0) renders identically to before z-index existed.
class _DrawItem {
  final int zIndex;
  final int order;
  final void Function(Canvas canvas) paint;
  _DrawItem(this.zIndex, this.order, this.paint);
}

/// One light's precomputed render data for `_EnginePainter._drawLighting`
/// — [clipPath] is computed once (raycasting, if the light casts
/// shadows, included) and reused for both the brightness-reveal and
/// color-tint passes.
class _LightRenderInfo {
  final Light2D light;
  final Offset screenPos;
  final double screenRadius;
  final Path? clipPath;
  _LightRenderInfo(this.light, this.screenPos, this.screenRadius, this.clipPath);
}

/// One `Canvas.drawAtlas` call's worth of sprites sharing a source
/// image — see `_EnginePainter._collectSpriteItems`.
class _SpriteBatch {
  final transforms = <RSTransform>[];
  final rects = <Rect>[];
}
