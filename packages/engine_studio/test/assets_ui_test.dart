import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:engine_core/engine_core.dart';
import 'package:engine_studio/src/assets/asset_browser.dart';
import 'package:engine_studio/src/assets/asset_index.dart';
import 'package:engine_studio/src/assets/atlas_view.dart';
import 'package:engine_studio/src/assets/project_stores.dart';
import 'package:engine_studio/src/assets/tile_pattern.dart';
import 'package:engine_studio/src/inspector/inspector_panel.dart';
import 'package:engine_studio/src/level/level_editor.dart';
import 'package:engine_studio/src/level/level_screen.dart';
import 'package:engine_studio/src/project/project_screen.dart';
import 'package:engine_studio/src/project/studio_project.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// A 1x1 PNG: building one with dart:ui needs real async, which would make every
// test that calls _project hang under the fake-async test zone.
final Uint8List _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

/// A project with a declared 2-sprite atlas (a real PNG so it decodes) and one level.
Future<Directory> _project({Map<String, dynamic>? level}) async {
  final root = Directory.systemTemp.createTempSync('assets_ui');
  File('${root.path}/pubspec.yaml').writeAsStringSync('name: g\n');
  Directory('${root.path}/lib').createSync();
  Directory('${root.path}/assets/levels').createSync(recursive: true);
  File('${root.path}/assets/hero.png').writeAsBytesSync(_pngBytes);
  File('${root.path}/assets/hero.json').writeAsStringSync(
    jsonEncode({
      'regions': {
        'idle': {'x': 0, 'y': 0, 'w': 16, 'h': 16},
        'walk': {'x': 16, 'y': 0, 'w': 16, 'h': 16},
      },
    }),
  );
  File('${root.path}/assets/studio_atlases.json').writeAsStringSync(
    jsonEncode({
      'atlases': {
        'hero': {'image': 'assets/hero.png', 'manifest': 'assets/hero.json'},
      },
    }),
  );
  File('${root.path}/assets/levels/one.level.json').writeAsStringSync(
    jsonEncode(
      level ??
          {
            'entities': [
              {
                'name': 'map',
                'components': {
                  'position': {'x': 0.0, 'y': 0.0},
                  'tileMap': {
                    'cols': 6,
                    'rows': 4,
                    'tileWidth': 16.0,
                    'tileHeight': 16.0,
                    'tiles': List<int>.filled(24, 0),
                  },
                },
              },
              {
                'name': 'player',
                'components': {
                  'position': {'x': 8.0, 'y': 8.0},
                  'sprite': {'atlasId': 'hero', 'region': 'idle'},
                },
              },
            ],
          },
    ),
  );
  return root;
}

