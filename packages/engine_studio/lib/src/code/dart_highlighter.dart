import 'package:flutter/material.dart';

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

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    return TextSpan(
      style: style,
      children: [
        for (final token in tokenizeDart(text))
          TextSpan(
            text: token.text,
            style: dartPalette[token.kind] == null
                ? null
                : TextStyle(color: dartPalette[token.kind]),
          ),
      ],
    );
  }
}
