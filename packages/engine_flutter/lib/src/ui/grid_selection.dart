import 'dart:ui';

import 'package:engine_core/engine_core.dart';

import '../rendering/hud_bar.dart';

/// Links a marker entity (the visible selection indicator) back to the
/// unit it belongs to. A component, not a private map inside
/// `SelectionMarkerSystem`, so a saved world's markers are recognised
/// and cleaned up on load instead of leaking as orphans.
class SelectionMarker {
  final int owner;
  const SelectionMarker(this.owner);

  Map<String, dynamic> toJson() => {'owner': owner};
  factory SelectionMarker.fromJson(Map<String, dynamic> json) =>
      SelectionMarker((json['owner'] as num).toInt());
}

/// Draws a bar under each `Selected` unit by managing one `HudBar`
/// marker entity per selection. A bar rather than a ring because it
/// reuses the existing world-space `HudBar` renderer -- no new painter
/// code in the 3000-line `EngineView` for a purely visual cue.
class SelectionMarkerSystem extends System {
  final double cellSize;
  final int colorArgb;

  SelectionMarkerSystem(this.cellSize, {this.colorArgb = 0xFF40E0D0});

  @override
  String get name => 'selectionMarkers';

  @override
  void update(World world, double dt) {
    final markers = world.storeOf<SelectionMarker>();
    final selected = world.storeOf<Selected>();
    final positions = world.storeOf<Position>();
    final markerByOwner = <int, int>{};
    final stale = <int>[];
    for (var i = 0; i < markers.length; i++) {
      final owner = markers.denseAt(i).owner;
      final marker = markers.entityAt(i);
      if (world.entities.isAlive(owner) && selected.has(owner)) {
        markerByOwner[owner] = marker;
      } else {
        stale.add(marker);
      }
    }
    stale.forEach(world.destroy);

    const barHeight = 4.0;
    for (var i = 0; i < selected.length; i++) {
      final owner = selected.entityAt(i);
      final pos = positions.get(owner);
      if (pos == null) continue;
      var marker = markerByOwner[owner];
      if (marker == null) {
        marker = world.spawn();
        world.storeOf<SelectionMarker>().set(marker, SelectionMarker(owner));
        world.storeOf<Position>().set(marker, Position(0, 0));
        world.storeOf<HudBar>().set(
              marker,
              HudBar(
                value: 1,
                maxValue: 1,
                width: cellSize,
                height: barHeight,
                fillColorArgb: colorArgb,
                backgroundColorArgb: 0x00000000,
                screenSpace: false,
                zIndex: 1000,
              ),
            );
      }
      final p = positions.get(marker)!;
      p.x = pos.x - cellSize / 2;
      p.y = pos.y + cellSize / 2 - barHeight;
    }
  }
}

/// What a tap did, so the UI can react (e.g. play a sound on `commanded`).
enum GridTapResult { selected, commanded, ignored }

/// Converts world-space taps/drags into grid selection and commands, so
/// a `Scene.handleTap` is one line. The selection and ordering rules
/// live in `engine_core` (`selectAtCell`, `commandSelected`); this class
/// only owns the pixel-to-cell mapping.
class GridTapController {
  final double cellSize;
  final double originX;
  final double originY;

  GridTapController(this.cellSize, {this.originX = 0, this.originY = 0, this.localTeam});

  /// The team the local player commands. Required for real-time games (no turn
  /// clock to say whose side it is); in turn-based games leave it null and the
  /// active team is used.
  final String? localTeam;

  int colOf(double worldX) => ((worldX - originX) / cellSize).floor();
  int rowOf(double worldY) => ((worldY - originY) / cellSize).floor();

  /// Tap on a own unit selects it; otherwise, with a selection, issues
  /// move/attack orders to that cell; otherwise nothing.
  GridTapResult handleTap(World world, Offset worldPosition, {bool additive = false}) {
    final col = colOf(worldPosition.dx);
    final row = rowOf(worldPosition.dy);
    if (selectAtCell(world, col, row, additive: additive, team: localTeam) != null) {
      return GridTapResult.selected;
    }
    if (selectedEntities(world).isNotEmpty && commandSelected(world, col, row, replace: !additive, team: localTeam) > 0) {
      return GridTapResult.commanded;
    }
    return GridTapResult.ignored;
  }

  /// Box-selects between two world points (a drag rectangle).
  int handleDrag(World world, Offset start, Offset end, {bool additive = false}) =>
      selectInBox(world, colOf(start.dx), rowOf(start.dy), colOf(end.dx), rowOf(end.dy),
          additive: additive, team: localTeam);
}
