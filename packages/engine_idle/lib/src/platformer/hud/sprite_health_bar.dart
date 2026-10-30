import 'dart:ui' show Rect;

import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;
import 'package:engine_platformer/engine_platformer.dart';

/// Regions of the generated `ui_bars` sheet (ornate frame + coloured fills),
/// in the sheet's own pixels.
///
/// The frame is trimmed to its drawn pixels; [innerLeft]/[innerTop]/
/// [innerWidth]/[innerHeight] are the dark opening the fill sits in, relative
/// to the frame's top-left. A different bar sheet needs its own numbers.
class BarsArt {
  const BarsArt._();

  static const frame = Rect.fromLTWH(6, 11, 107, 23);
  static const fillSize = (w: 87.0, h: 10.0);
  static const innerLeft = 19.0;
  static const innerTop = 6.0;
  static const innerWidth = 69.0;
  static const innerHeight = 11.0;

  /// Fill regions by colour (red `hp`, cyan `xp`, orange `boss`).
  static const fills = ['hp', 'xp', 'boss'];

  /// The atlas for `<stem>.png`: regions `frame` and `fill_hp` / `fill_xp` /
  /// `fill_boss`.
  static Future<SpriteAtlas> load(String stem) async {
    final sheet = await SpriteAtlas.loadFullImageFromAssets('$stem.png');
    return SpriteAtlas(sheet.image, {
      'frame': frame,
      for (var row = 0; row < fills.length; row++)
        'fill_${fills[row]}': Rect.fromLTWH(
          132,
          row * 34.0 + 24,
          fillSize.w,
          fillSize.h,
        ),
    });
  }
}

/// A health bar drawn with the generated ornate frame and a fill sprite that
/// shrinks with the source's `Health`. World units; [left]/[top] is the
/// frame's top-left, [width] its width.
class SpriteHealthBar {
  SpriteHealthBar._(
    this._world,
    this._source,
    this._frame,
    this._fill,
    this._s,
  );

  final World _world;
  final EntityId _source;
  final EntityId _frame;
  final EntityId _fill;
  final double _s;
  double _left = 0;
  double _top = 0;

  factory SpriteHealthBar.spawn(
    World world, {
    required String atlasId,
    required EntityId source,
    required double left,
    required double top,
    required double width,
    String fill = 'hp',
    int zIndex = 100,
  }) {
    final s = width / BarsArt.frame.width;
    final frame = world.spawn();
    world.storeOf<Position>().set(
      frame,
      Position(left + width / 2, top + BarsArt.frame.height * s / 2),
    );
    world.storeOf<Sprite>().set(
      frame,
      Sprite(atlasId, 'frame', scaleX: s, scaleY: s, zIndex: zIndex),
    );
    final fillEntity = world.spawn();
    world.storeOf<Position>().set(fillEntity, Position(left, top));
    world.storeOf<Sprite>().set(
      fillEntity,
      Sprite(atlasId, 'fill_$fill', scaleX: 0, scaleY: s, zIndex: zIndex + 1),
    );
    return SpriteHealthBar._(world, source, frame, fillEntity, s)
      .._left = left
      .._top = top
      ..sync();
  }

  /// Recolours the fill (e.g. `boss` for the boss encounter).
  void setFill(String fill) {
    _world.storeOf<Sprite>().get(_fill)?.region = 'fill_$fill';
  }

  /// Resizes the fill to the source's current health.
  void sync() {
    final hp = _world.storeOf<Health>().get(_source);
    final fraction = hp == null || hp.max <= 0
        ? 0.0
        : (hp.current / hp.max).clamp(0.0, 1.0);
    final fillW = BarsArt.innerWidth * _s * fraction;
    _world.storeOf<Position>().get(_fill)
      ?..x = _left + BarsArt.innerLeft * _s + fillW / 2
      ..y = _top + (BarsArt.innerTop + BarsArt.innerHeight / 2) * _s;
    _world.storeOf<Sprite>().get(_fill)
      ?..scaleX = fillW / BarsArt.fillSize.w
      ..scaleY = BarsArt.innerHeight * _s / BarsArt.fillSize.h;
  }

  void destroy() {
    _world.destroy(_frame);
    _world.destroy(_fill);
  }
}
