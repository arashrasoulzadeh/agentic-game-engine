import 'dart:ui' show Offset;

import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;
import 'package:engine_platformer/engine_platformer.dart';

import '../combat/auto_combat_system.dart';
import '../combat/combat_components.dart';
import '../combat/fighter_death_system.dart';
import '../combat/spawn_fighter.dart';
import '../fighters/fighter_meta.dart';
import '../fx/combat_fx.dart';
import '../hud/dialogue_caption.dart';
import '../hud/hud_layout.dart';
import '../hud/scene_hud.dart';
import '../hud/sprite_health_bar.dart';
import '../hud/wave_path.dart';
import '../hud/wave_ui_art.dart';
import '../level/level_data.dart';
import '../level/wave_progress.dart';
import 'walk_phase.dart';

/// Where a [WaveCombatScene]'s art lives and how it plays. Everything a
/// second zone or game changes is here; the scene's behaviour is shared.
class WaveCombatConfig {
  const WaveCombatConfig({
    required this.heroStem,
    required this.enemyRoot,
    required this.backgroundDir,
    required this.backgroundPrefix,
    this.heroId = 'hero',
    this.hitFxStem,
    this.slashFxStem,
    this.deathFxStem,
    this.hitBurst = 6,
    this.fighterSize = 80,
    this.walkSpeed = 70,
    this.enterDistance = 190,
    this.deathHoldSeconds = 0.5,
    this.fallenMessage = 'The hero has fallen — tap to replay',
    this.clearedMessage = 'Cleared — tap to replay',
    this.bossLabel = 'Boss',
    this.impactParticles = defaultImpactParticles,
    this.hud = const HudLayout(),
    this.ui = const WaveUiArt(),
  });

  /// Asset stem of the hero sheets (`<stem>_idle.png`, `_attack`, `_death`).
  final String heroStem;
  final String heroId;

  /// Directory of enemy sheets: `<enemyRoot>/<id>_idle.png` and so on.
  final String enemyRoot;

  /// Directory of parallax layer images `<name>.png`, registered as atlas
  /// `<backgroundPrefix>_<name>`.
  final String backgroundDir;
  final String backgroundPrefix;

  /// Effect sheet stems (null skips that effect).
  final String? hitFxStem;
  final String? slashFxStem;
  final String? deathFxStem;

  /// Particles bursting from a fighter each time it is hit (0 off).
  final int hitBurst;

  /// Every fighter is drawn this many world units square whatever its sheet's
  /// cell, so high-resolution sheets and small ones stand the same size.
  final double fighterSize;

  final double walkSpeed;
  final double enterDistance;

  /// How long a finished death clip lingers before the scene moves on.
  final double deathHoldSeconds;

  final String fallenMessage;
  final String clearedMessage;

  /// HUD caption for the boss encounter.
  final String bossLabel;

  /// Where the HUD's labels and health bars sit and their colours.
  final HudLayout hud;

  /// Generated UI art for the bars, path and caption (each optional).
  final WaveUiArt ui;

  /// Builds the spark emitter each fighter gets.
  final ParticleEmitter Function() impactParticles;

  /// Sparks that spread from a fighter when it is hit.
  static ParticleEmitter defaultImpactParticles() => ParticleEmitter(
    speedMin: 25,
    speedMax: 70,
    lifetimeMin: 0.2,
    lifetimeMax: 0.45,
    startScale: 1.6,
    colorArgb: 0xFFFFD27A,
    zIndex: 35,
    emissionShape: EmissionShape.circle,
    emissionRadius: 6,
  );
}

/// A portrait idle-combat scene: the hero walks (scenery scrolling in
/// parallax), meets the next enemy of a [LevelData] wave, auto-fights it, and
/// walks on, ending with the boss. Combat, animation states, pivots, effects,
/// shake/particle cues and the walk are engine systems this scene registers;
/// a game supplies a [LevelData] and a [WaveCombatConfig].
class WaveCombatScene extends Scene {
  WaveCombatScene({required this.level, required this.config});

