import 'dart:ui' show Offset, Rect;

import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_flutter/zarvan_flutter.dart'
    as eng
    show Sprite, SpriteAtlas, Text;

import '../progress/hero_progress.dart';
import '../progress/hero_skill.dart';
import 'wave_strings.dart';
import 'world_text.dart';

/// Where the upgrade buttons and the retry button sit (world units).
class UpgradeLayout {
  const UpgradeLayout({
    this.y = 296,
    this.left = 18,
    this.right = 162,
    this.buttonWidth = 44,
    this.coinsY = 64,
    this.skillY = 262,
    this.retryX = 90,
    this.retryY = 196,
    this.retryWidth = 70,
  });

  /// Centre line of the upgrade buttons, and the span they spread across.
  final double y;
  final double left;
  final double right;
  final double buttonWidth;

  /// Where the coin counter is drawn, and the centre line of the skill row.
  final double coinsY;
  final double skillY;

  /// The retry button's centre and width.
  final double retryX;
  final double retryY;
  final double retryWidth;
}

/// The `ui_button_atlas` sheet: cells of [cellWidth] x [cellHeight] with
/// [gap] between them; one row per style, the first column is the normal state.
class ButtonSheet {
  const ButtonSheet._();

  static const cellWidth = 96.0;
  static const cellHeight = 44.0;
  static const gap = 4.0;

  /// Row names in sheet order.
  static const styles = ['primary', 'secondary', 'disabled'];

  /// Region rectangles by style name (normal state).
  static Map<String, Rect> regions() => {
    for (var row = 0; row < styles.length; row++)
      styles[row]: Rect.fromLTWH(gap, row * cellHeight, cellWidth, cellHeight),
  };
}

/// The in-world upgrade buttons, the coin counter and the retry button of a
/// wave-combat scene. Buttons are ordinary entities (a sprite and two labels);
/// [hit] maps a tap to what it pressed.
class UpgradeBar {
  UpgradeBar.spawn(
    World world, {
    required this.atlasId,
    required this.upgrades,
    required this.progress,
    this.layout = const UpgradeLayout(),
    this.skills = const [],
    this.strings = const WaveStrings(),
  }) {
    final span = layout.right - layout.left;
    for (var i = 0; i < upgrades.length; i++) {
      final cx = layout.left + span * (i + 0.5) / upgrades.length;
      _buttons.add(_spawnButton(world, cx, layout.y, layout.buttonWidth));
    }
    for (var i = 0; i < skills.length; i++) {
      final cx = layout.left + span * (i + 0.5) / skills.length;
      _skillButtons.add(
        _spawnButton(world, cx, layout.skillY, layout.buttonWidth),
      );
    }
    _coins = _text(world, 90, layout.coinsY, 5.2, 0xFFFFE7A0);
    sync(world);
  }

  static const _sprite = 120;
  static const _label = 125;

  final String atlasId;
  final List<HeroUpgrade> upgrades;
  final HeroProgress progress;
  final UpgradeLayout layout;

  /// Active skills drawn as a second row of buttons above the upgrades.
  final List<HeroSkill> skills;
  final WaveStrings strings;

  final _buttons = <_Button>[];
  final _skillButtons = <_Button>[];
  _Button? _ascend;
  late final EntityId _coins;
  _Button? _retry;

  /// What [hit] returns for the retry and ascend buttons, and the prefix of a
  /// skill's id.
  static const retryAction = 'retry';
  static const ascendAction = 'ascend';
  static const skillPrefix = 'skill:';

  _Button _spawnButton(
    World world,
    double cx,
    double cy,
    double width, {
    double fontScale = 1,
  }) {
    final scale = width / ButtonSheet.cellWidth;
    final sprite = world.spawn();
    world.componentsOf<Position>().set(sprite, Position(cx, cy));
    world.componentsOf<eng.Sprite>().set(
      sprite,
      eng.Sprite(
        atlasId,
        'primary',
        scaleX: scale,
        scaleY: scale,
        zIndex: _sprite,
      ),
    );
    final height = ButtonSheet.cellHeight * scale;
    return _Button(
      sprite,
      _text(world, cx, cy - height * 0.14, 4.6 * fontScale, 0xFFFFFFFF),
      _text(world, cx, cy + height * 0.16, 4.6 * fontScale, 0xFFFFE7A0),
      Rect.fromCenter(center: Offset(cx, cy), width: width, height: height),
    );
  }

