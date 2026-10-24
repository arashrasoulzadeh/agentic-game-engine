import 'package:test/test.dart';

import 'support.dart';

void main() {
  test(
    'a project with a broken level lists it with a file and severity',
    () async {
      final s = await Scratch.create();
      final r = await s.map('project.problems');
      expect(r['ok'], isFalse);
      final problems = (r['problems']! as List).cast<Map>();
      expect(
        problems.where((p) => p['file'] == 'assets/levels/broken.json'),
        isNotEmpty,
      );
      expect(
        problems.every(
          (p) => p['severity'] == 'error' || p['severity'] == 'warning',
        ),
        isTrue,
      );
      expect(
        problems.where((p) => p['file'] == 'assets/levels/level1.json'),
        isEmpty,
      );
    },
  );

  test('graph and idle problems are included; a clean project is ok', () async {
    final s = await Scratch.create();
    s.write('assets/levels/broken.json', '{"entities": []}');
    s.write(
      'graphs/graph1.json',
      '{"graph": {"nodes": [{"id": "a", "kind": "say"}], "edges": [], "entryNodeId": "a"}}',
    );
    final clean = await s.map('project.problems');
    expect(clean['ok'], isTrue, reason: '${clean['problems']}');

    await s.data('graph.create', {'path': 'graphs/g.json'});
    await s.data('graph.add_node', {'path': 'graphs/g.json', 'kind': 'say'});
    await s.data('graph.add_node', {'path': 'graphs/g.json', 'kind': 'say'});
    final withGraph = (await s.map('project.problems'))['problems']! as List;
    expect(
      withGraph.map((p) => (p as Map)['file']),
      contains('graphs/g.json'),
      reason: 'say1 is unreachable',
    );

    s.write('assets/idle_game.json', '{"generators": 5}');
    final withIdle = (await s.map('project.problems'))['problems']! as List;
    expect(
      withIdle.map((p) => (p as Map)['file']),
      contains('assets/idle_game.json'),
    );
  });

  test('unreadable graph files are reported, not thrown', () async {
    final s = await Scratch.create();
    s.write('graphs/junk.json', 'not json');
    final problems = ((await s.map('project.problems'))['problems']! as List)
        .cast<Map>();
    expect(
      problems.where((p) => p['file'] == 'graphs/junk.json').single['message'],
      contains('not a graph file'),
    );
  });
}
