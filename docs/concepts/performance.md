# Performance

Measure before you optimise. The engine gives you a per-system profiler, a set of benchmarks,
and a fixed-timestep loop that keeps the simulation cost predictable.

The profiler samples are executed by
`packages/engine_core/test/doc_examples_performance_test.dart`.

## Find the slow system: `WorldProfiler`

```dart
world.profiler = WorldProfiler();     // off by default: a world without one pays nothing
// ... run some frames ...
print(world.profiler!.format());
```

```text
# example output - your numbers will differ
step 0.412ms  events 0.020ms  entities 1840
collision  avg 0.188ms  max 0.390ms
movement   avg 0.075ms  max 0.120ms
...
```

- `report()` lists systems slowest first, each with `lastMs`, a smoothed `averageMs` and the worst
  `maxMs` since the last `reset()`.
- `stepMs`, `eventsMs` and `entityCount` describe the latest step; `stepHistory` keeps the last
  120 step times (a ring buffer) for a graph.
- `toJson()` gives the same data for tooling and agents.
- In the [studio](../studio/user-guide.md#play-test), the preview has a **Profiler** switch that
  shows these numbers live.

The profiler measures *simulation*. Rendering cost (drawing thousands of sprites, shaders,
lighting) is separate: a world can step in 0.3 ms and still render slowly. On a device, use Flutter's
own tools (DevTools performance overlay) for that side.

## Benchmarks

`engine_core/benchmark/` has micro-benchmarks for the pieces that scale with entity count:

```bash
cd packages/engine_core
dart run benchmark/world_step_benchmark.dart
dart run benchmark/collision_system_benchmark.dart
dart run benchmark/entity_churn_benchmark.dart
dart run benchmark/particle_system_benchmark.dart
dart run benchmark/world_view_benchmark.dart
```

Each prints a time per run for several entity counts (for example `WorldStep(movement only,
n=1000)`), so you can see whether a change is linear or worse. Numbers depend on the machine; compare
before and after on the *same* one, and run twice. The CLAUDE.md rule for this repo is to re-run the
relevant benchmark for any change to a hot path.

## Keep the step cost predictable

- **Fixed timestep.** Set `GameConfig.fixedTimestepSeconds` (for example `1 / 60`, or `1 / 20` for
  strategy games). The simulation then always advances by the same `dt`, so results are identical across devices -
  which replays and multiplayer need - and one slow frame cannot produce one huge step.
- **Iterate by entity id** in systems that must be deterministic; a component store's dense order
  depends on add/remove history (see the real-time strategy guide's determinism section).
- **Cap what grows**: particle `rate × lifetime`, projectiles, and anything spawned per frame all
  count as entities and show up in `entityCount`.
- **Avoid per-step allocation** in systems you write (build lists once, reuse them); `Archetype`
  gives dense iteration over entities that share a component set when a hot loop needs it.

## Background work: `JobSystem`

For CPU-heavy work that does not need the live world, `JobSystem` runs a `Job` on a pool of worker
isolates (default 3):

```dart
class SumJob implements Job<List<int>, int> {
  @override
  int run(List<int> input) => input.fold(0, (a, b) => a + b);
}

final jobs = JobSystem(workerCount: 2);
final total = await jobs.dispatch(SumJob(), [1, 2, 3]);                 // 6
final squares = await jobs.dispatchBatch(SquareJob(), [1, 2, 3]);       // results in input order
jobs.shutdown();
```

- A job is a **class** (a closure cannot cross isolates) and its input and output must be sendable:
  numbers, strings, lists, maps and plain objects, not entities of a live `World` or anything holding
  native resources. Copy the data you need into the input.
- An error thrown in a job is rethrown to the caller of `dispatch`; the system keeps working.
- Workers start on the first dispatch (or `start()`); concurrent callers share that start.
- `shutdown()` fails any jobs still in flight with a `StateError`, and the system can be started
  again afterwards.
- It costs a copy of the input and output per job, so it pays off for work that takes noticeably
  longer than that (broadphase over thousands of entities, large searches), not for small tasks.
- Isolates are unavailable on the web: do not use it in a game that ships there.
- Two ready-made jobs: `CollisionBroadphaseJob` and `PathfindingJob` (four-way A* over a tile grid,
  returning tile centres; it knows nothing about gravity, so it is for top-down or flying movement).

These behaviours are tested in `packages/engine_core/test/job_system_test.dart`.
