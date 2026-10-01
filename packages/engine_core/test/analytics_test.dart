import 'dart:async';

import 'package:engine_core/src/content/analytics.dart';
import 'package:test/test.dart';

class _FakeProvider implements AnalyticsProvider {
  final List<AnalyticsEvent> events = [];
  bool paused = false;

  @override
  Future<void> initialize({
    String? userId,
    Map<String, dynamic>? userProperties,
  }) async {}

  @override
  Future<void> logEvent(AnalyticsEvent event) async => events.add(event);

  @override
  Future<void> setUserId(String? userId) async {}

  @override
  Future<void> setUserProperties(Map<String, dynamic> properties) async {}

  @override
  Future<void> logScreenView(String screenName, {String? screenClass}) async {}

  @override
  Future<void> flush() async {}

  @override
  Future<void> onPause() async => paused = true;

  @override
  Future<void> onResume() async => paused = false;

  @override
  Future<void> close() async {}
}

void main() {
  group('AnalyticsManager pause/resume', () {
    late AnalyticsManager manager;
    late _FakeProvider provider;

    setUp(() async {
      manager = AnalyticsManager.instance;
      provider = _FakeProvider();
      await manager.initialize(providers: [provider]);
      manager.clearQueue();
    });

    tearDown(() async {
      await manager.shutdown();
    });

    test('logEvent is dropped while paused, resumes delivering after onResume', () async {
      await manager.onPause();
      // session_pause itself must still get through despite the pause flag.
      expect(manager.getQueuedEvents().map((e) => e.name), contains('session_pause'));

      await manager.log('coin_collected');
      expect(manager.getQueuedEvents().map((e) => e.name), isNot(contains('coin_collected')));

      await manager.onResume();
      expect(manager.getQueuedEvents().map((e) => e.name), contains('session_resume'));

      await manager.log('coin_collected');
      expect(manager.getQueuedEvents().map((e) => e.name), contains('coin_collected'));
    });
  });

  group('ConsoleAnalyticsProvider verbosity', () {
    test('prints nothing when verbose is false', () async {
      final provider = ConsoleAnalyticsProvider(verbose: false);
      final lines = <String>[];
      await runZoned(() async {
        await provider.logEvent(AnalyticsEvent(name: 'test_event'));
      }, zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => lines.add(line),
      ));
      expect(lines, isEmpty);
    });

    test('prints when verbose is true', () async {
      final provider = ConsoleAnalyticsProvider();
      final lines = <String>[];
      await runZoned(() async {
        await provider.logEvent(AnalyticsEvent(name: 'test_event'));
      }, zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => lines.add(line),
      ));
      expect(lines, isNotEmpty);
      expect(lines.single, contains('test_event'));
    });
  });
}
