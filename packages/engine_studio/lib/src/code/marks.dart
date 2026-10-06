import 'dart_highlighter.dart';

/// A stretch of text to underline: from [start] up to [end] (offsets into the text),
/// as an error or a warning.
class TextMark {
  final int start;
  final int end;
  final bool isError;

  const TextMark(this.start, this.end, {required this.isError});
}

/// One run of text with its colour kind and whether it is underlined.
class StyledRun {
  final String text;
  final DartTokenKind kind;
  final TextMark? mark;

  const StyledRun(this.text, this.kind, this.mark);
}

/// Splits highlighted [tokens] further at every mark boundary, so each run is wholly
/// inside or wholly outside a mark. The runs' texts still rebuild the source exactly.
List<StyledRun> applyMarks(List<DartToken> tokens, List<TextMark> marks) {
  final runs = <StyledRun>[];
  var offset = 0;
  for (final token in tokens) {
    var start = offset;
    final end = offset + token.text.length;
    while (start < end) {
      final mark = _markAt(marks, start);
      final boundary = _nextBoundary(marks, start, end);
      runs.add(
        StyledRun(
          token.text.substring(start - offset, boundary - offset),
          token.kind,
          mark,
        ),
      );
      start = boundary;
    }
    offset = end;
  }
  return runs;
}

TextMark? _markAt(List<TextMark> marks, int at) {
  for (final mark in marks) {
    if (at >= mark.start && at < mark.end) return mark;
  }
  return null;
}

/// The next position after [from] where the mark state changes, capped at [end].
int _nextBoundary(List<TextMark> marks, int from, int end) {
  var next = end;
  for (final mark in marks) {
    if (mark.start > from && mark.start < next) next = mark.start;
    if (mark.end > from && mark.end < next) next = mark.end;
  }
  return next;
}
