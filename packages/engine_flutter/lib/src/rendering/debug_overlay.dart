import 'dart:async';
import 'dart:convert';

import 'package:engine_core/engine_core.dart';
import 'package:flutter/material.dart' hide Action, Text;
import 'package:flutter/material.dart' as m show Text;

import '../input/input.dart';
import 'debug_memory.dart';
import 'frame_stats.dart';
import 'frame_timing_monitor.dart';

/// A rolling line graph of [values] (oldest first) against an optional
/// [budget] line -- e.g. 16.7 ms for a 60 fps frame. Values above the budget are
/// drawn in the warning colour, so a spike is visible at a glance.
class DebugGraph extends StatelessWidget {
  const DebugGraph({
    super.key,
    required this.label,
    required this.values,
    this.budget,
    this.unit = 'ms',
    this.height = 44,
    this.width = 180,
  });

  final String label;
  final List<double> values;

  /// Draws a horizontal line here and colours bars above it red.
  final double? budget;
  final String unit;
  final double height;
  final double width;

  @override
  Widget build(BuildContext context) {
    final last = values.isEmpty ? 0.0 : values.last;
    final peak = values.isEmpty ? 0.0 : values.reduce((a, b) => a > b ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        m.Text(
          '$label  ${last.toStringAsFixed(1)}$unit  (peak ${peak.toStringAsFixed(1)})',
          style: const TextStyle(color: Colors.white, fontSize: 10),
        ),
        CustomPaint(
          key: const Key('debug-graph-canvas'),
          size: Size(width, height),
          painter: DebugGraphPainter(values: values, budget: budget),
        ),
      ],
    );
  }
}

/// Paints the bars for [DebugGraph]. Public so a game can embed the same
/// graph in its own layout, and so it can be tested without a widget tree.
class DebugGraphPainter extends CustomPainter {
  DebugGraphPainter({required this.values, this.budget});

  final List<double> values;
  final double? budget;

  /// The value mapped to the full height: the budget doubled (so the budget line
  /// sits mid-graph with headroom), or the peak when there is no budget.
  double get scaleMax {
    final peak = values.isEmpty ? 0.0 : values.reduce((a, b) => a > b ? a : b);
    final base = budget != null ? budget! * 2 : peak;
    final top = peak > base ? peak : base;
    return top <= 0 ? 1 : top;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0x99000000),
    );
    if (values.isEmpty) return;
    final max = scaleMax;
    final barW = size.width / FrameStats.historyLength;
    for (var i = 0; i < values.length; i++) {
      final h = (values[i] / max).clamp(0.0, 1.0) * size.height;
      final over = budget != null && values[i] > budget!;
      canvas.drawRect(
        Rect.fromLTWH(
          i * barW,
          size.height - h,
          barW > 1 ? barW - 0.5 : barW,
          h,
        ),
        Paint()
          ..color = over ? const Color(0xFFFF5252) : const Color(0xFF69F0AE),
      );
    }
    if (budget != null) {
      final y = size.height - (budget! / max).clamp(0.0, 1.0) * size.height;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = const Color(0xFFFFEB3B)
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(DebugGraphPainter old) => true;
}

/// Shows every component on one entity as readable JSON, with prev/next to walk
/// the world's entities. `World.components.serializeEntity` is the source, so it
/// shows exactly what `World.toJson()` (and so an agent) would see.
class EntityInspector extends StatefulWidget {
  const EntityInspector({super.key, required this.world, this.initial});

  final World world;
  final EntityId? initial;

  /// Pretty JSON for [entity], or a note when it has no (registered)
  /// components or is gone.
  static String describeEntity(World world, EntityId entity) {
    if (!world.entities.isAlive(entity)) return 'entity $entity is not alive';
    final data = world.components.serializeEntity(entity);
    if (data.isEmpty) return 'entity $entity has no registered components';
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  @override
  State<EntityInspector> createState() => _EntityInspectorState();
}

class _EntityInspectorState extends State<EntityInspector> {
  EntityId? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
  }

  List<EntityId> get _ids => widget.world.entities.all.toList()..sort();

  void _step(int delta) {
    final ids = _ids;
    if (ids.isEmpty) return;
    final at = _selected == null ? -1 : ids.indexOf(_selected!);
    setState(() => _selected = ids[(at + delta) % ids.length]);
  }

  @override
  Widget build(BuildContext context) {
    final ids = _ids;
    final id = _selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: const Key('inspector-prev'),
              icon: const Icon(
                Icons.chevron_left,
                color: Colors.white,
                size: 18,
              ),
              onPressed: ids.isEmpty ? null : () => _step(-1),
            ),
            m.Text(
              id == null
                  ? 'entity: none (${ids.length})'
                  : 'entity: $id (${ids.length})',
              key: const Key('inspector-title'),
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
            IconButton(
              key: const Key('inspector-next'),
              icon: const Icon(
                Icons.chevron_right,
                color: Colors.white,
                size: 18,
              ),
              onPressed: ids.isEmpty ? null : () => _step(1),
            ),
          ],
        ),
        if (id != null)
          m.Text(
            EntityInspector.describeEntity(widget.world, id),
            key: const Key('inspector-body'),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
      ],
    );
  }
}

