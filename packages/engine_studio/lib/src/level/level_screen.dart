import 'dart:convert';
import 'dart:io';

import 'package:engine_core/engine_core.dart';
import 'package:flutter/material.dart';

import 'level_canvas.dart';
import 'level_geometry.dart';

/// Shows one level file read-only: the tile map and entities, with a tap on a
/// marker selecting that entity and naming it in the status bar. Editing comes
/// in later phase 3 items.
class LevelScreen extends StatefulWidget {
  final String levelPath;

  const LevelScreen({super.key, required this.levelPath});

  @override
  State<LevelScreen> createState() => _LevelScreenState();
}

class _LevelScreenState extends State<LevelScreen> {
  late final LevelDocument _document;
  late final LevelGeometry _geometry;
  int? _selected;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    try {
      final json =
          jsonDecode(File(widget.levelPath).readAsStringSync())
              as Map<String, dynamic>;
      _document = LevelDocument.fromJson(json);
      _geometry = LevelGeometry.of(_document);
    } on Object catch (e) {
      _loadError = 'Could not open ${widget.levelPath}: $e';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Level')),
        body: Center(child: Text(_loadError!, key: const Key('level-error'))),
      );
    }

    final selectedName = _selected == null
        ? null
        : _document.entities[_selected!].name;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.levelPath.split(Platform.pathSeparator).last),
      ),
      body: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              minScale: 0.25,
              maxScale: 8,
              constrained: false,
              child: GestureDetector(
                key: const Key('level-canvas'),
                onTapUp: (details) => setState(() {
                  _selected = _geometry.entityAt(details.localPosition);
                }),
                child: CustomPaint(
                  size: _canvasSize(),
                  painter: LevelCanvasPainter(
                    document: _document,
                    geometry: _geometry,
                    selectedEntity: _selected,
                  ),
                ),
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              selectedName == null && _selected == null
                  ? 'Tap an entity to select it.'
                  : 'Selected: ${selectedName ?? 'entity ${_selected! + 1}'}',
              key: const Key('selection-status'),
            ),
          ),
        ],
      ),
    );
  }

  /// Canvas extent in world units: the tile map if there is one, otherwise a
  /// box around the entities, with a margin so markers at the edge are reachable.
  Size _canvasSize() {
    final map = _geometry.tileMap;
    if (map != null) {
      return Size(
        map.cols * map.tileWidth * LevelCanvasPainter.scale,
        map.rows * map.tileHeight * LevelCanvasPainter.scale,
      );
    }
    var maxX = 320.0;
    var maxY = 240.0;
    for (final at in _geometry.entityPositions.values) {
      if (at.dx > maxX) maxX = at.dx;
      if (at.dy > maxY) maxY = at.dy;
    }
    return Size(maxX + 64, maxY + 64);
  }
}