  final LevelData level;
  final WaveCombatConfig config;

  static const _hitFx = 'fx_hit';
  static const _slashFx = 'fx_slash';
  static const _deathFx = 'fx_death';
  static const _uiBars = 'ui_bars';
  static const _uiNodes = 'ui_path_nodes';
  static const _uiLine = 'ui_path_line';
  static const _uiScroll = 'ui_caption_scroll';

  late final WaveProgress waves = WaveProgress(
    wave: level.wave,
    boss: level.boss,
  );
  late final Map<String, String> _fxStems = {
    if (config.hitFxStem != null) _hitFx: config.hitFxStem!,
    if (config.slashFxStem != null) _slashFx: config.slashFxStem!,
    if (config.deathFxStem != null) _deathFx: config.deathFxStem!,
  };
  late SceneHud _hud;
  late DialogueCaption _caption;
  late WalkPhase _walk;
  late Camera _camera;
  final _combat = AutoCombatSystem();
  final _pivots = PivotTable();
  final Map<String, FighterMeta> _meta = {};
  EntityId? heroId;
  EntityId? enemyId;
  EntityId? _enemyHudId;
  SpriteHealthBar? _heroBar;
  SpriteHealthBar? _enemyBar;
  WavePath? _path;
  EntityId? _corpse;
  SceneController? _scenes;

  bool finished = false;
  late String status = level.name;
  String enemyLabel = '';
  String enemyDescription = '';

  double _enemyTargetX = 0;
  double _enemyBaseY = 0;
  double _deathHold = 0;

  @override
  bool get showOnScreenControls => false;

  String _enemyStem(String id) => '${config.enemyRoot}/$id';

  double _fitScale(double cell) => config.fighterSize / cell;

  @override
  Future<void> populate(
    World world,
    SceneController scenes,
    GameState state,
  ) async {
    _scenes = scenes;
    registerPlatformerComponents(world);
    registerCombatComponents(world);
    world
      ..addSystem(_combat)
      ..addSystem(TweenSystem())
      ..addSystem(MovementSystem())
      ..addSystem(ParticleSystem())
      ..addSystem(HitFlashSystem())
      ..addSystem(HealthSystem())
      ..addSystem(HealthHudSystem())
      ..addSystem(FighterDeathSystem())
      ..addSystem(SpriteStateSystem())
      ..addSystem(AnimationSystem())
      ..addSystem(SpritePivotSystem(_pivots))
      ..addSystem(OneShotFxSystem());

    _camera = Camera(x: world.width / 2, y: world.height / 2);
    // Shake / particle cues authored in the level JSON fire from animation
    // frames through the engine's cue bridges.
    installAnimationCueSystems(world, camera: _camera);
    _walk = WalkPhase(
      scroller: ParallaxScroller.spawn(
        world,
        config.backgroundPrefix,
        level.parallax,
      ),
      speed: config.walkSpeed,
      distance: config.enterDistance,
    );
    Future<FxClip?> fx(String id) async =>
        _fxStems.containsKey(id) ? loadFxClip(id, _fxStems[id]!) : null;
    installCombatFx(
      world,
      CombatFx(
        hit: await fx(_hitFx),
        slash: await fx(_slashFx),
        death: await fx(_deathFx),
        hitBurst: config.hitBurst,
      ),
      pivots: _pivots,
    );

    _meta[config.heroId] = await FighterMeta.load(
      config.heroId,
      config.heroStem,
    );
    for (final id in level.enemyIds) {
      _meta[id] = await FighterMeta.load(id, _enemyStem(id));
    }

    _spawnHero(world);
    _hud = SceneHud.spawn(world, status: status, layout: config.hud);
    final ui = config.ui;
    _caption = DialogueCaption.spawn(
      world,
      style: config.hud.description,
      backdropAtlasId: ui.captionBackdropImage == null ? null : _uiScroll,
      backdropWidth: ui.captionBackdropWidth,
      backdropHeight: ui.captionBackdropHeight,
    );
    if (ui.pathNodesStem != null) {
      _path = WavePath.spawn(
        world,
        nodesAtlasId: _uiNodes,
        lineAtlasId: ui.pathLineImage == null ? null : _uiLine,
        count: level.wave.length + 1,
        y: ui.pathY,
        left: ui.pathInset,
        right: world.width - ui.pathInset,
        nodeSize: ui.pathNodeSize,
      );
    }
    _spawnEnemy(world);
  }