  EntityId _text(World world, double x, double y, double size, int color) =>
      spawnWorldText(
        world,
        x,
        y,
        '',
        fontSize: size,
        colorArgb: color,
        zIndex: _label,
      );

  void _set(World world, _Button b, String region, String top, String bottom) {
    world.componentsOf<eng.Sprite>().get(b.sprite)?.region = region;
    world.componentsOf<eng.Text>().get(b.top)?.text = top;
    world.componentsOf<eng.Text>().get(b.bottom)?.text = bottom;
  }

  /// Refreshes labels and styles from [progress]: affordable upgrades look
  /// active, the rest disabled, a maxed one reads MAX.
  void sync(World world) {
    world.componentsOf<eng.Text>().get(_coins)?.text = strings.coinsLabel(
      progress.coins,
    );
    for (var i = 0; i < upgrades.length; i++) {
      final u = upgrades[i];
      final level = progress.levelOf(u);
      if (progress.isMaxed(u)) {
        _set(world, _buttons[i], 'secondary', '${u.label} $level', strings.max);
      } else {
        _set(
          world,
          _buttons[i],
          progress.canBuy(u) ? 'primary' : 'disabled',
          '${u.label} $level',
          '${progress.costOf(u)}',
        );
      }
    }
  }

  /// Refreshes the skill buttons: ready ones are active, those cooling down
  /// show the seconds left.
  void syncSkills(World world, SkillCooldowns cooldowns) {
    for (var i = 0; i < skills.length; i++) {
      final s = skills[i];
      final left = cooldowns.remaining(s);
      _set(
        world,
        _skillButtons[i],
        left > 0 ? 'disabled' : 'primary',
        s.label,
        left > 0 ? '${left.ceil()}s' : strings.ready,
      );
    }
  }

  /// Shows the ascend (prestige) button under the retry one (idempotent).
  void showAscend(World world, {String? label}) {
    if (_ascend != null) return;
    final b = _spawnButton(
      world,
      layout.retryX,
      layout.retryY + layout.retryWidth * 0.5,
      layout.retryWidth,
      fontScale: 1.5,
    );
    _ascend = b;
    _set(world, b, 'secondary', label ?? strings.ascend, '');
  }

  /// Shows the retry button (idempotent).
  void showRetry(World world, {String? label}) {
    if (_retry != null) return;
    final b = _spawnButton(
      world,
      layout.retryX,
      layout.retryY,
      layout.retryWidth,
      fontScale: 1.5,
    );
    _retry = b;
    world.componentsOf<eng.Text>().get(b.bottom)?.text = '';
    _set(world, b, 'primary', label ?? strings.retry, '');
  }

  bool get retryVisible => _retry != null;

  bool get ascendVisible => _ascend != null;

  /// What a tap at [worldPosition] pressed: an upgrade's `id`, [retryAction],
  /// or null for nothing.
  String? hit(Offset worldPosition) {
    final retry = _retry;
    if (retry != null && retry.rect.contains(worldPosition)) return retryAction;
    final ascend = _ascend;
    if (ascend != null && ascend.rect.contains(worldPosition)) {
      return ascendAction;
    }
    for (var i = 0; i < _skillButtons.length; i++) {
      if (_skillButtons[i].rect.contains(worldPosition)) {
        return '$skillPrefix${skills[i].id}';
      }
    }
    for (var i = 0; i < _buttons.length; i++) {
      if (_buttons[i].rect.contains(worldPosition)) return upgrades[i].id;
    }
    return null;
  }

  /// The atlas to register under [atlasId] for a loaded sheet image.
  static eng.SpriteAtlas atlasFor(eng.SpriteAtlas sheet) =>
      eng.SpriteAtlas(sheet.image, ButtonSheet.regions());
}

class _Button {
  _Button(this.sprite, this.top, this.bottom, this.rect);
  final EntityId sprite;
  final EntityId top;
  final EntityId bottom;
  final Rect rect;
}
