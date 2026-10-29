import 'package:engine_core/engine_core.dart';

import 'parallax_layer.dart';

/// One scrolling background layer: atlas `<prefix>_<name>`, moved [speed]
/// times as fast as the ground (far scenery < 1, foreground > 1).
class ParallaxSpec {
  const ParallaxSpec(this.name, this.speed, {this.zIndex = -100});

  final String name;
  final double speed;
  final int zIndex;

  factory ParallaxSpec.fromJson(Map<String, dynamic> json) => ParallaxSpec(
    json['name'] as String,
    (json['speed'] as num).toDouble(),
    zIndex: (json['z'] as num?)?.toInt() ?? -100,
  );

  /// Atlas id a scene registers this layer's image under.
  String atlasId(String prefix) => '${prefix}_$name';
}

/// Spawns tiled [ParallaxLayer]s for a list of [ParallaxSpec]s and scrolls
/// them together: call [scroll] with the distance travelled and each layer
/// moves by its own speed.
///
/// Layers move through `Position`, not the camera, so a scene whose hero
/// stays put on screen (idle/auto-walk games) keeps its camera and HUD fixed.
class ParallaxScroller {
  ParallaxScroller._(this._layers);

  final List<({EntityId id, double speed})> _layers;

  factory ParallaxScroller.spawn(
    World world,
    String atlasPrefix,
    List<ParallaxSpec> specs,
  ) {
    final layers = <({EntityId id, double speed})>[];
    for (final spec in specs) {
      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(0, 0));
      world.storeOf<ParallaxLayer>().set(
        id,
        ParallaxLayer(
          spec.atlasId(atlasPrefix),
          'full',
          scrollFactorX: 0,
          scrollFactorY: 0,
          tileX: true,
          fitHeight: true,
          zIndex: spec.zIndex,
        ),
      );
      layers.add((id: id, speed: spec.speed));
    }
    return ParallaxScroller._(layers);
  }

  /// Moves every layer left by [distance] world units × its speed.
  void scroll(World world, double distance) {
    final pos = world.storeOf<Position>();
    for (final l in _layers) {
      final p = pos.get(l.id);
      if (p != null) p.x -= distance * l.speed;
    }
  }
}
