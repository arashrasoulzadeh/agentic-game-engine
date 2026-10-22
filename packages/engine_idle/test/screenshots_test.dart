import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:engine_core/engine_core.dart';
import 'package:engine_idle/engine_idle.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renders the idle UI with the real Material fonts and (with `UPDATE_SCREENSHOTS=1`) writes the PNGs used in
/// the docs to `docs/img/`. Without the variable it only checks the render works, so the docs images are
/// regenerated on purpose rather than churning on every test run.
Future<void> _loadFonts() async {
  final dir =
      '${Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/develop/flutter'}'
      '/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final file = File('$dir/$f');
      if (file.existsSync()) {
        loader.addFont(
          Future.value(ByteData.sublistView(file.readAsBytesSync())),
        );
      }
    }
    await loader.load();
  }

  await load('Roboto', [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

void main() {
  testWidgets('idle game screenshot', (tester) async {
    await tester.runAsync(_loadFonts);
    tester.view.physicalSize = const Size(900, 1500);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final json =
        jsonDecode(File('example/cookie_clicker.json').readAsStringSync())
            as Map<String, dynamic>;
    final world = World(width: 10, height: 10);
    registerCoreComponents(world);
    final game = loadIdleDefinition(world, json);
    world.addSystem(IdleSystem());
    final report = simulateIdle(
      world,
      game.wallet,
      limit: const Duration(minutes: 50),
    );
    expect(report.purchases, greaterThan(5));
    final controller = IdleController(world: world);

    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorSchemeSeed: Colors.deepOrange,
            useMaterial3: true,
            fontFamily: 'Roboto',
          ),
          home: DefaultTabController(
            length: 4,
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Cookie clicker'),
                bottom: const TabBar(
                  isScrollable: true,
                  tabs: [
                    Tab(text: 'Generators'),
                    Tab(text: 'Upgrades'),
                    Tab(text: 'Progress'),
                    Tab(text: 'Settings'),
                  ],
                ),
              ),
              body: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: ResourceHeader(
                      controller: controller,
                      resources: const ['coins', 'gems'],
                    ),
                  ),
                  FilledButton(
                    onPressed: controller.tap,
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('Tap'),
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        GeneratorList(controller: controller),
                        UpgradeList(controller: controller),
                        AchievementList(controller: controller),
                        const SizedBox(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final png = await tester.runAsync(() async {
      final ro = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundary),
      );
      final image = await ro.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    expect(png!.length, greaterThan(5000), reason: 'something was drawn');
    if (Platform.environment['UPDATE_SCREENSHOTS'] == '1') {
      File('../../docs/img/idle-game.png').writeAsBytesSync(png);
    }
    controller.dispose();
  });
}
