import 'dart:math' show cos, exp, sin, pi, sqrt;
import 'dart:ui' as ui;

import 'package:engine_core/engine_core.dart';
// Hidden -- flutter/widgets.dart's own Velocity (gesture fling
// velocity) would otherwise collide with engine_core's component of
// the same name; every use of the physics one below is unambiguous.
import 'package:flutter/widgets.dart' hide Velocity;
import 'package:flutter/scheduler.dart';

import 'camera.dart';
import 'clip_shape.dart';
import 'parallax_layer.dart';
import 'sprite.dart';
// Aliased -- `Text` collides with Flutter's own widget of the same
// name, which `package:flutter/widgets.dart` (imported above) already
// brings into scope.
import 'animation_transition.dart';
import 'frame_stats.dart';
import 'gpu_light_shader.dart';
import 'hud_bar.dart';
import 'light2d.dart';
import 'nine_slice_sprite.dart';
import 'screen_tint.dart';
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

  /// Overlays Flutter's own built-in `PerformanceOverlay` — two live
  /// bar graphs, UI thread and **raster thread**, each frame's actual
  /// bar height. Exists specifically because [showFpsOverlay]/
  /// [FrameStats] can only ever measure this engine's own Dart-side
  /// work (`world.step`, `CustomPainter.paint` recording draw
  /// commands) — a real investigation found a genuine, sustained
  /// on-device lag whose cost was *entirely* on the raster thread
  /// (Skia/Impeller's GPU command encoding, well past what any
  /// Dart-side `Stopwatch` can see) and needed a raster-thread graph,
  /// not another Dart timer, to actually spot. This is that graph,
  /// exposed as a one-line opt-in instead of every game needing to
  /// know Flutter's `PerformanceOverlay` widget exists or how to wire
  /// it in above an `EngineView`. `false` by default (some real
  /// per-frame cost of its own — Flutter has to actually measure and
  /// draw the bars — so it stays opt-in, not part of
  /// [showFpsOverlay]).
  final bool showPerformanceOverlay;

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

  /// When set, drives the ambient-darkness pass's tint, and *scales*
  /// its brightness, from a looping time-of-day clock and current
  /// weather — see `DayNightCycle`'s own doc comment (`engine_core`)
  /// for the brightness curve/tint it computes. `advance(dt)` is called
  /// once per tick automatically, the same way `camera.update(dt)`
  /// already is. `null` (default) leaves [ambientBrightness] as the
  /// sole source of ambient darkness, at no per-frame cost beyond one
  /// comparison — fully backward compatible. When both are set, the
  /// effective brightness is `ambientBrightness * dayNightCycle.ambientBrightness`
  /// — [ambientBrightness] stays a real, participating ceiling (a
  /// scene's own tuned baseline for its lights), never silently
  /// discarded; full daylight (`dayNightCycle.ambientBrightness == 1.0`)
  /// reproduces [ambientBrightness] exactly.
  final DayNightCycle? dayNightCycle;

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

  /// When set, filled in with real wall-clock per-phase timing
  /// (`world.step`, paint, lighting) for the most recently rendered
  /// frame — see `FrameStats`'s own doc comment for why this exists.
  /// The timing itself (a couple of `Stopwatch` calls) always runs at
  /// negligible cost regardless; `null` (default) just means nowhere
  /// keeps the result *unless* [showFpsOverlay] is also on, which
  /// needs it for its own readout and uses an internal instance in
  /// that case. Pass your own instance to read/log/export the numbers
  /// yourself instead of (or in addition to) the on-screen overlay —
  /// e.g. print it every N frames, or send it to your own telemetry.
  final FrameStats? frameStats;

  /// Extra margin (screen pixels, before `camera.zoom`) `_collectTileMapItems`
  /// pads its visible-tile culling rect with on all 4 sides, beyond the
  /// existing 1-tile safety margin — `96.0` by default. Exists for two
  /// reasons: (1) a moving camera reveals tiles right at the viewport
  /// edge exactly on the frame they'd otherwise pop in; a buffer keeps
  /// them drawn (harmlessly, just off-screen) slightly before they're
  /// needed. (2) it's what makes the *caching* below actually pay off —
  /// a buffered range is recomputed only when the camera's real visible
  /// rect would no longer fit inside the last-computed buffered one, so
  /// normal-speed panning reuses the same cached tile range across many
  /// frames instead of recomputing it every single one. The recompute,
  /// when it does happen, also extends further in whichever direction
  /// the camera is currently moving (its own real velocity, sampled
  /// once per tick) — a small predictive look-ahead so a fast pan is
  /// less likely to immediately outrun the buffer it just got. `0`
  /// disables both the visual buffer and the caching (recomputes every
  /// frame using just the existing 1-tile margin, the original
  /// behavior). Real ingredients benchmarked together in
  /// `engine_platformer/benchmark/render_pipeline_benchmark_test.dart`.
  final double cullBufferPx;

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
    this.showPerformanceOverlay = false,
    this.onWorldTap,
    this.fixedTimestepSeconds,
    this.ambientBrightness = 1.0,
    this.dayNightCycle,
    this.maxFps,
    this.frameStats,
    this.cullBufferPx = 96.0,
  });

  @override
  State<EngineView> createState() => _EngineViewState();
}

