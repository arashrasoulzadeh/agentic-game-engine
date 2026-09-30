import 'package:engine_core/engine_core.dart';

/// Base class for platform-specific analytics providers.
/// Override methods to integrate with Firebase, Game Center, Play Games, etc.
abstract class PlatformAnalyticsProvider implements AnalyticsProvider {
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

/// Firebase Analytics provider (skeleton - implement with firebase_analytics package).
/// Add `firebase_analytics` to your pubspec.yaml and implement the methods.
class FirebaseAnalyticsProvider extends PlatformAnalyticsProvider {
  // final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  @override
  Future<void> initialize({
    String? userId,
    Map<String, dynamic>? userProperties,
  }) async {
    // await _analytics.setUserId(id: userId);
    // if (userProperties != null) {
    //   for (final entry in userProperties.entries) {
    //     await _analytics.setUserProperty(name: entry.key, value: entry.value.toString());
    //   }
    // }
  }

  @override
  Future<void> logEvent(AnalyticsEvent event) async {
    // await _analytics.logEvent(
    //   name: event.name,
    //   parameters: event.payload,
    // );
  }

  @override
  Future<void> setUserId(String? userId) async {
    // await _analytics.setUserId(id: userId);
  }

  @override
  Future<void> setUserProperties(Map<String, dynamic> properties) async {
    // for (final entry in properties.entries) {
    //   await _analytics.setUserProperty(name: entry.key, value: entry.value.toString());
    // }
  }

  @override
  Future<void> logScreenView(String screenName, {String? screenClass}) async {
    // await _analytics.logScreenView(screenName: screenName, screenClass: screenClass);
  }
}

/// Google Play Games / Apple Game Center provider (skeleton).
/// Implement with Google Play Games Services or GameKit.
class GameServicesAnalyticsProvider extends PlatformAnalyticsProvider {
  @override
  Future<void> logAchievementUnlocked(String achievementId) async {
    // Unlock achievement in Play Games / Game Center
  }

  @override
  Future<void> logEvent(AnalyticsEvent event) async {
    // Handle custom events
  }
}

/// Adjust / AppsFlyer / custom attribution provider (skeleton).
class AttributionAnalyticsProvider extends PlatformAnalyticsProvider {
  @override
  Future<void> logEvent(AnalyticsEvent event) async {
    // Send to attribution provider
  }

  @override
  Future<void> logPurchase(String productId, double price, String currency,
      {Map<String, dynamic>? extra}) async {
    // Track revenue for attribution
  }
}