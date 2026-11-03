/// A text edit from the language server: replace the text between two positions
/// (0-based line and character) with [newText].
class TextEdit {
  final int startLine;
  final int startCharacter;
  final int endLine;
  final int endCharacter;
  final String newText;

  const TextEdit(
    this.startLine,
    this.startCharacter,
    this.endLine,
    this.endCharacter,
    this.newText,
  );
}

/// Applies [edits] to [text]. The server sends edits that do not overlap and refer
/// to the original text, so they are applied from the end backwards, which keeps
/// earlier positions valid.
String applyEdits(String text, List<TextEdit> edits) {
  final starts = _lineStarts(text);
  final ordered = [...edits]
    ..sort((a, b) {
      final byLine = b.startLine.compareTo(a.startLine);
      return byLine != 0
          ? byLine
          : b.startCharacter.compareTo(a.startCharacter);
    });
  var result = text;
  for (final edit in ordered) {
    final start = _offsetOf(
      starts,
      edit.startLine,
      edit.startCharacter,
      text.length,
    );
    final end = _offsetOf(starts, edit.endLine, edit.endCharacter, text.length);
    result = result.replaceRange(start, end, edit.newText);
  }
  return result;
}

List<int> _lineStarts(String text) {
  final starts = [0];
  for (var i = 0; i < text.length; i++) {
    if (text.codeUnitAt(i) == 10) starts.add(i + 1);
  }
  return starts;
}

int _offsetOf(List<int> starts, int line, int character, int length) {
  if (line >= starts.length) return length;
  final offset = starts[line] + character;
  return offset > length ? length : offset;
}

/// Splits a rename's grouped edits into the current file's new text (ready to put
/// in the open buffer) and the other files' edits (to write to disk after review).
/// [currentPath] not being in [grouped] is fine: the symbol may not appear there.
class RenamePlan {
  final String? currentFileText;
  final Map<String, List<TextEdit>> otherFiles;

  const RenamePlan({required this.currentFileText, required this.otherFiles});
}

RenamePlan planRename(
  Map<String, List<TextEdit>> grouped,
  String currentPath,
  String currentText,
) {
  final currentEdits = grouped[currentPath];
  final others = {
    for (final e in grouped.entries)
      if (e.key != currentPath) e.key: e.value,
  };
  return RenamePlan(
    currentFileText: currentEdits == null
        ? null
        : applyEdits(currentText, currentEdits),
    otherFiles: others,
  );
}
