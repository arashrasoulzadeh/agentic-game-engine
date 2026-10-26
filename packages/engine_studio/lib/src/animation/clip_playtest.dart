import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart'
    show
        AnimationClip,
        AnimationState,
        AnimationSystem,
        AtlasRegistry,
        Camera,
        EngineView,
        Sprite,
        registerFlutterComponents;
import 'package:flutter/material.dart' hide Velocity;

import '../prefs/strings.dart';
import '../textures/atlas_catalog.dart';

/// Minimal live [EngineView] playtest for one AnimationClip JSON map.
///
/// Spawns a single entity with `Sprite` + `AnimationState` and runs
/// `AnimationSystem` so frame advance, pivots, and `frameEvents` match
/// runtime — unlike [ClipPreview]'s static CustomPaint scrubber.
class ClipPlaytest extends StatefulWidget {
  final String projectRoot;
  final Map<String, dynamic> clip;
  final String atlasId;

  /// Bump to rebuild the world from the latest clip (e.g. after edits).
  final int revision;

  const ClipPlaytest({
    super.key,
    required this.projectRoot,
    required this.clip,
    required this.atlasId,
    this.revision = 0,
  });

  @override
  State<ClipPlaytest> createState() => _ClipPlaytestState();
}

class _ClipPlaytestState extends State<ClipPlaytest> {
  World? _world;
  AtlasRegistry? _registry;
  Camera? _camera;
  EntityId? _entity;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void didUpdateWidget(ClipPlaytest old) {
    super.didUpdateWidget(old);
    if (old.projectRoot != widget.projectRoot ||
        old.atlasId != widget.atlasId ||
        old.revision != widget.revision) {
      _boot();
    }
  }

  Future<void> _boot() async {
    _loading = true;
    _error = null;
    try {
      final atlases = await AtlasCatalog.read(widget.projectRoot).load(
        widget.projectRoot,
      );
      if (!mounted) return;
      final atlas = atlases[widget.atlasId];
      if (atlas == null) {
        setState(() {
          _loading = false;
          _error = StudioStrings.t(
            'clip.previewMissingAtlas',
            {'id': widget.atlasId},
          );
          _world = null;
        });
        return;
      }

      final clipMap = Map<String, dynamic>.from(widget.clip);
      clipMap.putIfAbsent('name', () => 'playtest');
      final animClip = AnimationClip.fromJson(clipMap);
      if (animClip.frameRegions.isEmpty) {
        setState(() {
          _loading = false;
          _error = StudioStrings.t('clip.previewEmpty');
          _world = null;
        });
        return;
      }

      final world = World(width: 320, height: 240);
      registerCoreComponents(world);
      registerFlutterComponents(world);
      world.addSystem(AnimationSystem());

      final entity = world.spawn();
      world.storeOf<Position>().set(entity, Position(160, 180));
      world.storeOf<Sprite>().set(
        entity,
        Sprite(widget.atlasId, animClip.frameRegions.first),
      );
      world.storeOf<AnimationState>().set(entity, AnimationState(animClip));

      final registry = AtlasRegistry()..register(widget.atlasId, atlas);
      final camera = Camera(x: 160, y: 120, zoom: 2);

      setState(() {
        _world = world;
        _registry = registry;
        _camera = camera;
        _entity = entity;
        _loading = false;
        _error = null;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
        _world = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        key: Key('clip-playtest-loading'),
        child: CircularProgressIndicator(),
      );
    }
    final error = _error;
    if (error != null) {
      return Center(
        key: const Key('clip-playtest-error'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(error, textAlign: TextAlign.center),
        ),
      );
    }
    final world = _world;
    final registry = _registry;
    final camera = _camera;
    if (world == null || registry == null || camera == null) {
      return const SizedBox.shrink();
    }
    return ColoredBox(
      key: const Key('clip-playtest'),
      color: const Color(0xFF1A1A1A),
      child: EngineView(
        key: ValueKey('playtest-${widget.revision}-${widget.atlasId}'),
        world: world,
        atlasRegistry: registry,
        camera: camera,
        cameraFollowEntity: _entity,
        backgroundColor: const Color(0xFF1A1A1A),
        fixedTimestepSeconds: 1 / 60,
      ),
    );
  }
}
