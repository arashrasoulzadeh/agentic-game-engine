# Post-processing and screen effects

Full-screen looks for a finished frame: colour grading, vignette, scanlines, bloom, chromatic aberration, pixelate and
a CRT. They live in `zarvan_flutter` and are all optional; a game that uses none of them pays nothing.

![The same scene, eight looks](../img/postfx-presets.jpg)

*The same 300 random procedural sprites and seed in every cell, rendered in Chrome with the demo described
[below](#try-it-yourself-random-assets-in-the-browser).*

## Two layers, one choice

| | `PostProcessed` | `ShaderPostProcessed` |
|---|---|---|
| Effects | `ColorGrade`, `Vignette`, `Scanlines` | bloom, chromatic aberration, pixelate, CRT curvature, phosphor mask, vignette, grain, one pass |
| How | A colour filter plus painted overlays on top of the child | The child is snapshotted each frame and redrawn through one fragment shader |
| Cost | About nothing (see [measurements](#measurements)) | One snapshot per frame, **independent of how many effects are on** |
| Latency | None | One frame behind |
| Works on | Everywhere | Every backend (it does not need `ImageFilter.shader`) |
| Switch it on | Wrap a widget: `PostProcessed(effects: [...], child: ...)` | `game.postFx.value = ShaderPostFx.crt()`, or wrap a widget |

Use `PostProcessed` for grade, vignette and scanlines, and `ShaderPostFx` for everything that needs a shader. Both can
be on at once; `runGame` wires `Game.postFx` for you.

## Effects reference

| Effect | Where | Parameters |
|---|---|---|
| Brightness, contrast, saturation, tint | `ColorGrade` | 1 is neutral; several grades compose into one filter layer |
| Edge darkening | `Vignette`, or `ShaderPostFx.vignette` | strength and radius, or strength 0..1 |
| CRT lines | `Scanlines`, or `ShaderPostFx.scanlines` | opacity and spacing |
| Glow on bright areas | `ShaderPostFx.bloom` | `bloom`, `bloomThreshold` (luminance 0..1), `bloomRadius` (px) |
| Colour fringing | `ShaderPostFx.chromaticAberration` | pixels of red/blue split at the screen edge |
| Big pixels | `ShaderPostFx.pixelSize` | pixels per big pixel; 0 is off |
| CRT screen | `ShaderPostFx.curvature`, `phosphorMask`, `scanlines` | 0 flat; presets `ShaderPostFx.crt()` and `bloomOnly()` |
| Film grain | `ShaderPostFx.grain` | animated noise amplitude |

A `ShaderPostFx` with every field at its default is the identity: `ShaderPostProcessed` then shows its child
unchanged and never takes a snapshot.

## Measurements

The cost of an effect is not the effect. It is the snapshot.

!!! warning "These benchmarks are web only"
    Every figure below was measured in **Chrome on a Mac, on the web**. None of it was measured on a phone or tablet, and
    mobile GPUs, Impeller and thermal throttling can change both the absolute numbers and the ratios. Device
    measurements (an Android phone and an iPhone) are still to do; until they are added, treat the numbers as a guide to
    what scales (pixels, not effects), not as a promise for your target device.

**Setup.** Chrome on an Apple M1 Pro (Metal), a 1512x862 window at 2x device pixel ratio (3024x1724 px), a
`flutter build web --profile` build, 400 random sprites. Each preset ran for 4 s after a 1.5 s warm-up; the figures are
the average of `FrameTiming.totalSpan`. Raw numbers: [`docs/data/postfx-benchmark.json`](../data/postfx-benchmark.json).

![Frame time by preset, before and after the pixel cap](../img/postfx-frame-time.svg)

| Preset | Before (5.2 MP snapshot) | After (capped to 1.6 MP) | p95 after |
|---|---:|---:|---:|
| off | 3.0 ms | 3.1 ms | 4.5 ms |
| grade | 3.2 ms | 3.6 ms | 4.9 ms |
| vignette + scanlines | 3.0 ms | 3.6 ms | 5.0 ms |
| bloom | 36.0 ms | 13.8 ms | 15.1 ms |
| chromatic aberration | 35.3 ms | 12.0 ms | 12.9 ms |
| pixelate | 35.1 ms | 12.3 ms | 13.6 ms |
| CRT | 35.2 ms | 13.8 ms | 15.9 ms |
| CRT at 0.5x | 11.9 ms | 12.1 ms | 14.0 ms |
| everything on | 36.0 ms | 14.5 ms | 17.4 ms |

What the numbers say:

- **Grade, vignette and scanlines are free.** Within a few tenths of a millisecond of no effect at all.
- **Every shader preset costs the same.** Bloom (a 16-tap blur), a three-tap chromatic split and a single-tap pixelate
  all land within about 1.5 ms of each other, and "everything on" is only 1 to 2 ms above the cheapest. The fragment
  shader is not the bottleneck; stacking effects in one `ShaderPostFx` is essentially free.
- **The snapshot is the cost, and it grows with pixels.**

![Extra milliseconds per frame against snapshot megapixels](../img/postfx-cost-vs-pixels.svg)

  Roughly 6 ms per megapixel here. On a 2x display a full-resolution snapshot is 5.2 MP, about 32 ms: more than a
  frame at 30 fps. That is why `ShaderPostProcessed` now caps the snapshot to `maxPixels` (1.6 MP by default), which
  cut the shader presets from about 35 ms to about 13 ms. The cap only ever lowers the resolution: a screen already
  under budget is untouched, and `maxPixels: 0` turns the cap off.
- **`scale` and the cap do the same job.** `scale: 0.5` at 2x is already 1.3 MP, so it measured the same as the cap.

**Read these as relative.** One machine, a window the browser ran at about 30 Hz (so frame time is reported, not fps),
two runs on a quiet machine. Runs taken while the machine was busy swung from 3 ms to 190 ms for the same preset and
were thrown away. Phones will differ: measure on the devices you ship to (see
[Reproduce it](#try-it-yourself-random-assets-in-the-browser)). The Flutter web raster time is not reported reliably, so
the figures are whole-frame spans.

**Two traps found while measuring**

- A hidden or backgrounded browser tab runs `requestAnimationFrame` at about 1 Hz or not at all, so benchmarks from a
  hidden pane show every preset as unusably slow. Measure in a visible, focused window.
- After rebuilding a Flutter web app, the old build can keep loading from its service worker. Unregister it (or use a
  fresh profile) before trusting a before/after comparison; ours first reported no change from a fix that worked.

## Tuning

| Goal | Do |
|---|---|
| Cheapest possible look | `PostProcessed` only: grade, vignette, scanlines |
| A CRT or bloom on a phone | Leave `maxPixels` at its default, or lower it (`1e6`) on slow devices |
| Crisp bloom on a desktop | `maxPixels: 0` (no cap) and accept the snapshot cost, or `scale: 1` with a lower DPR |
| Effects only sometimes | Set `game.postFx.value` back to `const ShaderPostFx()`: the identity takes no snapshot |
| Settings toggle | Store a bool and map it to `ShaderPostFx.crt()` or the identity |

## Recipes

**A hit flash.** Fringe and darken the edges for a moment, then clear it:

```dart
Future<void> flashOnHit(Game game) async {
  game.postFx.value = const ShaderPostFx(chromaticAberration: 6, vignette: 0.55);
  await Future<void>.delayed(const Duration(milliseconds: 120));
  game.postFx.value = const ShaderPostFx(); // identity: no snapshot, no cost
}
```

**Low health.** Let the vignette grow as health falls (call it from a system or a listener, not every frame if health
did not change):

```dart
void showDanger(Game game, double health01) {
  final danger = (1 - health01).clamp(0.0, 1.0);
  game.postFx.value = danger < 0.3
      ? const ShaderPostFx()
      : ShaderPostFx(vignette: 0.15 + danger * 0.55, grain: danger * 0.05);
}
```

**Underwater or night.** A grade needs no shader at all:

```dart
PostProcessed(
  effects: const [
    ColorGrade(saturation: 0.7, brightness: 0.85, tint: Color(0xFF8CC8FF)),
    Vignette(strength: 0.5),
  ],
  child: GameRunner(game: game),
)
```

**A retro-mode setting.** One flag, two looks:

```dart
void applyRetro(Game game, bool on) =>
    game.postFx.value = on ? const ShaderPostFx.crt() : const ShaderPostFx();
```

**A per-scene look.** Set `game.postFx.value` when a scene starts (a boss arena in CRT green, a menu with none) and set
it back when you leave. Scenes never touch the renderer; they only set data.

**Respect accessibility.** Grain, scanlines and chromatic aberration are motion and contrast noise; skip them when the
player turned on reduced motion or high contrast (see [Settings](settings.md)).

## Try it yourself: random assets in the browser

The screenshots and the numbers on this page come from a small local app (kept out of the repository, like every sample
app) that draws random procedural sprites, so there is nothing to download. Its core, about 60 lines:

```dart
class DemoScene extends Scene {
  @override
  Future<AtlasRegistry> loadAssets() async {
    final r = math.Random(7); // change the seed for a new set of assets
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final rects = <String, Rect>{};
    for (var i = 0; i < 16; i++) {
      final cx = (i % 4) * 32.0 + 16, cy = (i ~/ 4) * 32.0 + 16;
      rects['r$i'] = Rect.fromLTWH((i % 4) * 32.0, (i ~/ 4) * 32.0, 32, 32);
      final hue = r.nextDouble() * 360;
      final base = HSVColor.fromAHSV(1, hue, .8, .9).toColor();
      final spikes = 3 + r.nextInt(5);
      final path = Path();
      for (var k = 0; k < spikes * 2; k++) {
        final a = k * math.pi / spikes, rad = k.isEven ? 12.0 : 6.0;
        final p = Offset(cx + math.cos(a) * rad, cy + math.sin(a) * rad);
        k == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      c.drawPath(path..close(), Paint()..color = base);
    }
    final img = await rec.endRecording().toImage(128, 128);
    return AtlasRegistry()..register('rnd', SpriteAtlas(img, rects));
  }

  @override
  Future<void> populate(World world, SceneController scenes, GameState state) async {
    world.addSystem(MovementSystem());
    final r = math.Random(7);
    for (var i = 0; i < 400; i++) {
      final e = world.spawn();
      world.componentsOf<Position>().set(e, Position(r.nextDouble() * 360, r.nextDouble() * 640));
      world.componentsOf<Velocity>().set(e, Velocity((r.nextDouble() - .5) * 60, (r.nextDouble() - .5) * 60));
      world.componentsOf<Sprite>().set(e, Sprite('rnd', 'r${r.nextInt(16)}', rotation: r.nextDouble() * 6.28));
    }
  }
}
```

Wrap it the way the benchmark did, then switch `fx` from a chip row or a query parameter:

```dart
final fx = ValueNotifier<ShaderPostFx>(const ShaderPostFx.crt());
runApp(MaterialApp(
  home: ValueListenableBuilder<ShaderPostFx>(
    valueListenable: fx,
    builder: (_, value, _) => ShaderPostProcessed(
      fx: value,
      child: GameRunner(game: DemoGame()),
    ),
  ),
));
```

**To measure on your own device**, add a timings callback and average it over a few seconds per preset:

```dart
SchedulerBinding.instance.addTimingsCallback((timings) {
  for (final t in timings) {
    samples.add(t.totalSpan.inMicroseconds / 1000); // ms
  }
});
```

Build with `flutter build web --profile` (or run a profile build on the phone), keep the window visible and focused,
and throw away any run where the no-effect preset is not steady.

## Limits and what is next

- **The snapshot is the whole cost.** On Impeller platforms (iOS, Android) `ImageFilter.shader` could run the same
  shader with no snapshot at all; that path is not built yet. See [TODO](https://github.com/arashrasoulzadeh/zarvan/blob/main/TODO.md).
- **One frame behind.** The overlay shows the previous frame's snapshot. For a CRT or bloom this is invisible; do not
  use it for a hit flash that must land on the exact frame (use `PostProcessed`, or accept 16 ms).
- **No depth of field, motion blur or distortion yet** (shockwaves, heat haze).
- **Web.** Measured and tested on the CanvasKit renderer only; the older HTML renderer has no fragment shaders.
- **Not yet measured on devices.** See the warning above.

See also: [Rendering](rendering.md), [Settings and accessibility](settings.md), [Performance](performance.md).
