import 'package:engine_core/engine_core.dart';

/// Persistent player options (volume, controls, accessibility) separate from
/// gameplay save slots. Stored locally via shared_preferences on Flutter,
/// or in-memory for testing/other platforms.
///
/// Options survive app restarts and are independent of save slots.
/// Games read/write these at any time; the engine never mutates them
/// automatically.
class PlayerOptions {
  /// Master volume (0.0 - 1.0).
  double masterVolume;

  /// Music volume (0.0 - 1.0).
  double musicVolume;

  /// SFX volume (0.0 - 1.0).
  double sfxVolume;

  /// Current control scheme identifier (e.g., 'keyboard', 'gamepad', 'touch').
  String controlScheme;

  /// Keyboard key bindings (action -> key code).
  Map<String, int> keyboardBindings;

  /// Gamepad button bindings (action -> button index).
  Map<String, int> gamepadBindings;

  /// Touch control bindings (action -> virtual button ID).
  Map<String, String> touchBindings;

  /// Text scale factor (1.0 = normal, >1 = larger text).
  double textScale;

  /// High contrast mode for accessibility.
  bool highContrast;

  /// Colorblind mode: 'none', 'protanopia', 'deuteranopia', 'tritanopia'.
  String colorblindMode;

  /// Reduce motion/animations.
  bool reduceMotion;

  /// Screen shake intensity (0.0 - 1.0).
  double screenShakeIntensity;

  /// Auto-advance dialogue speed multiplier.
  double dialogueSpeed;

  /// Language/locale code (e.g., 'en', 'ja', 'es').
  String locale;

  /// Whether to show FPS overlay (debug).
  bool showFpsOverlay;

  /// Custom game-specific options.
  Map<String, dynamic> custom;

  PlayerOptions({
    this.masterVolume = 1.0,
    this.musicVolume = 1.0,
    this.sfxVolume = 1.0,
    this.controlScheme = 'keyboard',
    Map<String, int>? keyboardBindings,
    Map<String, int>? gamepadBindings,
    Map<String, String>? touchBindings,
    this.textScale = 1.0,
    this.highContrast = false,
    this.colorblindMode = 'none',
    this.reduceMotion = false,
    this.screenShakeIntensity = 1.0,
    this.dialogueSpeed = 1.0,
    this.locale = 'en',
    this.showFpsOverlay = false,
    Map<String, dynamic>? custom,
  })  : keyboardBindings = keyboardBindings ?? const {},
        gamepadBindings = gamepadBindings ?? const {},
        touchBindings = touchBindings ?? const {},
        custom = custom ?? {};

  /// Creates a copy with modified fields.
  PlayerOptions copyWith({
    double? masterVolume,
    double? musicVolume,
    double? sfxVolume,
    String? controlScheme,
    Map<String, int>? keyboardBindings,
    Map<String, int>? gamepadBindings,
    Map<String, String>? touchBindings,
    double? textScale,
    bool? highContrast,
    String? colorblindMode,
    bool? reduceMotion,
    double? screenShakeIntensity,
    double? dialogueSpeed,
    String? locale,
    bool? showFpsOverlay,
    Map<String, dynamic>? custom,
  }) {
    return PlayerOptions(
      masterVolume: masterVolume ?? this.masterVolume,
      musicVolume: musicVolume ?? this.musicVolume,
      sfxVolume: sfxVolume ?? this.sfxVolume,
      controlScheme: controlScheme ?? this.controlScheme,
      keyboardBindings: keyboardBindings ?? this.keyboardBindings,
      gamepadBindings: gamepadBindings ?? this.gamepadBindings,
      touchBindings: touchBindings ?? this.touchBindings,
      textScale: textScale ?? this.textScale,
      highContrast: highContrast ?? this.highContrast,
      colorblindMode: colorblindMode ?? this.colorblindMode,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      screenShakeIntensity: screenShakeIntensity ?? this.screenShakeIntensity,
      dialogueSpeed: dialogueSpeed ?? this.dialogueSpeed,
      locale: locale ?? this.locale,
      showFpsOverlay: showFpsOverlay ?? this.showFpsOverlay,
      custom: custom ?? this.custom,
    );
  }

