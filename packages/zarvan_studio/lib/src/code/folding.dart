import 'package:flutter/painting.dart';

import '../lsp/dart_session.dart';

/// Offset of the newline that ends [line] (0-based), or the text length for the last line. Returns the
/// text length for a line past the end.
int lineEnd(String text, int line) {
  var at = 0;
  for (var i = 0; i < line; i++) {
    final nl = text.indexOf('\n', at);
    if (nl < 0) return text.length;
    at = nl + 1;
  }
  final nl = text.indexOf('\n', at);
  return nl < 0 ? text.length : nl;
}

/// The character ranges to hide for the folds in [collapsed] (identified by their start line) among
/// [ranges]: from the end of the fold's first line to the end of its last line, so the first line stays and
/// everything below it up to the closing line disappears. Overlapping folds are merged. A fold of one line
/// (nothing to hide) or one that no longer fits the text hides nothing.
List<TextRange> hiddenRangesFor(
  String text,
  Iterable<FoldingRange> ranges,
  Set<int> collapsed,
) {
  final raw = <TextRange>[];
  for (final r in ranges) {
    if (!collapsed.contains(r.startLine) || r.endLine <= r.startLine) continue;
    final start = lineEnd(text, r.startLine);
    final end = lineEnd(text, r.endLine);
    if (end > start) raw.add(TextRange(start: start, end: end));
  }
  raw.sort((a, b) => a.start.compareTo(b.start));
  final merged = <TextRange>[];
  for (final r in raw) {
    if (merged.isNotEmpty && r.start <= merged.last.end) {
      final last = merged.removeLast();
      merged.add(
        TextRange(start: last.start, end: r.end > last.end ? r.end : last.end),
      );
    } else {
      merged.add(r);
    }
  }
  return merged;
}

/// The 0-based lines that are not shown because they sit inside a collapsed fold (every line after a fold's
/// first, up to and including its last). The gutter skips these numbers.
Set<int> hiddenLinesFor(Iterable<FoldingRange> ranges, Set<int> collapsed) => {
  for (final r in ranges)
    if (collapsed.contains(r.startLine))
      for (var l = r.startLine + 1; l <= r.endLine; l++) l,
};

/// Whether [offset] lies inside one of [hidden] (the caret is somewhere the player cannot see).
bool insideHidden(Iterable<TextRange> hidden, int offset) =>
    hidden.any((r) => offset > r.start && offset <= r.end);
