import 'dart:io';

import 'package:engine_studio/src/code/completion.dart';
import 'package:engine_studio/src/code/project_symbols.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('completion');
    Directory('${root.path}/lib').createSync();
    File(
      '${root.path}/lib/hero.dart',
    ).writeAsStringSync('class Hero {}\nclass Hellhound {}\n');
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('offers Dart keywords and project names that start with the prefix', () {
    final items = completionsFor('cl', ProjectSymbols.scan(root.path));
    expect(items.map((i) => i.name), contains('class'));
    expect(items.first.kind, 'keyword', reason: 'keywords come first');
  });

  test('project classes are offered for a capital-letter prefix', () {
    final names = completionsFor(
      'He',
      ProjectSymbols.scan(root.path),
    ).map((i) => i.name);
    expect(names, containsAll(['Hero', 'Hellhound']));
  });

  test('no prefix means no suggestions, and no name is offered twice', () {
    final symbols = ProjectSymbols.scan(root.path);
    expect(completionsFor('', symbols), isEmpty);
    final names = completionsFor('c', symbols).map((i) => i.name).toList();
    expect(names.toSet().length, names.length);
  });

  test('an item with no explicit label displays its insert text', () {
    final item = CompletionItem('jump', 'method');
    expect(item.label, 'jump');
  });

  test('an explicit label (e.g. with parameters) is kept as given', () {
    final item = CompletionItem('jump', 'method', label: 'jump(double dy)');
    expect(item.label, 'jump(double dy)');
    expect(item.name, 'jump', reason: 'insert text stays just the name');
  });

  test('every completion kind has its own icon, not a shared fallback', () {
    const kinds = [
      'keyword',
      'method',
      'function',
      'constructor',
      'field',
      'property',
      'variable',
      'class',
      'interface',
      'module',
      'enum',
      'constant',
      'atlas',
      'entity',
      'component',
    ];
    final icons = kinds.map(iconForCompletionKind).toSet();
    expect(icons.length, kinds.length);
  });

  test('an unrecognised kind falls back to a plain icon', () {
    expect(iconForCompletionKind('something-new'), Icons.circle_outlined);
  });
}