/// The profiler's per-system table: slowest average first, with the share of the
/// last step each took. Needs `world.profiler` set; otherwise shows how to enable
/// it.
class ProfilerPanel extends StatelessWidget {
  const ProfilerPanel({super.key, required this.world, this.maxRows = 8});

  final World world;
  final int maxRows;

  @override
  Widget build(BuildContext context) {
    final profiler = world.profiler;
    if (profiler == null) {
      return const m.Text(
        'profiler off: world.profiler = WorldProfiler()',
        style: TextStyle(color: Colors.white54, fontSize: 10),
      );
    }
    final shares = profiler.shares();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        m.Text(
          'step ${profiler.stepMs.toStringAsFixed(2)}ms  events ${profiler.eventsMs.toStringAsFixed(2)}ms',
          style: const TextStyle(color: Colors.white, fontSize: 10),
        ),
        for (final t in profiler.report().take(maxRows))
          m.Text(
            '${t.name}  ${t.averageMs.toStringAsFixed(2)}ms  '
            '${((shares[t.name] ?? 0) * 100).toStringAsFixed(0)}%',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
      ],
    );
  }
}

/// A composed debug HUD: frame / step / raster graphs, a memory graph where the
/// platform allows it, the pressed input actions (by their friendly alias), a
/// component census, the profiler table and an entity inspector.
///
/// Put it in a `Stack` above the `EngineView`, passing the same `FrameStats` you
/// gave that view. It repaints on a timer ([refresh]) rather than every frame, so
/// the overlay itself stays cheap.
class DebugOverlay extends StatefulWidget {
  const DebugOverlay({
    super.key,
    required this.world,
    required this.frameStats,
    this.timings,
    this.input,
    this.refresh = const Duration(milliseconds: 250),
    this.showInspector = true,
    this.frameBudgetMs = 1000 / 60,
  });

  final World world;
  final FrameStats frameStats;
  final FrameTimingMonitor? timings;
  final InputController? input;
  final Duration refresh;
  final bool showInspector;
  final double frameBudgetMs;

  /// "Jump, Left" for the held actions, labelled by alias.
  static String pressedLabel(InputController input) {
    final held = input.state.pressedActions.toList()..sort();
    if (held.isEmpty) return 'input: -';
    return 'input: ${held.map(input.aliases.labelFor).join(', ')}';
  }

  /// "position 12, velocity 9, ..." -- the biggest stores first.
  static String census(World world, {int top = 6}) {
    final counts = world.componentCounts().entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return counts.take(top).map((e) => '${e.key} ${e.value}').join(', ');
  }

  @override
  State<DebugOverlay> createState() => _DebugOverlayState();
}

class _DebugOverlayState extends State<DebugOverlay> {
  Timer? _timer;
  final RingBuffer<double> _memoryMb = RingBuffer<double>(
    FrameStats.historyLength,
  );

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.refresh, (_) {
      final bytes = currentMemoryUsageBytes();
      if (bytes != null) _memoryMb.add(bytes / (1024 * 1024));
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stats = widget.frameStats;
    final timings = widget.timings;
    final input = widget.input;
    const style = TextStyle(color: Colors.white, fontSize: 10);
    return IgnorePointer(
      ignoring: !widget.showInspector,
      child: Container(
        key: const Key('debug-overlay'),
        padding: const EdgeInsets.all(6),
        color: const Color(0x66000000),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              DebugGraph(
                label: 'frame',
                values: stats.frameHistory.toList(),
                budget: widget.frameBudgetMs,
              ),
              DebugGraph(
                label: 'step',
                values: stats.stepHistory.toList(),
                budget: widget.frameBudgetMs,
              ),
              if (timings != null)
                DebugGraph(
                  label: 'raster (gpu)',
                  values: timings.rasterHistory.toList(),
                  budget: widget.frameBudgetMs,
                ),
              if (!_memoryMb.isEmpty)
                DebugGraph(
                  label: 'memory',
                  values: _memoryMb.toList(),
                  unit: 'MB',
                ),
              m.Text(
                'entities ${stats.entities}  sprites ${stats.sprites}  particles ${stats.particles}',
                style: style,
              ),
              if (timings != null)
                m.Text(
                  'jank ${(timings.jankRatio * 100).toStringAsFixed(1)}%  worst raster '
                  '${timings.worstRasterMs.toStringAsFixed(1)}ms',
                  key: const Key('debug-jank'),
                  style: style,
                ),
              if (input != null)
                m.Text(
                  DebugOverlay.pressedLabel(input),
                  key: const Key('debug-input'),
                  style: style,
                ),
              m.Text(
                'components: ${DebugOverlay.census(widget.world)}',
                key: const Key('debug-census'),
                style: style,
              ),
              ProfilerPanel(world: widget.world),
              if (widget.showInspector) EntityInspector(world: widget.world),
            ],
          ),
        ),
      ),
    );
  }
}
