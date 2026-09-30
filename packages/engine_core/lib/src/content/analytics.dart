/// Analytics/achievement event system for games.
/// Provides a generic "fire named event with payload" abstraction that
/// games can wire to any analytics SDK (Firebase, Game Center, Play Games,
/// Adjust, AppsFlyer, custom backend, etc.).
///
/// Events are buffered and sent via registered [AnalyticsProvider]s.
/// Providers handle batching, retry, offline queue, etc.
library;

import 'dart:async';
import 'dart:convert';

/// An analytics event with name, payload, and metadata.
class AnalyticsEvent {
  final String name;
  final Map<String, dynamic> payload;
  final DateTime timestamp;
  final String? userId;
  final String? sessionId;

  AnalyticsEvent({
    required this.name,
    this.payload = const {},
    DateTime? timestamp,
    this.userId,
    this.sessionId,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'name': name,
        'payload': payload,
        'timestamp': timestamp.toIso8601String(),
        'userId': userId,
        'sessionId': sessionId,
      };

  @override
  String toString() => 'AnalyticsEvent($name, $payload)';
}

/// Interface for analytics providers (Firebase, Game Center, custom, etc.).
abstract class AnalyticsProvider {
  /// Called once at startup. Initialize SDK, set user properties, etc.
  Future<void> initialize({
    String? userId,
    Map<String, dynamic>? userProperties,
  });

  /// Sends an event to the analytics backend.
  Future<void> logEvent(AnalyticsEvent event);

  /// Sets user ID for subsequent events.
  Future<void> setUserId(String? userId);

  /// Sets user properties (dimensions like level, tier, etc.).
  Future<void> setUserProperties(Map<String, dynamic> properties);

  /// Logs a screen view (for funnel/retention analysis).
  Future<void> logScreenView(String screenName, {String? screenClass});

  /// Flushes any buffered events.
  Future<void> flush();

  /// Called when the app goes to background.
  Future<void> onPause();

  /// Called when the app returns to foreground.
  Future<void> onResume();

  /// Cleans up resources.
  Future<void> close();
}

/// No-op provider for testing or when analytics is disabled.
class NoOpAnalyticsProvider implements AnalyticsProvider {
  @override
  Future<void> initialize({
    String? userId,
    Map<String, dynamic>? userProperties,
  }) async {}

  @override
  Future<void> logEvent(AnalyticsEvent event) async {}

  @override
  Future<void> setUserId(String? userId) async {}

  @override
  Future<void> setUserProperties(Map<String, dynamic> properties) async {}

  @override
  Future<void> logScreenView(String screenName, {String? screenClass}) async {}

  @override
  Future<void> flush() async {}

  @override
  Future<void> onPause() async {}

  @override
  Future<void> onResume() async {}

  @override
  Future<void> close() async {}
}

/// Console logging provider for development.
class ConsoleAnalyticsProvider implements AnalyticsProvider {
  final bool _verbose;

  ConsoleAnalyticsProvider({bool verbose = true}) : _verbose = verbose;

  @override
  Future<void> initialize({
    String? userId,
    Map<String, dynamic>? userProperties,
  }) async {
    print('[Analytics] Initialized (userId: $userId, properties: $userProperties)');
  }

  @override
  Future<void> logEvent(AnalyticsEvent event) async {
    final payloadStr = event.payload.isEmpty ? '' : ' ${json.encode(event.payload)}';
    print('[Analytics] ${event.name}$payloadStr');
  }

  @override
  Future<void> setUserId(String? userId) async {
    print('[Analytics] User ID set: $userId');
  }

  @override
  Future<void> setUserProperties(Map<String, dynamic> properties) async {
    print('[Analytics] User properties: $properties');
  }

  @override
  Future<void> logScreenView(String screenName, {String? screenClass}) async {
    print('[Analytics] Screen view: $screenName (class: $screenClass)');
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> onPause() async {}

  @override
  Future<void> onResume() async {}

  @override
  Future<void> close() async {}
}

/// Manager for analytics with multiple providers, batching, and offline queue.
class AnalyticsManager {
  static AnalyticsManager? _instance;
  static AnalyticsManager get instance => _instance ??= AnalyticsManager._();

  final List<AnalyticsProvider> _providers = [];
  final List<AnalyticsEvent> _eventQueue = [];
  final int _maxQueueSize;
  Timer? _flushTimer;
  String? _sessionId;
  String? _userId;
  bool _initialized = false;
  bool _isPaused = false;

  AnalyticsManager._() : _maxQueueSize = 1000 {
    _sessionId = _generateSessionId();
  }

  String _generateSessionId() =>
      DateTime.now().millisecondsSinceEpoch.toString() +
      '_' +
      (DateTime.now().microsecondsSinceEpoch % 1000000).toString();

  /// Initializes all providers and starts session tracking.
  Future<void> initialize({
    List<AnalyticsProvider> providers = const [],
    String? userId,
    Map<String, dynamic>? userProperties,
    Duration flushInterval = const Duration(seconds: 30),
    bool autoTrackScreens = false,
  }) async {
    if (_initialized) return;

    _providers.addAll(providers);
    _userId = userId;

    for (final provider in _providers) {
      await provider.initialize(userId: userId, userProperties: userProperties);
    }

    // Periodic flush
    _flushTimer = Timer.periodic(flushInterval, (_) => flush());

    // Track session start
    await logEvent(AnalyticsEvent(
      name: 'session_start',
      sessionId: _sessionId,
      userId: _userId,
    ));

    _initialized = true;
  }

