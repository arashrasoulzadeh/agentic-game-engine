/// Schedules the "your generators are full" reminder. The engine only defines the contract; a game wires
/// a platform notification plugin (kept out of the engine so it stays web-safe and testable).
abstract class ReturnNotifier {
  /// Shows [message] after [delay] unless cancelled first. Replaces any reminder already scheduled.
  void schedule(Duration delay, String message);

  /// Drops the pending reminder, if any.
  void cancel();
}

/// A [ReturnNotifier] that only records what was asked, for tests.
class RecordingNotifier implements ReturnNotifier {
  /// The pending reminder, or null.
  ({Duration delay, String message})? pending;

  @override
  void schedule(Duration delay, String message) =>
      pending = (delay: delay, message: message);

  @override
  void cancel() => pending = null;
}
