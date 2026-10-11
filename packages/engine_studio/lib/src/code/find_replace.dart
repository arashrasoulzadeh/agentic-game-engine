/// One occurrence of a search query in text, as offsets into it.
class TextMatch {
  final int start;
  final int end;

  const TextMatch(this.start, this.end);

  @override
  bool operator ==(Object other) =>
      other is TextMatch && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// Every non-overlapping occurrence of [query] in [text], left to right. An
/// empty query has no matches.
List<TextMatch> findMatches(
  String text,
  String query, {
  bool caseSensitive = false,
}) {
  if (query.isEmpty) return const [];
  final haystack = caseSensitive ? text : text.toLowerCase();
  final needle = caseSensitive ? query : query.toLowerCase();
  final matches = <TextMatch>[];
  var start = 0;
  while (true) {
    final index = haystack.indexOf(needle, start);
    if (index < 0) break;
    matches.add(TextMatch(index, index + needle.length));
    start = index + needle.length;
  }
  return matches;
}

/// [text] with every occurrence of [query] replaced by [replacement]. Text
/// with no matches is returned unchanged.
String replaceAllMatches(
  String text,
  String query,
  String replacement, {
  bool caseSensitive = false,
}) {
  final matches = findMatches(text, query, caseSensitive: caseSensitive);
  if (matches.isEmpty) return text;
  final buffer = StringBuffer();
  var last = 0;
  for (final match in matches) {
    buffer.write(text.substring(last, match.start));
    buffer.write(replacement);
    last = match.end;
  }
  buffer.write(text.substring(last));
  return buffer.toString();
}
