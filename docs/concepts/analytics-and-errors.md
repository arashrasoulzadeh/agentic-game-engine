# Analytics and error reporting

Two separate, optional systems. Neither does anything until you register a **provider** or
**reporter**, and nothing is sent anywhere by default.

Samples are executed by `packages/engine_flutter/test/doc_examples_error_reporting_test.dart` and
`packages/engine_core/test/analytics_test.dart`.

## Analytics (`engine_core`)

`AnalyticsManager.instance` fans events out to your `AnalyticsProvider`s.

```dart
await AnalyticsManager.instance.initialize(
  providers: [ConsoleAnalyticsProvider()],      // prints; write your own for a real backend
  flushInterval: const Duration(minutes: 5),
);

final analytics = AnalyticsManager.instance;
await analytics.logLevelStart('1-1');
await analytics.logLevelComplete('1-1', score: 1200, stars: 3, time: const Duration(seconds: 94));
await analytics.log('boss_defeated', {'boss': 'warden'});
await analytics.logScreenView('main_menu');
```

- `initialize` runs each provider's `initialize`, starts a session id, and logs `session_start`.
  A second call is ignored.
- Helpers (`logLevelStart/Complete/Fail`, `logAchievement`, `logPurchase`) just call `log` with
  conventional names from `AnalyticsEvents`.
- Events are also kept in a capped in-memory queue (1000) for debugging: `getQueuedEvents()`. It is
  **not** a persistent offline queue; a restart loses it.
- `onPause` / `onResume` (call them from your app lifecycle) stop and restart recording; events
  logged while paused are dropped.
- A provider that throws is reported to the console and does not affect the others.

### Respect the player's choice

```dart
analytics.setConsent(false);   // nothing is queued or sent; anything queued is discarded
analytics.setConsent(true);    // resume
analytics.hasConsent;
```

Consent defaults to **on**, since analytics only acts once you register a provider. A game that must
ask first calls `setConsent(false)` before `initialize` and `setConsent(true)` when the player
agrees. Keep personal data out of event payloads and `userId`; payloads go to every provider.

## Error reporting (`engine_flutter`)

`ErrorReportingManager.instance` sends errors to your `ErrorReporter`s. Bundled reporters:
`ConsoleErrorReporter`, `NoOpErrorReporter`, `SentryErrorReporter` (posts to Sentry's HTTP API),
`CustomHttpReporter` (posts JSON to your endpoint) and `MultiErrorReporter` (fans out to several).

!!! warning "`FirebaseCrashlyticsReporter` and `GooglePlayReporter` are placeholders"
    They have the right shape but their bodies are commented-out sketches: they do not call
    Firebase or Google Play, because the engine does not depend on those SDKs. Use them as a
    template (call `FirebaseCrashlytics.instance.recordError` from your own `ErrorReporter`
    subclass) rather than expecting reports to arrive.

```dart
await ErrorReportingManager.instance.initialize(
  reporters: [ConsoleErrorReporter()],
  captureFlutterErrors: true,     // FlutterError.onError
  captureDartErrors: true,        // PlatformDispatcher.onError (uncaught async errors, as fatal)
);

final errors = ErrorReportingManager.instance;
await errors.setUserContext(userId: 'player-42');     // an opaque id, not an email, if you can
await errors.setTags({'build': 'release'});

await errors.reportError(StateError('boom'), context: 'loading level', severity: ErrorSeverity.warning);
await 'low on memory'.reportAsError(severity: ErrorSeverity.info);

await runWithErrorReporting(() => saveGame(), context: 'save');   // reports, then rethrows
```

- Severities: `info`, `warning`, `error`, `fatal`.
- Each report carries a timestamp, session id, and `platform` (`android`, `ios`, `web`, ...). The
  platform name works on the web; it deliberately does not use `dart:io`.
- A reporter that fails is caught and logged, so reporting can never crash the game.
- The last 100 errors are kept in memory (`getPendingErrors()`) for a "send logs" button.
- `initialize` replaces `FlutterError.onError` and `PlatformDispatcher.onError` when asked to. In
  tests pass `false` for both, as the sample does.

## Privacy checklist

- Ask before enabling analytics where required, and wire the answer to `setConsent`.
- Do not put names, emails or free text in event payloads or error `extra`.
- Stack traces can contain file paths and sometimes data; scrub in a custom reporter if that matters.
