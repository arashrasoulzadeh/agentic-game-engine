import 'dart:async';
import 'dart:isolate';

import '../physics/spatial_hash.dart';

/// A job that can be executed in a background isolate.
/// Jobs must be stateless and contain all data needed for execution.
abstract class Job<Input, Output> {
  /// Runs the job and returns the result.
  Output run(Input input);
}

/// Result of a job execution, sent back from the worker isolate.
class JobResult<Output> {
  final int jobId;
  final Output? output;
  final Object? error;
  final StackTrace? stackTrace;

  JobResult.success(this.jobId, this.output) : error = null, stackTrace = null;
  JobResult.failure(this.jobId, this.error, this.stackTrace) : output = null;

  bool get isSuccess => error == null;
}

/// Message sent to worker isolates.
class WorkerMessage<Input> {
  final int jobId;
  final Job<Input, dynamic> job;
  final Input input;
  final SendPort replyPort;

  WorkerMessage(this.jobId, this.job, this.input, this.replyPort);
}

/// A simple job queue that distributes work across multiple worker isolates.
/// Designed for CPU-intensive tasks like collision broadphase, pathfinding, etc.
class JobSystem {
  final int workerCount;
  final List<Isolate> _workers = [];
  final List<SendPort> _workerPorts = [];
  final Map<int, Completer<JobResult>> _pendingJobs = {};
  int _nextJobId = 0;
  int _currentWorker = 0;

  JobSystem({this.workerCount = 3});

  Future<void>? _starting;

  /// Starts the worker isolates. Safe to call repeatedly or concurrently: every caller gets the
  /// same in-progress start, so a [dispatchBatch] issued before the workers are up waits for
  /// them instead of finding none.
  Future<void> start() => _starting ??= _spawnWorkers();

  /// Bumped by [shutdown]. A start that finds it changed has been shut down mid-way and must
  /// not leave workers behind.
  int _generation = 0;

  Future<void> _spawnWorkers() async {
    final generation = _generation;
    for (int i = 0; i < workerCount; i++) {
      final receivePort = ReceivePort();
      final isolate = await Isolate.spawn(_workerEntry, receivePort.sendPort);
      if (generation != _generation) {
        isolate.kill(priority: Isolate.immediate);
        receivePort.close();
        return;
      }
      _workers.add(isolate);

      final sendPort = await receivePort.first as SendPort;
      if (generation != _generation) {
        isolate.kill(priority: Isolate.immediate);
        _workers.remove(isolate);
        return;
      }
      _workerPorts.add(sendPort);
    }
  }

  /// Entry point for worker isolates.
  static void _workerEntry(SendPort mainPort) {
    final port = ReceivePort();
    mainPort.send(port.sendPort);

    port.listen((message) {
      if (message is WorkerMessage) {
        try {
          final result = message.job.run(message.input);
          message.replyPort.send(JobResult.success(message.jobId, result));
        } catch (e, st) {
          message.replyPort.send(JobResult.failure(message.jobId, e, st));
        }
      }
    });
  }

  /// Dispatches a job to a worker and returns a future that completes with the result.
  Future<Output> dispatch<Input, Output>(
    Job<Input, Output> job,
    Input input,
  ) async {
    await start();
    if (_workerPorts.isEmpty) {
      // shutdown() ran while this dispatch was waiting for the workers.
      throw StateError('JobSystem was shut down');
    }

    final jobId = _nextJobId++;
    final completer = Completer<JobResult>();
    _pendingJobs[jobId] = completer;

    // Matched as a plain JobResult, not JobResult<Output>: the worker builds it with a dynamic
    // type argument, and a JobResult<dynamic> is not a JobResult<int> at runtime, so a typed
    // match never fired and every dispatch hung forever.
    final replyPort = ReceivePort();
    replyPort.listen((message) {
      if (message is JobResult && !completer.isCompleted) {
        completer.complete(message);
        replyPort.close();
      }
    });

    // Round-robin worker selection
    final workerPort = _workerPorts[_currentWorker];
    _currentWorker = (_currentWorker + 1) % _workerPorts.length;

    workerPort.send(WorkerMessage(jobId, job, input, replyPort.sendPort));

    final result = await completer.future;
    _pendingJobs.remove(jobId);

    if (!result.isSuccess) {
      throw result.error!;
    }
    return result.output as Output;
  }

  /// Dispatches multiple jobs of the same type and waits for all results.
  Future<List<Output>> dispatchBatch<Input, Output>(
    Job<Input, Output> job,
    List<Input> inputs,
  ) async {
    final futures = <Future<Output>>[];
    for (final input in inputs) {
      futures.add(dispatch(job, input));
    }
    return Future.wait(futures);
  }

  /// Shuts down all worker isolates. Jobs still in flight fail with a [StateError] rather than
  /// waiting forever for a worker that no longer exists. Can be followed by [start] (or just
  /// another [dispatch]) to bring up fresh workers.
  void shutdown() {
    _generation++;
    for (final pending in _pendingJobs.values.toList()) {
      if (!pending.isCompleted) {
        pending.complete(
          JobResult.failure(-1, StateError('JobSystem was shut down'), null),
        );
      }
    }
    _pendingJobs.clear();
    for (final worker in _workers) {
      worker.kill(priority: Isolate.immediate);
    }
    _workers.clear();
    _workerPorts.clear();
    _starting = null;
  }
}

