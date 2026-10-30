import 'dart:convert';

import 'package:engine_idle/engine_idle.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _combat = WaveCombatConfig(
  heroStem: 'h',
  enemyRoot: 'e',
  backgroundDir: 'b',
  backgroundPrefix: 'bg',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('load reads the engine config and level and fits the world', () async {
    final assets = {
      'assets/game_config.json': jsonEncode({
        'title': 'Test',
        'worldWidth': 180,
        'worldHeight': 320,
      }),
      'levels/l.json': jsonEncode({
        'name': 'L',
        'wave': ['a'],
        'boss': 'b',
        'background': 'x',
        'hero': {'x': 1, 'y': 2},
        'enemy_anchor': {'x': 3, 'y': 4},
      }),
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
          final key = utf8.decode(message!.buffer.asUint8List());
          return const StringCodec().encodeMessage(assets[key]!);
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', null);
    });

    final game = await WaveCombatGame.load(
      levelAsset: 'levels/l.json',
      combat: _combat,
    );

    expect(game.config.title, 'Test');
    expect(game.level.name, 'L');
    expect(game.viewportConfig.fitWorld, isTrue);
    expect(game.viewportConfig.targetAspectRatio, 180 / 320);
    expect(game.createInitialScene(), isA<WaveCombatScene>());
  });

  test(
    'HudLayout defaults suit the 180x320 portrait world and are replaceable',
    () {
      const d = HudLayout();
      expect((d.heroBar.x, d.enemyBar.x), (5, 95)); // side by side at the top
      expect(d.description.y, 160); // world centre
      expect(d.description.rtl, isTrue);
      const custom = WaveCombatConfig(
        heroStem: 'h',
        enemyRoot: 'e',
        backgroundDir: 'b',
        backgroundPrefix: 'bg',
        hud: HudLayout(
          heroBar: HudBarStyle(x: 4, y: 300, fillColorArgb: 0xFF00FF00),
        ),
      );
      expect(custom.hud.heroBar.y, 300);
      expect(custom.hud.enemyBar.y, 3);
    },
  );
}
