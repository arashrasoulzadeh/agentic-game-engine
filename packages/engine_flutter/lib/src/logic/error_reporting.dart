import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show FlutterError, FlutterErrorDetails;

/// Error severity levels.
enum ErrorSeverity {
  /// Non-critical issue, app continues normally.
  info,

  /// Something unexpected but recoverable.
  warning,

  /// Error that may affect functionality but app continues.
  error,

  /// Critical error that crashes or severely impacts the app.
  fatal,
}

/// A captured error with context.
class CapturedError {
  final ErrorSeverity severity;
  final Object error;
  final StackTrace? stackTrace;
  final String? context;
  final Map<String, dynamic>? extra;
  final DateTime timestamp;
  final String? userId;
  final String? sessionId;
  final String platform;
  final String? appVersion;
  final String? buildNumber;

  CapturedError({
    required this.severity,
    required this.error,
    this.stackTrace,
    this.context,
    this.extra,
    DateTime? timestamp,
    this.userId,
    this.sessionId,
    String? platform,
    this.appVersion,
    this.buildNumber,
  })  : timestamp = timestamp ?? DateTime.now(),
        platform = platform ?? Platform.operatingSystem;

  Map<String, dynamic> toJson() => {
        'severity': severity.name,
        'error': error.toString(),
        'stackTrace': stackTrace?.toString(),
        'context': context,
        'extra': extra,
        'timestamp': timestamp.toIso8601String(),
        'userId': userId,
        'sessionId': sessionId,
        'platform': platform,
        'appVersion': appVersion,
        'buildNumber': buildNumber,
      };

  @override
  String toString() =>
      'CapturedError(${severity.name}): $error\n$stackTrace';
}

/// Interface for error reporting backends (Sentry, Crashlytics, custom, etc.).
abstract class ErrorReporter {
  /// Called when the reporter is initialized.
  Future<void> init();

  /// Reports a captured error.
  Future<void> report(CapturedError error);

  /// Reports a simple error with optional context.
  Future<void> reportError(
    Object error, {
    StackTrace? stackTrace,
    String? context,
    Map<String, dynamic>? extra,
    ErrorSeverity severity = ErrorSeverity.error,
  }) {
    return report(CapturedError(
      severity: severity,
      error: error,
      stackTrace: stackTrace,
      context: context,
      extra: extra,
    ));
  }

  /// Reports a message (info/warning) without an error object.
  Future<void> reportMessage(
    String message, {
    ErrorSeverity severity = ErrorSeverity.info,
    String? context,
    Map<String, dynamic>? extra,
  }) {
    return report(CapturedError(
      severity: severity,
      error: message,
      context: context,
      extra: extra,
    ));
  }

  /// Sets user context for subsequent reports.
  Future<void> setUserContext({
    String? userId,
    String? email,
    String? username,
    Map<String, dynamic>? data,
  });

  /// Sets tags for subsequent reports.
  Future<void> setTags(Map<String, String> tags);

  /// Clears user context.
  Future<void> clearUserContext();

  /// Flushes any pending reports.
  Future<void> flush();

  /// Closes the reporter and releases resources.
  Future<void> close();
}

/// Console/logger-based error reporter for development.
class ConsoleErrorReporter extends ErrorReporter {
  final bool _printToConsole;
  final bool _includeStackTrace;

  ConsoleErrorReporter({
    bool printToConsole = true,
    bool includeStackTrace = true,
  })  : _printToConsole = printToConsole,
        _includeStackTrace = includeStackTrace;

  @override
  Future<void> init() async {
    if (_printToConsole) {
      print('[ConsoleErrorReporter] Initialized');
    }
  }

