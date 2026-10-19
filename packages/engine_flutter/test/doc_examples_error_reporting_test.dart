// The samples in docs/concepts/analytics-and-errors.md, executed so the guide cannot drift.
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

class _Recorder extends ErrorReporter {
  final List<CapturedError> seen = [];
  Map<String, String> tags = {};
  String? user;

  @override
  Future<void> init() async {}
  @override
  Future<void> report(CapturedError error) async => seen.add(error);
  @override
  Future<void> setUserContext({String? userId, String? email, String? username, Map<String, dynamic>? data}) async =>
      user = userId;
  @override
  Future<void> setTags(Map<String, String> t) async => tags = t;
  @override
  Future<void> clearUserContext() async => user = null;
  @override
  Future<void> flush() async {}
  @override
  Future<void> close() async {}
}

void main() {
  test('report errors by hand and through the helpers; reporters get user and tags', () async {
    final recorder = _Recorder();
    final manager = ErrorReportingManager.instance;
    await manager.initialize(
      reporters: [recorder],
      captureFlutterErrors: false, // leave FlutterError.onError alone in tests
      captureDartErrors: false,
    );
    addTearDown(manager.shutdown);

    await manager.setUserContext(userId: 'player-42');
    await manager.setTags({'build': 'release'});
    await manager.reportError(StateError('boom'), context: 'loading level', severity: ErrorSeverity.warning);
    await 'low on memory'.reportAsError(severity: ErrorSeverity.info);

    expect(recorder.user, 'player-42');
    expect(recorder.tags, {'build': 'release'});
    expect(recorder.seen.map((e) => e.severity), [ErrorSeverity.warning, ErrorSeverity.info]);
    expect(recorder.seen.first.context, 'loading level');
    expect(recorder.seen.first.platform, currentPlatformName());
    expect(manager.getPendingErrors(), hasLength(2));
  });

  test('runWithErrorReporting reports a thrown error and rethrows it', () async {
    final recorder = _Recorder();
    final manager = ErrorReportingManager.instance;
    await manager.initialize(reporters: [recorder], captureFlutterErrors: false, captureDartErrors: false);
    addTearDown(manager.shutdown);

    await expectLater(
      runWithErrorReporting<void>(() => throw ArgumentError('bad'), context: 'save'),
      throwsArgumentError,
    );
    expect(recorder.seen.single.context, 'save');
  });
}
