import 'dart:convert';
import 'dart:typed_data';

import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_flutter/zarvan_flutter.dart';
import 'package:flutter/services.dart' show AssetBundle;
import 'package:flutter_test/flutter_test.dart';

class _Bundle extends AssetBundle {
  _Bundle(this.files);
  final Map<String, String> files;

  @override
  Future<ByteData> load(String key) async {
    final text = files[key];
    if (text == null) throw StateError('Unable to load asset: $key');
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(text)));
  }

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

void main() {
  final bundle = _Bundle({
    'levels/1.json': jsonEncode({
      'entities': [
        {
          'name': 'hero',
          'components': {
            'position': {'x': 1.0, 'y': 2.0},
          },
        },
      ],
    }),
    'levels/strict.json': jsonEncode({
      'entities': [
        {
          'components': {
            'positon': {'x': 1.0, 'y': 2.0},
          },
        },
      ],
    }),
    'levels/bad.json': '{not json',
    'levels/list.json': '[]',
  });

  test(
    'load reads the asset into the world and returns named entities',
    () async {
      final world = _world();
      final named = await LevelAsset.load(
        world,
        'levels/1.json',
        bundle: bundle,
      );
      expect(world.getComponent<Position>(named['hero']!)!.y, 2.0);
      expect(world.find('hero'), named['hero']);
    },
  );

  test('strict reports a typo with its suggestion', () async {
    await expectLater(
      LevelAsset.load(
        _world(),
        'levels/strict.json',
        strict: true,
        bundle: bundle,
      ),
      throwsA(
        isA<LevelLoadException>().having(
          (e) => e.message,
          'message',
          contains('did you mean "position"?'),
        ),
      ),
    );
  });

  test('bad JSON and non-object JSON name the asset', () async {
    for (final asset in ['levels/bad.json', 'levels/list.json']) {
      await expectLater(
        LevelAsset.read(asset, bundle: bundle),
        throwsA(
          isA<LevelLoadException>().having(
            (e) => e.message,
            'message',
            contains(asset),
          ),
        ),
      );
    }
  });
}
