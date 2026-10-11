import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'marks.dart';

/// What a run of Dart source is, for colouring.
enum DartTokenKind { comment, string, number, keyword, type, plain }

/// A run of source text and what it is.
class DartToken {
  final String text;
  final DartTokenKind kind;

  const DartToken(this.text, this.kind);
}

/// Dart's reserved and built-in words. Also offered by completion.
const dartKeywords = {
  'abstract',
  'as',
  'assert',
  'async',
  'await',
  'base',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'default',
  'do',
  'dynamic',
  'else',
  'enum',
  'export',
  'extends',
  'extension',
  'external',
  'factory',
  'false',
  'final',
  'finally',
  'for',
  'Function',
  'if',
  'implements',
  'import',
  'in',
  'interface',
  'is',
  'late',
  'library',
  'mixin',
  'new',
  'null',
  'on',
  'part',
  'required',
  'rethrow',
  'return',
  'sealed',
  'set',
  'static',
  'super',
  'switch',
  'this',
  'throw',
  'true',
  'try',
  'typedef',
  'var',
  'void',
  'when',
  'while',
  'with',
  'yield',
};

/// One alternative per token kind. The order matters: a comment must be matched
/// before the `/` operator, and a string before any identifier inside it.
final _pattern = RegExp(
  r"""//[^\n]*|/\*[\s\S]*?\*/|'(?:\\.|[^'\\\n])*'|"(?:\\.|[^"\\\n])*"|\b\d[\d_]*(?:\.\d+)?\b|\b[A-Za-z_]\w*\b""",
);

/// Splits Dart [source] into coloured tokens. Plain text between matches is kept
/// as plain tokens, so concatenating the token texts gives back [source] exactly.
List<DartToken> tokenizeDart(String source) {
  final tokens = <DartToken>[];
  var at = 0;
  for (final match in _pattern.allMatches(source)) {
    if (match.start > at) {
      tokens.add(
        DartToken(source.substring(at, match.start), DartTokenKind.plain),
      );
    }
    tokens.add(DartToken(match.group(0)!, _kindOf(match.group(0)!)));
    at = match.end;
  }
  if (at < source.length) {
    tokens.add(DartToken(source.substring(at), DartTokenKind.plain));
  }
  return tokens;
}

DartTokenKind _kindOf(String text) {
  if (text.startsWith('//') || text.startsWith('/*')) {
    return DartTokenKind.comment;
  }
  if (text.startsWith("'") || text.startsWith('"')) {
    return DartTokenKind.string;
  }
  if (RegExp(r'^\d').hasMatch(text)) return DartTokenKind.number;
  if (dartKeywords.contains(text)) return DartTokenKind.keyword;
  if (RegExp(r'^[A-Z]').hasMatch(text)) return DartTokenKind.type;
  return DartTokenKind.plain;
}

/// Colours for each token kind, chosen to read on both light and dark themes.
const dartPalette = <DartTokenKind, Color?>{
  DartTokenKind.comment: Color(0xFF6A9955),
  DartTokenKind.string: Color(0xFFCE9178),
  DartTokenKind.number: Color(0xFFB5CEA8),
  DartTokenKind.keyword: Color(0xFF569CD6),
  DartTokenKind.type: Color(0xFF4EC9B0),
  DartTokenKind.plain: null,
};

/// A text controller that colours Dart as it is typed. It only changes how the text
/// is shown; the text itself, and what gets saved, are untouched.
class DartHighlightController extends TextEditingController {
  DartHighlightController({super.text});

  List<TextMark> _marks = const [];
  List<TextMark> _searchMarks = const [];

  /// The stretches to underline as errors or warnings. Setting them redraws the
  /// text. A value equal to the current one is ignored: both this and
  /// [searchMarks] are set from this controller's own text-changed listener, and
  /// notifying on every call (even a no-op one) would re-trigger that listener
  /// and recurse forever — caught as a `StackOverflowError` that froze the editor.
  set marks(List<TextMark> value) {
    if (listEquals(_marks, value)) return;
    _marks = value;
    notifyListeners();
  }

  /// The find/replace matches to highlight. Setting them redraws the text. See
  /// [marks] for why an unchanged value is ignored rather than always notifying.
  set searchMarks(List<TextMark> value) {
    if (listEquals(_searchMarks, value)) return;
    _searchMarks = value;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    return TextSpan(
      style: style,
      children: [
        for (final run in applyMarks(tokenizeDart(text), [
          ..._marks,
          ..._searchMarks,
        ]))
          TextSpan(text: run.text, style: _styleFor(run)),
      ],
    );
  }

  /// The colour of a run, plus a wavy underline for an error/warning or a
  /// background highlight for a search match.
  TextStyle? _styleFor(StyledRun run) {
    final colour = dartPalette[run.kind];
    final mark = run.mark;
    if (colour == null && mark == null) return null;
    switch (mark?.kind) {
      case MarkKind.error:
        return TextStyle(
          color: colour,
          decoration: TextDecoration.underline,
          decorationStyle: TextDecorationStyle.wavy,
          decorationColor: const Color(0xFFF14C4C),
        );
      case MarkKind.warning:
        return TextStyle(
          color: colour,
          decoration: TextDecoration.underline,
          decorationStyle: TextDecorationStyle.wavy,
          decorationColor: const Color(0xFFCCA700),
        );
      case MarkKind.searchMatch:
        return TextStyle(color: colour, backgroundColor: const Color(0x66FFA500));
      case MarkKind.currentMatch:
        return TextStyle(color: colour, backgroundColor: const Color(0xAAFFA500));
      case null:
        return TextStyle(color: colour);
    }
  }
}
