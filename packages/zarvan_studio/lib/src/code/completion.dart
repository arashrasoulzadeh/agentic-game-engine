import 'package:flutter/material.dart';

import 'dart_highlighter.dart';
import 'project_symbols.dart';

/// One suggestion: the text to insert ([name]), what kind of name it is, what to
/// show for it ([label], such as `jump()` for a method whose [name] is just
/// `jump`), and an optional [detail] (a type signature or short description)
/// shown alongside it, the way an IDE completion list does.
class CompletionItem {
  final String name;
  final String kind;
  final String label;
  final String? detail;

  CompletionItem(this.name, this.kind, {String? label, this.detail})
    : label = label ?? name;
}

/// The icon shown for a completion of [kind], so the list reads at a glance the
/// way an IDE's does: a different glyph for a method than for a class.
IconData iconForCompletionKind(String kind) => switch (kind) {
  'keyword' => Icons.key_outlined,
  'method' => Icons.functions,
  'function' => Icons.bolt,
  'constructor' => Icons.add_box_outlined,
  'field' => Icons.short_text,
  'property' => Icons.tune,
  'variable' => Icons.data_object,
  'class' => Icons.class_,
  'interface' => Icons.layers_outlined,
  'module' => Icons.inventory_2_outlined,
  'enum' => Icons.list_alt,
  'constant' => Icons.push_pin_outlined,
  'atlas' => Icons.image_outlined,
  'entity' => Icons.smart_toy_outlined,
  'component' => Icons.extension_outlined,
  _ => Icons.circle_outlined,
};

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
