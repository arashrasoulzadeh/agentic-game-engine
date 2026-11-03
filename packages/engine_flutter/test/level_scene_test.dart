import 'dart:convert';
import 'dart:typed_data';

import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter/services.dart' show AssetBundle;
import 'package:flutter_test/flutter_test.dart';

class _Bundle extends AssetBundle {
  _Bundle(this.files);
  final Map<String, String> files;

  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(
    Uint8List.fromList(utf8.encode(files[key] ?? (throw StateError(key)))),
  );

  @override
  Future<T> loadStructuredData<T>(
    String key,
    Future<T> Function(String value) parser,
  ) async => parser(await loadString(key));
}

World _world() {
  final world = World(width: 100, height: 100);
  registerCoreComponents(world);
  return world;
}

final _bundle = _Bundle({
  'l.json': jsonEncode({
    'entities': [
      {
        'name': 'player',
        'components': {
          'position': {'x': 4.0},
        },
      },
    ],
  }),
});

void main() {
  test(
    'populate loads the level, then runs setup with the named entities',
    () async {
      final world = _world();
      Map<String, EntityId>? seen;
      final scene = LevelScene(
        asset: 'l.json',
        defaults: true,
        bundle: _bundle,
        setup: (world, named, scenes, state) {
          seen = named;
          expect(world.find('player'), named['player'], reason: 'loaded first');
        },
      );
      await scene.populate(world, SceneController(), GameState());
      expect(seen!.keys, ['player']);
      expect(world.getComponent<Position>(seen!['player']!)!.y, 0);
    },
  );

  test('the camera follows the named entity, or nothing', () async {
    final world = _world();
    final scene = LevelScene(
      asset: 'l.json',
      follow: 'player',
      defaults: true,
      bundle: _bundle,
    );
    await scene.populate(world, SceneController(), GameState());
    expect(scene.cameraFollowEntity(world), world.find('player'));
    expect(
      LevelScene(asset: 'l.json', bundle: _bundle).cameraFollowEntity(world),
      isNull,
    );
  });

  test('without atlases the scene loads an empty registry', () async {
    final scene = LevelScene(asset: 'l.json', bundle: _bundle);
    expect(await scene.loadAssets(), isA<AtlasRegistry>());
  });

  test('strict surfaces a bad level through populate', () async {
    final bundle = _Bundle({
      'bad.json': jsonEncode({
        'entities': [
          {
            'components': {
              'positon': {'x': 1.0, 'y': 1.0},
            },
          },
        ],
      }),
    });
    await expectLater(
      LevelScene(
        asset: 'bad.json',
        strict: true,
        bundle: bundle,
      ).populate(_world(), SceneController(), GameState()),
      throwsA(isA<LevelLoadException>()),
    );
  });
}
