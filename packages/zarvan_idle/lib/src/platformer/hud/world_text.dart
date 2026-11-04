import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_flutter/zarvan_flutter.dart'
    as eng
    show Text, TextAlignment;

/// Spawns a centred text entity at world position ([x], [y]).
///
/// World space on purpose: positions are world units and the text scales with
/// the camera, so a layout authored for a 180x320 world stays put at any
/// window size (screen-space text positions are raw pixels). Every HUD label,
/// button caption and floating number of a wave-combat scene goes through here.
EntityId spawnWorldText(
  World world,
  double x,
  double y,
  String text, {
  required double fontSize,
  required int colorArgb,
  required int zIndex,
  double? maxWidth,
  bool? rtl,
}) {
  final id = world.spawn();
  world.componentsOf<Position>().set(id, Position(x, y));
  world.componentsOf<eng.Text>().set(
    id,
    eng.Text(
      text,
      fontSize: fontSize,
      colorArgb: colorArgb,
      align: eng.TextAlignment.center,
      screenSpace: false,
      zIndex: zIndex,
      maxWidth: maxWidth,
      rtl: rtl,
    ),
  );
  return id;
}
