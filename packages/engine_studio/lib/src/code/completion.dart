import 'dart_highlighter.dart';
import 'project_symbols.dart';

/// One suggestion: the name to insert, and what kind of name it is, for the list.
class CompletionItem {
  final String name;
  final String kind;

  const CompletionItem(this.name, this.kind);
}

/// Suggestions for the word being typed: Dart keywords plus the names the project
/// defines. Keywords come first, then project names, each group sorted. A name
/// appears once even if it is both a keyword and a project name. An empty prefix
/// gives nothing, so the list only appears once something is typed.
List<CompletionItem> completionsFor(String prefix, ProjectSymbols symbols) {
  if (prefix.isEmpty) return const [];
  final seen = <String>{};
  final items = <CompletionItem>[];
  final keywords = dartKeywords.where((k) => k.startsWith(prefix)).toList()
    ..sort();
  for (final keyword in keywords) {
    if (seen.add(keyword)) items.add(CompletionItem(keyword, 'keyword'));
  }
  for (final (name, kind) in symbols.completionsFor(prefix)) {
    if (seen.add(name)) items.add(CompletionItem(name, kind));
  }
  return items;
}
