import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart'
    as eng
    show Text, TextAlignment;

import 'hud_layout.dart';

/// Screen-space labels for a portrait idle-combat scene: a status line, the
/// current enemy's name, and a short description of it. Where they sit comes from a [HudLayout].
class SceneHud {
  SceneHud._(this._status, this._enemy, this._description);

  final EntityId _status;
  final EntityId _enemy;
  final EntityId _description;

  factory SceneHud.spawn(
    World world, {
    required String status,
    HudLayout layout = const HudLayout(),
  }) => SceneHud._(
    _text(world, layout.status, status),
    _text(world, layout.enemy, ''),
    _text(world, layout.description, ''),
  );

  void sync(
    World world, {
    required String status,
    required String enemy,
    String description = '',
  }) {
    world.storeOf<eng.Text>().get(_status)?.text = status;
    world.storeOf<eng.Text>().get(_enemy)?.text = enemy;
    world.storeOf<eng.Text>().get(_description)?.text = description;
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
        screenSpace: true,
        zIndex: 110,
        maxWidth: style.maxWidth,
        rtl: style.rtl,
      ),
    );
    return id;
  }
}
