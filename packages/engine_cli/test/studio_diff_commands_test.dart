import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'support/run_studio.dart';

Directory _dir() {
  final d = Directory.systemTemp.createTempSync('studio_diff');
  addTearDown(() => d.deleteSync(recursive: true));
  return d;
}

String _level(Directory d, String name, List<Map<String, dynamic>> entities) {
  final f = File('${d.path}/$name.json')
    ..writeAsStringSync(jsonEncode({'entities': entities}));
  return f.path;
}

Map<String, dynamic> _ent(String name, num x, {num hp = 5}) => {
  'name': name,
  'components': {
    'position': {'x': x, 'y': 0},
    'health': {'current': hp, 'max': 5},
  },
};

List<dynamic> _entities(String path) =>
    (jsonDecode(File(path).readAsStringSync()) as Map)['entities'] as List;

void main() {
  group('studio diff', () {
    test(
      'exits 0 for equal levels and for differing ones, unless --exit-code',
      () async {
        final d = _dir();
        final a = _level(d, 'a', [_ent('p', 1)]);
        final b = _level(d, 'b', [_ent('p', 2)]);
        expect(await runStudio(['diff', a, a, '--exit-code']), 0);
        expect(await runStudio(['diff', a, b]), 0);
        expect(await runStudio(['diff', a, b, '--exit-code']), 1);
        expect(await runStudio(['diff', a, b, '--json']), 0);
      },
    );

    test('a missing or unloadable file is an error', () async {
      final d = _dir();
      final a = _level(d, 'a', []);
      expect(await runStudio(['diff', a, '${d.path}/nope.json']), 1);
      File('${d.path}/bad.json').writeAsStringSync('{ not json');
      expect(await runStudio(['diff', a, '${d.path}/bad.json']), 1);
    });
  });

  group('studio merge', () {
    test(
      'merges non-conflicting edits into the "ours" file and exits 0',
      () async {
        final d = _dir();
        final base = _level(d, 'base', [_ent('p', 1), _ent('q', 1)]);
        final ours = _level(d, 'ours', [_ent('p', 2), _ent('q', 1)]);
        final theirs = _level(d, 'theirs', [_ent('p', 1), _ent('q', 1, hp: 3)]);
        expect(await runStudio(['merge', base, ours, theirs]), 0);
        final merged = _entities(ours);
        final p = merged.firstWhere((e) => e['name'] == 'p');
        final q = merged.firstWhere((e) => e['name'] == 'q');
        expect(p['components']['position']['x'], 2);
        expect(q['components']['health']['current'], 3);
      },
    );

    test(
      'a conflict exits 1 but still writes the merge (ours kept there)',
      () async {
        final d = _dir();
        final base = _level(d, 'base', [_ent('p', 1)]);
        final ours = _level(d, 'ours', [_ent('p', 2)]);
        final theirs = _level(d, 'theirs', [_ent('p', 3)]);
        expect(await runStudio(['merge', base, ours, theirs]), 1);
        expect(_entities(ours).single['components']['position']['x'], 2);
      },
    );

    test('--out leaves the inputs alone', () async {
      final d = _dir();
      final base = _level(d, 'base', [_ent('p', 1)]);
      final ours = _level(d, 'ours', [_ent('p', 1)]);
      final theirs = _level(d, 'theirs', [_ent('p', 9)]);
      final out = '${d.path}/out.json';
      expect(await runStudio(['merge', base, ours, theirs, '--out', out]), 0);
      expect(_entities(out).single['components']['position']['x'], 9);
      expect(_entities(ours).single['components']['position']['x'], 1);
    });

    test('wrong argument counts are usage errors', () async {
      final d = _dir();
      final a = _level(d, 'a', []);
      await expectLater(runStudio(['merge', a, a]), throwsA(anything));
      await expectLater(runStudio(['diff', a]), throwsA(anything));
    });
  });
}
