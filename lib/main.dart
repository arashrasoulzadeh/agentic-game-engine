import 'dart:math';

import 'package:engine_core/engine_core.dart';
import 'package:flutter/material.dart' hide Velocity;
import 'package:flutter/scheduler.dart';

void main() => runApp(const StressTestApp());

class StressTestApp extends StatelessWidget {
  const StressTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: StressTestScreen(),
    );
  }
}

class StressTestScreen extends StatefulWidget {
  const StressTestScreen({super.key});

  @override
  State<StressTestScreen> createState() => _StressTestScreenState();
}

class _StressTestScreenState extends State<StressTestScreen>
    with SingleTickerProviderStateMixin {
  static const worldW = 1600.0;
  static const worldH = 900.0;

  late final World _world;
  late final Ticker _ticker;
  final _rng = Random();
  Duration _lastTick = Duration.zero;

  int _entityCount = 0;
  double _fps = 0;
  double _stepMs = 0;
  final List<double> _frameTimes = [];

  @override
  void initState() {
    super.initState();
    _world = World(width: worldW, height: worldH);
    registerCoreComponents(_world);
    _world.addSystem(MovementSystem());
    _world.addSystem(CollisionSystem());
    _setCount(200);
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final dt = _lastTick == Duration.zero
        ? 0.0
        : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (dt <= 0 || dt > 0.25) return;

    final sw = Stopwatch()..start();
    _world.step(dt);
    sw.stop();

    _frameTimes.add(dt);
    if (_frameTimes.length > 30) _frameTimes.removeAt(0);
    final avgDt = _frameTimes.reduce((a, b) => a + b) / _frameTimes.length;

    setState(() {
      _fps = avgDt > 0 ? 1 / avgDt : 0;
      _stepMs = sw.elapsedMicroseconds / 1000;
    });
  }

  void _setCount(int target) {
    final diff = target - _entityCount;
    if (diff > 0) {
      for (var i = 0; i < diff; i++) {
        final id = _world.spawn();
        final speed = 40 + _rng.nextDouble() * 120;
        final angle = _rng.nextDouble() * 2 * pi;
        _world.storeOf<Position>().set(
              id,
              Position(_rng.nextDouble() * worldW, _rng.nextDouble() * worldH),
            );
        _world.storeOf<Velocity>().set(
              id,
              Velocity(cos(angle) * speed, sin(angle) * speed),
            );
        _world.storeOf<Collider>().set(id, Collider(4 + _rng.nextDouble() * 4));
      }
    } else if (diff < 0) {
      final toRemove = _world.entities.all.take(-diff).toList();
      for (final id in toRemove) {
        _world.destroy(id);
      }
    }
    _entityCount = target;
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'entities: $_entityCount   fps: ${_fps.toStringAsFixed(1)}   sim step: ${_stepMs.toStringAsFixed(2)}ms',
                    style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace'),
                  ),
                  for (final n in [200, 500, 1000, 2000, 5000, 10000])
                    ElevatedButton(
                      onPressed: () => _setCount(n),
                      child: Text('$n'),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: worldW / worldH,
                  child: ClipRect(
                    child: CustomPaint(
                      painter: _WorldPainter(_world),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorldPainter extends CustomPainter {
  final World world;
  _WorldPainter(this.world) : super(repaint: null);

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / world.width;
    final scaleY = size.height / world.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF111318));

    final paint = Paint()..color = Colors.cyanAccent;
    final positions = world.storeOf<Position>();
    final colliders = world.storeOf<Collider>();
    for (var i = 0; i < positions.length; i++) {
      final entity = positions.entityAt(i);
      final pos = positions.denseAt(i);
      final radius = colliders.get(entity)?.radius ?? 3;
      canvas.drawCircle(
        Offset(pos.x * scaleX, pos.y * scaleY),
        radius * ((scaleX + scaleY) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WorldPainter oldDelegate) => true;
}
