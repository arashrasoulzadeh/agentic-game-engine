import 'dart:ui' show Offset;

import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';

/// A scene that displays scrolling credits/attribution text.
/// Tapping anywhere dismisses the scene (pops the overlay).
///
/// Example usage:
/// ```dart
/// class MyCreditsScene extends CreditsScene {
///   @override
///   List<CreditsEntry> get credits => [
///     CreditsEntry('Game Title', style: CreditsStyle.title),
///     CreditsEntry(''),
///     CreditsEntry('Developed by', style: CreditsStyle.section),
///     CreditsEntry('Your Name'),
///     CreditsEntry(''),
///     CreditsEntry('Art Assets', style: CreditsStyle.section),
///     CreditsEntry('Artist Name', style: CreditsStyle.name),
///     CreditsEntry(''),
///     CreditsEntry('Music', style: CreditsStyle.section),
///     CreditsEntry('Composer Name', style: CreditsStyle.name),
///     CreditsEntry(''),
///     CreditsEntry('Special Thanks', style: CreditsStyle.section),
///     CreditsEntry('Community Contributors'),
///   ];
/// }
abstract class CreditsScene extends Scene {
  /// The credits entries to display.
  List<CreditsEntry> get credits;

  /// Scroll speed in world units per second. Default 50.
  double get scrollSpeed => 50;

  /// Text style for regular entries.
  CreditsStyle get defaultStyle => const CreditsStyle(
    fontSize: 24,
    colorArgb: 0xFFFFFFFF,
    alignment: TextAlignment.center,
  );

  /// Whether to show a "Tap to skip" hint at the bottom.
  bool get showSkipHint => true;

  /// Text for the skip hint.
  String get skipHintText => 'Tap anywhere to skip';

  /// Internal state
  final List<_CreditsLine> _lines = [];
  double _elapsedTime = 0;
  bool _finished = false;
  SceneController? _scenes;

  @override
  bool get showOnScreenControls => false;

  @override
  double get ambientBrightness => 1.0;

  @override
  Future<void> populate(World world, SceneController scenes, GameState state) async {
    _scenes = scenes;
    _lines.clear();
    _elapsedTime = 0;
    _finished = false;

    double y = 0;
    for (final entry in credits) {
      final style = entry.style ?? defaultStyle;
      final textEntity = world.spawn();
      world.storeOf<Position>().set(textEntity, Position(world.width / 2, y));
      world.storeOf<Text>().set(textEntity, Text(
        entry.text,
        fontSize: style.fontSize,
        colorArgb: style.colorArgb,
        align: style.alignment,
        screenSpace: false,
      ));
      _lines.add(_CreditsLine(textEntity, y, style.fontSize * 1.5));
      y += style.fontSize * 1.5;
    }

    // Add skip hint if enabled
    if (showSkipHint) {
      final hintEntity = world.spawn();
      world.storeOf<Position>().set(hintEntity, Position(world.width / 2, y + 40));
      world.storeOf<Text>().set(hintEntity, Text(
        skipHintText,
        fontSize: 16,
        colorArgb: 0x88FFFFFF,
        align: TextAlignment.center,
        screenSpace: false,
      ));
      _lines.add(_CreditsLine(hintEntity, y + 40, 16 * 1.5));
    }

    }

  @override
  void update(double dt, World world) {
    if (_finished) return;

    _elapsedTime += dt;
    final scrollDistance = _elapsedTime * scrollSpeed;

    // Update positions of all credit lines
    final posStore = world.storeOf<Position>();
    for (final line in _lines) {
      final pos = posStore.get(line.entity);
      if (pos != null) {
        // Each line starts at its initial Y and moves up by scrollDistance
        pos.y = line.initialY - scrollDistance;
      }
    }

    // Check if all content has scrolled past top of screen
    final bottomMostLine = _lines.isNotEmpty
        ? _lines.map((l) => l.initialY + l.height).reduce((a, b) => a > b ? a : b)
        : 0;
    if (bottomMostLine - scrollDistance < -world.height) {
      _finished = true;
      _scenes?.popOverlay();
    }
  }

  @override
  void handleTap(World world, SceneController scenes, Offset worldPosition) {
    // Tap anywhere to skip
    scenes.popOverlay();
  }
}

/// Internal class to track a credit line's entity and initial position.
class _CreditsLine {
  final EntityId entity;
  final double initialY;
  final double height;

  _CreditsLine(this.entity, this.initialY, this.height);
}

/// A single entry in the credits list.
class CreditsEntry {
  final String text;
  final CreditsStyle? style;

  CreditsEntry(this.text, {this.style});
}

/// Text styling for credits entries.
class CreditsStyle {
  final double fontSize;
  final int colorArgb;
  final TextAlignment alignment;

  const CreditsStyle({
    this.fontSize = 24,
    this.colorArgb = 0xFFFFFFFF,
    this.alignment = TextAlignment.center,
  });

  /// Large title style.
  static const CreditsStyle title = CreditsStyle(
    fontSize: 48,
    colorArgb: 0xFFFFFFFF,
    alignment: TextAlignment.center,
  );

  /// Section header style.
  static const CreditsStyle section = CreditsStyle(
    fontSize: 32,
    colorArgb: 0xFFFFFF00,
    alignment: TextAlignment.center,
  );

  /// Name/credit line style.
  static const CreditsStyle name = CreditsStyle(
    fontSize: 24,
    colorArgb: 0xFFCCCCCC,
    alignment: TextAlignment.center,
  );

  /// Small body text style.
  static const CreditsStyle body = CreditsStyle(
    fontSize: 20,
    colorArgb: 0xFFCCCCCC,
    alignment: TextAlignment.center,
  );
}