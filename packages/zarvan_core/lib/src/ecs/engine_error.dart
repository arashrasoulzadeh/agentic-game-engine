/// An engine exception an agent can act on without parsing prose: a stable
/// [code], the human [message], and the pieces that locate the fault.
///
/// The human message stays the source of truth for people; [toJson] is for
/// tools and agents (the operation layer copies it into an error's `details`).
abstract interface class EngineError implements Exception {
  /// Stable machine name, e.g. `patch_invalid`. Safe to branch on.
  String get code;

  /// The same text `toString()` shows after the class name.
  String get message;

  /// `{code, message, ...}` plus whatever locates the fault (`entity`,
  /// `component`, `problems`). Only JSON-encodable values.
  Map<String, Object?> toJson();
}

/// One located fault: where in a patch or level, and what is wrong there.
class ErrorProblem {
  /// Where, e.g. `entities[2].components.position`.
  final String path;

  /// What is wrong, with enough detail (and any `did you mean`) to fix it.
  final String message;

  const ErrorProblem(this.path, this.message);

  Map<String, String> toJson() => {'path': path, 'message': message};

  @override
  String toString() => ' - $path: $message';
}