  @override
  Future<AtlasRegistry> loadAssets() async {
    final registry = AtlasRegistry();
    for (final layer in level.parallax) {
      registry.register(
        layer.atlasId(config.backgroundPrefix),
        await SpriteAtlas.loadFullImageFromAssets(
          '${config.backgroundDir}/${layer.name}.png',
        ),
      );
    }
    for (final meta in _meta.values) {
      for (final state in FighterMeta.states) {
        final sheet = await loadSpriteSheet(meta.stem(state));
        registry.register(meta.atlasId(state), sheet.atlas);
        _pivots.register(
          meta.atlasId(state),
          sheet.pivots,
          cell: sheet.sidecar.cell.toDouble(),
        );
      }
    }
    for (final e in _fxStems.entries) {
      registry.register(
        e.key,
        (await loadSpriteSheet(e.value, measurePivots: false)).atlas,
      );
    }
    final ui = config.ui;
    if (ui.barsStem != null) {
      registry.register(_uiBars, await BarsArt.load(ui.barsStem!));
    }
    if (ui.pathNodesStem != null) {
      registry.register(
        _uiNodes,
        (await loadSpriteSheet(ui.pathNodesStem!, measurePivots: false)).atlas,
      );
    }
    if (ui.pathLineImage != null) {
      registry.register(
        _uiLine,
        await SpriteAtlas.loadFullImageFromAssets(ui.pathLineImage!),
      );
    }
    if (ui.captionBackdropImage != null) {
      registry.register(
        _uiScroll,
        await SpriteAtlas.loadFullImageFromAssets(ui.captionBackdropImage!),
      );
    }
    return registry;
  }

  @override
  Camera createCamera(World world) => _camera;

  void _spawnHero(World world) {
    final meta = _meta[config.heroId]!;
    final hs = meta.stats;
    final scale = _fitScale(hs.cell);
    final drawn = hs.cell * scale;
    heroId = spawnFighter(
      world,
      side: 'hero',
      x: level.hero.x + drawn / 2,
      y: level.hero.y + drawn / 2,
      hp: level.scaled('hp', hs.hp),
      attack: level.scaled('attack', hs.attack),
      attackSpeed: level.scaled('attack_speed', hs.attackSpeed),
      armor: level.scaled('armor', hs.armor),
      atlasId: meta.atlasId('idle'),
      frameCount: meta.frames['idle']!,
      extraClips: meta.extraClips(cues: level.cues),
      impactParticles: config.impactParticles(),
      scaleX: scale,
      scaleY: scale,
      // The hero draws in front of enemies and the corpse sliding past him.
      zIndex: 25,
    );
    final bar = config.hud.heroBar;
    if (config.ui.barsStem != null) {
      _heroBar = SpriteHealthBar.spawn(
        world,
        atlasId: _uiBars,
        source: heroId!,
        left: bar.x,
        top: bar.y,
        width: bar.width,
        fill: 'xp',
      );
    } else {
      spawnHealthHudBar(
        world,
        source: heroId!,
        x: bar.x,
        y: bar.y,
        width: bar.width,
        height: bar.height,
        fillColorArgb: bar.fillColorArgb,
        screenSpace: false,
        zIndex: 100,
      );
    }
  }

