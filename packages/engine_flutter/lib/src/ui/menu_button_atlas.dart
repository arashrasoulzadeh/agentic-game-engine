import 'dart:ui' as ui;

import 'package:engine_core/engine_core.dart';
import 'package:flutter/painting.dart';

import '../components/sprite.dart';
import '../sprite_atlas.dart';

/// Layout every engine-generated menu button shares — both
/// `buildMenuButtonAtlas` (what's drawn) and `spawnMenuButton` (the
/// `Collider` sized to match it) read these, so the two can't silently
/// drift apart. A game that wants different sizing builds its own atlas
/// with `buildMenuButtonAtlas`'s pattern instead of overriding these.
const kMenuButtonWidth = 220.0;
const kMenuButtonHeight = 64.0;
const kMenuButtonAtlasId = 'engineMenuButtons';

/// Builds one atlas region per label in [labels] — a rounded rect with
/// centered text, generated at runtime so a menu needs no bundled image
/// asset. Regions are keyed by label, one per row in the source image,
/// so `spawnMenuButton(label: "PLAY")` and this atlas's `"PLAY"` region
/// always refer to the same button. [backgroundColor]/[textColor] are
/// the one thing most games *do* want to customize per-menu (a title
/// screen's button vs. a "danger" quit button, say); everything else
/// about the button (size, corner radius, font size) stays fixed so
/// every engine-generated button in a game looks consistent by default.
Future<SpriteAtlas> buildMenuButtonAtlas(
  List<String> labels, {
  Color backgroundColor = const Color(0xFF3A6EA5),
  Color textColor = const Color(0xFFFFFFFF),
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final regions = <String, Rect>{};

  for (var i = 0; i < labels.length; i++) {
    final rect = Rect.fromLTWH(0, i * kMenuButtonHeight, kMenuButtonWidth, kMenuButtonHeight);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(4), const Radius.circular(10)),
      Paint()..color = backgroundColor,
    );
    final painter = TextPainter(
      text: TextSpan(
        text: labels[i],
        style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(rect.left + (kMenuButtonWidth - painter.width) / 2, rect.top + (kMenuButtonHeight - painter.height) / 2),
    );
    regions[labels[i]] = rect;
  }

  final image = await recorder
      .endRecording()
      .toImage(kMenuButtonWidth.toInt(), (kMenuButtonHeight * labels.length).toInt());
  return SpriteAtlas(image, regions);
}

/// Spawns one `Position`/`Collider`/`Sprite`/`Button` entity — the
/// engine's canonical "tappable menu button" shape, sized to match
/// `buildMenuButtonAtlas`'s [kMenuButtonWidth]/[kMenuButtonHeight] so a
/// button's hit area (circular — see `hitTestButton`) sits within its
/// drawn rounded rect rather than spilling past the corners. [label]
/// must match a region name in the atlas registered under
/// [kMenuButtonAtlasId] (`buildMenuButtonAtlas([label, ...])`).
/// [actionId] is what a `Scene.handleTap`/`ButtonMenuScene.onButtonPressed`
/// reads back via `Button.actionId` — free-form, chosen by the game.
EntityId spawnMenuButton(
  World world, {
  required Offset position,
  required String label,
  required String actionId,
}) {
  final id = world.spawn();
  world.storeOf<Position>().set(id, Position(position.dx, position.dy));
  world.storeOf<Collider>().set(id, Collider(kMenuButtonHeight / 2));
  world.storeOf<Sprite>().set(id, Sprite(kMenuButtonAtlasId, label));
  world.storeOf<Button>().set(id, Button(actionId));
  return id;
}
