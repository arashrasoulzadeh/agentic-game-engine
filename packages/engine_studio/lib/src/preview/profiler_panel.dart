import 'package:engine_core/engine_core.dart';
import 'package:flutter/material.dart';

/// How long the preview's own painting takes, smoothed so the number is readable. The painter records into
/// it after each frame; [ProfilerPanel] shows it beside the simulation cost.
class PaintTimer {
  /// The most recent paint, in milliseconds.
  double lastMs = 0;

  /// An exponential moving average of recent paints (new samples weigh 20%).
  double averageMs = 0;

  /// How many paints were recorded.
  int frames = 0;

  /// Records one paint of [ms] milliseconds.
  void record(double ms) {
    lastMs = ms;
    averageMs = frames == 0 ? ms : averageMs * 0.8 + ms * 0.2;
    frames++;
  }
}

/// Live timings from the running preview's [WorldProfiler]: the step cost, the entity count,
/// a sparkline of recent step times, and the slowest systems with their smoothed and worst
/// times. Draws from the profiler each build, so it follows the preview as it ticks.
///
/// The step and system numbers are the *simulation* cost: a level that looks slow there is slow in the game too.
/// The paint line is the studio preview's own drawing, not the game's renderer, so a level that looks fine
/// here is still not guaranteed to render fast on a device.
class ProfilerPanel extends StatelessWidget {
  const ProfilerPanel({
    super.key,
    required this.profiler,
    this.paintTimer,
    this.rows = 6,
  });

  final WorldProfiler profiler;

  /// When given, the studio's own paint cost is shown too (the numbers below it are simulation only).
  final PaintTimer? paintTimer;

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
              if (paintTimer != null && paintTimer!.frames > 0)
                Text(
                  'paint ${paintTimer!.lastMs.toStringAsFixed(2)} ms (avg ${paintTimer!.averageMs.toStringAsFixed(2)})',
                  key: const Key('profiler-paint'),
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