  /// Logs an event to all providers.
  Future<void> logEvent(AnalyticsEvent event) async {
    final enriched = AnalyticsEvent(
      name: event.name,
      payload: event.payload,
      timestamp: event.timestamp,
      userId: event.userId ?? _userId,
      sessionId: event.sessionId ?? _sessionId,
    );

    _eventQueue.add(enriched);
    if (_eventQueue.length > _maxQueueSize) {
      _eventQueue.removeRange(0, _eventQueue.length - _maxQueueSize);
    }

    // Fire immediately for real-time providers
    for (final provider in _providers) {
      provider.logEvent(enriched).catchError((e) {
        print('[AnalyticsManager] Provider error: $e');
      });
    }
  }

  /// Convenience method for simple events.
  Future<void> log(String name, [Map<String, dynamic>? payload]) async {
    await logEvent(AnalyticsEvent(name: name, payload: payload ?? {}));
  }

  /// Logs an achievement unlock.
  Future<void> logAchievement(String achievementId,
      {Map<String, dynamic>? extra}) async {
    await log('achievement_unlocked', {
      'achievement_id': achievementId,
      ...?extra,
    });
  }

  /// Logs a purchase/IAP event.
  Future<void> logPurchase(String productId, double price, String currency,
      {Map<String, dynamic>? extra}) async {
    await log('purchase', {
      'product_id': productId,
      'price': price,
      'currency': currency,
      ...?extra,
    });
  }

  /// Logs a level/mission start.
  Future<void> logLevelStart(String levelId,
      {Map<String, dynamic>? extra}) async {
    await log('level_start', {
      'level_id': levelId,
      ...?extra,
    });
  }

  /// Logs a level/mission complete.
  Future<void> logLevelComplete(String levelId,
      {int? score, int? stars, Duration? time, Map<String, dynamic>? extra}) async {
    await log('level_complete', {
      'level_id': levelId,
      if (score != null) 'score': score,
      if (stars != null) 'stars': stars,
      if (time != null) 'time_seconds': time.inSeconds,
      ...?extra,
    });
  }

  /// Logs a level/mission fail.
  Future<void> logLevelFail(String levelId,
      {Map<String, dynamic>? extra}) async {
    await log('level_fail', {
      'level_id': levelId,
      ...?extra,
    });
  }

  /// Logs a screen view.
  Future<void> logScreenView(String screenName, {String? screenClass}) async {
    await logEvent(AnalyticsEvent(
      name: 'screen_view',
      payload: {
        'screen_name': screenName,
        if (screenClass != null) 'screen_class': screenClass,
      },
      userId: _userId,
      sessionId: _sessionId,
    ));

    for (final provider in _providers) {
      await provider.logScreenView(screenName, screenClass: screenClass);
    }
  }

  /// Sets user ID for all providers.
  Future<void> setUserId(String? userId) async {
    _userId = userId;
    for (final provider in _providers) {
      await provider.setUserId(userId);
    }
  }

  /// Sets user properties for all providers.
  Future<void> setUserProperties(Map<String, dynamic> properties) async {
    for (final provider in _providers) {
      await provider.setUserProperties(properties);
    }
  }

  /// Flushes all providers.
  Future<void> flush() async {
    for (final provider in _providers) {
      await provider.flush().catchError((e) {
        print('[AnalyticsManager] Flush error: $e');
      });
    }
  }

  /// Called when app goes to background.
  Future<void> onPause() async {
    _isPaused = true;
    await logEvent(AnalyticsEvent(
      name: 'session_pause',
      sessionId: _sessionId,
      userId: _userId,
    ));
    for (final provider in _providers) {
      await provider.onPause();
    }
  }

  /// Called when app returns to foreground.
  Future<void> onResume() async {
    _isPaused = false;
    await logEvent(AnalyticsEvent(
      name: 'session_resume',
      sessionId: _sessionId,
      userId: _userId,
    ));
    for (final provider in _providers) {
      await provider.onResume();
    }
  }

  /// Gets queued events (for debugging/export).
  List<AnalyticsEvent> getQueuedEvents() => List.unmodifiable(_eventQueue);

  /// Clears the event queue.
  void clearQueue() => _eventQueue.clear();

  /// Shuts down analytics.
  Future<void> shutdown() async {
    _flushTimer?.cancel();
    await logEvent(AnalyticsEvent(
      name: 'session_end',
      sessionId: _sessionId,
      userId: _userId,
    ));
    await flush();
    for (final provider in _providers) {
      await provider.close();
    }
    _providers.clear();
    _initialized = false;
  }
}

/// Predefined event names for consistency.
class AnalyticsEvents {
  static const String sessionStart = 'session_start';
  static const String sessionEnd = 'session_end';
  static const String sessionPause = 'session_pause';
  static const String sessionResume = 'session_resume';
  static const String screenView = 'screen_view';
  static const String achievementUnlocked = 'achievement_unlocked';
  static const String purchase = 'purchase';
  static const String levelStart = 'level_start';
  static const String levelComplete = 'level_complete';
  static const String levelFail = 'level_fail';
  static const String tutorialComplete = 'tutorial_complete';
  static const String settingsChanged = 'settings_changed';
  static const String adViewed = 'ad_viewed';
  static const String adClicked = 'ad_clicked';
  static const String share = 'share';
  static const String inviteSent = 'invite_sent';
  static const String error = 'error';
}

/// Extension for easy event logging from anywhere.
extension Analytics on Object {
  /// Logs this object as an event with the given name.
  Future<void> logAsEvent(String name,
      {Map<String, dynamic>? payload}) async {
    await AnalyticsManager.instance.logEvent(AnalyticsEvent(
      name: name,
      payload: payload ?? (this is Map ? Map<String, dynamic>.from(this as Map) : {'value': toString()}),
    ));
  }
}