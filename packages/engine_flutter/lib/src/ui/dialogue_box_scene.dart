import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';

/// A ready-made dialogue box scene that renders a [DialogueRunner]'s
/// current node text and choices as vertically-stacked buttons.
/// Subclass to provide the runner and handle choice events.
abstract class DialogueBoxScene extends ButtonMenuScene {
  /// The [DialogueRunner] driving this dialogue. Must be set before
  /// `populate` is called (typically in the subclass's constructor or
  /// via `GameState`).
  late final DialogueRunner runner;

  /// The [StringTable] used to resolve text keys. Delegates to [runner.stringTable].
  StringTable get stringTable => runner.stringTable;

  /// Override to return a custom atlas/region for dialogue box background.
  /// Defaults to the engine's generated rounded-rect atlas.
  String? get dialogueBoxAtlasId => null;

  /// Override to return a custom atlas/region for dialogue box background.
  /// Defaults to the engine's generated rounded-rect atlas.
  String? get dialogueBoxRegion => null;

  /// Override to return a list of atlas IDs that this dialogue scene needs
  /// (for dialogue box background, portraits, etc.). These will be
  /// registered in the scene's [AtlasRegistry] returned by [loadAssets].
  /// The base scene's atlases are NOT automatically available to overlays;
  /// this scene must declare its own dependencies.
  List<String> get requiredAtlasIds => const [];

  // Internal reference to the world, set during populate
  World? _world;

  // Entity ID of the dialogue text, for updating during typewriter
  EntityId? textEntityId;

  // Entity ID of the portrait sprite, for updating when node changes
  EntityId? portraitEntityId;

  // The atlas registry for this scene (created in loadAssets)
  AtlasRegistry? _atlasRegistry;

  /// Called when the player selects a choice.
  /// By default, calls [runner.advance] and emits the choice's event.
  /// Override to add custom logic (e.g. playing a sound, updating quest state).
  void onChoiceSelected(
      DialogueChoice choice, World world, SceneController scenes) {
    runner.advance(world, _choiceIndex(choice));
    // If dialogue ended, typically pop this overlay or load next scene
    if (runner.currentNode == null) {
      scenes.popOverlay();
    }
  }

  /// Finds the index of [choice] in the current node's choices list.
  /// Returns -1 if not found (shouldn't happen for a valid choice).
  int _choiceIndex(DialogueChoice choice) {
    final node = runner.currentNode;
    if (node == null) return -1;
    return node.choices.indexOf(choice);
  }

  @override
  List<MenuButtonSpec> buttons() {
    final world = _world;
    if (world == null) return [];
    final choices = runner.availableChoices(WorldView(world));
    return choices.map((choice) {
      return MenuButtonSpec(
        label: stringTable.resolve(choice.textKey),
        actionId: choice.textKey, // use textKey as actionId; choice object matched in onButtonPressed
        labelFontSize: 18,
      );
    }).toList();
  }

  @override
  void onButtonPressed(String actionId, SceneController scenes) {
    final world = _world;
    if (world == null) return;
    final choices = runner.availableChoices(WorldView(world));
    DialogueChoice? choice;
    for (final c in choices) {
      if (c.textKey == actionId) {
        choice = c;
        break;
      }
    }
    if (choice != null) {
      onChoiceSelected(choice, world, scenes);
    }
  }

  @override
  Future<void> populate(World world, SceneController scenes, GameState state) async {
    _world = world;

    // Add dialogue box background if specified (screen-space, at bottom)
    if (dialogueBoxAtlasId != null && dialogueBoxRegion != null) {
      final atlas = _atlasRegistry?.resolve(dialogueBoxAtlasId!);
      if (atlas != null) {
        final region = atlas.regionFor(dialogueBoxRegion!);
        final bg = world.spawn();
        // Position at bottom center of screen
        final bgHeight = region.height * world.height / region.height * 0.4;
        final bgY = world.height - bgHeight / 2;
        world.storeOf<Position>().set(bg, Position(world.width / 2, bgY));
        // Scale to fit width with padding
        final scaleX = world.width / region.width * 0.85;
        final scaleY = bgHeight / region.height;
        world.storeOf<Sprite>().set(bg, Sprite(
          dialogueBoxAtlasId!,
          dialogueBoxRegion!,
          zIndex: -5,
          scaleX: scaleX,
          scaleY: scaleY,
          screenSpace: true,
        ));
      }
    }

    // Add dialogue text as a Text entity (screen-space, at bottom)
    textEntityId = world.spawn();
    final textY = world.height - 120; // Near bottom
    world.storeOf<Position>().set(textEntityId!, Position(world.width / 2, textY));
    world.storeOf<Text>().set(textEntityId!, Text(
      runner.visibleText(WorldView(world)) ?? '',
      colorArgb: 0xFFFFFFFF,
      fontSize: 22,
      align: TextAlignment.center,
      screenSpace: true,
    ));

    // Add portrait entity if specified
    await _addPortraitEntity(world);

    // Initialize typewriter
    runner.reset();

    await super.populate(world, scenes, state);
  }