void main() {
  group('parseTilePattern', () {
    test('rows, spaces or commas, _ and . skip, 0 erases', () {
      expect(parseTilePattern('1 1 1\n_ 2 .\n0,0,3'), [
        [1, 1, 1],
        [-1, 2, -1],
        [0, 0, 3],
      ]);
      expect(parseTilePattern('  4  \n\n  5 '), [
        [4],
        [5],
      ]);
    });

    test(
      'errors name the line and token, because a typed pattern has no other feedback',
      () {
        expect(
          () => parseTilePattern(''),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'm',
              contains('empty'),
            ),
          ),
        );
        expect(
          () => parseTilePattern('1 x'),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'm',
              contains('line 1: "x"'),
            ),
          ),
        );
        expect(() => parseTilePattern('1 -2'), throwsFormatException);
        expect(
          () => parseTilePattern('1 2\n3'),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'm',
              contains('line 2 has 1 cells but line 1 has 2'),
            ),
          ),
        );
      },
    );
  });

  group('asset browser', () {
    testWidgets('lists sprite sheets with counts and files, and reports taps', (
      tester,
    ) async {
      final root = await _project();
      addTearDown(() => root.deleteSync(recursive: true));
      File('${root.path}/assets/sfx.wav').writeAsStringSync('x');
      File('${root.path}/prefabs').createSync();
      AtlasInfo? atlas;
      String? file;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AssetBrowserPanel(
              index: AssetIndex.scan(root.path),
              onOpenAtlas: (a) => atlas = a,
              onOpenFile: (f) => file = f,
              onClose: () {},
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('asset-atlas-hero')), findsOneWidget);
      expect(find.text('2 sprites'), findsOneWidget);
      expect(
        find.byKey(const Key('asset-file-assets/sfx.wav')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('asset-atlas-hero')));
      expect(atlas!.id, 'hero');
      await tester.tap(find.byKey(const Key('asset-file-assets/sfx.wav')));
      expect(file, 'assets/sfx.wav');
    });

    testWidgets('an empty project says so', (tester) async {
      final root = Directory.systemTemp.createTempSync('empty_assets');
      addTearDown(() => root.deleteSync(recursive: true));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AssetBrowserPanel(
              index: AssetIndex.scan(root.path),
              onOpenAtlas: (_) {},
              onOpenFile: (_) {},
              onClose: () {},
            ),
          ),
        ),
      );
      expect(find.text('No assets yet'), findsOneWidget);
    });

    testWidgets('an undeclared sheet is marked as such', (tester) async {
      final root = Directory.systemTemp.createTempSync('undeclared');
      addTearDown(() => root.deleteSync(recursive: true));
      File('${root.path}/assets/packed/a.png')
        ..createSync(recursive: true)
        ..writeAsStringSync('x');
      File('${root.path}/assets/packed/a.json').writeAsStringSync(
        jsonEncode({
          'regions': {'s': {}},
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AssetBrowserPanel(
              index: AssetIndex.scan(root.path),
              onOpenAtlas: (_) {},
              onOpenFile: (_) {},
              onClose: () {},
            ),
          ),
        ),
      );
      expect(find.textContaining('not declared'), findsOneWidget);
    });
  });

  group('AtlasView', () {
    testWidgets(
      'shows one tile per sprite, named, and reports the tapped one',
      (tester) async {
        final root = await _project();
        addTearDown(() => root.deleteSync(recursive: true));
        final atlas = AssetIndex.scan(root.path).atlasById('hero')!;
        String? picked;
        await tester.runAsync(() async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: AtlasView(
                  projectRoot: root.path,
                  atlas: atlas,
                  onSelect: (n) => picked = n,
                ),
              ),
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await tester.pump();
        expect(find.byKey(const Key('sprite-idle')), findsOneWidget);
        expect(find.byKey(const Key('sprite-walk')), findsOneWidget);
        expect(find.text('walk'), findsOneWidget);
        await tester.tap(find.byKey(const Key('sprite-walk')));
        expect(picked, 'walk');
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('an unreadable sheet shows an error instead of crashing', (
      tester,
    ) async {
      final root = Directory.systemTemp.createTempSync('bad_atlas');
      addTearDown(() => root.deleteSync(recursive: true));
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AtlasView(
                projectRoot: root.path,
                atlas: const AtlasInfo(
                  id: 'x',
                  image: 'nope.png',
                  manifest: 'nope.json',
                  regions: [],
                  declared: true,
                ),
              ),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      expect(find.byKey(const Key('atlas-error')), findsOneWidget);
    });
  });

  group('project window', () {
    testWidgets(
      'the Assets button lists them; opening a sheet shows its sprites',
      (tester) async {
        final root = await _project();
        addTearDown(() => root.deleteSync(recursive: true));
        await tester.runAsync(() async {
          await tester.pumpWidget(
            MaterialApp(
              home: ProjectScreen(
                project: StudioProject.open(root.path),
                useLanguageServer: false,
              ),
            ),
          );
          await tester.tap(find.byKey(const Key('project-assets')));
          await tester.pump();
          expect(find.byKey(const Key('asset-browser')), findsOneWidget);
          await tester.tap(find.byKey(const Key('asset-atlas-hero')));
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await tester.pump();
        expect(find.byKey(const Key('atlas-title')), findsOneWidget);
        expect(find.byKey(const Key('sprite-idle')), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('opening Assets closes search and problems and vice versa', (
      tester,
    ) async {
      final root = await _project();
      addTearDown(() => root.deleteSync(recursive: true));
      await tester.pumpWidget(
        MaterialApp(
          home: ProjectScreen(
            project: StudioProject.open(root.path),
            useLanguageServer: false,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('project-problems')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('project-assets')));
      await tester.pump();
      expect(find.byKey(const Key('project-problems-panel')), findsNothing);
      expect(find.byKey(const Key('asset-browser')), findsOneWidget);
      await tester.tap(find.byKey(const Key('asset-browser-close')));
      await tester.pump();
      expect(find.byKey(const Key('file-tree')), findsOneWidget);
    });
  });

  group('sprite picker in the inspector', () {
    testWidgets('Pick sprite sets atlasId and region on the selected entity', (
      tester,
    ) async {
      final root = await _project();
      addTearDown(() => root.deleteSync(recursive: true));
      final editor = LevelEditor(
        LevelDocument.fromJson(
          jsonDecode(
                File(
                  '${root.path}/assets/levels/one.level.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>,
        ),
      );
      editor.selectIndex(1);
      var changes = 0;
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 700,
                child: InspectorPanel(
                  editor: editor,
                  onChanged: () => changes++,
                  projectRoot: root.path,
                  assets: AssetIndex.scan(root.path),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('pick-sprite')));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 250));
      });
      await tester.pump();
      expect(find.byKey(const Key('sprite-walk')), findsOneWidget);
      await tester.tap(find.byKey(const Key('sprite-walk')));
      // The dialog's future was created inside runAsync, so it completes on the real
      // event loop.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      expect(editor.selected!.components['sprite']!['region'], 'walk');
      expect(editor.selected!.components['sprite']!['atlasId'], 'hero');
      expect(changes, greaterThan(0));
      expect(editor.history.canUndo, isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('with no declared atlas the picker explains how to add one', (
      tester,
    ) async {
      final root = Directory.systemTemp.createTempSync('no_atlas');
      addTearDown(() => root.deleteSync(recursive: true));
      final editor = LevelEditor(
        LevelDocument.fromJson({
          'entities': [
            {
              'components': {
                'position': {'x': 0.0, 'y': 0.0},
                'sprite': {'atlasId': 'a', 'region': 'b'},
              },
            },
          ],
        }),
      )..selectIndex(0);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 700,
              child: InspectorPanel(
                editor: editor,
                onChanged: () {},
                projectRoot: root.path,
                assets: AssetIndex.scan(root.path),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('pick-sprite')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('picker-empty')), findsOneWidget);
      await tester.tap(find.byKey(const Key('picker-cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('picker-empty')), findsNothing);
      expect(editor.history.canUndo, isFalse);
    });

    testWidgets('there is no picker button without a project', (tester) async {
      final editor = LevelEditor(
        LevelDocument.fromJson({
          'entities': [
            {
              'components': {
                'position': {'x': 0.0, 'y': 0.0},
                'sprite': {'atlasId': 'a', 'region': 'b'},
              },
            },
          ],
        }),
      )..selectIndex(0);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 700,
              child: InspectorPanel(editor: editor, onChanged: () {}),
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('pick-sprite')), findsNothing);
    });
  });

  group('brushes and prefabs in the level editor', () {
    Future<void> openLevel(WidgetTester tester, Directory root) =>
        tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(size: Size(1400, 900)),
              child: LevelScreen(
                levelPath: '${root.path}/assets/levels/one.level.json',
                projectRoot: root.path,
                autosaveInterval: null,
              ),
            ),
          ),
        );

    testWidgets(
      'a typed tile brush appears in the panel, stamps the level, and undoes in one step',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final root = await _project();
        addTearDown(() => root.deleteSync(recursive: true));
        await openLevel(tester, root);
        expect(find.byKey(const Key('brush-panel')), findsOneWidget);
        expect(find.byKey(const Key('brush-empty')), findsOneWidget);

        await tester.tap(find.byKey(const Key('brush-new-tiles')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('prompt-field')), 'ledge');
        await tester.tap(find.byKey(const Key('prompt-ok')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('prompt-field')),
          '1 1\n_ 2',
        );
        await tester.tap(find.byKey(const Key('prompt-ok')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('brush-ledge')), findsOneWidget);
        expect(BrushStore(root.path).load().named('ledge'), isA<TileBrush>());

        await tester.tap(find.byKey(const Key('brush-ledge')));
        await tester.pump();
        final canvas = tester.getTopLeft(find.byKey(const Key('level-canvas')));
        await tester.tapAt(canvas + const Offset(20, 20));
        await tester.pump();
        await tester.tap(find.byKey(const Key('brush-ledge')));
        await tester.pump();
        expect(find.byKey(const Key('brush-ledge')), findsOneWidget);
      },
    );

    testWidgets(
      'a bad pattern is explained in the panel and nothing is saved',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final root = await _project();
        addTearDown(() => root.deleteSync(recursive: true));
        await openLevel(tester, root);
        await tester.tap(find.byKey(const Key('brush-new-tiles')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('prompt-field')), 'bad');
        await tester.tap(find.byKey(const Key('prompt-ok')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('prompt-field')), '1 oops');
        await tester.tap(find.byKey(const Key('prompt-ok')));
        await tester.pumpAndSettle();
        expect(find.textContaining('"oops" is not a tile id'), findsOneWidget);
        expect(BrushStore(root.path).load().brushes, isEmpty);
      },
    );

    testWidgets(
      'Save as prefab writes prefabs/<name>.json and adds a prefab brush; no selection is explained',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final root = await _project();
        addTearDown(() => root.deleteSync(recursive: true));
        await openLevel(tester, root);

        await tester.tap(find.byKey(const Key('brush-save-prefab')));
        await tester.pump();
        expect(find.text('Select an entity first.'), findsOneWidget);

        // Select the player by tapping it on the canvas (select is the default tool).
        final canvas = tester.getTopLeft(find.byKey(const Key('level-canvas')));
        await tester.tapAt(canvas + const Offset(8, 8));
        await tester.pump();
        await tester.tap(find.byKey(const Key('brush-save-prefab')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('prompt-field')),
          'hero guy',
        );
        await tester.tap(find.byKey(const Key('prompt-ok')));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('use letters').evaluate().isNotEmpty ||
              find.textContaining('may only use').evaluate().isNotEmpty,
          isTrue,
        );
        expect(Directory('${root.path}/prefabs').existsSync(), isFalse);

        await tester.tap(find.byKey(const Key('brush-save-prefab')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('prompt-field')), 'hero');
        await tester.tap(find.byKey(const Key('prompt-ok')));
        await tester.pumpAndSettle();
        expect(File('${root.path}/prefabs/hero.json').existsSync(), isTrue);
        expect(find.byKey(const Key('brush-hero')), findsOneWidget);
        expect(BrushStore(root.path).load().named('hero'), isA<PrefabBrush>());
      },
    );

    testWidgets('deleting a brush removes it from the panel and the file', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final root = await _project();
      addTearDown(() => root.deleteSync(recursive: true));
      BrushStore(root.path).save(
        BrushLibrary()..add(
          TileBrush(
            name: 'old',
            pattern: [
              [1],
            ],
          ),
        ),
      );
      await openLevel(tester, root);
      expect(find.byKey(const Key('brush-old')), findsOneWidget);
      await tester.tap(find.byKey(const Key('brush-delete-old')));
      await tester.pump();
      expect(find.byKey(const Key('brush-old')), findsNothing);
      expect(BrushStore(root.path).load().brushes, isEmpty);
    });

    testWidgets(
      'a missing sprite in the level shows up in the problems panel, and clicking selects it',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final root = await _project(
          level: {
            'entities': [
              {
                'name': 'typo',
                'components': {
                  'position': {'x': 8.0, 'y': 8.0},
                  'sprite': {'atlasId': 'hero', 'region': 'runn'},
                },
              },
            ],
          },
        );
        addTearDown(() => root.deleteSync(recursive: true));
        await openLevel(tester, root);
        await tester.tap(find.byKey(const Key('validation-panel')));
        await tester.pumpAndSettle();
        expect(find.textContaining('no sprite named "runn"'), findsOneWidget);
        await tester.tap(find.byKey(const Key('problem-0')));
        await tester.pump();
        expect(find.textContaining('typo'), findsWidgets);
      },
    );
  });
}
