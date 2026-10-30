import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart'
    as eng
    show Text, TextAlignment;

import 'hud_layout.dart';

/// Labels for a portrait idle-combat scene: a status line, the
/// current enemy's name. Where they sit comes from a [HudLayout]; the enemy's
/// description is a `DialogueCaption`.
class SceneHud {
  SceneHud._(this._status, this._enemy);

  final EntityId _status;
  final EntityId _enemy;

  factory SceneHud.spawn(
    World world, {
    required String status,
    HudLayout layout = const HudLayout(),
  }) => SceneHud._(
    _text(world, layout.status, status),
    _text(world, layout.enemy, ''),
  );

  void sync(World world, {required String status, required String enemy}) {
    world.storeOf<eng.Text>().get(_status)?.text = status;
    world.storeOf<eng.Text>().get(_enemy)?.text = enemy;
  }

  static EntityId _text(World world, HudTextStyle style, String text) {
    final id = world.spawn();
    world.storeOf<Position>().set(id, Position(style.x, style.y));
    world.storeOf<eng.Text>().set(
      id,
      eng.Text(
        text,
        fontSize: style.fontSize,
        colorArgb: style.colorArgb,
        align: eng.TextAlignment.center,
        screenSpace: false,
        zIndex: 110,
        maxWidth: style.maxWidth,
        rtl: style.rtl,
      ),
    );
    return id;
  }
}
