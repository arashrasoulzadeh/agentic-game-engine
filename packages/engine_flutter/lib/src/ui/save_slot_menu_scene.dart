import 'dart:ui' as ui;

import 'package:engine_core/engine_core.dart';

import '../logic/save_game.dart';
import '../logic/scene.dart';
import '../rendering/sprite.dart';
import '../rendering/sprite_atlas.dart';
import 'button_menu_scene.dart';
import 'menu_button_atlas.dart';

/// One save slot a `SaveSlotMenuScene` shows: which `SaveGame` slot id
/// it reads/writes, and the label to show when it holds a save (an
/// empty slot's label is derived from this — see
/// `SaveSlotMenuScene.slotLabel`).
class SaveSlotSpec {
  final String slot;
  final String label;
  const SaveSlotSpec({required this.slot, required this.label});
}

/// A ready-made save/load slot-picker menu, built on the existing
/// `SaveGame` (`hasSave`) — the "menu" analogue of what
/// `OnScreenControls` already is for touch input: give it a list of
/// slots and what selecting one should do, it handles checking which
/// slots already hold a save and showing that in each button's label.
///
/// Checks `SaveGame.hasSave` for every slot fresh each time this scene
/// is populated (e.g. a return trip to this menu reflects a save made
/// since it was last shown) — one reason this needs its own `populate`
/// override rather than just precomputed `buttons()`, since
/// `SaveGame.hasSave` is async and `ButtonMenuScene.buttons()` isn't.
///
/// Also shows each slot's `SaveGame`-stored thumbnail (see
/// `SaveGame.save`'s `thumbnail` parameter, typically captured via
/// `SceneController.captureScreenshot` right before saving) next to its
/// button, if one was saved — a slot saved without a thumbnail, or
/// still empty, just shows its button with no image, exactly like
/// before this existed.
abstract class SaveSlotMenuScene extends ButtonMenuScene {
  /// The slots this menu shows, top to bottom.
  List<SaveSlotSpec> slots();

  /// Called with the tapped slot's id and whether it currently holds a
  /// save (`SaveGame.hasSave`, checked when this scene was populated —
  /// not re-checked at tap time, so this always matches what the
  /// button's label showed). Typical implementations: load it and
  /// `scenes.loadScene(...)` when `hasSave` is true, or start a fresh
  /// game into that slot (`SaveGame.save`, then switch scenes) when
  /// it's false.
  void onSlotSelected(String slot, bool hasSave, SceneController scenes);

  /// How a slot's button label reflects whether it holds a save.
  /// Override to customize; defaults to appending "(empty)" for a slot
  /// with no save yet.
  String slotLabel(SaveSlotSpec spec, bool hasSave) =>
      hasSave ? spec.label : '${spec.label} (empty)';

  /// Width (world/screen-space units, matching `ButtonMenuScene`'s
  /// buttons) a slot's thumbnail is scaled to — height follows the
  /// saved screenshot's own aspect ratio. Override to size thumbnails
  /// differently.
  double get thumbnailWidth => 48;

  /// Horizontal gap between a button's left edge and its thumbnail's
  /// right edge.
  double get thumbnailGap => 12;

  Map<String, bool> _hasSaveBySlot = {};

  /// Decoded during [populate] (not [loadAssets], despite decoding
  /// otherwise belonging there) because [onButtonSpawned] needs each
  /// image's native size to scale it to [thumbnailWidth], and
  /// `ButtonMenuScene.populate` (which `super.populate` below calls
  /// into, spawning every button via [onButtonSpawned]) always runs
  /// before `loadAssets` ever does — see `GameRunner._load`.
  /// [loadAssets] just registers these already-decoded images.
  final Map<String, ui.Image> _thumbnailImageBySlot = {};

  @override
  Future<void> populate(World world, SceneController scenes, GameState state) async {
    final specs = slots();
    final hasSaveBySlot = <String, bool>{};
    for (final spec in specs) {
      hasSaveBySlot[spec.slot] = await SaveGame.hasSave(slot: spec.slot);
      final thumbnailBytes = await SaveGame.getThumbnail(slot: spec.slot);
      if (thumbnailBytes != null) {
        final codec = await ui.instantiateImageCodec(thumbnailBytes);
        final frame = await codec.getNextFrame();
        _thumbnailImageBySlot[spec.slot] = frame.image;
      }
    }
    _hasSaveBySlot = hasSaveBySlot;
    await super.populate(world, scenes, state);
  }

  @override
  List<MenuButtonSpec> buttons() => [
        for (final spec in slots())
          MenuButtonSpec(
            label: slotLabel(spec, _hasSaveBySlot[spec.slot] ?? false),
            actionId: spec.slot,
          ),
      ];

  @override
  void onButtonPressed(String actionId, SceneController scenes) {
    onSlotSelected(actionId, _hasSaveBySlot[actionId] ?? false, scenes);
  }

  @override
  Future<AtlasRegistry> loadAssets() async {
    final registry = await super.loadAssets();
    for (final entry in _thumbnailImageBySlot.entries) {
      final image = entry.value;
      registry.register(
        _thumbnailAtlasId(entry.key),
        SpriteAtlas(image, {
          'thumb': ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        }),
      );
    }
    return registry;
  }

  @override
  void onButtonSpawned(World world, MenuButtonSpec spec, int index, ui.Offset position) {
    final image = _thumbnailImageBySlot[spec.actionId];
    if (image == null) return;

    final scale = thumbnailWidth / image.width;
    final buttonWidth = spec.width ?? kMenuButtonWidth;
    final entity = world.spawn();
    world.storeOf<Position>().set(
          entity,
          Position(
            position.dx - buttonWidth / 2 - thumbnailGap - thumbnailWidth / 2,
            position.dy,
          ),
        );
    world.storeOf<Sprite>().set(
          entity,
          Sprite(_thumbnailAtlasId(spec.actionId), 'thumb', scaleX: scale, scaleY: scale),
        );
    trackExtraEntity(entity);
  }

  static String _thumbnailAtlasId(String slot) => 'save_slot_thumbnail_$slot';
}
