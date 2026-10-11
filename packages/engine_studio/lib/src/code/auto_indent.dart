const _opens = '{[(';
const _closerFor = {'{': '}', '[': ']', '(': ')'};

/// What pressing Enter at [cursor] in [text] should produce: the resulting
/// full text and where the cursor lands in it. The new line matches the
/// current line's leading whitespace; it gets one more level of [indentUnit]
/// when the cursor sits right after an opening bracket, and — when the very
/// next character closes that same bracket — the closer is pushed onto its
/// own line at the original indent, splitting an empty `{}` into three lines
/// the way an IDE does.
(String text, int cursor) indentedNewline(
  String text,
  int cursor, {
  String indentUnit = '  ',
}) {
  final lineStart = text.lastIndexOf('\n', cursor - 1) + 1;
  final currentLine = text.substring(lineStart, cursor);
  final leading = RegExp(r'^[ \t]*').firstMatch(currentLine)!.group(0)!;

  final before = text.substring(0, cursor).trimRight();
  final opensBlock =
      before.isNotEmpty && _opens.contains(before[before.length - 1]);
  final afterChar = cursor < text.length ? text[cursor] : '';
  final closesHere =
      opensBlock && afterChar == _closerFor[before[before.length - 1]];

  final indent = leading + (opensBlock ? indentUnit : '');
  if (closesHere) {
    final inserted = '\n$indent\n$leading';
    return (
      text.replaceRange(cursor, cursor, inserted),
      cursor + 1 + indent.length,
    );
  }
  final inserted = '\n$indent';
  return (text.replaceRange(cursor, cursor, inserted), cursor + inserted.length);
}
