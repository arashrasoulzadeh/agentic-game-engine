import 'dart:convert';

import 'package:engine_core/engine_core_ops.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  test('mergeProjectManifest keeps notes and refreshes name/levels/ref', () {
    const pubspec = '''
name: bakery
dependencies:
  engine_core:
    git:
      url: https://example.com/e.git
      path: packages/engine_core
      ref: v0.1.0
''';
    final m = mergeProjectManifest(
      pubspecText: pubspec,
      levels: ['assets/levels/a.json'],
      existing: {'notes': 'keep me', 'name': 'old'},
    );
    expect(m['name'], 'bakery');
    expect(m['engineVersion'], 'v0.1.0');
    expect(m['levels'], ['assets/levels/a.json']);
    expect(m['notes'], 'keep me');
  });

  test('project.manifest writes project.json and keeps notes', () async {
    final s = await Scratch.create();
    final first = await s.map('project.manifest');
    expect(first['name'], 'ops_demo');
    expect(first['created'], isTrue);
    expect(first['levels'], isA<List>());
    expect(s.read('project.json'), contains('"name": "ops_demo"'));

    s.write('project.json', '{"notes": "hand", "name": "x"}\n');
    final again = await s.map('project.manifest');
    expect(again['created'], isFalse);
    final back = jsonDecode(s.read('project.json')) as Map;
    expect(back['notes'], 'hand');
    expect(back['name'], 'ops_demo');
  });
}
