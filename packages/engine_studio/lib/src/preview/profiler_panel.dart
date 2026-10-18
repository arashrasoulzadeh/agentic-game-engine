import 'package:engine_core/engine_core.dart';
import 'package:flutter/material.dart';

/// Live timings from the running preview's [WorldProfiler]: the step cost, the entity count,
/// a sparkline of recent step times, and the slowest systems with their smoothed and worst
/// times. Draws from the profiler each build, so it follows the preview as it ticks.
///
/// This is the *simulation* cost. It does not include the studio's own painting, so a level
/// that looks slow here is slow in the game too, and one that looks fine here is not
/// guaranteed to render fast on a device.
class ProfilerPanel extends StatelessWidget {
  const ProfilerPanel({super.key, required this.profiler, this.rows = 6});

  final WorldProfiler profiler;

  /// How many systems to list, slowest first.
  final int rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final systems = profiler.report().take(rows).toList();
    final style = theme.textTheme.bodySmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Material(
      key: const Key('profiler-panel'),
      color: theme.colorScheme.surface.withValues(alpha: 0.88),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: SizedBox(
          width: 230,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'step ${profiler.stepMs.toStringAsFixed(2)} ms · ${profiler.entityCount} entities',
                key: const Key('profiler-summary'),
                style: theme.textTheme.labelMedium,
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 28,
                width: double.infinity,
                child: CustomPaint(
                  key: const Key('profiler-sparkline'),
                  painter: _Sparkline([
                    for (final v in profiler.stepHistory.toList()) v,
                  ], theme.colorScheme.primary),
                ),
              ),
              const SizedBox(height: 4),
              if (systems.isEmpty)
                Text(
                  'No systems timed yet.',
                  key: const Key('profiler-empty'),
                  style: style,
                )
              else
                for (final t in systems)
                  Row(
                    key: Key('profiler-row-${t.name}'),
                    children: [
                      Expanded(
                        child: Text(
                          t.name,
                          style: style,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${t.averageMs.toStringAsFixed(3)} avg',
                        style: style,
                      ),
                      const SizedBox(width: 6),
                      Text('${t.maxMs.toStringAsFixed(2)} max', style: style),
                    ],
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Sparkline extends CustomPainter {
  _Sparkline(this.values, this.color);

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final top = values.reduce((a, b) => a > b ? a : b);
    final scale = top <= 0 ? 0.0 : size.height / top;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = size.height - values[i] * scale;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_Sparkline old) => true;
}