class _EngineViewState extends State<EngineView>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  Duration? _nextTickDue;
  final FocusNode _focusNode = FocusNode();
  double _fps = 0;
  int? _memoryBytes;
  int _memorySampleCounter = 0;
  final List<double> _recentDts = [];
  double _lastDt = 0;

  /// `widget.frameStats` when given, otherwise an internal instance
  /// used only by [showFpsOverlay]'s own readout -- either way, one
  /// stable object per `State` (not recreated each build), so a
  /// `FrameStats` the painter writes into during `paint()` is still
  /// the same instance the next `build()` reads from.
  late FrameStats _frameStats;

  // Fixed-timestep bookkeeping -- unused (stays at defaults, at no
  // per-frame cost beyond a null check) when `fixedTimestepSeconds` is
  // null.
  double _accumulator = 0;
  Map<EntityId, Position> _previousPositions = const {};
  double _interpolationAlpha = 1;

  // Camera-velocity tracking (world units/sec) -- used only to give
  // _collectTileMapItems's culling buffer a little predictive
  // look-ahead in whichever direction the camera is actually moving
  // (see EngineView.cullBufferPx's doc comment). Recomputed once per
  // tick from how far camera.x/y actually moved since last tick, after
  // cameraFollowEntity (if any) has already updated it this frame.
  double? _lastCameraX;
  double? _lastCameraY;
  double _cameraVelocityX = 0;
  double _cameraVelocityY = 0;

  /// Per-`TileMap` cached, buffered visible-tile range -- same `Map`
  /// instance reused every frame (like `_previousPositions` above), so
  /// a fresh `_EnginePainter` each build can still read/update what the
  /// previous frame computed. See `_collectTileMapItems`'s doc comment.
  final Map<EntityId, _TileCullCache> _tileCullCache = {};

  static const _maxStepsPerFrame = 5;

  @override
  void initState() {
    super.initState();
    _frameStats = widget.frameStats ?? FrameStats();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(EngineView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.frameStats != oldWidget.frameStats) {
      _frameStats = widget.frameStats ?? FrameStats();
    }
  }

  void _onTick(Duration elapsed) {
    // maxFps caps how often a raw display callback is actually turned
    // into a world step + repaint. This is scheduled against a virtual
    // clock (_nextTickDue) that advances by exactly minInterval every
    // processed frame, rather than comparing against the last
    // *processed* callback's own (jittery) timestamp -- on a display
    // whose refresh interval isn't an exact multiple of minInterval
    // (a 90Hz or 120Hz phone capped to 60fps, e.g.), comparing against
    // the last processed timestamp makes alternating real frame
    // intervals unequal (e.g. ~11ms/~22ms on 90Hz->60fps) even though
    // the long-run average hits 60 -- visible as uneven, "not solid"
    // pacing rather than a real dropped-frame stutter. Anchoring to a
    // virtual clock that ticks forward by a fixed amount each time
    // removes that jitter; a stall (e.g. the app was backgrounded)
    // resyncs the virtual clock to now instead of bursting through a
    // backlog of catch-up frames.
    final maxFps = widget.maxFps;
    if (maxFps != null && maxFps > 0) {
      final minInterval = Duration(microseconds: (1e6 / maxFps).round());
      if (_nextTickDue != null && elapsed < _nextTickDue!) return;
      final due = (_nextTickDue ?? elapsed) + minInterval;
      _nextTickDue = due < elapsed ? elapsed + minInterval : due;
    } else {
      _nextTickDue = null;
    }
    final dt = _lastTick == Duration.zero
        ? 0.0
        : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (dt <= 0 || dt > 0.25) return;
    _lastDt = dt;
    if (widget.paused) return;

    final stepStopwatch = Stopwatch()..start();
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
    stepStopwatch.stop();
    _frameStats.stepMs = stepStopwatch.elapsedMicroseconds / 1000;
    _frameStats.frameMs = dt * 1000;
    _frameStats.entities = widget.world.entities.count;
    _frameStats.sprites = widget.world.storeOf<Sprite>().length;
    _frameStats.particles = widget.world.storeOf<Particle>().length;
    // Decays/recomputes any active Camera.shake() offset -- called
    // unconditionally (not just when cameraFollowEntity is set), since
    // a static camera still needs to shake on e.g. an explosion.
    widget.camera.update(dt);
    widget.dayNightCycle?.advance(dt);

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
      final vel = widget.world.storeOf<Velocity>().get(followId);
      _frameStats.followedSpeed = vel == null ? null : sqrt(vel.x * vel.x + vel.y * vel.y);
    } else {
      _frameStats.followedSpeed = null;
    }

    // After camera.follow() above has settled this tick's real
    // position -- so a followed player's own speed doesn't get
    // double-counted as camera lag on top of its own motion.
    if (dt > 0) {
      final lastX = _lastCameraX;
      final lastY = _lastCameraY;
      if (lastX != null && lastY != null) {
        _cameraVelocityX = (widget.camera.x - lastX) / dt;
        _cameraVelocityY = (widget.camera.y - lastY) / dt;
      }
      _lastCameraX = widget.camera.x;
      _lastCameraY = widget.camera.y;
    }

    // Fired last, once every field above has this tick's real value --
    // see FrameStats.onSpike's own doc comment for why this exists
    // (catches every spiking frame directly, with no sampling gap, as
    // opposed to a periodic logging Timer that can miss one entirely).
    if (_frameStats.frameMs > _frameStats.spikeThresholdMs) {
      _frameStats.onSpike?.call(_frameStats);
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
      _frameStats.toString(),
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
      dayNightCycle: widget.dayNightCycle,
      frameDtSeconds: _lastDt,
      frameStats: _frameStats,
      cullBufferPx: widget.cullBufferPx,
      cameraVelocityX: _cameraVelocityX,
      cameraVelocityY: _cameraVelocityY,
      tileCullCache: _tileCullCache,
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
    if (onWorldTap != null) {
      child = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapUp: (details) {
          final box = context.findRenderObject() as RenderBox?;
          onWorldTap(widget.camera.screenToWorld(details.localPosition, box?.size ?? Size.zero));
        },
        child: child,
      );
    }

    if (!widget.showPerformanceOverlay) return child;

    // Flutter's own bar-graph widget, not this engine's -- see
    // EngineView.showPerformanceOverlay's doc comment for why a raster-
    // thread graph specifically (not another Dart-side FrameStats
    // number) is what this adds. Needs an explicit height (Flutter's
    // own convention -- see its docs/examples): tall enough for both
    // bars to actually be readable, not so tall it eats the screen.
    return Stack(
      children: [
        child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SizedBox(
            height: 150,
            child: PerformanceOverlay.allEnabled(),
          ),
        ),
      ],
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

  /// When set, overrides [ambientBrightness]/a plain black overlay with
  /// this clock's computed brightness and ARGB tint — see
  /// `EngineView.dayNightCycle`'s own doc comment.
  final DayNightCycle? dayNightCycle;

  /// [ambientBrightness] scaled by [dayNightCycle]'s own computed
  /// brightness (`1.0`, a no-op multiplier, when no cycle is set) —
  /// what every ambient-darkness site below should actually read.
  /// Deliberately a *multiply*, not a full override: an earlier version
  /// of this let [dayNightCycle] replace [ambientBrightness] outright,
  /// which silently discarded a scene's own tuned baseline (found live
  /// -- `test_game`'s prison level ships `ambientBrightness: 0.25`,
  /// carefully tuned against its torches/lava-glow lights; a
  /// `dayNightCycle` reaching deep night (brightness ~0.18, *brighter*
  /// than 0.25) would have made the whole level lighter than its
  /// authored baseline, not darker as intended, purely because 0.25 was
  /// discarded rather than participating). Multiplying instead means
  /// [ambientBrightness] acts as a scene-authored ceiling the cycle can
  /// only ever dim *further*, in proportion — never silently replaced,
  /// and full daylight (`dayNightCycle.ambientBrightness == 1.0`)
  /// reproduces the original baseline exactly (`x * 1.0 == x`).
  double get _effectiveAmbientBrightness =>
      ambientBrightness * (dayNightCycle?.ambientBrightness ?? 1.0);

  /// [dayNightCycle]'s computed tint when set (else plain black
  /// `0xFF000000`, matching the overlay's pre-`DayNightCycle` behavior
  /// exactly), further scaled toward black by [ambientBrightness].
  ///
  /// `DayNightCycle.ambientColorArgb` already scales its own hue by the
  /// *cycle's* brightness (see that getter's doc comment) — but it has
  /// no way to know about this scene's *own* [ambientBrightness]
  /// ceiling, which [_effectiveAmbientBrightness] above also folds in.
  /// Without this second scaling, color and the alpha actually used for
  /// the overlay could still desync: e.g. a scene-tuned
  /// `ambientBrightness: 0.25` combined with a cycle brightness of
  /// ~0.8 gives a *combined* brightness of ~0.2 (correctly dark, per
  /// `_effectiveAmbientBrightness`) — but the cycle's own tint, scaled
  /// only by its own ~0.8, would still read as a fairly bright color.
  /// Composited at the correctly-high alpha that ~0.2 combined
  /// brightness produces, that still-bright tint could end up visibly
  /// *brighter* than an area a light had actually revealed back to the
  /// scene's true (but comparatively dim) colors — the same on-screen
  /// inversion `DayNightCycle.ambientColorArgb`'s own fix addressed,
  /// caught again here once a scene supplies both a `dayNightCycle`
  /// *and* a non-default `ambientBrightness` together (prison.level.json's
  /// combination, real DIAG evidence of the fix in
  /// `day_night_cycle_view_test.dart`).
  int get _effectiveAmbientColorArgb {
    final cycle = dayNightCycle;
    if (cycle == null) return 0xFF000000;
    return (Color.lerp(
              const Color(0xFF000000),
              Color(cycle.ambientColorArgb),
              ambientBrightness.clamp(0, 1),
            ) ??
            const Color(0xFF000000))
        .toARGB32();
  }

  /// Real wall-clock seconds since the last rendered frame — used only
  /// to advance `Light2D.shadowSmoothingSeconds`' exponential smoothing
  /// at the actual render frame rate (not the simulation's fixed/
  /// variable tick rate, which can differ). `0` (the default) makes
  /// every smoothed ray jump straight to its raw value the first time
  /// it's read, same as smoothing being off.
  final double frameDtSeconds;

  /// Written into (not read from) during [paint] — see `FrameStats`'s
  /// own doc comment. Never null in practice (`_EngineViewState`
  /// always supplies at least its own internal instance), but kept
  /// nullable so a painter built without one (e.g. directly in a
  /// test) doesn't need to fabricate one just to satisfy this field.
  final FrameStats? frameStats;

  /// See `EngineView.cullBufferPx`'s own doc comment.
  final double cullBufferPx;

  /// World units/sec, sampled once per tick by `_EngineViewState` — see
  /// `EngineView.cullBufferPx`'s doc comment on the predictive
  /// look-ahead these drive.
  final double cameraVelocityX;
  final double cameraVelocityY;

  /// Same `Map` instance across every frame's fresh `_EnginePainter` —
  /// see `EngineView.cullBufferPx`'s doc comment and `_TileCullCache`.
  final Map<EntityId, _TileCullCache> tileCullCache;

  _EnginePainter({
    required this.world,
    required this.atlasRegistry,
    required this.camera,
    required this.backgroundColor,
    this.showColliderDebug = false,
    this.previousPositions = const {},
    this.interpolationAlpha = 1,
    this.ambientBrightness = 1.0,
    this.dayNightCycle,
    this.frameDtSeconds = 0,
    this.frameStats,
    this.cullBufferPx = 96.0,
    this.cameraVelocityX = 0,
    this.cameraVelocityY = 0,
    Map<EntityId, _TileCullCache>? tileCullCache,
  })  : tileCullCache = tileCullCache ?? {},
        super(repaint: null);

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
    final paintStopwatch = Stopwatch()..start();
    frameStats?.lightingMs = 0; // accumulated across every _drawLighting call this frame
    final positions = world.storeOf<Position>();
    final clipShapes = world.storeOf<ClipShape>();
    final reveals = <_ClipShapeInfo>[];
    final cutouts = <_ClipShapeInfo>[];
    for (var i = 0; i < clipShapes.length; i++) {
      final entity = clipShapes.entityAt(i);
      final shape = clipShapes.denseAt(i);
      final worldPos = positions.get(entity);
      if (worldPos == null) continue;
      final info = _ClipShapeInfo(shape, camera.worldToScreen(worldPos.x, worldPos.y, size));
      (shape.mode == ClipShapeMode.reveal ? reveals : cutouts).add(info);
    }

    // "reveal" has to *clip drawing as it happens* (a real Canvas is
    // immediate-mode -- there's no way to retroactively confine
    // already-drawn pixels to a region after the fact), so it wraps
    // the entire body below in a save/clipPath/restore, applied before
    // a single pixel of it is drawn. "cutout" is the opposite problem
    // -- it has to *erase* pixels the body below is about to draw, so
    // it wraps that same body in an extra saveLayer, punching holes
    // (`BlendMode.dstOut`, same technique `_drawLighting`'s own
    // darkness pass already uses) once everything is on the layer,
    // right before compositing it back. Both are skipped entirely
    // (i.e. free) whenever no `ClipShape` of that mode exists.
    if (cutouts.isNotEmpty) canvas.saveLayer(Offset.zero & size, Paint());

    canvas.save();
    if (reveals.isNotEmpty) {
      final combined = Path();
      for (final info in reveals) {
        combined.addPath(_clipShapePath(info), Offset.zero);
      }
      canvas.clipPath(combined);
    }

    canvas.drawRect(Offset.zero & size, Paint()..color = backgroundColor);

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

    if (_effectiveAmbientBrightness < 1.0) {
      _paintZBanded(canvas, size, positions, items);
    } else {
      for (final item in items) {
        item.paint(canvas);
      }
    }

    _drawScreenTint(canvas, size);

    // Drawn last (on top of everything else) and outside the z-sorted
    // item list entirely -- debug outlines are diagnostic, not part of
    // the game's actual draw order, so they always win regardless of
    // any zIndex a real renderable happens to have.
    if (showColliderDebug) {
      _drawColliderDebug(canvas, size, positions);
      _drawTileMapDebug(canvas, size, positions);
    }

    canvas.restore(); // undo the reveal clip (a no-op if none applied)

    if (cutouts.isNotEmpty) {
      for (final info in cutouts) {
        final paint = Paint()..blendMode = BlendMode.dstOut;
        if (info.shape.softness > 0) {
          paint.maskFilter =
              ui.MaskFilter.blur(ui.BlurStyle.normal, info.shape.softness * camera.zoom);
        }
        canvas.drawPath(_clipShapePath(info), paint);
      }
      canvas.restore(); // composite the holed layer back
    }
    paintStopwatch.stop();
    frameStats?.paintMs = paintStopwatch.elapsedMicroseconds / 1000;
  }

  /// The screen-space `Path` for one `ClipShape` — a circle
  /// (`addOval`) or a rectangle (`addRect`) centered on
  /// [_ClipShapeInfo.screenPos], scaled by `Camera.zoom` the same way
  /// every other world-space size in this file is.
  Path _clipShapePath(_ClipShapeInfo info) {
    final shape = info.shape;
    final path = Path();
    if (shape.isCircle) {
      path.addOval(Rect.fromCircle(center: info.screenPos, radius: shape.radius * camera.zoom));
    } else {
      path.addRect(Rect.fromCenter(
        center: info.screenPos,
        width: shape.width * camera.zoom,
        height: shape.height * camera.zoom,
      ));
    }
    return path;
  }

  /// Splits [items] into z-bands at every `Light2D.minZIndex`/
  /// `maxZIndex` boundary and draws + lights each band in isolation
  /// (its own `saveLayer`/`restore`) before the next band's content is
  /// drawn on top — see `Light2D.minZIndex`'s doc comment for why: a
  /// light scoped to one band must only darken/reveal that band's own
  /// content, never anything drawn before or after it in z-order. No
  /// light in [items]' world using `minZIndex`/`maxZIndex` collapses
  /// this back to exactly one band covering everything, i.e. the
  /// original single full-screen pass — this path costs nothing extra
  /// for a game that never sets those fields.
  void _paintZBanded(
    Canvas canvas,
    Size size,
    ComponentStore<Position> positions,
    List<_DrawItem> items,
  ) {
    final lights = world.storeOf<Light2D>();
    final boundaries = <int>{};
    for (var i = 0; i < lights.length; i++) {
      final light = lights.denseAt(i);
      if (light.minZIndex != null) boundaries.add(light.minZIndex!);
      if (light.maxZIndex != null) boundaries.add(light.maxZIndex! + 1);
    }

    if (boundaries.isEmpty) {
      for (final item in items) {
        item.paint(canvas);
      }
      _drawLighting(canvas, size, positions);
      return;
    }

    final fullRect = Offset.zero & size;
    final sorted = boundaries.toList()..sort();
    final edges = [_negInfZ, ...sorted, _posInfZ];

    var itemIndex = 0;
    for (var b = 0; b < edges.length - 1; b++) {
      final start = edges[b];
      final end = edges[b + 1];
      // A representative z within this band, used to test each light's
      // range against it -- valid because bands are cut exactly at the
      // points where light coverage can change, so every z inside one
      // band gives the same answer for every light.
      final bandZ = start == _negInfZ ? end - 1 : start;

      canvas.saveLayer(fullRect, Paint());
      while (itemIndex < items.length && items[itemIndex].zIndex < end) {
        items[itemIndex].paint(canvas);
        itemIndex++;
      }
      _drawLighting(
        canvas,
        size,
        positions,
        lightFilter: (light) =>
            bandZ >= (light.minZIndex ?? _negInfZ) && bandZ <= (light.maxZIndex ?? _posInfZ),
      );
      canvas.restore();
    }
  }

  static const int _negInfZ = -1 << 30;
  static const int _posInfZ = 1 << 30;

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
  ///
  /// [lightFilter], when given (by `_paintZBanded`, scoping this call to
  /// one z-band), skips any light it returns `false` for — `null` (the
  /// plain, unbanded path) includes every light, identical to before
  /// z-scoped lights existed.
  ///
  /// Whenever [lightFilter] is given, the darkness rect below composites
  /// with `BlendMode.srcATop` instead of the default `srcOver` — src-atop
  /// only paints where the destination *already has* alpha, at that
  /// alpha's own strength, so this pass darkens only pixels `_paintZBanded`
  /// already drew into this band's layer and leaves the rest of it fully
  /// transparent. Plain `srcOver` (used for the unbanded, single-pass
  /// call, where "the destination" is the whole already-drawn scene, which
  /// covers 100% of the screen) would otherwise have this band's darkness
  /// rect blanket the *entire* screen in opaque black regardless of
  /// whether this band drew anything there — silently erasing whatever
  /// every other band composited before or after it. Caught by a real
  /// pixel-sampling test (not just "renders without crashing"): a
  /// zIndex-1 sprite outside a zIndex-0-scoped light's range was
  /// correctly left dark, but so was the zIndex-0 sprite the light was
  /// actually supposed to reveal, because the zIndex-1 band's own (empty
  /// there) darkness rect painted over the whole canvas afterward.
  void _drawLighting(
    Canvas canvas,
    Size size,
    ComponentStore<Position> positions, {
    bool Function(Light2D)? lightFilter,
  }) {
    final lightingStopwatch = Stopwatch()..start();
    final lights = world.storeOf<Light2D>();
    final fullRect = Offset.zero & size;

    // Computed once per light, reused for both the darkness-reveal
    // pass and the (optional) color-tint pass below, so a
    // shadow-casting light's raycasts don't run twice.
    final infos = <_LightRenderInfo>[];
    for (var i = 0; i < lights.length; i++) {
      final entity = lights.entityAt(i);
      final light = lights.denseAt(i);
      if (lightFilter != null && !lightFilter(light)) continue;
      final rawPos = positions.get(entity);
      if (rawPos == null) continue;
      if (light.radius <= 0) continue;

      // Same interpolation `Sprite`/`Particle` rendering already gets
      // -- without this, a light attached to a moving entity would
      // visibly lag/step relative to that entity's own smoothly-
      // interpolated sprite whenever fixedTimestepSeconds is set,
      // since Position alone (the fixed-step *simulation* value) can
      // be one whole fixed step behind the render frame.
      final interpolated = _interpolated(entity, rawPos);
      final worldPos = Position(interpolated.dx, interpolated.dy);
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
      final clipPath = _lightClipPath(light, worldPos, size, entity);
      infos.add(_LightRenderInfo(light, screenPos, screenRadius, clipPath, worldPos));
    }

    canvas.saveLayer(
      fullRect,
      lightFilter != null ? (Paint()..blendMode = BlendMode.srcATop) : Paint(),
    );
    canvas.drawRect(
      fullRect,
      Paint()..color = Color(_effectiveAmbientColorArgb).withValues(
        alpha: (1 - _effectiveAmbientBrightness).clamp(0, 1),
      ),
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
      _drawLightGradientCircle(canvas, info, revealPaint);
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
      _drawLightGradientCircle(canvas, info, tintPaint);
    }

    // Overbright glow: also additive (BlendMode.plus, same reasoning
    // as the tint pass above -- needs the real scene colors
    // underneath), but plain white and independent of colorArgb, so
    // overlapping lights' glows genuinely stack past what the
    // brightness-reveal pass alone can reach (that pass only ever
    // erases darkness back to the scene's *original* brightness, which
    // can't make an overlap area brighter than either light manages
    // alone -- see Light2D.overbrightIntensity's doc comment). Skipped
    // per-light whenever overbrightIntensity is 0 (the default), so a
    // game that never sets it pays nothing extra.
    for (final info in infos) {
      final peak = info.light.overbrightIntensity.clamp(0.0, 1.0);
      if (peak == 0) continue;

      final overbrightPaint = Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(
          info.screenPos,
          info.screenRadius,
          _falloffColors(Color.fromRGBO(255, 255, 255, peak)),
          _falloffStops,
        )
        ..maskFilter = _shadowEdgeMaskFilter(info);
      _drawLightGradientCircle(canvas, info, overbrightPaint);
    }

    // GPU-shader shadow-casting pass -- see Light2D.useGpuShadows's doc
    // comment for why this exists (a real per-pixel-parallel
    // alternative to the CPU raycastTileMap sweep) and why it's
    // additive rather than replicating the CPU path's darkness-mask
    // semantics. Skipped per-light whenever useGpuShadows/castsShadows
    // isn't set, and skipped entirely for a frame where the shader
    // hasn't finished its one-time async compile yet.
    for (final info in infos) {
      if (!info.light.useGpuShadows || !info.light.castsShadows) continue;
      // Defensive: a degenerate uRadius (0, negative, NaN/Infinity --
      // shouldn't happen given the `light.radius <= 0` guard earlier in
      // this method already filters those out, but a shader reading an
      // out-of-range uniform is undefined behavior on the GPU, not a
      // clean no-op the way CPU code would be) must never reach the
      // shader; skip this light's GPU pass entirely rather than risk
      // an unclipped full-rect draw.
      if (!info.screenRadius.isFinite || info.screenRadius <= 0) continue;
      if (!info.screenPos.dx.isFinite || !info.screenPos.dy.isFinite) continue;
      final shader = GpuLightShader.shader();
      if (shader == null) continue;

      final segments = _gpuLightSegmentsFor(info, size);
      final segmentCount = segments.length ~/ 2;

      final rawColor = Color(info.light.colorArgb);
      final tinted = rawColor.a > 0;
      final color = tinted ? rawColor : const Color(0xFFFFFFFF);

      var u = 0;
      shader
        ..setFloat(u++, size.width)
        ..setFloat(u++, size.height)
        ..setFloat(u++, info.screenPos.dx)
        ..setFloat(u++, info.screenPos.dy)
        ..setFloat(u++, info.screenRadius)
        ..setFloat(u++, info.light.intensity.clamp(0.0, 1.0))
        ..setFloat(u++, color.r)
        ..setFloat(u++, color.g)
        ..setFloat(u++, color.b)
        ..setFloat(u++, tinted ? color.a : 1.0)
        ..setFloat(u++, segmentCount.toDouble());
      for (var i = 0; i < _gpuMaxSegments; i++) {
        if (i < segmentCount) {
          final a = segments[i * 2];
          final b = segments[i * 2 + 1];
          shader
            ..setFloat(u++, a.dx)
            ..setFloat(u++, a.dy)
            ..setFloat(u++, b.dx)
            ..setFloat(u++, b.dy);
        } else {
          shader
            ..setFloat(u++, 0)
            ..setFloat(u++, 0)
            ..setFloat(u++, 0)
            ..setFloat(u++, 0);
        }
      }

      final lightRect = Rect.fromCircle(center: info.screenPos, radius: info.screenRadius);
      canvas.drawRect(lightRect, Paint()..shader = shader..blendMode = BlendMode.plus);
    }
    lightingStopwatch.stop();
    final stats = frameStats;
    if (stats != null) stats.lightingMs += lightingStopwatch.elapsedMicroseconds / 1000;
  }

  static const int _gpuMaxSegments = 32;

  /// Up to [_gpuMaxSegments] world-solid-tile *boundary* edges near
  /// [info]'s light, as consecutive screen-space `(a, b)` `Offset`
  /// pairs, for `Light2D.useGpuShadows`'s shader to test ray-segment
  /// occlusion against. "Boundary" means a solid tile's edge is only
  /// emitted when the neighboring cell across it is *not* solid (off
  /// the map counts as not solid too) — skips the interior edges
  /// shared between two adjacent solid tiles, which would otherwise
  /// vastly over-count segments for a dense solid block (a light deep
  /// inside a thick wall region would blow the segment budget on
  /// interior edges nothing ever actually needs to occlude against).
  /// Solid cells are visited nearest-to-the-light first so a light
  /// whose local area has more boundary edges than the budget allows
  /// still gets the closest, most visually-significant ones rather
  /// than an arbitrary subset.
  List<Offset> _gpuLightSegmentsFor(_LightRenderInfo info, Size size) {
    final tileMaps = world.storeOf<TileMap>();
    final mapPositions = world.storeOf<Position>();
    final segments = <Offset>[];

    for (var m = 0; m < tileMaps.length && segments.length < _gpuMaxSegments * 2; m++) {
      final mapEntity = tileMaps.entityAt(m);
      final map = tileMaps.denseAt(m);
      final origin = mapPositions.get(mapEntity) ?? Position(0, 0);

      final minCol = ((info.worldPos.x - info.light.radius - origin.x) / map.tileWidth)
          .floor()
          .clamp(0, map.cols - 1);
      final maxCol = ((info.worldPos.x + info.light.radius - origin.x) / map.tileWidth)
          .ceil()
          .clamp(0, map.cols - 1);
      final minRow = ((info.worldPos.y - info.light.radius - origin.y) / map.tileHeight)
          .floor()
          .clamp(0, map.rows - 1);
      final maxRow = ((info.worldPos.y + info.light.radius - origin.y) / map.tileHeight)
          .ceil()
          .clamp(0, map.rows - 1);

      final candidates = <_GpuSolidCell>[];
      for (var row = minRow; row <= maxRow; row++) {
        for (var col = minCol; col <= maxCol; col++) {
          if (!map.isSolid(col, row)) continue;
          final cx = origin.x + (col + 0.5) * map.tileWidth;
          final cy = origin.y + (row + 0.5) * map.tileHeight;
          final dx = cx - info.worldPos.x;
          final dy = cy - info.worldPos.y;
          candidates.add(_GpuSolidCell(col, row, dx * dx + dy * dy));
        }
      }
      candidates.sort((a, b) => a.distSq.compareTo(b.distSq));

      for (final cell in candidates) {
        if (segments.length >= _gpuMaxSegments * 2) break;
        final left = origin.x + cell.col * map.tileWidth;
        final right = left + map.tileWidth;
        final top = origin.y + cell.row * map.tileHeight;
        final bottom = top + map.tileHeight;

        void addIfBoundary(bool neighborSolid, Offset a, Offset b) {
          if (neighborSolid || segments.length >= _gpuMaxSegments * 2) return;
          segments
            ..add(camera.worldToScreen(a.dx, a.dy, size))
            ..add(camera.worldToScreen(b.dx, b.dy, size));
        }

        addIfBoundary(map.isSolid(cell.col, cell.row - 1), Offset(left, top), Offset(right, top));
        addIfBoundary(
            map.isSolid(cell.col, cell.row + 1), Offset(left, bottom), Offset(right, bottom));
        addIfBoundary(map.isSolid(cell.col - 1, cell.row), Offset(left, top), Offset(left, bottom));
        addIfBoundary(
            map.isSolid(cell.col + 1, cell.row), Offset(right, top), Offset(right, bottom));
      }
    }

    return segments;
  }

  /// Draws [paint] (already carrying its radial gradient/blend mode) as
  /// a circle at [info]'s screen position/radius, clipped to
  /// [info.clipPath] first when one exists (a shadow-casting/cone
  /// light's visibility polygon) -- the exact same
  /// save/clipPath/drawCircle/restore-or-not shape the reveal, tint,
  /// and overbright passes all need, factored out so a third
  /// (overbright) pass didn't triplicate it.
  void _drawLightGradientCircle(Canvas canvas, _LightRenderInfo info, Paint paint) {
    if (info.clipPath == null) {
      canvas.drawCircle(info.screenPos, info.screenRadius, paint);
    } else {
      canvas.save();
      canvas.clipPath(info.clipPath!);
      canvas.drawCircle(info.screenPos, info.screenRadius, paint);
      canvas.restore();
    }
  }

  /// Draws one full-viewport rect per `ScreenTint` entity, normal
  /// (`SrcOver`) blending — see `ScreenTint`'s doc comment for why this
  /// runs after the lighting pass (so a tint isn't itself darkened) and
  /// why multiple entities are allowed to layer. Skips a fully
  /// transparent tint (`colorArgb`'s alpha `0`, the common case for a
  /// `ScreenTintStep` mid-fade-in) entirely rather than drawing a
  /// no-op rect every frame.
  void _drawScreenTint(Canvas canvas, Size size) {
    final tints = world.storeOf<ScreenTint>();
    if (tints.length == 0) return;
    final fullRect = Offset.zero & size;
    for (var i = 0; i < tints.length; i++) {
      final color = Color(tints.denseAt(i).colorArgb);
      if (color.a == 0) continue;
      canvas.drawRect(fullRect, Paint()..color = color);
    }
  }

  /// Radial-gradient stop positions shared by the reveal and tint
  /// passes, paired with [_falloffFractions] (that stop's alpha as a
  /// fraction of the center's) — a *plateau*, not a curve that starts
  /// dimming the instant it leaves the center: full strength held flat
  /// out to 60% of the radius (the light's actual body reads as a real,
  /// solidly-lit area, not something hazy from its own center), then
  /// falls off only over the remaining 40%, landing at fully faded
  /// right at the edge. Two earlier attempts got this wrong in
  /// opposite directions: a flat 2-stop linear dim faded from the
  /// center outward (read as artificial/washed-out); a quadratic-ish
  /// curve that dimmed immediately from the peak, however smooth,
  /// still read as the *light itself* being soft/hazy rather than a
  /// real light with a soft *edge* — the actual, explicit ask. Softness
  /// belongs at the boundary (here, plus the separate edge blur from
  /// `Light2D.shadowEdgeSoftness` for a shadow-casting/cone light's
  /// polygon), not smeared across the whole radius. `ui.Gradient.radial`
  /// only interpolates linearly *between* stops, so the falloff portion
  /// is sampled at a few points to still read as a smooth transition
  /// rather than one visible linear kink.
  static const List<double> _falloffStops = [0.0, 0.6, 0.8, 0.92, 1.0];
  static const List<double> _falloffFractions = [1.0, 1.0, 0.7, 0.25, 0.0];

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
  Path? _lightClipPath(Light2D light, Position worldPos, Size size, EntityId lightEntity) {
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

    // See Light2D.cacheShadowGeometry's doc comment: this only ever
    // skips the raycastTileMap sweep itself (world-space, camera-
    // independent) -- the screen-space Path below is always rebuilt
    // fresh every frame from whichever distances (cached or freshly
    // raycast) end up in `rawDistances`, so panning/zooming the camera
    // while a cache hit is in effect still looks correct.
    final cacheHit = light.cacheShadowGeometry &&
        light.cachedShadowDistances != null &&
        light.cachedShadowDistances!.length == rayCount + 1 &&
        light.cachedShadowWorldX == worldPos.x &&
        light.cachedShadowWorldY == worldPos.y &&
        light.cachedShadowRadius == light.radius &&
        light.cachedShadowConeAngle == light.coneAngle &&
        light.cachedShadowConeDirection == light.coneDirection &&
        light.cachedShadowRayCount == rayCount &&
        light.cachedShadowBlockOneWay == light.blockOneWayPlatforms &&
        light.cachedShadowCastsShadows == light.castsShadows &&
        light.cachedShadowOpenAirFalloffScale == light.openAirFalloffScale;

    final List<double> rawDistances;
    if (cacheHit) {
      rawDistances = light.cachedShadowDistances!;
    } else {
      // Collected once per light, not once per ray -- a per-ray scan
      // of the *entire* Collider store (this repo's own test_game has
      // ~15-20 of them: player, enemies, every coin) multiplied by
      // shadowRayCount (up to 64) turned into a real, measured frame-
      // rate regression the moment more than one shadow-casting light
      // was on screen at once, even with zero entities actually tagged
      // blocksLight -- the short-circuiting `if (!blocksLight) continue`
      // still means walking the whole store that many times over.
      // useGpuShadows takes over the actual raycastTileMap sweep this
      // light would otherwise run here (see the GPU-shadow pass in
      // _drawLighting) -- the CPU reveal/tint path below still runs
      // for it, but as a plain circle/cone, not a duplicated sweep of
      // its own. Enabling useGpuShadows is meant to *replace* the CPU
      // sweep's cost for that light, not add the GPU pass on top of it.
      final skipCpuRaycast = light.useGpuShadows;
      final blockers = light.castsShadows && !skipCpuRaycast
          ? _collectLightBlockingColliders(lightEntity)
          : const <_LightBlocker>[];
      rawDistances = List<double>.filled(rayCount + 1, 0);
      for (var i = 0; i <= rayCount; i++) {
        final angle = startAngle + sweep * i / rayCount;
        if (!light.castsShadows || skipCpuRaycast) {
          rawDistances[i] = light.radius;
          continue;
        }
        final hitDist = _raycastLightDistance(
            worldPos, angle, light.radius, light.blockOneWayPlatforms, blockers);
        // A ray that reached the light's full radius without hitting
        // anything is genuinely open air along that direction -- pull
        // it in to openAirFalloffScale * radius instead. A ray that
        // *did* hit a surface short of the radius is left exactly as
        // raycast, so the light still fully reaches whatever it's
        // actually illuminating.
        rawDistances[i] =
            hitDist >= light.radius ? light.radius * light.openAirFalloffScale : hitDist;
      }
      if (light.cacheShadowGeometry) {
        light.cachedShadowDistances = rawDistances;
        light.cachedShadowWorldX = worldPos.x;
        light.cachedShadowWorldY = worldPos.y;
        light.cachedShadowRadius = light.radius;
        light.cachedShadowConeAngle = light.coneAngle;
        light.cachedShadowConeDirection = light.coneDirection;
        light.cachedShadowRayCount = rayCount;
        light.cachedShadowBlockOneWay = light.blockOneWayPlatforms;
        light.cachedShadowCastsShadows = light.castsShadows;
        light.cachedShadowOpenAirFalloffScale = light.openAirFalloffScale;
      }
    }

    final path = Path();
    final centerScreen = camera.worldToScreen(worldPos.x, worldPos.y, size);
    path.moveTo(centerScreen.dx, centerScreen.dy);

    for (var i = 0; i <= rayCount; i++) {
      final angle = startAngle + sweep * i / rayCount;
      final rawDist = rawDistances[i];
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

  /// Every `Collider(blocksLight: true)` entity's position/radius,
  /// collected once per light per frame (not once per *ray* — see
  /// `_raycastLightDistance`'s call site for why that distinction is
  /// what actually matters) — [lightEntity] excluded so a light never
  /// self-shadows at zero distance if it also happens to carry a
  /// light-blocking `Collider` (e.g. a torch prop that's also solid).
  /// Empty (allocates nothing but a `const []`, effectively) the
  /// common case: no entity in the world is tagged at all.
  List<_LightBlocker> _collectLightBlockingColliders(EntityId lightEntity) {
    final colliders = world.storeOf<Collider>();
    if (colliders.length == 0) return const [];
    final positions = world.storeOf<Position>();
    final blockers = <_LightBlocker>[];
    for (var c = 0; c < colliders.length; c++) {
      final entity = colliders.entityAt(c);
      if (entity == lightEntity) continue;
      final collider = colliders.denseAt(c);
      if (!collider.blocksLight) continue;
      final pos = positions.get(entity);
      if (pos == null) continue;
      blockers.add(_LightBlocker(pos.x, pos.y, collider.radius));
    }
    return blockers;
  }

  /// How far a light at [worldPos] can see along [angle] before the
  /// nearest solid tile in any `TileMap`, or the nearest entry in
  /// [blockers], blocks it — capped at [maxRadius] when nothing blocks
  /// it at all. [blockOneWay] forwards straight to `raycastTileMap`'s
  /// own parameter of the same name (see `Light2D.blockOneWayPlatforms`'s
  /// doc comment for why a light would want this on).
  double _raycastLightDistance(
    Position worldPos,
    double angle,
    double maxRadius,
    bool blockOneWay,
    List<_LightBlocker> blockers,
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

    if (blockers.isNotEmpty) {
      final dirX = cos(angle);
      final dirY = sin(angle);
      for (final blocker in blockers) {
        final hitDist = _rayCircleDistance(
            worldPos.x, worldPos.y, dirX, dirY, blocker.x, blocker.y, blocker.radius);
        if (hitDist != null && hitDist < nearest) {
          nearest = hitDist;
        }
      }
    }

    return nearest;
  }

  /// Standard ray-vs-circle intersection: the distance from
  /// `(originX, originY)` along the unit direction `(dirX, dirY)` to
  /// the nearest point where it enters the circle at
  /// `(circleX, circleY)` radius [radius], or `null` if the ray misses
  /// it entirely (or the origin already starts inside it, treated the
  /// same as a miss -- a light's own position is never occluded by
  /// something it's already overlapping).
  double? _rayCircleDistance(
    double originX,
    double originY,
    double dirX,
    double dirY,
    double circleX,
    double circleY,
    double radius,
  ) {
    final ocX = originX - circleX;
    final ocY = originY - circleY;
    final b = ocX * dirX + ocY * dirY;
    final c = ocX * ocX + ocY * ocY - radius * radius;
    if (c < 0) return null; // origin already inside the circle
    final discriminant = b * b - c;
    if (discriminant < 0) return null;
    final t = -b - sqrt(discriminant);
    return t >= 0 ? t : null;
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
  /// this deliberately doesn't cover). Every circle shares one `Path`
  /// (via `addOval`) stroked in a single `drawPath` call instead of one
  /// `drawCircle` command per collider — every circle already shares
  /// the same `Paint`, so batching them costs nothing in fidelity and
  /// avoids a real per-frame cost this debug overlay would otherwise
  /// add for a level with many colliders left on during iteration (the
  /// same batching principle `_collectSpriteItems`'s `Canvas.drawAtlas`
  /// path already applies to regular sprites).
  void _drawColliderDebug(Canvas canvas, Size size, ComponentStore<Position> positions) {
    final colliders = world.storeOf<Collider>();
    if (colliders.length == 0) return;
    final paint = Paint()
      ..color = const Color(0xFF00FF00)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path();
    for (var i = 0; i < colliders.length; i++) {
      final entity = colliders.entityAt(i);
      final pos = positions.get(entity);
      if (pos == null) continue;
      final screenPos = camera.worldToScreen(pos.x, pos.y, size);
      final radius = colliders.denseAt(i).radius * camera.zoom;
      path.addOval(Rect.fromCircle(center: screenPos, radius: radius));
    }
    canvas.drawPath(path, paint);
  }

  /// A stroked border per solid (red)/one-way (blue)/slope (orange)
  /// tile, on top of `_collectTileMapItems`'s filled color — makes a
  /// tile's exact collision boundary unambiguous even when its fill
  /// color is hard to tell apart from a neighboring tile at a glance.
  /// Every tile of the same collision kind shares that kind's `Path`
  /// (`addRect` per tile), stroked in one `drawPath` call per kind (at
  /// most 3 draw calls total, not one per solid/one-way/slope tile) —
  /// same batching reasoning as `_drawColliderDebug`.
  void _drawTileMapDebug(Canvas canvas, Size size, ComponentStore<Position> positions) {
    final tileMaps = world.storeOf<TileMap>();
    final solidPath = Path();
    final oneWayPath = Path();
    final slopePath = Path();
    var hasSolid = false;
    var hasOneWay = false;
    var hasSlope = false;

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
          final rect = Rect.fromLTWH(
            screenPos.dx,
            screenPos.dy,
            map.tileWidth * camera.zoom,
            map.tileHeight * camera.zoom,
          );
          if (isSolid) {
            solidPath.addRect(rect);
            hasSolid = true;
          } else if (isOneWay) {
            oneWayPath.addRect(rect);
            hasOneWay = true;
          } else {
            slopePath.addRect(rect);
            hasSlope = true;
          }
        }
      }
    }

    void strokeBatch(Path path, Color color) {
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    if (hasSolid) strokeBatch(solidPath, const Color(0xFFFF3B30));
    if (hasOneWay) strokeBatch(oneWayPath, const Color(0xFF3B82F6));
    if (hasSlope) strokeBatch(slopePath, const Color(0xFFFF9500));
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
  ///
  /// `TileMap.backgroundTiles`/`foregroundTiles`, when set, draw as a
  /// second/third full pass under/over the main layer respectively
  /// (same texture-or-flat-color resolution, just never contributing a
  /// collision-kind color since those layers are purely visual). Every
  /// tile id drawn (main, background, or foreground) is first resolved
  /// through `TileMap.currentTileId` so an animated id shows its
  /// current frame's texture — collision itself always keys off the
  /// *base* id regardless of which frame is currently on screen.
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
        // world-space rect the viewport currently shows.
        final topLeftWorld = camera.screenToWorld(Offset.zero, size);
        final bottomRightWorld = camera.screenToWorld(Offset(size.width, size.height), size);
        final realRect = Rect.fromPoints(topLeftWorld, bottomRightWorld);

        // Reuse the last computed range outright when it's still valid
        // -- same zoom, same map origin (a moving-platform TileMap
        // would otherwise reuse a stale range), and the real visible
        // rect still fits entirely inside the buffered rect that range
        // was computed for. This is what turns "recompute the visible
        // tile range every single frame" into "recompute it only when
        // the camera's pan/zoom has actually outrun its buffer" --
        // see EngineView.cullBufferPx's doc comment.
        final cached = tileCullCache[mapEntity];
        final int minCol, maxCol, minRow, maxRow;
        if (cached != null &&
            cached.zoom == camera.zoom &&
            cached.originX == origin.x &&
            cached.originY == origin.y &&
            cached.bufferedWorldRect.left <= realRect.left &&
            cached.bufferedWorldRect.top <= realRect.top &&
            cached.bufferedWorldRect.right >= realRect.right &&
            cached.bufferedWorldRect.bottom >= realRect.bottom) {
          minCol = cached.minCol;
          maxCol = cached.maxCol;
          minRow = cached.minRow;
          maxRow = cached.maxRow;
        } else {
          // World-space buffer -- cullBufferPx is a *screen*-pixel
          // margin, so it's divided by zoom to stay a consistent
          // on-screen size regardless of how zoomed in/out the camera
          // is. Extended further in whichever direction the camera is
          // currently moving (its real per-tick velocity) as a small
          // predictive look-ahead, so a fast, sustained pan is less
          // likely to immediately outrun the buffer it was just given.
          final bufferWorld = cullBufferPx / camera.zoom;
          const predictSeconds = 0.25;
          final aheadX = (cameraVelocityX * predictSeconds).abs();
          final aheadY = (cameraVelocityY * predictSeconds).abs();
          final buffered = Rect.fromLTRB(
            realRect.left - bufferWorld - (cameraVelocityX < 0 ? aheadX : 0),
            realRect.top - bufferWorld - (cameraVelocityY < 0 ? aheadY : 0),
            realRect.right + bufferWorld + (cameraVelocityX > 0 ? aheadX : 0),
            realRect.bottom + bufferWorld + (cameraVelocityY > 0 ? aheadY : 0),
          );
          // Plus the original 1-tile safety margin, same reasoning as
          // before this cache existed: a tile straddling the buffered
          // rect's own edge should still get drawn.
          minCol = (((buffered.left - origin.x) / map.tileWidth).floor() - 1)
              .clamp(0, map.cols - 1);
          maxCol = (((buffered.right - origin.x) / map.tileWidth).ceil() + 1)
              .clamp(0, map.cols - 1);
          minRow = (((buffered.top - origin.y) / map.tileHeight).floor() - 1)
              .clamp(0, map.rows - 1);
          maxRow = (((buffered.bottom - origin.y) / map.tileHeight).ceil() + 1)
              .clamp(0, map.rows - 1);
          tileCullCache[mapEntity] = _TileCullCache(
              buffered, camera.zoom, origin.x, origin.y, minCol, maxCol, minRow, maxRow);
        }

        // Resolved once per TileMap (not per tile) -- a missing/
        // not-yet-loaded atlas just means every tile in this map falls
        // back to its flat debug color, same as a level authored with
        // no atlasId at all.
        final atlas = map.atlasId != null && atlasRegistry.has(map.atlasId!)
            ? atlasRegistry.resolve(map.atlasId!)
            : null;

        // Draws one tile face at [col]/[row] for raw (pre-animation) id
        // [rawTileId] -- shared by the background/main/foreground
        // passes below so texture/color resolution and destRect math
        // isn't triplicated. [colorFallback] is a background/
        // foreground layer's own flat color when it has no atlas
        // region (those layers are purely visual, so collision-kind
        // colors like "one-way blue" don't apply to them the way they
        // do for the main layer).
        void drawTile(int rawTileId, int col, int row, Color Function() colorFallback) {
          if (rawTileId == 0) return;
          final tileId = map.currentTileId(rawTileId);

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
          // to a flat color, so a level using textures for most tiles
          // can still leave some ids (an invisible trigger marker,
          // say) as plain color.
          final regionName = map.regionByTileId[tileId];
          final region = atlas != null && regionName != null
              ? atlas.regions[regionName]
              : null;
          if (region != null) {
            canvas.drawImageRect(atlas!.image, region, destRect, Paint());
            return;
          }

          canvas.drawRect(destRect, Paint()..color = colorFallback());
        }

        const backgroundForegroundFallback = Color(0xFF4A4A4A);

        for (var row = minRow; row <= maxRow; row++) {
          for (var col = minCol; col <= maxCol; col++) {
            drawTile(map.backgroundTileAt(col, row), col, row,
                () => backgroundForegroundFallback);
          }
        }

        for (var row = minRow; row <= maxRow; row++) {
          for (var col = minCol; col <= maxCol; col++) {
            final tileId = map.tileAt(col, row);
            drawTile(tileId, col, row, () {
              return map.oneWayTileIds.contains(tileId)
                  ? const Color(0x8899CCFF)
                  : (map.slopeUpRightTileIds.contains(tileId) ||
                          map.slopeUpLeftTileIds.contains(tileId))
                      ? const Color(0xFFC08040)
                      : map.ladderTileIds.contains(tileId)
                          ? const Color(0x88C09050)
                          : const Color(0xFF4A4A4A);
            });
          }
        }

        for (var row = minRow; row <= maxRow; row++) {
          for (var col = minCol; col <= maxCol; col++) {
            drawTile(map.foregroundTileAt(col, row), col, row,
                () => backgroundForegroundFallback);
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
/// One `TileMap` entity's cached, buffered visible-tile range — see
/// `EngineView.cullBufferPx`'s doc comment. [bufferedWorldRect] is the
/// padded world-space rect this range was computed against; a later
/// frame reuses [minCol]/[maxCol]/[minRow]/[maxRow] outright as long as
/// its own real (unbuffered) visible rect still fits entirely inside
/// [bufferedWorldRect] at the same [zoom] and map [origin] — recomputes
/// (a fresh, re-buffered rect) the moment any of those stop holding.
class _TileCullCache {
  final Rect bufferedWorldRect;
  final double zoom;
  final double originX;
  final double originY;
  final int minCol;
  final int maxCol;
  final int minRow;
  final int maxRow;

  _TileCullCache(
    this.bufferedWorldRect,
    this.zoom,
    this.originX,
    this.originY,
    this.minCol,
    this.maxCol,
    this.minRow,
    this.maxRow,
  );
}

class _LightRenderInfo {
  final Light2D light;
  final Offset screenPos;
  final double screenRadius;
  final Path? clipPath;
  final Position worldPos;
  _LightRenderInfo(
      this.light, this.screenPos, this.screenRadius, this.clipPath, this.worldPos);
}

/// One `Collider(blocksLight: true)` entity's world-space position/
/// radius, snapshotted once per light per frame by
/// `_collectLightBlockingColliders` — see that method's doc comment
/// for why collecting these once per *light* instead of once per *ray*
/// is what actually matters here.
class _LightBlocker {
  final double x;
  final double y;
  final double radius;
  _LightBlocker(this.x, this.y, this.radius);
}

/// One solid `TileMap` cell candidate for `_gpuLightSegmentsFor`'s
/// nearest-first boundary-edge walk.
class _GpuSolidCell {
  final int col;
  final int row;
  final double distSq;
  _GpuSolidCell(this.col, this.row, this.distSq);
}

/// One `ClipShape`'s precomputed screen position, alongside the shape
/// itself — computed once in `paint()` and reused by `_clipShapePath`.
class _ClipShapeInfo {
  final ClipShape shape;
  final Offset screenPos;
  _ClipShapeInfo(this.shape, this.screenPos);
}

/// One `Canvas.drawAtlas` call's worth of sprites sharing a source
/// image — see `_EnginePainter._collectSpriteItems`.
class _SpriteBatch {
  final transforms = <RSTransform>[];
  final rects = <Rect>[];
}
