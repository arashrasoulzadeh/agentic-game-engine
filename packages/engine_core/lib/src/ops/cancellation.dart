import 'result.dart';

/// Symbol key for the [CancellationToken] installed by [OperationRegistry.call]
/// into the current [Zone] (so concurrent calls on one [OpContext] do not share a token).
const Symbol opCancellationZoneKey = #engineOpCancellation;

/// Cooperative cancel for long-running operations. Callers cancel; handlers
/// poll [throwIfCancelled] (or [isCancelled]) between units of work.
class CancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  /// Marks this token cancelled. Idempotent; already-finished handlers that
  /// never poll again are unaffected.
  void cancel() => _cancelled = true;

  /// Throws [OpError] with [ErrorCode.cancelled] when [cancel] has been called.
  void throwIfCancelled() {
    if (_cancelled) {
      throw OpError(
        ErrorCode.cancelled,
        'The operation was cancelled.',
        hint: 'The client sent notifications/cancelled for this request.',
      );
    }
  }
}
