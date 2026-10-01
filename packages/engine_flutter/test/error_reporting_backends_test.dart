import 'dart:convert';

import 'package:engine_flutter/src/logic/error_reporting.dart';
import 'package:engine_flutter/src/logic/error_reporting_backends.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('SentryErrorReporter', () {
    late List<Map<String, dynamic>> sentPayloads;
    late SentryErrorReporter reporter;

    setUp(() {
      sentPayloads = [];
      final mockClient = MockClient((request) async {
        sentPayloads.add(json.decode(request.body) as Map<String, dynamic>);
        return http.Response('{"id": "abc"}', 200);
      });
      reporter = SentryErrorReporter(
        dsn: 'https://publickey@o1.ingest.sentry.io/123',
        httpClient: mockClient,
      );
    });

    test('setUserContext is included in the next report\'s payload', () async {
      await reporter.setUserContext(userId: 'player-42');
      await reporter.report(CapturedError(severity: ErrorSeverity.error, error: 'boom'));

      expect(sentPayloads, hasLength(1));
      expect(sentPayloads.single['user'], {'id': 'player-42'});
    });

    test("a report's own userId wins over the reporter-wide setUserContext value", () async {
      await reporter.setUserContext(userId: 'ambient-user');
      await reporter.report(CapturedError(
        severity: ErrorSeverity.error,
        error: 'boom',
        userId: 'specific-user',
      ));

      expect(sentPayloads.single['user'], {'id': 'specific-user'});
    });

    test('clearUserContext removes the user from subsequent reports', () async {
      await reporter.setUserContext(userId: 'player-42');
      await reporter.clearUserContext();
      await reporter.report(CapturedError(severity: ErrorSeverity.error, error: 'boom'));

      expect(sentPayloads.single['user'], isNull);
    });

    test('setTags are included in the next report\'s payload', () async {
      await reporter.setTags({'level': '3'});
      await reporter.report(CapturedError(severity: ErrorSeverity.error, error: 'boom'));

      expect(sentPayloads.single['tags'], {'level': '3'});
    });

    test('setTags accumulate across calls and merge with per-error tags', () async {
      await reporter.setTags({'level': '3'});
      await reporter.setTags({'build': 'debug'});
      await reporter.report(CapturedError(
        severity: ErrorSeverity.error,
        error: 'boom',
        extra: {
          'tags': {'session': 'abc'},
        },
      ));

      expect(sentPayloads.single['tags'], {
        'session': 'abc',
        'level': '3',
        'build': 'debug',
      });
    });
  });
}
