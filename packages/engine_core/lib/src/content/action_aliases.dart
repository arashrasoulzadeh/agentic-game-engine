/// Friendly display names for logical input actions ("Jump" for
/// `action_0`), so remap menus and the debug overlay show something a
/// player can read.
///
/// Plain data like the rest of the content layer: it round-trips through
/// JSON and lives in `engine_core` so any genre or tool can use it. It only
/// changes how an action is *labelled* -- the action id stays what systems
/// read, so renaming a label can never break gameplay input or saved
/// bindings.
class ActionAliases {
  final Map<String, String> _labels;

  ActionAliases([Map<String, String>? labels]) : _labels = {...?labels};

  /// The label for [action]: the alias if one is set, otherwise a readable
  /// form of the id itself (`move_left` -> `Move Left`, `action_0` ->
  /// `Action 0`) -- so an unaliased action never shows a raw identifier.
  String labelFor(String action) => _labels[action] ?? prettify(action);

  bool hasAlias(String action) => _labels.containsKey(action);

  /// Sets or, with an empty/blank [label], clears the alias for [action].
  void set(String action, String label) {
    if (label.trim().isEmpty) {
      _labels.remove(action);
    } else {
      _labels[action] = label;
    }
  }

  Map<String, dynamic> toJson() => Map<String, dynamic>.of(_labels);

  factory ActionAliases.fromJson(Map<String, dynamic> json) =>
      ActionAliases({for (final e in json.entries) e.key: e.value as String});

  /// `move_left`, `moveLeft` and `move-left` all become `Move Left`.
  static String prettify(String id) {
    final spaced = id
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (m) => '${m[1]} ${m[2]}',
        )
        .replaceAll(RegExp(r'[_\-]+'), ' ')
        .trim();
    if (spaced.isEmpty) return id;
    return spaced
        .split(RegExp(r'\s+'))
        .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}
