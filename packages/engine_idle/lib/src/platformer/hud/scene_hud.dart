import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart'
    as eng
    show Text, TextAlignment;

/// Screen-space labels for a portrait idle-combat scene: a status line, the
/// current enemy's name, and a footer blurb. Positions assume the 180×320
/// logical canvas the idle-combat games use.
class SceneHud {
  SceneHud._(this._status, this._enemy);

  final EntityId _status;
  final EntityId _enemy;

  factory SceneHud.spawn(
    World world, {
    required String status,
    String blurb = '',
  }) {
    final s = _text(world, 90, 14, status, 11, 0xFFFFE7A0, 170);
    _text(world, 90, 300, blurb, 7, 0xFFC8C0A8, 168);
    final e = _text(world, 90, 44, '', 9, 0xFFFFCCBC, 170);
    return SceneHud._(s, e);
  }

  void sync(World world, {required String status, required String enemy}) {
    world.storeOf<eng.Text>().get(_status)?.text = status;
    world.storeOf<eng.Text>().get(_enemy)?.text = enemy;
  }

  static EntityId _text(
    World world,
    double x,
    double y,
    String text,
    double size,
    int color,
    double maxWidth,
  ) {
    final id = world.spawn();
    world.storeOf<Position>().set(id, Position(x, y));
    world.storeOf<eng.Text>().set(
      id,
      eng.Text(
        text,
        fontSize: size,
        colorArgb: color,
        align: eng.TextAlignment.center,
        screenSpace: true,
        zIndex: 110,
        maxWidth: maxWidth,
      ),
    );
    return id;
  }
}
