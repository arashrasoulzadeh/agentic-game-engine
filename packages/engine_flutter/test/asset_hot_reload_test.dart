import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemorySource implements AssetSource {
  final Map<String, Uint8List> files = {};
  final Map<String, int> times = {};
  int clock = 1;
  bool failScan = false;

  void put(String path, List<int> bytes) {
    files[path] = Uint8List.fromList(bytes);
    times[path] = clock++;
  }

  void putJson(String path, Object json) => put(path, utf8.encode(jsonEncode(json)));

  @override
  Future<Map<String, AssetStamp>> scan() async {
    if (failScan) throw StateError('disk gone');
    return {for (final e in files.entries) e.key: AssetStamp(times[e.key]!, e.value.length)};
  }

  @override
  Future<Uint8List> read(String path) async => files[path]!;
}

Map<String, dynamic> _level(double x) => {
      'entities': [
        {
          'name': 'player',
          'components': {
            'position': {'x': x, 'y': 0.0},
          },
        },
      ],
    };

Future<Uint8List> _png(int w, int h) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), ui.Paint());
  final image = await recorder.endRecording().toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  group('AssetChangeTracker', () {
    test('first diff is all added; later diffs report added, changed and removed', () {
      final t = AssetChangeTracker();
      expect(t.diff({'a': const AssetStamp(1, 1)}).single.kind, AssetChangeKind.added);
      expect(t.diff({'a': const AssetStamp(1, 1)}), isEmpty);
      final changes = t.diff({'a': const AssetStamp(2, 1), 'b': const AssetStamp(1, 5)});
      expect(changes.map((c) => c.toString()), ['changed a', 'added b']);
      expect(t.diff({'b': const AssetStamp(1, 5)}).single.kind, AssetChangeKind.removed);
    });

    test('a same-time edit that changes size is still seen; prime reports nothing', () {
      final t = AssetChangeTracker()..prime({'a': const AssetStamp(1, 1)});
      expect(t.diff({'a': const AssetStamp(1, 1)}), isEmpty);
      expect(t.diff({'a': const AssetStamp(1, 2)}).single.kind, AssetChangeKind.changed);
    });
  });

  group('AssetHotReloader + LevelAssetHandler', () {
    late World world;
    late _MemorySource source;
    late LevelHandle handle;
    late AssetHotReloader reloader;
    final reloaded = <String>[];
    final errors = <Object>[];

    setUp(() {
      reloaded.clear();
      errors.clear();
      world = World(width: 10, height: 10);
      registerCoreComponents(world);
      source = _MemorySource()..putJson('levels/main.json', _level(1));
      handle = LevelHandle.load(world, _level(1));
      reloader = AssetHotReloader(
        source: source,
        handlers: [LevelAssetHandler('levels/main.json', handle)],
        onReloaded: (c) => reloaded.add(c.path),
        onError: (c, e) => errors.add(e),
      );
    });

    double playerX() => world.storeOf<Position>().get(handle.named['player']!)!.x;

    test('editing the level file reloads it into the running world', () async {
      await reloader.start();
      reloader.stop();
      expect(await reloader.poll(), isEmpty);

      source.putJson('levels/main.json', _level(77));
      final changes = await reloader.poll();
      expect(changes.single.kind, AssetChangeKind.changed);
      expect(playerX(), 77);
      expect(reloaded, ['levels/main.json']);
      expect(world.entities.count, 1);
    });

    test('a broken edit leaves the running level untouched and reports the error', () async {
      await reloader.start();
      reloader.stop();
      source.putJson('levels/main.json', {'entities': 'nope'});
      await reloader.poll();
      expect(playerX(), 1);
      expect(errors, hasLength(1));
      expect(reloaded, isEmpty);

      source.put('levels/main.json', utf8.encode('{not json'));
      await reloader.poll();
      expect(errors, hasLength(2));
      expect(playerX(), 1);

      source.putJson('levels/main.json', _level(5));
      await reloader.poll();
      expect(playerX(), 5);
    });

    test('files nobody handles, and removals, do not call any handler', () async {
      await reloader.start();
      reloader.stop();
      source.put('notes.txt', [1, 2, 3]);
      source.files.remove('levels/main.json');
      source.times.remove('levels/main.json');
      final changes = await reloader.poll();
      expect(changes.map((c) => c.kind), containsAll([AssetChangeKind.added, AssetChangeKind.removed]));
      expect(reloaded, isEmpty);
      expect(errors, isEmpty);
    });

    test('a failing scan is reported, not thrown, and polling recovers', () async {
      await reloader.start();
      reloader.stop();
      source.failScan = true;
      expect(await reloader.poll(), isEmpty);
      expect(errors.single, isA<StateError>());
      source.failScan = false;
      source.putJson('levels/main.json', _level(9));
      await reloader.poll();
      expect(playerX(), 9);
    });

    test('start is idempotent, runs on a timer and stop cancels it', () async {
      final timed = AssetHotReloader(
        source: source,
        handlers: [LevelAssetHandler('levels/main.json', handle)],
        interval: const Duration(milliseconds: 20),
      );
      await timed.start();
      await timed.start();
      expect(timed.isRunning, isTrue);
      source.putJson('levels/main.json', _level(42));
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(playerX(), 42);
      timed.stop();
      expect(timed.isRunning, isFalse);
    });
  });

  group('AtlasAssetHandler', () {
    testWidgets('replaces the registered atlas when the image or manifest changes', (tester) async {
      await tester.runAsync(() async {
        final registry = AtlasRegistry();
        final source = _MemorySource()
          ..put('a.png', await _png(4, 4))
          ..putJson('a.json', {
            'regions': {
              'hero': {'x': 0, 'y': 0, 'w': 2, 'h': 2},
            },
          });
        final handler = AtlasAssetHandler(
          registry: registry,
          atlasId: 'main',
          imagePath: 'a.png',
          manifestPath: 'a.json',
        );
        final reloader = AssetHotReloader(source: source, handlers: [handler]);

        await reloader.poll();
        final first = registry.resolve('main');
        expect(first.regionFor('hero').width, 2);
        expect(first.image.width, 4);

        source.putJson('a.json', {
          'regions': {
            'hero': {'x': 0, 'y': 0, 'w': 3, 'h': 3},
            'coin': {'x': 3, 'y': 0, 'w': 1, 'h': 1},
          },
        });
        await reloader.poll();
        final second = registry.resolve('main');
        expect(identical(first, second), isFalse);
        expect(second.regionFor('hero').width, 3);
        expect(second.regions.containsKey('coin'), isTrue);

        source.put('a.png', await _png(8, 8));
        await reloader.poll();
        expect(registry.resolve('main').image.width, 8);
      });
    });

    test('handles only its own two files', () {
      final h = AtlasAssetHandler(
        registry: AtlasRegistry(),
        atlasId: 'x',
        imagePath: 'x.png',
        manifestPath: 'x.json',
      );
      expect(h.handles('x.png'), isTrue);
      expect(h.handles('x.json'), isTrue);
      expect(h.handles('y.png'), isFalse);
    });

    test('tryResolve is null for an unknown atlas', () {
      expect(AtlasRegistry().tryResolve('nope'), isNull);
    });
  });

  group('directoryAssetSource', () {
    test('scans nested files with forward-slash relative paths and reads them', () async {
      final dir = Directory.systemTemp.createTempSync('assets_');
      addTearDown(() => dir.deleteSync(recursive: true));
      Directory('${dir.path}/levels').createSync();
      File('${dir.path}/levels/one.json').writeAsStringSync('{}');
      File('${dir.path}/top.txt').writeAsStringSync('hi');

      final source = directoryAssetSource(dir.path)!;
      final scan = await source.scan();
      expect(scan.keys.toSet(), {'levels/one.json', 'top.txt'});
      expect(scan['top.txt']!.size, 2);
      expect(utf8.decode(await source.read('levels/one.json')), '{}');
    });

    test('a directory that does not exist yet scans as empty, then appears', () async {
      final dir = Directory.systemTemp.createTempSync('assets_');
      final path = '${dir.path}/later';
      addTearDown(() => dir.deleteSync(recursive: true));
      final source = directoryAssetSource(path)!;
      expect(await source.scan(), isEmpty);
      Directory(path).createSync();
      File('$path/x').writeAsStringSync('1');
      expect((await source.scan()).keys, ['x']);
    });
  });

  test('CallbackAssetHandler fires for its paths only, on change', () async {
    final source = _MemorySource()..put('levels/a.json', [1])..put('levels/b.json', [1]);
    final seen = <String>[];
    final reloader = AssetHotReloader(
      source: source,
      handlers: [CallbackAssetHandler({'levels/a.json'}, seen.add)],
    );
    await reloader.start();
    source.put('levels/a.json', [1, 2]);
    source.put('levels/b.json', [1, 2]);
    await reloader.poll();
    reloader.stop();
    expect(seen, ['levels/a.json']);
  });
}