  @override
  Future<void> report(CapturedError error) async {
    if (!_printToConsole) return;

    final prefix = '[${error.severity.name.toUpperCase()}]';
    final contextStr = error.context != null ? ' (${error.context})' : '';
    final extraStr = error.extra != null ? '\nExtra: ${error.extra}' : '';
    final stackStr = _includeStackTrace && error.stackTrace != null
        ? '\nStack: ${error.stackTrace}'
        : '';

    final message =
        '$prefix${contextStr}: ${error.error}$extraStr$stackStr';

    switch (error.severity) {
      case ErrorSeverity.info:
        print(message);
        break;
      case ErrorSeverity.warning:
        print(message);
        break;
      case ErrorSeverity.error:
        print(message);
        break;
      case ErrorSeverity.fatal:
        print(message);
        break;
    }

    // Also log to developer log for Flutter DevTools
    developer.log(
      message,
      name: 'ErrorReporter',
      level: _severityToLevel(error.severity),
      error: error.error,
      stackTrace: error.stackTrace,
    );
  }

  int _severityToLevel(ErrorSeverity severity) {
    switch (severity) {
      case ErrorSeverity.info:
        return 800; // info
      case ErrorSeverity.warning:
        return 900; // warning
      case ErrorSeverity.error:
        return 1000; // severe
      case ErrorSeverity.fatal:
        return 1200; // shout
    }
  }

  @override
  Future<void> setUserContext({
    String? userId,
    String? email,
    String? username,
    Map<String, dynamic>? data,
  }) async {
    if (_printToConsole) {
      print('[ConsoleErrorReporter] User context set: userId=$userId');
    }
  }

  @override
  Future<void> setTags(Map<String, String> tags) async {
    if (_printToConsole) {
      print('[ConsoleErrorReporter] Tags set: $tags');
    }
  }

  @override
  Future<void> clearUserContext() async {
    if (_printToConsole) {
      print('[ConsoleErrorReporter] User context cleared');
    }
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {
    if (_printToConsole) {
      print('[ConsoleErrorReporter] Closed');
    }
  }
}

/// A no-op error reporter for production builds where you don't want
/// any reporting (or haven't configured a backend yet).
class NoOpErrorReporter extends ErrorReporter {
  @override
  Future<void> init() async {}

  @override
  Future<void> report(CapturedError error) async {}

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

/// Manager for error reporting that handles multiple reporters,
/// automatic crash catching, and error batching.
class ErrorReportingManager {
  static ErrorReportingManager? _instance;
  static ErrorReportingManager get instance =>
      _instance ??= ErrorReportingManager._();

  final List<ErrorReporter> _reporters = [];
  final List<CapturedError> _pendingErrors = [];
  final int _maxPendingErrors;
  Timer? _flushTimer;
  bool _initialized = false;
  String? _sessionId;

  ErrorReportingManager._() : _maxPendingErrors = 100 {
    _sessionId = _generateSessionId();
  }

  String _generateSessionId() {
    return DateTime.now().millisecondsSinceEpoch.toString() +
        '_' +
        (math.Random().nextDouble() * 1000000).toInt().toString();
  }

  /// Initializes all registered reporters.
  Future<void> initialize({
    List<ErrorReporter> reporters = const [],
    bool captureFlutterErrors = true,
    bool captureDartErrors = true,
    Duration flushInterval = const Duration(seconds: 30),
  }) async {
    if (_initialized) return;

    _reporters.addAll(reporters);
    for (final reporter in _reporters) {
      await reporter.init();
    }

    if (captureFlutterErrors) {
      FlutterError.onError = (FlutterErrorDetails details) {
        _onFlutterError(details);
      };
    }

    if (captureDartErrors) {
      PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
        _onDartError(error, stack);
        return true;
      };
    }

    // Periodic flush
    _flushTimer = Timer.periodic(flushInterval, (_) => flush());

    _initialized = true;
  }

  void _onFlutterError(FlutterErrorDetails details) {
    final error = CapturedError(
      severity: ErrorSeverity.error,
      error: details.exception,
      stackTrace: details.stack,
      context: details.library,
      extra: {
        'context': details.context?.toString(),
        'informationCollector': details.informationCollector?.toString(),
      },
      sessionId: _sessionId,
    );
    _reportToAll(error);
  }

