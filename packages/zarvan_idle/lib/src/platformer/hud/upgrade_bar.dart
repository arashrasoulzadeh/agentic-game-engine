import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_flutter/zarvan_flutter.dart'
    as eng
    show BackdropBlur, Sprite, SpriteAtlas, Text, TextAlignment;

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
    this.iconSize = 13,
    this.iconOnly = false,
    this.menu = false,
    this.menuX = 90,
    this.menuY = 308,
    this.menuWidth = 40,
    this.dialog = const Rect.fromLTRB(10, 70, 170, 250),
    this.frameCorner = 9,
    this.frameInset = 24,
    this.frameSource = const Size(96, 75),
    this.menuFontScale = 0.75,
    this.rowHeight = 28,
    this.rowButtonWidth = 34,
    this.blurSigma = 3,
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

  /// Width and height of a button's icon (world units).
  final double iconSize;

  /// Draws buttons that have an icon as the icon alone, centred, with at most
  /// a small number under it (cost, seconds left, charge). Words such as the
  /// label, `Ready` or `MAX` are left out so the row reads in any language.
  final bool iconOnly;

  /// Keeps the upgrade buttons out of sight behind one small menu button
  /// (drawn at [menuX], [menuY], [menuWidth] wide); tapping it opens or closes
  /// the panel of upgrades at [y]. Skills stay on screen in their own row.
  final bool menu;
  final double menuX;
  final double menuY;
  final double menuWidth;

  /// With [menu], the dialog's rectangle in world units. Every button (skills
  /// at [skillY], upgrades at [y]) sits inside it, under a title.
  final Rect dialog;

  /// Edge of the frame's corner pieces in world units, and the width in source
  /// pixels of the corner/edge border of the frame image (see
  /// [UpgradeBar.frameAtlasFor]).
  final double frameCorner;
  final double frameInset;

  /// Size in pixels of the frame image (`ui_panel_9slice` is 96 x 75). Part of
  /// the layout, not read from the loaded image, because a replayed scene
  /// reuses the loaded assets and never sees the image itself.
  final Size frameSource;

  /// Text scale of the buttons inside the dialog, which are narrower than the
  /// stand-alone ones.
  final double menuFontScale;

  /// In the dialog every upgrade is one row: icon, name with its level and a
  /// description, and a small buy button with the price. Rows start at [y] and
  /// are [rowHeight] apart; the button is [rowButtonWidth] wide.
  final double rowHeight;
  final double rowButtonWidth;

  /// Blur (world units) the game behind the dialog fades to while it is open;
  /// 0 leaves the game sharp under the veil.
  final double blurSigma;
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
    this.iconAtlasId,
    this.iconCellSize = 32,
    this.frameAtlasId,
    required this.upgrades,
    required this.progress,
    this.layout = const UpgradeLayout(),
    this.skills = const [],
    this.strings = const WaveStrings(),
  }) {
    final span = layout.right - layout.left;
    for (var i = 0; i < upgrades.length; i++) {
      if (layout.menu) {
        _buttons.add(_spawnRow(world, i));
        continue;
      }
      final cx = layout.left + span * (i + 0.5) / upgrades.length;
      _buttons.add(
        _spawnButton(
          world,
          cx,
          layout.y,
          layout.buttonWidth,
          icon: upgrades[i].icon,
          iconOnly: layout.iconOnly,
        ),
      );
    }
    for (var i = 0; i < skills.length; i++) {
      final cx = layout.left + span * (i + 0.5) / skills.length;
      _skillButtons.add(
        _spawnButton(
          world,
          cx,
          layout.skillY,
          layout.menu ? span / skills.length * 0.92 : layout.buttonWidth,
          icon: skills[i].icon,
          fontScale: layout.menu ? layout.menuFontScale : 1,
          iconOnly: !layout.menu && layout.iconOnly,
          lift: layout.menu ? _dialogLift : 0,
        ),
      );
    }
    _coins = _text(world, 90, layout.coinsY, 5.2, 0xFFFFE7A0);
    if (layout.menu && (upgrades.isNotEmpty || skills.isNotEmpty)) {
      final m = _spawnButton(
        world,
        layout.menuX,
        layout.menuY,
        layout.menuWidth,
        iconOnly: false,
      );
      _menu = m;
      world.componentsOf<eng.Text>().get(m.top)?.text = strings.upgradesMenu;
      world.componentsOf<eng.Text>().get(m.bottom)?.text = '';
      world.componentsOf<eng.Sprite>().get(m.sprite)?.region = 'secondary';
      _spawnDialogParts(world);
      _shown = true;
      _setShown(world, false);
      // The label is the only text, so it sits in the middle of the button.
      world.componentsOf<Position>().get(m.top)?.y = layout.menuY;
    }
    sync(world);
  }

  static const _sprite = 120;
  static const _label = 125;

  final String atlasId;

  /// Atlas of the icon strip (regions `0`, `1`, ...), or null for no icons.
  final String? iconAtlasId;

  /// Atlas of the dialog frame (see [frameAtlasFor]), or null for a plain
  /// dialog with no art.
  final String? frameAtlasId;

  /// Edge of one icon frame in the strip, in pixels.
  final double iconCellSize;
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
  _Button? _menu;
  final _dialogParts = <EntityId>[];
  bool _menuOpen = false;
  bool _shown = false;
  double _fade = 0;
  EntityId? _overlay;
  EntityId? _blur;
  final _rowTitles = <EntityId>[];
  static const _hidden = 3000.0;

  /// Draw-order boost of the dialog's contents, so it covers the captions and
  /// damage numbers of the fight behind it.
  static const _dialogLift = 40;

  /// What [hit] returns for the retry and ascend buttons, and the prefix of a
  /// skill's id.
  static const retryAction = 'retry';
  static const ascendAction = 'ascend';
  static const skillPrefix = 'skill:';

  /// What [hit] returns for the menu button (see [UpgradeLayout.menu]).
  static const menuAction = 'menu';

  /// One upgrade of the dialog: icon and text on the left, a small buy button
  /// with the price on the right; a tap anywhere on the row buys.
  _Button _spawnRow(World world, int i) {
    final u = upgrades[i];
    final r = layout.dialog;
    final y = layout.y + i * layout.rowHeight;
    final bw = layout.rowButtonWidth;
    final button = _spawnButton(
      world,
      r.right - 8 - bw / 2,
      y,
      bw,
      fontScale: layout.menuFontScale,
      iconOnly: false,
      lift: _dialogLift,
    );
    // Only the price is written, so it sits in the middle of the button.
    world.componentsOf<Position>().get(button.top)?.y = y;
    if (iconAtlasId != null && u.icon != null) {
      final icon = world.spawn();
      final scale = layout.iconSize / iconCellSize;
      world.componentsOf<Position>().set(icon, Position(r.left + 16, y));
      world.componentsOf<eng.Sprite>().set(
        icon,
        eng.Sprite(
          iconAtlasId!,
          '${u.icon}',
          scaleX: scale,
          scaleY: scale,
          zIndex: _label + _dialogLift,
        ),
      );
      _dialogParts.add(icon);
    }
    final textX = r.left + 30;
    final width = r.right - 8 - bw - 6 - textX;
    final title = _text(
      world,
      textX,
      y - 5,
      4.6,
      0xFF3A2410,
      lift: _dialogLift,
    );
    final desc = _text(world, textX, y + 4, 3.5, 0xFF6A5034, lift: _dialogLift);
    final texts = world.componentsOf<eng.Text>();
    for (final e in [title, desc]) {
      texts.get(e)
        ?..align = eng.TextAlignment.left
        ..maxWidth = width;
    }
    texts.get(desc)?.text = u.description ?? '';
    _rowTitles.add(title);
    _dialogParts.addAll([title, desc]);
    return _Button(
      button.sprite,
      button.top,
      button.bottom,
      Rect.fromLTRB(
        r.left + 4,
        y - layout.rowHeight / 2,
        r.right - 4,
        y + layout.rowHeight / 2,
      ),
    );
  }

  _Button _spawnButton(
    World world,
    double cx,
    double cy,
    double width, {
    double fontScale = 1,
    int? icon,
    bool? iconOnly,
    int lift = 0,
  }) {
    final scale = width / ButtonSheet.cellWidth;
    final hasIcon = icon != null && iconAtlasId != null;
    // Text moves right so the icon and the label share the button.
    final compact = hasIcon && (iconOnly ?? layout.iconOnly);
    final textX = hasIcon && !compact ? cx + width * 0.14 : cx;
    final sprite = world.spawn();
    world.componentsOf<Position>().set(sprite, Position(cx, cy));
    world.componentsOf<eng.Sprite>().set(
      sprite,
      eng.Sprite(
        atlasId,
        'primary',
        scaleX: scale,
        scaleY: scale,
        zIndex: _sprite + lift,
      ),
    );
    final height = ButtonSheet.cellHeight * scale;
    EntityId? iconSprite;
    if (hasIcon) {
      iconSprite = world.spawn();
      final s = layout.iconSize / iconCellSize;
      world.componentsOf<Position>().set(
        iconSprite,
        Position(
          compact ? cx : cx - width * 0.3,
          compact ? cy - height * 0.1 : cy,
        ),
      );
      world.componentsOf<eng.Sprite>().set(
        iconSprite,
        eng.Sprite(
          iconAtlasId!,
          '$icon',
          scaleX: s,
          scaleY: s,
          zIndex: _label + lift,
        ),
      );
    }
    return _Button(
      sprite,
      _text(
        world,
        textX,
        cy - height * 0.14,
        4.6 * fontScale,
        0xFFFFFFFF,
        lift: lift,
      ),
      _text(
        world,
        textX,
        compact ? cy + height * 0.3 : cy + height * 0.16,
        4.6 * fontScale,
        0xFFFFE7A0,
        lift: lift,
      ),
      Rect.fromCenter(center: Offset(cx, cy), width: width, height: height),
      icon: iconSprite,
      iconOnly: compact,
    );
  }

  EntityId _text(
    World world,
    double x,
    double y,
    double size,
    int color, {
    int lift = 0,
  }) => spawnWorldText(
    world,
    x,
    y,
    '',
    fontSize: size,
    colorArgb: color,
    zIndex: _label + lift,
  );

  void _set(World world, _Button b, String region, String top, String bottom) {
    world.componentsOf<eng.Sprite>().get(b.sprite)?.region = region;
    final iconOnly = b.iconOnly;
    world.componentsOf<eng.Text>().get(b.top)?.text = iconOnly ? '' : top;
    world.componentsOf<eng.Text>().get(b.bottom)?.text =
        iconOnly && !bottom.contains(RegExp(r'\d')) ? '' : bottom;
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
      if (layout.menu) {
        final b = _buttons[i];
        final texts = world.componentsOf<eng.Text>();
        texts.get(_rowTitles[i])?.text = '${u.label}  $level';
        texts.get(b.top)?.text = progress.isMaxed(u)
            ? strings.max
            : '${progress.costOf(u)}';
        texts.get(b.bottom)?.text = '';
        world
            .componentsOf<eng.Sprite>()
            .get(b.sprite)
            ?.region = progress.isMaxed(u)
            ? 'secondary'
            : progress.canBuy(u)
            ? 'primary'
            : 'disabled';
        continue;
      }
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
  void syncSkills(
    World world,
    SkillCooldowns cooldowns, {
    double ultimate = 0,
  }) {
    for (var i = 0; i < skills.length; i++) {
      final s = skills[i];
      if (s.ultimate) {
        // Charged by play, not by a timer: show the meter.
        final full = ultimate >= 1;
        _set(
          world,
          _skillButtons[i],
          full ? 'primary' : 'disabled',
          s.label,
          full ? strings.ready : '${(ultimate * 100).floor()}%',
        );
        continue;
      }
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
    final menu = _menu;
    if (menu != null && menu.rect.contains(worldPosition)) return menuAction;
    if (layout.menu && !_menuOpen) return null;
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

  /// Whether the dialog is showing (always true without a menu).
  bool get menuOpen => !layout.menu || _menuOpen;

  /// Whether a [UpgradeLayout.menu] dialog is open and should stop the game.
  bool get dialogOpen => layout.menu && _menuOpen;

  /// Opens or closes the dialog of a [UpgradeLayout.menu] bar. It fades in
  /// and out over [fadeSeconds]; call [update] every frame for that.
  void toggleMenu(World world) {
    if (_menu == null) return;
    _menuOpen = !_menuOpen;
    if (_menuOpen) _setShown(world, true);
  }

  /// How long the dialog and the veil behind it take to fade.
  static const fadeSeconds = 0.2;

  /// Moves the fade along (real time, so it runs while the game is paused).
  void update(World world, double dt) {
    if (_menu == null) return;
    final target = _menuOpen ? 1.0 : 0.0;
    if (_fade == target) return;
    final step = dt / fadeSeconds;
    _fade = target > _fade
        ? math.min(target, _fade + step)
        : math.max(target, _fade - step);
    _applyFade(world);
    if (_fade == 0) _setShown(world, false);
  }

  void _setShown(World world, bool shown) {
    if (shown == _shown) return;
    _shown = shown;
    _shiftDialog(world, shown ? -_hidden : _hidden);
  }

  void _applyFade(World world) {
    final a = (_fade * 255).round();
    final white = (a << 24) | 0xFFFFFF;
    final sprites = world.componentsOf<eng.Sprite>();
    final texts = world.componentsOf<eng.Text>();
    final tint = (_fade * 0.6 * 255).round() << 24 | 0x101828;
    world.componentsOf<eng.BackdropBlur>().get(_blur ?? -1)?.sigma =
        _fade * layout.blurSigma;
    for (final e in _dialogParts) {
      sprites.get(e)?.tintArgb = e == _overlay ? tint : white;
      final t = texts.get(e);
      if (t != null) t.colorArgb = (a << 24) | (t.colorArgb & 0xFFFFFF);
    }
    for (final b in [..._buttons, ..._skillButtons]) {
      sprites.get(b.sprite)?.tintArgb = white;
      if (b.icon != null) sprites.get(b.icon!)?.tintArgb = white;
      for (final e in [b.top, b.bottom]) {
        final t = texts.get(e);
        if (t != null) t.colorArgb = (a << 24) | (t.colorArgb & 0xFFFFFF);
      }
    }
  }

  void _spawnDialogParts(World world) {
    final r = layout.dialog;
    final atlas = frameAtlasId;
    if (atlas != null) {
      // A flat dark veil over the whole fight, taken from the frame's middle
      // piece and tinted, that fades in with the dialog.
      final src = layout.frameSource;
      final mid = src.width - 2 * layout.frameInset;
      final midH = src.height - 2 * layout.frameInset;
      final veil = world.spawn();
      world.componentsOf<Position>().set(veil, Position(90, 160));
      world.componentsOf<eng.Sprite>().set(
        veil,
        eng.Sprite(
          atlas,
          'f11',
          scaleX: 200 / mid,
          scaleY: 340 / midH,
          zIndex: _sprite + _dialogLift - 20,
          tintArgb: 0x00101828,
        ),
      );
      _overlay = veil;
      _dialogParts.add(veil);
      _blur = world.spawn();
      world.componentsOf<eng.BackdropBlur>().set(
        _blur!,
        eng.BackdropBlur(belowZIndex: _sprite + _dialogLift - 20),
      );
    }
    if (atlas != null) {
      final frameSize = layout.frameSource;
      final i = layout.frameInset;
      final c = layout.frameCorner;
      final srcX = [i, frameSize.width - 2 * i, i];
      final srcY = [i, frameSize.height - 2 * i, i];
      final dstX = [c, r.width - 2 * c, c];
      final dstY = [c, r.height - 2 * c, c];
      var y = r.top;
      for (var row = 0; row < 3; row++) {
        var x = r.left;
        for (var col = 0; col < 3; col++) {
          final e = world.spawn();
          world.componentsOf<Position>().set(
            e,
            Position(x + dstX[col] / 2, y + dstY[row] / 2),
          );
          world.componentsOf<eng.Sprite>().set(
            e,
            eng.Sprite(
              atlas,
              'f$row$col',
              scaleX: dstX[col] / srcX[col],
              scaleY: dstY[row] / srcY[row],
              zIndex: _sprite + _dialogLift - 10,
            ),
          );
          _dialogParts.add(e);
          x += dstX[col];
        }
        y += dstY[row];
      }
    }
    final title = _text(
      world,
      r.center.dx,
      r.top + 14,
      6.4,
      0xFF3A2410,
      lift: _dialogLift,
    );
    world.componentsOf<eng.Text>().get(title)?.text = strings.upgradesMenu;
    _dialogParts.add(title);
  }

  void _shiftDialog(World world, double dy) {
    final positions = world.componentsOf<Position>();
    final all = <EntityId>[
      ..._dialogParts,
      for (final b in [..._buttons, ..._skillButtons]) ...[
        b.sprite,
        b.top,
        b.bottom,
        ?b.icon,
      ],
    ];
    for (final e in all) {
      final p = positions.get(e);
      if (p != null) p.y += dy;
    }
  }

  /// The atlas to register under [frameAtlasId] for a loaded frame image: nine
  /// regions `f<row><col>` cut [inset] pixels in from each edge.
  static eng.SpriteAtlas frameAtlasFor(eng.SpriteAtlas full, double inset) {
    final w = full.image.width.toDouble();
    final h = full.image.height.toDouble();
    final xs = [0.0, inset, w - inset, w];
    final ys = [0.0, inset, h - inset, h];
    return eng.SpriteAtlas(full.image, {
      for (var r = 0; r < 3; r++)
        for (var c = 0; c < 3; c++)
          'f$r$c': Rect.fromLTRB(xs[c], ys[r], xs[c + 1], ys[r + 1]),
    });
  }

  /// The atlas to register under [atlasId] for a loaded sheet image.
  static eng.SpriteAtlas atlasFor(eng.SpriteAtlas sheet) =>
      eng.SpriteAtlas(sheet.image, ButtonSheet.regions());
}

class _Button {
  _Button(
    this.sprite,
    this.top,
    this.bottom,
    this.rect, {
    this.icon,
    this.iconOnly = false,
  });

  /// Whether only the icon (and a number) is drawn; see [UpgradeLayout.iconOnly].
  final bool iconOnly;
  final EntityId sprite;

  /// The icon sprite, if this button has one.
  final EntityId? icon;
  final EntityId top;
  final EntityId bottom;
  final Rect rect;
}
