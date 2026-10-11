import 'dart_highlighter.dart';

const _closeFor = {'(': ')', '[': ']', '{': '}'};
const _openFor = {')': '(', ']': '[', '}': '{'};

/// The bracket at or just before [cursor] in [text] and the offset of the one
/// it pairs with, as `(at, pair)` — or null when there is no bracket there or
/// its pair can't be found (unbalanced code). Brackets inside a string or
/// comment are never matched, so `'('` in a string doesn't pair with real code.
(int at, int pair)? matchingBracket(String text, int cursor) {
  final mask = _codeMask(text);
  for (final offset in [cursor, cursor - 1]) {
    if (offset < 0 || offset >= text.length || !mask[offset]) continue;
    final char = text[offset];
    if (_closeFor.containsKey(char)) {
      final pair = _scanForward(text, mask, offset, char, _closeFor[char]!);
      if (pair != null) return (offset, pair);
    }
    if (_openFor.containsKey(char)) {
      final pair = _scanBackward(text, mask, offset, char, _openFor[char]!);
      if (pair != null) return (offset, pair);
    }
  }
  return null;
}

int? _scanForward(
  String text,
  List<bool> mask,
  int start,
  String open,
  String close,
) {
  var depth = 0;
  for (var i = start; i < text.length; i++) {
    if (!mask[i]) continue;
    if (text[i] == open) depth++;
    if (text[i] == close) {
      depth--;
      if (depth == 0) return i;
    }
  }
  return null;
}

int? _scanBackward(
  String text,
  List<bool> mask,
  int start,
  String close,
  String open,
) {
  var depth = 0;
  for (var i = start; i >= 0; i--) {
    if (!mask[i]) continue;
    if (text[i] == close) depth++;
    if (text[i] == open) {
      depth--;
      if (depth == 0) return i;
    }
  }
  return null;
}

/// Which offsets are real code, as opposed to inside a string or a comment,
/// so a bracket character typed inside either is never treated as a real one.
List<bool> _codeMask(String text) {
  final mask = List<bool>.filled(text.length, true);
  var offset = 0;
  for (final token in tokenizeDart(text)) {
    final isCode =
        token.kind != DartTokenKind.comment &&
        token.kind != DartTokenKind.string;
    for (var i = offset; i < offset + token.text.length; i++) {
      mask[i] = isCode;
    }
    offset += token.text.length;
  }
  return mask;
}
