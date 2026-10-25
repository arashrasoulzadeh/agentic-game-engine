import 'package:engine_core/engine_core.dart';
import 'package:engine_idle/engine_idle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

BigNumber n(String s) => BigNumber.parse(s);

void main() {
  test('HttpCloudSaveStore round-trips through injected transport', () async {
    String? remote;
    final cloud = HttpCloudSaveStore(
      uri: Uri.parse('https://example.test/save'),
      getBody: (_) async => remote,
      putBody: (_, body) async => remote = body,
    );
    expect(await cloud.fetch(), isNull);
    await cloud.push({
      'lastActiveAt': '2026-01-01T00:00:00.000Z',
      'world': {'entities': []},
    });
    final fetched = await cloud.fetch();
    expect(fetched!['lastActiveAt'], '2026-01-01T00:00:00.000Z');
  });

  testWidgets('nameKey resolves through IdleController.strings', (tester) async {
    final w = World(width: 10, height: 10);
    registerCoreComponents(w);
    registerIdleComponents(w);
    w.storeOf<BigTreasury>().set(
      w.spawn(),
      BigTreasury(amounts: {'coins': n('100')}),
    );
    w.storeOf<IdleModifiers>().set(w.spawn(), IdleModifiers());
    w.storeOf<IdleStats>().set(w.spawn(), IdleStats());
    w.storeOf<Generator>().set(
      w.spawn(),
      Generator(
        id: 'cursor',
        name: 'Cursor',
        nameKey: 'gen.cursor',
        cost: GeometricCost(base: n('10'), growth: 1.1),
        output: {'coins': n('1')},
      ),
    );
    final c = IdleController(
      world: w,
      strings: StringTable.fromFlatLocale({'gen.cursor': 'Zeiger'}),
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: GeneratorList(controller: c))),
    );
    expect(find.text('Zeiger'), findsOneWidget);
    expect(find.text('Cursor'), findsNothing);
    c.dispose();
  });

  testWidgets('ResearchPanel buys a node and unlocks tech', (tester) async {
    final w = World(width: 10, height: 10);
    registerCoreComponents(w);
    registerIdleComponents(w);
    w.storeOf<BigTreasury>().set(
      w.spawn(),
      BigTreasury(amounts: {'coins': n('1000')}),
    );
    w.storeOf<IdleModifiers>().set(w.spawn(), IdleModifiers());
    w.storeOf<IdleStats>().set(w.spawn(), IdleStats());
    w.storeOf<ResearchNode>().set(
      w.spawn(),
      ResearchNode(id: 'mining', name: 'Mining', cost: {'coins': n('100')}),
    );
    final c = IdleController(world: w);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ResearchPanel(controller: c))),
    );
    await tester.tap(find.byKey(const Key('buy-research-mining')));
    await tester.pump();
    expect(availableTech(w, 'player'), contains('mining'));
    c.dispose();
  });
}
