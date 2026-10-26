import 'package:engine_core/engine_core.dart';

import '../rendering/animation.dart';
import 'audio_manager.dart';

/// Plays one-shots for [AnimationFrameEvent] cues with `type == 'sfx'`.
///
/// Call [attach] once on the world that runs [AnimationSystem] — events
/// fire during `World.step`'s flush after systems update, so this is
/// event-driven: [update] is a no-op kept only so the class can sit in
/// `systemOrder` next to other flutter systems.
///
/// Cue payload (in [AnimationEvent.data]):
/// - `id` (required unless `asset` is set) — looked up in [soundIds], or
///   used as the asset path when unmapped
/// - `asset` — optional direct asset path (wins over `id` when both set)
/// - `volume` — optional, default `1.0`
///
/// When [positional] is true and the emitting entity has a [Position],
/// uses [AudioManager.playPositionalSound] with [listenerAt] (defaults to
/// world center) as the listener.
class AnimationSfxSystem implements System {
  /// Maps cue `id` → asset path. Unmapped ids are treated as paths.
  final Map<String, String> soundIds;

  /// When true, play with distance/pan from the entity's [Position].
  final bool positional;

  /// Listener world coords for [positional] playback. Defaults to the
  /// world's center when omitted.
  final (double, double) Function(World world)? listenerAt;

  /// Max distance for positional attenuation (passed through to
  /// [AudioManager.playPositionalSound]).
  final double maxDistance;

  final Future<void> Function(String assetPath, {double volume}) _playSound;
  final Future<void> Function(
    String assetPath, {
    required double sourceX,
    required double sourceY,
    required double listenerX,
    required double listenerY,
    double maxDistance,
    double volume,
  })? _playPositional;

  bool _attached = false;

  /// Production constructor — wires [AudioManager.playSound] /
  /// [AudioManager.playPositionalSound].
  AnimationSfxSystem(
    AudioManager audio, {
    this.soundIds = const {},
    this.positional = false,
    this.listenerAt,
    this.maxDistance = 800,
  }) : _playSound = audio.playSound,
       _playPositional = audio.playPositionalSound;

  /// Test / custom playback hooks without constructing [AudioManager].
  AnimationSfxSystem.custom({
    required Future<void> Function(String assetPath, {double volume}) playSound,
    Future<void> Function(
      String assetPath, {
      required double sourceX,
      required double sourceY,
      required double listenerX,
      required double listenerY,
      double maxDistance,
      double volume,
    })? playPositional,
    this.soundIds = const {},
    this.positional = false,
    this.listenerAt,
    this.maxDistance = 800,
  }) : _playSound = playSound,
       _playPositional = playPositional;

  @override
  String get name => 'animationSfx';

  /// Registers the frame-event handler on [world]. Safe to call more than
  /// once — subsequent calls are no-ops.
  void attach(World world) {
    if (_attached) return;
    _attached = true;
    world.events.on<AnimationFrameEvent>((event) {
      if (event.type != 'sfx') return;
      final asset = _resolveAsset(event.data);
      if (asset == null || asset.isEmpty) return;
      final volume = (event.data['volume'] as num?)?.toDouble() ?? 1.0;
      _play(world, event.entity, asset, volume);
    });
  }

  @override
  void update(World world, double dt) {
    // Event-driven — see [attach].
  }

  String? _resolveAsset(Map<String, dynamic> data) {
    final direct = data['asset'] as String?;
    if (direct != null && direct.isNotEmpty) return direct;
    final id = data['id'] as String?;
    if (id == null || id.isEmpty) return null;
    return soundIds[id] ?? id;
  }

  void _play(World world, EntityId entity, String asset, double volume) {
    if (positional) {
      final pos = world.storeOf<Position>().get(entity);
      final playPositional = _playPositional;
      if (pos != null && playPositional != null) {
        final listener =
            listenerAt?.call(world) ?? (world.width / 2, world.height / 2);
        playPositional(
          asset,
          sourceX: pos.x,
          sourceY: pos.y,
          listenerX: listener.$1,
          listenerY: listener.$2,
          maxDistance: maxDistance,
          volume: volume,
        );
        return;
      }
    }
    _playSound(asset, volume: volume);
  }
}
