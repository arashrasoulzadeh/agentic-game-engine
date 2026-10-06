import 'dart:convert';
import 'dart:io';

import 'package:engine_core/engine_core.dart';
import 'package:engine_studio/src/preview/preview_world.dart';
import 'package:flutter_test/flutter_test.dart';

LevelDocument _fixture() => LevelDocument.fromJson(
  jsonDecode(File('test/fixtures/main_level.json').readAsStringSync())
      as Map<String, dynamic>,
);

void main() {
  group('PreviewWorld', () {
    test('loads the level into a live engine world with the named player', () {
      final preview = PreviewWorld.of(_fixture(), width: 4000, height: 4000);
      expect(preview.named.containsKey('player'), isTrue);
      expect(preview.positions, isNotEmpty);
    });

    test(
      'stepping the world runs the engine: the player falls under gravity',
      () {
        final preview = PreviewWorld.of(_fixture(), width: 4000, height: 4000);
        final player = preview.named['player']!;
        final startY = preview.world.components
            .storeOf<Position>()
            .get(player)!
            .y;

        for (var i = 0; i < 30; i++) {
          preview.step(1 / 60);
        }

        final endY = preview.world.components
            .storeOf<Position>()
            .get(player)!
            .y;
        expect(
          endY,
          isNot(startY),
          reason: 'the engine systems moved the player',
        );
      },
    );

    test('a level without a player still loads and steps', () {
      final doc = LevelDocument.fromJson({
        'entities': [
          {
            'components': {
              'position': {'x': 1.0, 'y': 2.0},
            },
          },
        ],
      });
      final preview = PreviewWorld.of(doc, width: 4000, height: 4000);
      preview.step(1 / 60);
      expect(preview.named, isEmpty);
    });
  });

  group('controls', () {
    test('holding right moves the player right; holding nothing does not', () {
      final preview = PreviewWorld.of(_fixture(), width: 4000, height: 4000);
      final player = preview.named['player']!;
      Position at() =>
          preview.world.components.storeOf<Position>().get(player)!;

      for (var i = 0; i < 30; i++) {
        preview.step(1 / 60);
      }
      final before = at().x;
      preview.pressActions({'right'});
      for (var i = 0; i < 30; i++) {
        preview.step(1 / 60);
      }
      expect(at().x, greaterThan(before));

      preview.pressActions({});
      final stopped = at().x;
      for (var i = 0; i < 30; i++) {
        preview.step(1 / 60);
      }
      expect(
        at().x,
        closeTo(stopped, 1),
        reason: 'no held action, no sideways motion',
      );
    });
  });
}
