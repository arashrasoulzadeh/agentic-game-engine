import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:engine_studio/src/project/project_screen.dart';
import 'package:engine_studio/src/project/studio_project.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renders the studio with the real Material fonts and (with `UPDATE_SCREENSHOTS=1`) writes the PNGs used in
/// the docs to `docs/img/`. Without the variable it only checks the render works, so the images change on
/// purpose, not on every test run.
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
  // Custom painters draw text without a family; in tests that resolves to the blocky Ahem font.
  await load('Ahem', ['Roboto-Regular.ttf']);
  await load('FlutterTest', ['Roboto-Regular.ttf']);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

List<int> _tiles() {
  const rows = [
    '..............',
    '..............',
    '..............',
    '..........##..',
    '.....###......',
    '..............',
    '..##..........',
    '##############',
  ];
  return [
    for (final r in rows)
      for (final c in r.split('')) c == '#' ? 1 : 0,
  ];
}

Map<String, dynamic> _level() => {
  'entities': [
    {
      'name': 'ground',
      'components': {
        'position': {'x': 0.0, 'y': 0.0},
        'tileMap': {
          'cols': 14,
          'rows': 8,
          'tileWidth': 32.0,
          'tileHeight': 32.0,
          'solidTileIds': [1],
          'tiles': _tiles(),
        },
      },
    },
    {
      'name': 'player',
      'components': {
        'position': {'x': 48.0, 'y': 190.0},
      },
    },
    {
      'name': 'coin_1',
      'components': {
        'position': {'x': 190.0, 'y': 120.0},
      },
    },
    {
      'name': 'coin_2',
      'components': {
        'position': {'x': 340.0, 'y': 60.0},
      },
    },
    {
      'name': 'guard',
      'components': {
        'position': {'x': 400.0, 'y': 222.0},
      },
    },
  ],
};

void main() {
  testWidgets('studio screenshot', (tester) async {
    await tester.runAsync(_loadFonts);
    tester.view.physicalSize = const Size(2200, 1300);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final base = Directory.systemTemp.createTempSync('studio_shot');
    addTearDown(() => base.deleteSync(recursive: true));
    final root = Directory('${base.path}/platformer_demo')..createSync();
    File(
      '${root.path}/pubspec.yaml',
    ).writeAsStringSync('name: platformer_demo\n');
    Directory('${root.path}/assets/levels').createSync(recursive: true);
    File(
      '${root.path}/assets/levels/level1.json',
    ).writeAsStringSync(jsonEncode(_level()));

    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorSchemeSeed: Colors.indigo,
            useMaterial3: true,
            fontFamily: 'Roboto',
          ),
          home: ProjectScreen(
            project: StudioProject.open(root.path),
            useLanguageServer: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('file-assets')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('file-assets/levels')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('file-assets/levels/level1.json')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('level-canvas')), findsOneWidget);

    // Select the player so the inspector shows its components.
    final canvas = find.byKey(const Key('level-canvas'));
    await tester.tapAt(tester.getTopLeft(canvas) + const Offset(48, 190));
    await tester.pumpAndSettle();

    final png = await tester.runAsync(() async {
      final ro = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundary),
      );
      final image = await ro.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    expect(png!.length, greaterThan(5000), reason: 'something was drawn');
    if (Platform.environment['UPDATE_SCREENSHOTS'] == '1') {
      File('../../docs/img/studio-level-editor.png').writeAsBytesSync(png);
    }
  });
}
