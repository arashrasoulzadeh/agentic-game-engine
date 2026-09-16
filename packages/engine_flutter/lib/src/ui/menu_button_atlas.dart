import 'dart:ui' as ui;

import 'package:engine_core/engine_core.dart';
import 'package:flutter/painting.dart';

import '../rendering/sprite.dart';
import '../rendering/sprite_atlas.dart';
import '../rendering/text.dart' as txt;

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

/// Spawns one `Position`/`Sprite`/`Button` entity plus a hit area — the
/// engine's canonical "tappable menu button" shape. By default (leave
/// [atlasId]/[region]/[width]/[height]/[scaleX]/[scaleY] `null`) draws
/// from [kMenuButtonAtlasId] at [label]'s region (i.e. a
/// `buildMenuButtonAtlas([label, ...])`-generated rect) sized to
/// [kMenuButtonWidth]/[kMenuButtonHeight], with a circular `Collider`
/// hit area — the original behavior, unchanged.
///
/// Pass [atlasId]/[region] to draw from real sprite-sheet art instead
/// (already registered in the scene's `AtlasRegistry`). [scaleX]/
/// [scaleY] (default `1`, i.e. native pixel size) scale that art the
/// same way any other `Sprite` does; [width]/[height] independently
/// size a `ButtonHitBox` (rectangular hit area — see its own doc
/// comment for why a rectangle over a circle) so the tappable area can
/// be told apart from the drawn size when they should differ (e.g. a
/// button whose art has transparent padding around a smaller visible
/// shape) — defaults to [kMenuButtonWidth]/[kMenuButtonHeight] if
/// omitted, a reasonable guess when the caller doesn't care to be
/// precise.
///
/// Real art (unlike [buildMenuButtonAtlas]'s generated rect) has no
/// way to know [label]'s text ahead of time, so this also spawns a
/// `Text` entity centered on the button showing [label] — skipped
/// when [label] is empty, for art that's already self-explanatory (an
/// icon-only button) or bakes its own text in. World-space, not
/// screen-space, matching the button's own `Sprite`/`Position` (both
/// go through `Camera.worldToScreen` identically), so the label stays
/// exactly centered on the button regardless of camera zoom/pan — a
/// screen-space label at the same raw `position` values would only
/// happen to line up by coincidence (default `Camera()` maps world
/// `(0,0)` to the viewport's own center, so world and "screen minus an
/// offset" aren't the same coordinate space in general).
/// [labelColorArgb]/[labelFontSize] style it; spawned *after* the
/// button's own `Sprite` entity, but that's not actually why it
/// layers on top — `EngineView` collects every `Text` after every
/// `Sprite` regardless of spawn order, so a same-`zIndex` `Text`
/// always draws over a same-`zIndex` `Sprite`.
///
/// [actionId] is what a `Scene.handleTap`/`ButtonMenuScene.onButtonPressed`
/// reads back via `Button.actionId` — free-form, chosen by the game.
EntityId spawnMenuButton(
  World world, {
  required Offset position,
  required String label,
  required String actionId,
  String? atlasId,
  String? region,
  double? width,
  double? height,
  double scaleX = 1,
  double scaleY = 1,
  int labelColorArgb = 0xFFFFFFFF,
  double labelFontSize = 20,
}) {
  final id = world.spawn();
  world.storeOf<Position>().set(id, Position(position.dx, position.dy));
  world.storeOf<Button>().set(id, Button(actionId));

  if (atlasId != null && region != null) {
    world.storeOf<ButtonHitBox>().set(
          id,
          ButtonHitBox(width ?? kMenuButtonWidth, height ?? kMenuButtonHeight),
        );
    world.storeOf<Sprite>().set(id, Sprite(atlasId, region, scaleX: scaleX, scaleY: scaleY));
    if (label.isNotEmpty) {
      final labelId = world.spawn();
      world.storeOf<Position>().set(labelId, Position(position.dx, position.dy));
      world.storeOf<txt.Text>().set(
            labelId,
            txt.Text(
              label,
              fontSize: labelFontSize,
              colorArgb: labelColorArgb,
            ),
          );
    }
  } else {
    world.storeOf<Collider>().set(id, Collider((height ?? kMenuButtonHeight) / 2));
    world.storeOf<Sprite>().set(id, Sprite(kMenuButtonAtlasId, label));
  }
  return id;
}
