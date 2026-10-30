import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;

/// A progress path across the top of the screen: one node per encounter on a
/// line, drawn from the generated `ui_level_node` sheet (regions `0` locked,
/// `1` current, `2` cleared, `3` boss; 32px cells). World units.
class WavePath {
  WavePath._(this._world, this._nodes);

  final World _world;
  final List<EntityId> _nodes;

  /// The node sheet's cell size in pixels.
  static const _cell = 32.0;

  factory WavePath.spawn(
    World world, {
    required String nodesAtlasId,
    String? lineAtlasId,
    required int count,
    required double y,
    required double left,
    required double right,
    required double nodeSize,
    int zIndex = 100,
  }) {
    if (lineAtlasId != null) {
      final line = world.spawn();
      world.storeOf<Position>().set(line, Position((left + right) / 2, y));
      world.storeOf<Sprite>().set(
        line,
        Sprite(
          lineAtlasId,
          'full',
          // The 128x16 divider stretched across the whole path.
          scaleX: (right - left + nodeSize) / 128,
          scaleY: nodeSize * 0.7 / 16,
          zIndex: zIndex - 1,
        ),
      );
    }
    final nodes = <EntityId>[];
    for (var i = 0; i < count; i++) {
      final id = world.spawn();
      final x = count == 1
          ? (left + right) / 2
          : left + (right - left) * i / (count - 1);
      world.storeOf<Position>().set(id, Position(x, y));
      world.storeOf<Sprite>().set(
        id,
        Sprite(
          nodesAtlasId,
          '0',
          scaleX: nodeSize / _cell,
          scaleY: nodeSize / _cell,
          zIndex: zIndex,
        ),
      );
      nodes.add(id);
    }
    return WavePath._(world, nodes)..update(0, nodeSize);
  }

  /// Marks encounters before [current] cleared, [current] highlighted and the
  /// rest locked; the last node always shows the boss.
  void update(int current, double nodeSize) {
    final sprites = _world.storeOf<Sprite>();
    for (var i = 0; i < _nodes.length; i++) {
      final sprite = sprites.get(_nodes[i]);
      if (sprite == null) continue;
      final isBoss = i == _nodes.length - 1;
      sprite.region = i < current
          ? '2'
          : (i == current && !isBoss ? '1' : (isBoss ? '3' : '0'));
      // The current encounter is drawn a little larger.
      final k = (i == current ? 1.35 : 1.0) * nodeSize / _cell;
      sprite
        ..scaleX = k
        ..scaleY = k
        ..zIndex = i == current ? 102 : 100;
    }
  }
}