  Map<String, dynamic> toJson() => {
        'masterVolume': masterVolume,
        'musicVolume': musicVolume,
        'sfxVolume': sfxVolume,
        'controlScheme': controlScheme,
        'keyboardBindings': keyboardBindings,
        'gamepadBindings': gamepadBindings,
        'touchBindings': touchBindings,
        'textScale': textScale,
        'highContrast': highContrast,
        'colorblindMode': colorblindMode,
        'reduceMotion': reduceMotion,
        'screenShakeIntensity': screenShakeIntensity,
        'dialogueSpeed': dialogueSpeed,
        'locale': locale,
        'showFpsOverlay': showFpsOverlay,
        'custom': custom,
      };

  factory PlayerOptions.fromJson(Map<String, dynamic> json) => PlayerOptions(
        masterVolume: (json['masterVolume'] as num?)?.toDouble() ?? 1.0,
        musicVolume: (json['musicVolume'] as num?)?.toDouble() ?? 1.0,
        sfxVolume: (json['sfxVolume'] as num?)?.toDouble() ?? 1.0,
        controlScheme: json['controlScheme'] as String? ?? 'keyboard',
        keyboardBindings: (json['keyboardBindings'] as Map<String, dynamic>?)
            ?.map((k, v) => MapEntry(k, v as int))
            ?? {},
        gamepadBindings: (json['gamepadBindings'] as Map<String, dynamic>?)
            ?.map((k, v) => MapEntry(k, v as int))
            ?? {},
        touchBindings: (json['touchBindings'] as Map<String, dynamic>?)
            ?.map((k, v) => MapEntry(k, v as String))
            ?? {},
        textScale: (json['textScale'] as num?)?.toDouble() ?? 1.0,
        highContrast: json['highContrast'] as bool? ?? false,
        colorblindMode: json['colorblindMode'] as String? ?? 'none',
        reduceMotion: json['reduceMotion'] as bool? ?? false,
        screenShakeIntensity: (json['screenShakeIntensity'] as num?)?.toDouble() ?? 1.0,
        dialogueSpeed: (json['dialogueSpeed'] as num?)?.toDouble() ?? 1.0,
        locale: json['locale'] as String? ?? 'en',
        showFpsOverlay: json['showFpsOverlay'] as bool? ?? false,
        custom: json['custom'] as Map<String, dynamic>? ?? {},
      );

  /// Clamps volume values to valid range.
  void clampVolumes() {
    masterVolume = masterVolume.clamp(0.0, 1.0);
    musicVolume = musicVolume.clamp(0.0, 1.0);
    sfxVolume = sfxVolume.clamp(0.0, 1.0);
    textScale = textScale.clamp(0.5, 3.0);
    screenShakeIntensity = screenShakeIntensity.clamp(0.0, 1.0);
    dialogueSpeed = dialogueSpeed.clamp(0.1, 5.0);
  }
}

/// Storage backend interface for player options.
abstract class PlayerOptionsStorage {
  /// Loads options from storage. Returns null if no saved options exist.
  Future<PlayerOptions?> load();

  /// Saves options to storage.
  Future<void> save(PlayerOptions options);

  /// Clears all saved options (resets to defaults).
  Future<void> clear();
}

/// In-memory storage for testing or platforms without persistence.
class InMemoryPlayerOptionsStorage implements PlayerOptionsStorage {
  PlayerOptions? _cached;

  @override
  Future<PlayerOptions?> load() async => _cached;

  @override
  Future<void> save(PlayerOptions options) async {
    _cached = options;
  }

  @override
  Future<void> clear() async {
    _cached = null;
  }
}