  /// Brings the next enemy in from off-screen; combat starts once it has
  /// walked up to its anchor. The previous one stays as a corpse that
  /// scrolls away with the ground.
  void _spawnEnemy(World world) {
    if (_corpse != null) world.destroy(_corpse!);
    _corpse = enemyId;
    if (_enemyHudId != null) world.destroy(_enemyHudId!);
    _enemyBar?.destroy();

    final meta = _meta[waves.currentId]!;
    final stats = meta.stats;
    status = waves.isBoss ? config.bossLabel : waves.label;
    final scale = _fitScale(stats.cell);
    final drawn = stats.cell * scale;
    _enemyTargetX = level.enemyAnchor.x + drawn / 2;
    _enemyBaseY = level.enemyAnchor.y + drawn / 2;
    enemyId = spawnFighter(
      world,
      side: 'enemy',
      x: _enemyTargetX + config.enterDistance,
      y: _enemyBaseY,
      hp: waves.isBoss ? level.bossScaled('hp', stats.hp) : stats.hp,
      attack: waves.isBoss
          ? level.bossScaled('attack', stats.attack)
          : stats.attack,
      attackSpeed: stats.attackSpeed,
      armor: stats.armor,
      atlasId: meta.atlasId('idle'),
      frameCount: meta.frames['idle']!,
      extraClips: meta.extraClips(cues: level.cues),
      impactParticles: config.impactParticles(),
      // Sheets already face the hero (leftward); do not mirror.
      scaleX: scale,
      scaleY: scale,
      zIndex: 20,
    );
    final bar = config.hud.enemyBar;
    if (config.ui.barsStem != null) {
      _enemyBar = SpriteHealthBar.spawn(
        world,
        atlasId: _uiBars,
        source: enemyId!,
        left: bar.x,
        top: bar.y,
        width: bar.width,
        fill: waves.isBoss ? 'boss' : 'hp',
      );
    } else {
      _enemyHudId = spawnHealthHudBar(
        world,
        source: enemyId!,
        x: bar.x,
        y: bar.y,
        width: bar.width,
        height: bar.height,
        fillColorArgb: waves.isBoss
            ? config.hud.bossBarColorArgb
            : bar.fillColorArgb,
        screenSpace: false,
        zIndex: 100,
      );
    }
    _path?.update(waves.index, config.ui.pathNodeSize);
    enemyLabel = meta.name;
    enemyDescription = meta.descriptionFa;
    _combat.enabled = false;
    _walk.start(world, hero: heroId!, enemy: enemyId!, corpse: _corpse);
    _caption.show(world, enemyDescription);
    _syncHud(world);
  }

  void _syncHud(World world) =>
      _hud.sync(world, status: status, enemy: enemyLabel);

  void _finish(World world, String message) {
    finished = true;
    status = message;
    _caption.hide();
    _syncHud(world);
  }

  /// True once [fighter]'s death clip has finished and lingered for a beat.
  bool _deathPlayed(World world, EntityId fighter, double dt) {
    if (!spriteStateFinished(world, fighter, 'death')) return false;
    _deathHold += dt;
    if (_deathHold < config.deathHoldSeconds) return false;
    _deathHold = 0;
    return true;
  }

  @override
  void update(double dt, World world) {
    _caption.update(world, dt);
    _heroBar?.sync();
    _enemyBar?.sync();
    if (finished) return;
    final h = heroId;
    final e = enemyId;
    if (h == null || e == null) return;

    if (_walk.active) {
      if (_walk.update(world)) {
        _corpse = null;
        _combat.enabled = true;
      }
      return;
    }

    final heroHp = world.storeOf<Health>().get(h);
    final enemyHp = world.storeOf<Health>().get(e);
    if (heroHp != null && heroHp.current <= 0) {
      if (!_deathPlayed(world, h, dt)) return;
      return _finish(world, config.fallenMessage);
    }
    if (enemyHp != null && enemyHp.current <= 0) {
      // The description stays up for the whole encounter and goes with the enemy.
      _caption.hide();
      if (!_deathPlayed(world, e, dt)) return;
      if (waves.isBoss) return _finish(world, config.clearedMessage);
      waves.advance();
      _spawnEnemy(world);
    }
  }

  @override
  void handleTap(World world, SceneController scenes, Offset worldPosition) {
    if (!finished) return;
    (_scenes ?? scenes).loadScene(
      WaveCombatScene(level: level, config: config),
    );
  }
}
