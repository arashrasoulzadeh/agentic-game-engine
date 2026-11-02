/// The entry of [candidates] closest to [input] when it is plausibly a typo of
/// it, otherwise null. Case is ignored. "Plausibly" means within two edits, or
/// a third of the input's length for long names, so `positon` finds
/// `position` but `zzz` finds nothing.
String? closestMatch(String input, Iterable<String> candidates) {
  final lower = input.toLowerCase();
  final limit = lower.length >= 9 ? lower.length ~/ 3 : 2;
  String? best;
  var bestDistance = limit + 1;
  for (final candidate in candidates) {
    final distance = _editDistance(lower, candidate.toLowerCase());
    if (distance < bestDistance) {
      bestDistance = distance;
      best = candidate;
    }
  }
  return best;
}

/// ` (did you mean "x"?)` for the closest [candidates] entry, or an empty
/// string, ready to append to an error message.
String didYouMean(String input, Iterable<String> candidates) {
  final match = closestMatch(input, candidates);
  return match == null ? '' : ' (did you mean "$match"?)';
}

int _editDistance(String a, String b) {
  if (a == b) return 0;
  var previous = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final current = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      final best = [
        previous[j] + 1,
        current[j - 1] + 1,
        previous[j - 1] + cost,
      ].reduce((x, y) => x < y ? x : y);
      current[j] = best;
    }
    previous = current;
  }
  return previous[b.length];
}