  void _onDartError(Object error, StackTrace stack) {
    final captured = CapturedError(
      severity: ErrorSeverity.fatal,
      error: error,
      stackTrace: stack,
      context: 'Uncaught Dart error',
      sessionId: _sessionId,
    );
    _reportToAll(captured);
  }

  void _reportToAll(CapturedError error) {
    // Store for batching
    _pendingErrors.add(error);
    if (_pendingErrors.length > _maxPendingErrors) {
      _pendingErrors.removeRange(0, _pendingErrors.length - _maxPendingErrors);
    }

    // Report immediately to all reporters
    for (final reporter in _reporters) {
      reporter.report(error).catchError((e) {
        // Don't let reporter errors crash the app
        print('[ErrorReportingManager] Reporter failed: $e');
      });
    }
  }

  /// Reports an error through all registered reporters.
  Future<void> reportError(
    Object error, {
    StackTrace? stackTrace,
    String? context,
    Map<String, dynamic>? extra,
    ErrorSeverity severity = ErrorSeverity.error,
  }) async {
    final captured = CapturedError(
      severity: severity,
      error: error,
      stackTrace: stackTrace,
      context: context,
      extra: extra,
      sessionId: _sessionId,
    );
    _reportToAll(captured);
  }

  /// Reports a message (info/warning).
  Future<void> reportMessage(
    String message, {
    ErrorSeverity severity = ErrorSeverity.info,
    String? context,
    Map<String, dynamic>? extra,
  }) async {
    final captured = CapturedError(
      severity: severity,
      error: message,
      context: context,
      extra: extra,
      sessionId: _sessionId,
    );
    _reportToAll(captured);
  }

  /// Sets user context for all reporters.
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

  /// Sets tags for all reporters.
  Future<void> setTags(Map<String, String> tags) async {
    for (final reporter in _reporters) {
      await reporter.setTags(tags);
    }
  }

  /// Clears user context for all reporters.
  Future<void> clearUserContext() async {
    for (final reporter in _reporters) {
      await reporter.clearUserContext();
    }
  }

  /// Flushes all reporters.
  Future<void> flush() async {
    for (final reporter in _reporters) {
      await reporter.flush();
    }
  }

  /// Gets all pending errors (for manual inspection/export).
  List<CapturedError> getPendingErrors() => List.unmodifiable(_pendingErrors);

  /// Clears pending errors.
  void clearPendingErrors() => _pendingErrors.clear();

  /// Shuts down all reporters.
  Future<void> shutdown() async {
    _flushTimer?.cancel();
    for (final reporter in _reporters) {
      await reporter.close();
    }
    _reporters.clear();
    _initialized = false;
  }
}

/// Extension for easy error reporting from anywhere.
extension ErrorReporting on Object {
  /// Reports this object as an error with the given context.
  Future<void> reportAsError({
    StackTrace? stackTrace,
    String? context,
    Map<String, dynamic>? extra,
    ErrorSeverity severity = ErrorSeverity.error,
  }) async {
    await ErrorReportingManager.instance.reportError(
      this,
      stackTrace: stackTrace,
      context: context,
      extra: extra,
      severity: severity,
    );
  }
}

/// Zone-based error catching for running code with automatic error reporting.
Future<T> runWithErrorReporting<T>(
  FutureOr<T> Function() body, {
  String? context,
  Map<String, dynamic>? extra,
  ErrorSeverity severity = ErrorSeverity.error,
}) async {
  try {
    return await body();
  } catch (error, stackTrace) {
    await ErrorReportingManager.instance.reportError(
      error,
      stackTrace: stackTrace,
      context: context,
      extra: extra,
      severity: severity,
    );
    rethrow;
  }
}

/// Synchronous version.
T runSyncWithErrorReporting<T>(
  T Function() body, {
  String? context,
  Map<String, dynamic>? extra,
  ErrorSeverity severity = ErrorSeverity.error,
}) {
  try {
    return body();
  } catch (error, stackTrace) {
    ErrorReportingManager.instance.reportError(
      error,
      stackTrace: stackTrace,
      context: context,
      extra: extra,
      severity: severity,
    );
    rethrow;
  }
}