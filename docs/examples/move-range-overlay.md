# Recipe: show where a unit can move

`GridNavigator.reachable` returns every cell a unit can reach within a budget,
mapped to the cheapest cost to get there — exactly what a blue "you can go
here" overlay needs.

```dart
final cells = nav.reachable(
  GridPosition(3, 3),                       // where the unit is
  2,                                        // its current action points
  blocked: (col, row) => col == 4 && row == 3,   // other units' cells
);

cells[(5, 3)];                // 2 — reached by walking around the blocker
cells.containsKey((4, 3));    // false — occupied
cells.containsKey((3, 3));    // false — the start cell is excluded
```

Terrain costs are respected (a forest cell costing 3 is unreachable on a
budget of 2), and diagonals follow the navigator's rules.

## Painting it

A `CustomPainter` placed above the `EngineView` and sharing its `Camera`:

```dart
class MoveRangePainter extends CustomPainter {
  MoveRangePainter(this.cells, this.camera, {this.cellSize = 48});

  final Iterable<(int, int)> cells;
  final Camera camera;
  final double cellSize;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = const Color(0x5540E0D0);
    for (final (col, row) in cells) {
      final topLeft = camera.worldToScreen(col * cellSize, row * cellSize, size);
      final bottomRight = camera.worldToScreen((col + 1) * cellSize, (row + 1) * cellSize, size);
      canvas.drawRect(Rect.fromPoints(topLeft, bottomRight), fill);
    }
  }

  @override
  bool shouldRepaint(MoveRangePainter old) => old.cells != cells || old.camera != camera;
}
```

Using it:

```dart
Stack(children: [
  EngineView(/* … */),
  IgnorePointer(
    child: CustomPaint(
      size: Size.infinite,
      painter: MoveRangePainter(cells.keys, camera),
    ),
  ),
]);
```

`IgnorePointer` keeps taps flowing through to the game. Recompute `cells`
when the selection changes or a unit moves — not every frame.

## Which budget to pass

| You want to show… | Budget |
|---|---|
| Where it can go this turn | `ActionPoints.current` |
| Its full potential next turn | `ActionPoints.max` |
| Attack range | not this API — attack range is Chebyshev distance (`GridPosition.chebyshev`) |

*Verified by `doc_examples_test.dart` ("move-range overlay").*
