import 'dart:async' show FutureOr;

import 'package:engine_core/engine_core.dart';
import 'package:flutter/services.dart' show AssetBundle;

import '../rendering/sprite_atlas.dart';
import 'level_asset.dart';
import 'scene.dart';

/// A [Scene] that is a level file plus whatever code the level cannot say:
/// the common case written as data instead of a class per room.
///
/// ```dart
/// LevelScene(
///   asset: 'assets/levels/1.json',
///   follow: 'player',
///   setup: (world, named, scenes, state) {
///     world.addSystem(MySystem(named['player']!));
///   },
/// )
/// ```
///
/// Level entities load first (so `setup` can find them), then [setup] adds
/// systems and wires the level to the game. Sprite atlases come from
/// [atlases], when the level uses sprites.
class LevelScene extends Scene {
  LevelScene({
    required this.asset,
    this.setup,
    this.follow,
    this.atlases,
    this.strict = false,
    this.prefabs,
    this.defaults = false,
    this.bundle,
  });

  /// The level JSON asset, e.g. `assets/levels/1.json`.
  final String asset;

  /// Runs after the level loads, with the named entities.
  final FutureOr<void> Function(
    World world,
    Map<String, EntityId> named,
    SceneController scenes,
    GameState state,
  )?
  setup;

  /// The name (a level entity's `name`) the camera follows; null for a static camera.
  final String? follow;

  /// Loads the sprite atlases; null for a scene without sprites.
  final Future<AtlasRegistry> Function()? atlases;

  /// Reject unknown or malformed components instead of skipping them
  /// ([Level.loadInto]'s `strict`).
  final bool strict;

  /// Expands `prefabRef` placeholders ([Level.loadInto]'s `prefabs`).
  final PrefabRegistry? prefabs;

  /// Fills schema defaults for fields the level omits ([Level.loadInto]'s `defaults`).
  final bool defaults;

  /// Where to read [asset] from; the app's bundle when null.
  final AssetBundle? bundle;

  @override
  Future<void> populate(
    World world,
    SceneController scenes,
    GameState state,
  ) async {
    final json = await LevelAsset.read(asset, bundle: bundle);
    final named = Level.loadInto(
      world,
      json,
      strict: strict,
      prefabs: prefabs,
      defaults: defaults,
    );
    await setup?.call(world, named, scenes, state);
  }

  @override
  Future<AtlasRegistry> loadAssets() => atlases?.call() ?? super.loadAssets();

  @override
  EntityId? cameraFollowEntity(World world) {
    final name = follow;
    return name == null ? null : world.find(name);
  }
}