/// A job that processes a chunk of collision pairs for the broadphase.
class CollisionBroadphaseJob
    implements Job<CollisionBroadphaseInput, CollisionBroadphaseOutput> {
  @override
  CollisionBroadphaseOutput run(CollisionBroadphaseInput input) {
    final pairs = <CollisionPair>[];
    final hash = SpatialHash(
      cellSize: input.cellSize,
      worldWidth: input.worldWidth,
    );

    // Insert entities into spatial hash
    for (final entity in input.entities) {
      hash.insert(entity.id, entity.x, entity.y);
    }

    // Find nearby pairs
    hash.forEachNearbyPair((a, b) {
      final entityA = input.entityMap[a]!;
      final entityB = input.entityMap[b]!;
      pairs.add(CollisionPair(entityA, entityB));
    });

    return CollisionBroadphaseOutput(pairs);
  }
}

/// Input for collision broadphase job.
class CollisionBroadphaseInput {
  final double cellSize;
  final double worldWidth;
  final List<CollisionEntity> entities;
  final Map<int, CollisionEntity> entityMap;

  CollisionBroadphaseInput({
    required this.cellSize,
    required this.worldWidth,
    required this.entities,
    required this.entityMap,
  });
}

/// Entity data for collision broadphase (serializable).
class CollisionEntity {
  final int id;
  final double x;
  final double y;
  final double radius;
  final int collisionGroup;
  final int collisionMask;
  final bool pushable;

  CollisionEntity({
    required this.id,
    required this.x,
    required this.y,
    required this.radius,
    required this.collisionGroup,
    required this.collisionMask,
    required this.pushable,
  });
}

/// A collision pair found by broadphase.
class CollisionPair {
  final CollisionEntity a;
  final CollisionEntity b;

  CollisionPair(this.a, this.b);
}

/// Output of collision broadphase job.
class CollisionBroadphaseOutput {
  final List<CollisionPair> pairs;

  CollisionBroadphaseOutput(this.pairs);
}

/// A job for pathfinding: A* over a tile grid, four-way, each step costing one.
///
/// Returns the centres of the tiles from the one holding the start to the one holding the goal
/// (both included), or an empty path when either lies outside the grid or inside a solid tile,
/// or no route exists. It knows nothing about gravity: [PathPoint.jumpRequired] and
/// [PathPoint.climbRequired] are always false, so this is for top-down or flying movement. For
/// platformer-aware paths use the platformer pathfinding on the main isolate.
class PathfindingJob implements Job<PathfindingInput, PathfindingOutput> {
  @override
  PathfindingOutput run(PathfindingInput input) {
    final grid = input.grid;
    final rows = grid.length;
    final cols = rows == 0 ? 0 : grid.first.length;
    final tw = input.tileWidth, th = input.tileHeight;
    final sc = (input.startX / tw).floor(), sr = (input.startY / th).floor();
    final gc = (input.goalX / tw).floor(), gr = (input.goalY / th).floor();

    bool open(int c, int r) =>
        c >= 0 && r >= 0 && c < cols && r < rows && grid[r][c] == 0;
    if (!open(sc, sr) || !open(gc, gr)) return PathfindingOutput(const []);

    int key(int c, int r) => r * cols + c;
    int h(int c, int r) => (c - gc).abs() + (r - gr).abs();

    final cost = <int, int>{key(sc, sr): 0};
    final from = <int, int>{};
    // Open set as a list kept small by the grid; ties broken by the lower key so the path is
    // deterministic.
    final frontier = <int>[key(sc, sr)];
    final closed = <int>{};

    while (frontier.isNotEmpty) {
      var best = 0;
      for (var i = 1; i < frontier.length; i++) {
        final a = frontier[i], b = frontier[best];
        final fa = cost[a]! + h(a % cols, a ~/ cols),
            fb = cost[b]! + h(b % cols, b ~/ cols);
        if (fa < fb || (fa == fb && a < b)) best = i;
      }
      final cur = frontier.removeAt(best);
      if (!closed.add(cur)) continue;
      final c = cur % cols, r = cur ~/ cols;
      if (c == gc && r == gr) {
        final tiles = <int>[cur];
        while (from.containsKey(tiles.last)) {
          tiles.add(from[tiles.last]!);
        }
        return PathfindingOutput([
          for (final t in tiles.reversed)
            PathPoint(x: (t % cols + 0.5) * tw, y: (t ~/ cols + 0.5) * th),
        ]);
      }
      for (final (dc, dr) in const [(0, -1), (1, 0), (0, 1), (-1, 0)]) {
        final nc = c + dc, nr = r + dr;
        if (!open(nc, nr)) continue;
        final nk = key(nc, nr);
        final ng = cost[cur]! + 1;
        if (ng < (cost[nk] ?? 1 << 30)) {
          cost[nk] = ng;
          from[nk] = cur;
          frontier.add(nk);
        }
      }
    }
    return PathfindingOutput(const []);
  }
}

/// Input for pathfinding job.
class PathfindingInput {
  final double startX;
  final double startY;
  final double goalX;
  final double goalY;
  final List<List<int>> grid; // 0 = empty, 1 = solid
  final int tileWidth;
  final int tileHeight;

  PathfindingInput({
    required this.startX,
    required this.startY,
    required this.goalX,
    required this.goalY,
    required this.grid,
    required this.tileWidth,
    required this.tileHeight,
  });
}

/// Output of pathfinding job.
class PathfindingOutput {
  final List<PathPoint> path;

  PathfindingOutput(this.path);
}

/// A simple path point.
class PathPoint {
  final double x;
  final double y;
  final bool jumpRequired;
  final bool climbRequired;

  PathPoint({
    required this.x,
    required this.y,
    this.jumpRequired = false,
    this.climbRequired = false,
  });
}
