import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import 'error_reporting.dart';

/// Sentry error reporter.
/// Requires `sentry_flutter` package or direct HTTP API calls.
/// See https://docs.sentry.io/platforms/flutter/
class SentryErrorReporter extends ErrorReporter {
  final String _dsn;
  final String? _environment;
  final String? _release;
  final bool _debug;
  final http.Client? _httpClient;
  String? _userId;
  Map<String, String> _tags = {};

  SentryErrorReporter({
    required String dsn,
    String? environment,
    String? release,
    bool debug = false,
    http.Client? httpClient,
  })  : _dsn = dsn,
        _environment = environment,
        _release = release,
        _debug = debug,
        _httpClient = httpClient ?? http.Client();

  @override
  Future<void> init() async {
    // Sentry initialization would go here if using sentry_flutter package
    // For now, we just validate the DSN
    if (_dsn.isEmpty) {
      throw ArgumentError('Sentry DSN cannot be empty');
    }
    if (_debug) {
      print('[SentryErrorReporter] Initialized with DSN: ${_dsn.substring(0, 20)}...');
    }
  }

  @override
  Future<void> report(CapturedError error) async {
    final payload = _buildPayload(error);

    try {
      final uri = Uri.parse(_dsn).replace(path: '/api/${_extractProjectId(_dsn)}/envelope/');
      final response = await _httpClient!.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'X-Sentry-Auth': _buildAuthHeader(),
        },
        body: json.encode(payload),
      );

      if (response.statusCode >= 400) {
        throw Exception('Sentry returned ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      // Don't crash the app if Sentry is down
      if (_debug) {
        print('[SentryErrorReporter] Failed to report: $e');
      }
      // Could queue for retry here
    }
  }

  String _extractProjectId(String dsn) {
    final uri = Uri.parse(dsn);
    final pathSegments = uri.pathSegments;
    return pathSegments.isNotEmpty ? pathSegments.last : '';
  }

  String _buildAuthHeader() {
    final uri = Uri.parse(_dsn);
    final publicKey = uri.userInfo.split(':').first;
    return 'Sentry sentry_key=$publicKey, sentry_version=7';
  }

  Map<String, dynamic> _buildPayload(CapturedError error) {
    return {
      'event_id': _generateEventId(),
      'timestamp': error.timestamp.toIso8601String(),
      'level': error.severity.name,
      'platform': error.platform,
      'message': error.error.toString(),
      'exception': {
        'values': [
          {
            'type': error.error.runtimeType.toString(),
            'value': error.error.toString(),
            'stacktrace': error.stackTrace?.toString() ?? '',
            'mechanism': {'type': 'flutter', 'handled': error.severity != ErrorSeverity.fatal},
          }
        ]
      },
      // error.userId (per-report) wins over the reporter-wide
      // setUserContext value -- a caller supplying one explicitly for
      // this specific error is more specific than the ambient context.
      'user': error.userId != null
          ? {'id': error.userId}
          : (_userId != null ? {'id': _userId} : null),
      'tags': {...?error.extra?['tags'] as Map<String, String>?, ..._tags},
      'contexts': {
        'app': {
          'app_version': error.appVersion,
          'build_number': error.buildNumber,
          'platform': error.platform,
        },
        'device': {
          'os': Platform.operatingSystem,
          'os_version': Platform.operatingSystemVersion,
        },
        'session': error.sessionId != null ? {'id': error.sessionId} : null,
      },
      'extra': error.extra,
      'release': _release,
      'environment': _environment,
    };
  }

  String _generateEventId() {
    final random = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  @override
  Future<void> setUserContext({
    String? userId,
    String? email,
    String? username,
    Map<String, dynamic>? data,
  }) async {
    _userId = userId;
  }

  @override
  Future<void> setTags(Map<String, String> tags) async {
    _tags.addAll(tags);
  }

  @override
  Future<void> clearUserContext() async {
    _userId = null;
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {
    _httpClient?.close();
  }
}

/// Firebase Crashlytics reporter.
/// Requires `firebase_crashlytics` package.
/// See https://firebase.google.com/docs/crashlytics
class FirebaseCrashlyticsReporter extends ErrorReporter {
  final bool _debug;
  bool _initialized = false;

  FirebaseCrashlyticsReporter({bool debug = false}) : _debug = debug;

  @override
  Future<void> init() async {
    if (_debug) {
      print('[FirebaseCrashlyticsReporter] Initialized');
    }
    _initialized = true;
    // In a real implementation:
    // await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
  }

  @override
  Future<void> report(CapturedError error) async {
    if (!_initialized) return;

    // In a real implementation:
    // if (error.severity == ErrorSeverity.fatal) {
    //   await FirebaseCrashlytics.instance.recordError(
    //     error.error,
    //     error.stackTrace,
    //     fatal: true,
    //     information: error.context,
    //   );
    // } else {
    //   await FirebaseCrashlytics.instance.recordError(
    //     error.error,
    //     error.stackTrace,
    //     fatal: false,
    //     information: error.context,
    //   );
    // }
    if (_debug) {
      print('[FirebaseCrashlyticsReporter] Would report: ${error.error}');
    }
  }

  @override
  Future<void> setUserContext({
    String? userId,
    String? email,
    String? username,
    Map<String, dynamic>? data,
  }) async {
    // await FirebaseCrashlytics.instance.setUserIdentifier(userId ?? '');
    // if (email != null) await FirebaseCrashlytics.instance.setCustomKey('email', email);
    // if (username != null) await FirebaseCrashlytics.instance.setCustomKey('username', username);
    // if (data != null) {
    //   for (final entry in data.entries) {
    //     await FirebaseCrashlytics.instance.setCustomKey(entry.key, entry.value.toString());
    //   }
    // }
  }

  @override
  Future<void> setTags(Map<String, String> tags) async {
    // for (final entry in tags.entries) {
    //   await FirebaseCrashlytics.instance.setCustomKey(entry.key, entry.value);
    // }
  }

  @override
  Future<void> clearUserContext() async {}

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}
}

/// Google Play Console / Play Integrity reporter.
/// For Android-specific crash reporting to Play Console.
class GooglePlayReporter extends ErrorReporter {
  final bool _debug;

