import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_flutter/zarvan_flutter.dart' hide Text;
import 'package:flutter/material.dart' hide Velocity;
import 'package:flutter_test/flutter_test.dart';

/// A shadow-casting light next to one solid tile. `cacheShadowGeometry`
/// leaves the per-ray distances on the light: the CPU raycast records a short
/// one for the ray that hits the tile, while a GPU light skips the raycast and
/// leaves every ray at the full radius.
Light2D _scene(World world, {Light2D? light, bool blocker = false}) {
  registerCoreComponents(world);
  registerFlutterComponents(world);
  final map = world.spawn();
  world.componentsOf<Position>().set(map, Position(0, 0));
  world.componentsOf<TileMap>().set(
    map,
    TileMap(
      cols: 5,
      rows: 5,
      tileWidth: 20,
      tileHeight: 20,
      tiles: [
        for (var r = 0; r < 5; r++)
          for (var c = 0; c < 5; c++) (c == 2 && r == 2) ? 1 : 0,
      ],
      solidTileIds: {1},
    ),
  );
  final e = world.spawn();
  world.componentsOf<Position>().set(e, Position(10, 50));
  final l =
      light ??
      Light2D(radius: 100, castsShadows: true, cacheShadowGeometry: true);
  world.componentsOf<Light2D>().set(e, l);
  if (blocker) {
    final b = world.spawn();
    world.componentsOf<Position>().set(b, Position(70, 50));
    world.componentsOf<Collider>().set(b, Collider(5, blocksLight: true));
  }
  return l;
}

bool _castCpuShadows(Light2D l) =>
    l.cachedShadowDistances!.any((d) => d < l.radius);

Future<void> _pump(WidgetTester tester, World world, {bool auto = true}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: EngineView(
        world: world,
        atlasRegistry: AtlasRegistry(),
        camera: Camera(),
        ambientBrightness: 0.3,
        autoGpuShadows: auto,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 16));
}

/// Loads the shader (real async), then renders again with a cleared cache.
Future<void> _settle(WidgetTester tester, Light2D light) async {
  await tester.runAsync(GpuLightShader.warmUp);
  light.cachedShadowDistances = null;
  await tester.pump(const Duration(milliseconds: 16));
  await tester.pump(const Duration(milliseconds: 16));
}

void main() {
  setUp(GpuLightShader.resetForTesting);

  testWidgets('a tile-only shadow light moves to the GPU once the shader is '
      'ready: the CPU raycast stops running', (tester) async {
    final world = World(width: 400, height: 300);
    final light = _scene(world);
    await _pump(tester, world);
    expect(_castCpuShadows(light), isTrue); // shader not ready: CPU
    await _settle(tester, light);
    expect(GpuLightShader.isReady, isTrue);
    expect(_castCpuShadows(light), isFalse);
  });

  testWidgets('autoGpuShadows: false keeps the CPU raycast', (tester) async {
    final world = World(width: 400, height: 300);
    final light = _scene(world);
    await _pump(tester, world, auto: false);
    await _settle(tester, light);
    expect(_castCpuShadows(light), isTrue);
  });

  testWidgets('a light-blocking collider keeps it on the CPU (the shader only '
      'knows tile edges)', (tester) async {
    final world = World(width: 400, height: 300);
    final light = _scene(world, blocker: true);
    await _pump(tester, world);
    await _settle(tester, light);
    expect(_castCpuShadows(light), isTrue);
  });

  testWidgets('CPU-only features (shadowSmoothingSeconds, openAirFalloffScale, '
      'one-way blocking) keep it on the CPU', (tester) async {
    for (final make in <Light2D Function()>[
      () => Light2D(
        radius: 100,
        castsShadows: true,
        cacheShadowGeometry: true,
        shadowSmoothingSeconds: 0.2,
      ),
      () => Light2D(
        radius: 100,
        castsShadows: true,
        cacheShadowGeometry: true,
        openAirFalloffScale: 0.5,
      ),
      () => Light2D(
        radius: 100,
        castsShadows: true,
        cacheShadowGeometry: true,
        blockOneWayPlatforms: true,
      ),
    ]) {
      final world = World(width: 400, height: 300);
      final light = _scene(world, light: make());
      await _pump(tester, world);
      await _settle(tester, light);
      expect(_castCpuShadows(light), isTrue);
    }
  });
}
