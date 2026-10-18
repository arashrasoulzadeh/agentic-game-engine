/// Parses the text a designer types for a tile brush into rows of tile ids.
///
/// One row per line; cells separated by spaces or commas; `_` (or `.`) means "leave
/// this cell alone" and becomes `TileBrush.skip` (-1). Whole numbers are tile ids; 0
/// erases. Returns the rows, or throws a [FormatException] whose message says which
/// line and token was wrong, because a pattern is typed by hand and the error is the
/// only feedback.
List<List<int>> parseTilePattern(String text) {
  final rows = <List<int>>[];
  final lines = text
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  if (lines.isEmpty) throw const FormatException('the pattern is empty');
  for (var i = 0; i < lines.length; i++) {
    final row = <int>[];
    for (final token
        in lines[i].split(RegExp(r'[\s,]+')).where((t) => t.isNotEmpty)) {
      if (token == '_' || token == '.') {
        row.add(-1);
        continue;
      }
      final id = int.tryParse(token);
      if (id == null || id < 0) {
        throw FormatException(
          'line ${i + 1}: "$token" is not a tile id (a whole number, or _ to skip)',
        );
      }
      row.add(id);
    }
    rows.add(row);
  }
  final width = rows.first.length;
  for (var i = 1; i < rows.length; i++) {
    if (rows[i].length != width) {
      throw FormatException(
        'line ${i + 1} has ${rows[i].length} cells but line 1 has $width',
      );
    }
  }
  return rows;
}
