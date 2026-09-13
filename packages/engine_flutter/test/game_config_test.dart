import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round-trips through toJson/fromJson', () {
    const config = GameConfig(
      title: 'My Game',
      orientation: GameOrientation.landscape,
      worldWidth: 800,
      worldHeight: 600,
      backgroundColor: Colors.red,
      showFpsOverlay: true,
      pauseOnBackground: false,
      onScreenControls: OnScreenControlsMode.on,
    );

    final restored = GameConfig.fromJson(config.toJson());

    expect(restored.title, 'My Game');
    expect(restored.orientation, GameOrientation.landscape);
    expect(restored.worldWidth, 800);
    expect(restored.worldHeight, 600);
    expect(restored.backgroundColor.toARGB32(), Colors.red.toARGB32());
    expect(restored.showFpsOverlay, isTrue);
    expect(restored.pauseOnBackground, isFalse);
    expect(restored.onScreenControls, OnScreenControlsMode.on);
  });

  test('fromJson falls back to defaults for missing/unknown fields', () {
    final config = GameConfig.fromJson({
      'worldWidth': 100,
      'worldHeight': 200,
      'orientation': 'not-a-real-value',
    });

    expect(config.title, 'Game');
    expect(config.orientation, GameOrientation.auto);
    expect(config.worldWidth, 100);
    expect(config.worldHeight, 200);
    expect(config.showFpsOverlay, isFalse);
    expect(config.pauseOnBackground, isTrue);
    expect(config.onScreenControls, OnScreenControlsMode.auto);
  });
}
