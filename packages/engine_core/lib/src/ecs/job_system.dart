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
  bool _started = false;

  JobSystem({this.workerCount = 3});

  /// Starts the worker isolates.
  Future<void> start() async {
    if (_started) return;
    _started = true;

    for (int i = 0; i < workerCount; i++) {
      final receivePort = ReceivePort();
      final isolate = await Isolate.spawn(_workerEntry, receivePort.sendPort);
      _workers.add(isolate);

      final sendPort = await receivePort.first as SendPort;
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
  Future<Output> dispatch<Input, Output>(Job<Input, Output> job, Input input) async {
    if (!_started) await start();

    final jobId = _nextJobId++;
    final completer = Completer<JobResult<Output>>();
    _pendingJobs[jobId] = completer;

    final replyPort = ReceivePort();
    replyPort.listen((message) {
      if (message is JobResult<Output>) {
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
    return result.output!;
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

  /// Shuts down all worker isolates.
  void shutdown() {
    for (final worker in _workers) {
      worker.kill(priority: Isolate.immediate);
    }
    _workers.clear();
    _workerPorts.clear();
    _started = false;
  }
}

/// A job that processes a chunk of collision pairs for the broadphase.
class CollisionBroadphaseJob implements Job<CollisionBroadphaseInput, CollisionBroadphaseOutput> {
  @override
  CollisionBroadphaseOutput run(CollisionBroadphaseInput input) {
    final pairs = <CollisionPair>[];
    final hash = SpatialHash(cellSize: input.cellSize, worldWidth: input.worldWidth);

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

/// A job for pathfinding.
class PathfindingJob implements Job<PathfindingInput, PathfindingOutput> {
  @override
  PathfindingOutput run(PathfindingInput input) {
    // Simple A* pathfinding implementation
    // In practice, this would use the platformer pathfinding logic
    final path = <PathPoint>[];
    // ... pathfinding logic here
    return PathfindingOutput(path);
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