/// Manager for player options with automatic persistence.
class PlayerOptionsManager {
  final PlayerOptionsStorage _storage;
  PlayerOptions _options;
  final List<void Function(PlayerOptions)> _listeners = [];

  PlayerOptionsManager(this._storage, [PlayerOptions? initialOptions])
      : _options = initialOptions ?? PlayerOptions();

  PlayerOptions get options => _options;

  /// Adds a listener that fires when options change.
  void addListener(void Function(PlayerOptions) listener) {
    _listeners.add(listener);
  }

  /// Removes a listener.
  void removeListener(void Function(PlayerOptions) listener) {
    _listeners.remove(listener);
  }

  /// Loads options from storage.
  Future<void> load() async {
    final loaded = await _storage.load();
    if (loaded != null) {
      _options = loaded;
      _options.clampVolumes();
    }
    _notify();
  }

  /// Updates options and persists them.
  Future<void> update(PlayerOptions Function(PlayerOptions) updater) async {
    _options = updater(_options);
    _options.clampVolumes();
    await _storage.save(_options);
    _notify();
  }

  /// Sets a single option by key (for simple UI bindings).
  Future<void> setOption(String key, dynamic value) async {
    await update((opts) {
      switch (key) {
        case 'masterVolume':
          opts.masterVolume = (value as num).toDouble();
        case 'musicVolume':
          opts.musicVolume = (value as num).toDouble();
        case 'sfxVolume':
          opts.sfxVolume = (value as num).toDouble();
        case 'controlScheme':
          opts.controlScheme = value as String;
        case 'keyboardBindings':
          opts.keyboardBindings = Map<String, int>.from(value as Map);
        case 'gamepadBindings':
          opts.gamepadBindings = Map<String, int>.from(value as Map);
        case 'touchBindings':
          opts.touchBindings = Map<String, String>.from(value as Map);
        case 'textScale':
          opts.textScale = (value as num).toDouble();
        case 'highContrast':
          opts.highContrast = value as bool;
        case 'colorblindMode':
          opts.colorblindMode = value as String;
        case 'reduceMotion':
          opts.reduceMotion = value as bool;
        case 'screenShakeIntensity':
          opts.screenShakeIntensity = (value as num).toDouble();
        case 'dialogueSpeed':
          opts.dialogueSpeed = (value as num).toDouble();
        case 'locale':
          opts.locale = value as String;
        case 'showFpsOverlay':
          opts.showFpsOverlay = value as bool;
        default:
          opts.custom[key] = value;
      }
      return opts;
    });
  }

  /// Gets an option by key.
  dynamic getOption(String key) {
    switch (key) {
      case 'masterVolume':
        return _options.masterVolume;
      case 'musicVolume':
        return _options.musicVolume;
      case 'sfxVolume':
        return _options.sfxVolume;
      case 'controlScheme':
        return _options.controlScheme;
      case 'keyboardBindings':
        return _options.keyboardBindings;
      case 'gamepadBindings':
        return _options.gamepadBindings;
      case 'touchBindings':
        return _options.touchBindings;
      case 'textScale':
        return _options.textScale;
      case 'highContrast':
        return _options.highContrast;
      case 'colorblindMode':
        return _options.colorblindMode;
      case 'reduceMotion':
        return _options.reduceMotion;
      case 'screenShakeIntensity':
        return _options.screenShakeIntensity;
      case 'dialogueSpeed':
        return _options.dialogueSpeed;
      case 'locale':
        return _options.locale;
      case 'showFpsOverlay':
        return _options.showFpsOverlay;
      default:
        return _options.custom[key];
    }
  }

  /// Resets all options to defaults.
  Future<void> reset() async {
    _options = PlayerOptions();
    await _storage.save(_options);
    _notify();
  }

  void _notify() {
    for (final listener in _listeners) {
      listener(_options);
    }
  }
}