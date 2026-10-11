const _pairFor = {'(': ')', '[': ']', '{': '}', '"': '"', "'": "'"};
const _closers = {')', ']', '}', '"', "'"};

/// What a single keystroke that just inserted one character should become,
/// the way an IDE auto-closes brackets and quotes: [previous] is the text
/// right before that keystroke, [text] is the text right after it (one
/// character longer), and [cursor] is where the caret landed.
///
/// Returns null when nothing should change (the typed character isn't an
/// opener or closer, or this wasn't a plain single-character insertion — a
/// paste, a rename, or any other programmatic edit leaves a different,
/// multi-character diff and is correctly left alone). Otherwise returns the
/// text an IDE would end up with and where the cursor belongs in it: either
/// a closing partner inserted right after the cursor (typing `(` inserts the
/// matching `)` and leaves the cursor between them), or, when the typed
/// character is a closer that's already sitting right after the cursor (the
/// closing half of a pair just auto-inserted), "typing through" it instead
/// of inserting a duplicate.
(String text, int cursor)? autoCloseResult(
  String previous,
  String text,
  int cursor,
) {
  if (cursor < 1 || cursor > text.length) return null;
  final typed = text[cursor - 1];
  final withoutTyped = text.substring(0, cursor - 1) + text.substring(cursor);
  if (withoutTyped != previous) return null;

  if (_closers.contains(typed) && cursor < text.length && text[cursor] == typed) {
    return (withoutTyped, cursor);
  }
  final closer = _pairFor[typed];
  if (closer == null) return null;
  final updated = text.substring(0, cursor) + closer + text.substring(cursor);
  return (updated, cursor);
}