  /// Loads each atlas declared by [requiredAtlasIds] from
  /// `assets/<id>.png` + `assets/<id>_manifest.json`.
  ///
  /// A missing atlas is logged and skipped rather than thrown: dialogue
  /// is content-driven, and a bad/missing portrait or background atlas
  /// ID (e.g. a typo in a hand-authored dialogue graph) shouldn't crash
  /// the whole scene — the sprite referencing it just won't render.
  @override
  Future<AtlasRegistry> loadAssets() async {
    _atlasRegistry = AtlasRegistry();

    for (final atlasId in requiredAtlasIds) {
      try {
        final atlas = await SpriteAtlas.loadFromAssets(
          imageAssetPath: 'assets/$atlasId.png',
          manifestAssetPath: 'assets/${atlasId}_manifest.json',
        );
        _atlasRegistry!.register(atlasId, atlas);
      } catch (e) {
        print('Warning: Failed to load dialogue atlas "$atlasId": $e');
      }
    }

    return _atlasRegistry!;
  }

  Future<EntityId?> _addPortraitEntity(World world) async {
    final node = runner.currentNode;
    if (node == null) return null;

    final portraitRegion = runner.getCurrentPortraitRegion();
    final portraitAtlasId = runner.getCurrentPortraitAtlasId();

    if (portraitRegion == null) return null;

    final atlasId = portraitAtlasId ?? 'atlas'; // fallback to default atlas

    // Just create the sprite with the atlas ID and region.
    // Resolution happens at render time via EngineView's AtlasRegistry.
    final portraitEntity = world.spawn();
    world.storeOf<Position>().set(portraitEntity, Position(100, 100)); // Top-left by default
    world.storeOf<Sprite>().set(portraitEntity, Sprite(
      atlasId,
      portraitRegion,
      zIndex: 10,
      scaleX: 0.5,
      scaleY: 0.5,
      screenSpace: true,
    ));

    return portraitEntity;
  }

  /// Updates the typewriter effect and refreshes the displayed text.
  /// Should be called once per frame while this scene is active.
  void update(double dt, World world) {
    final view = WorldView(world);
    final wasComplete = runner.isTypewriterComplete;
    runner.updateTypewriter(dt, view);
    
    // Update the text entity with the new visible text
    if (textEntityId != null) {
      final textStore = world.storeOf<Text>();
      final textComponent = textStore.get(textEntityId!);
      if (textComponent != null) {
        final newVisibleText = runner.visibleText(view) ?? '';
        if (textComponent.text != newVisibleText) {
          textStore.set(textEntityId!, Text(
            newVisibleText,
            colorArgb: textComponent.colorArgb,
            fontSize: textComponent.fontSize,
            align: textComponent.align,
          ));
        }
      }
      
      // Update portrait if node changed
      _updatePortraitIfNeeded(world);
    }
    
    // If typewriter just completed, the full text is now shown
    if (wasComplete != runner.isTypewriterComplete && runner.isTypewriterComplete) {
      // Typewriter just finished - full text is visible
    }
  }

  void _updatePortraitIfNeeded(World world) {
    final node = runner.currentNode;
    if (node == null) return;
    
    final portraitRegion = runner.getCurrentPortraitRegion();
    final portraitAtlasId = runner.getCurrentPortraitAtlasId();
    
    if (portraitRegion == null) {
      // No portrait for current node - remove existing
      if (portraitEntityId != null) {
        world.destroy(portraitEntityId!);
        portraitEntityId = null;
      }
      return;
    }
    
    final atlasId = portraitAtlasId ?? 'atlas';
    
    if (portraitEntityId == null) {
      // Create new portrait
      final portraitEntity = world.spawn();
      world.storeOf<Position>().set(portraitEntity, Position(100, 100));
      world.storeOf<Sprite>().set(portraitEntity, Sprite(
        atlasId,
        portraitRegion,
        zIndex: 10,
        scaleX: 0.5,
        scaleY: 0.5,
        screenSpace: true,
      ));
      portraitEntityId = portraitEntity;
    } else {
      // Update existing portrait
      final spriteStore = world.storeOf<Sprite>();
      final sprite = spriteStore.get(portraitEntityId!);
      if (sprite != null) {
        spriteStore.set(portraitEntityId!, Sprite(
          atlasId,
          portraitRegion,
          zIndex: 10,
          scaleX: 0.5,
          scaleY: 0.5,
          screenSpace: true,
        ));
}
    }
  }
}