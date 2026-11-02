/// Collects warnings about things that are legal but usually mistakes, so they
/// can be shown during development without changing what the engine does.
///
/// Enabled only in debug builds (when asserts are on) by default, and then
/// costs nothing in release. Warnings are collected, not printed: read
/// [messages], show them in the debug overlay, or hook [onWarning] to log.
class DevWarnings {
  /// Whether warnings are recorded. Defaults to true only when asserts are
  /// enabled; set it explicitly to force on or off.
  bool enabled = _assertsOn();

  /// Called for each new warning when [enabled].
  void Function(String message)? onWarning;

  final List<String> _messages = [];
  static const _cap = 100;

  /// Recorded warnings, oldest first; the oldest are dropped past 100.
  List<String> get messages => List.unmodifiable(_messages);

  /// Records [message] if [enabled]. Repeats of the last message are skipped
  /// so a warning in a per-frame path doesn't flood the list.
  void warn(String message) {
    if (!enabled) return;
    if (_messages.isNotEmpty && _messages.last == message) return;
    if (_messages.length >= _cap) _messages.removeAt(0);
    _messages.add(message);
    onWarning?.call(message);
  }

  /// Forgets everything recorded so far.
  void clear() => _messages.clear();

  static bool _assertsOn() {
    var on = false;
    assert(on = true);
    return on;
  }
}
