import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;
import 'package:flutter/material.dart';

/// A multiplayer client screen: mirrors a host's world, draws it, and turns taps into orders.
///
/// Give it an open [endpoint] (`connectWebSocket` on mobile/desktop, `connectBrowserWebSocket` on the web).
/// It builds the local mirror world and a `ClientSession`, shows [connectingBuilder] until the host has
/// assigned a team, then the game. Tap one of your units to select it; tap a cell to move the selected
/// unit there, or an enemy's cell to attack. Nothing is applied locally - an order is a request, and the
/// result arrives through the host's replicated state, so a refused order simply changes nothing (see
/// [onRejected]).
class OnlineStrategyView extends StatefulWidget {
  const OnlineStrategyView({
    super.key,
    required this.endpoint,
    required this.atlasRegistry,
    required this.gridCols,
    required this.gridRows,
    required this.cellSize,
    this.camera,
    this.onWelcome,
    this.onRejected,
    this.onDisconnected,
    this.connectingBuilder,
    this.disconnectedBuilder,
  });

  final NetEndpoint endpoint;
  final AtlasRegistry atlasRegistry;

  /// Size of the host's grid; the mirror world is sized to match.
  final int gridCols;
  final int gridRows;

  /// World units per grid cell (what the host's `GridToWorldSystem` uses).
  final double cellSize;

  /// The view's camera; by default centred on the grid.
  final Camera? camera;

  /// The host accepted this client; `session.team` is now set.
  final void Function(ClientSession session)? onWelcome;

  /// The host refused an order (a unit that is not yours, not your turn, ...).
  final void Function(EntityId unit, String reason)? onRejected;

  final VoidCallback? onDisconnected;

  /// Shown before the host's welcome arrives.
  final WidgetBuilder? connectingBuilder;

  /// Shown after the connection ends.
  final WidgetBuilder? disconnectedBuilder;

  @override
  State<OnlineStrategyView> createState() => OnlineStrategyViewState();
}

class OnlineStrategyViewState extends State<OnlineStrategyView> {
  late final World world;
  late final ClientSession session;
  late final Camera _camera;
  EntityId? _selected;
  bool _welcomed = false;
  bool _gone = false;

  /// The unit the next tap will command, or null.
  EntityId? get selected => _selected;

  @override
  void initState() {
    super.initState();
    world = World(
      width: widget.gridCols * widget.cellSize,
      height: widget.gridRows * widget.cellSize,
    );
    registerCoreComponents(world);
    registerFlutterComponents(world);
    world.addSystem(GridToWorldSystem(widget.cellSize));
    _camera =
        widget.camera ??
        Camera(
          x: widget.gridCols * widget.cellSize / 2,
          y: widget.gridRows * widget.cellSize / 2,
        );
    session = ClientSession(world: world, endpoint: widget.endpoint)
      ..onWelcome = () {
        if (!mounted) return;
        setState(() => _welcomed = true);
        widget.onWelcome?.call(session);
      }
      ..onRejected = (unit, reason) {
        widget.onRejected?.call(unit, reason);
      }
      ..onDisconnected = () {
        if (!mounted) return;
        setState(() => _gone = true);
        widget.onDisconnected?.call();
      };
  }

  /// What a tap on ([col], [row]) does; public so tests and custom input (keyboard cursor, gamepad) can
  /// drive it without going through pixel coordinates.
  void tapCell(int col, int row) {
    final team = session.team;
    if (team == null) return;
    final mine = selectAtCell(world, col, row, team: team);
    if (mine != null) {
      setState(() => _selected = mine);
      return;
    }
    final unit = _selected;
    if (unit == null || !world.entities.isAlive(unit)) return;

    final grid = world.storeOf<GridPosition>();
    final teams = world.storeOf<Team>();
    EntityId? enemy;
    for (var i = 0; i < grid.length; i++) {
      final e = grid.entityAt(i);
      final p = grid.denseAt(i);
      if (p.col == col && p.row == row) {
        final t = teams.get(e)?.id;
        if (t != null && t != team) enemy = e;
      }
    }
    session.sendOrder(
      unit,
      enemy != null ? AttackOrder(enemy) : MoveOrder(col, row),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_gone) {
      return widget.disconnectedBuilder?.call(context) ??
          const Center(child: Text('Disconnected'));
    }
    if (!_welcomed) {
      return widget.connectingBuilder?.call(context) ??
          const Center(child: CircularProgressIndicator());
    }
    return EngineView(
      world: world,
      atlasRegistry: widget.atlasRegistry,
      camera: _camera,
      stepsWorld: true,
      onWorldTap: (p) => tapCell(
        (p.dx / widget.cellSize).floor(),
        (p.dy / widget.cellSize).floor(),
      ),
    );
  }
}