  GooglePlayReporter({bool debug = false}) : _debug = debug;

  @override
  Future<void> init() async {
    if (_debug) print('[GooglePlayReporter] Initialized');
  }

  @override
  Future<void> report(CapturedError error) async {
    // Integration with Play Developer Reporting API
    if (_debug) print('[GooglePlayReporter] Would report: ${error.error}');
  }

  @override
  Future<void> setUserContext({
    String? userId,
    String? email,
    String? username,
    Map<String, dynamic>? data,
  }) async {}

  @override
  Future<void> setTags(Map<String, String> tags) async {}

  @override
  Future<void> clearUserContext() async {}

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}
}

/// Custom HTTP endpoint reporter for custom backends.
class CustomHttpReporter extends ErrorReporter {
  final String _endpoint;
  final Map<String, String> _headers;
  final http.Client _httpClient;
  final bool _debug;

  CustomHttpReporter({
    required String endpoint,
    Map<String, String>? headers,
    http.Client? httpClient,
    bool debug = false,
  })  : _endpoint = endpoint,
        _headers = headers ?? {'Content-Type': 'application/json'},
        _httpClient = httpClient ?? http.Client(),
        _debug = debug;

  @override
  Future<void> init() async {
    if (_debug) print('[CustomHttpReporter] Initialized with endpoint: $_endpoint');
  }

  @override
  Future<void> report(CapturedError error) async {
    try {
      final response = await _httpClient.post(
        Uri.parse(_endpoint),
        headers: _headers,
        body: json.encode(error.toJson()),
      );

      if (response.statusCode >= 400) {
        throw Exception('Custom endpoint returned ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      if (_debug) print('[CustomHttpReporter] Failed to report: $e');
    }
  }

  @override
  Future<void> setUserContext({
    String? userId,
    String? email,
    String? username,
    Map<String, dynamic>? data,
  }) async {}

  @override
  Future<void> setTags(Map<String, String> tags) async {}

  @override
  Future<void> clearUserContext() async {}

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {
    _httpClient.close();
  }
}

/// Multi-reporter that combines multiple reporters with priority.
class MultiErrorReporter extends ErrorReporter {
  final List<ErrorReporter> _reporters;
  final bool _stopOnFirstSuccess;

  MultiErrorReporter({
    required List<ErrorReporter> reporters,
    bool stopOnFirstSuccess = false,
  })  : _reporters = reporters,
        _stopOnFirstSuccess = stopOnFirstSuccess;

  @override
  Future<void> init() async {
    for (final reporter in _reporters) {
      await reporter.init();
    }
  }

  @override
  Future<void> report(CapturedError error) async {
    for (final reporter in _reporters) {
      try {
        await reporter.report(error);
        if (_stopOnFirstSuccess) break;
      } catch (e) {
        print('[MultiErrorReporter] Reporter failed: $e');
      }
    }
  }

  @override
  Future<void> setUserContext({
    String? userId,
    String? email,
    String? username,
    Map<String, dynamic>? data,
  }) async {
    for (final reporter in _reporters) {
      await reporter.setUserContext(
        userId: userId,
        email: email,
        username: username,
        data: data,
      );
    }
  }

  @override
  Future<void> setTags(Map<String, String> tags) async {
    for (final reporter in _reporters) {
      await reporter.setTags(tags);
    }
  }

  @override
  Future<void> clearUserContext() async {
    for (final reporter in _reporters) {
      await reporter.clearUserContext();
    }
  }

  @override
  Future<void> flush() async {
    for (final reporter in _reporters) {
      await reporter.flush();
    }
  }

  @override
  Future<void> close() async {
    for (final reporter in _reporters) {
      await reporter.close();
    }
  }
}