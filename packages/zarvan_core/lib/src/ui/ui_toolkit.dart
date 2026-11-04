import 'dart:math' as math;

/// A rectangle in UI space (top-left origin).
class UiRect {
  const UiRect(this.x, this.y, this.width, this.height);

  final double x;
  final double y;
  final double width;
  final double height;

  double get right => x + width;
  double get bottom => y + height;

  bool contains(double px, double py) =>
      px >= x && px < right && py >= y && py < bottom;

  @override
  bool operator ==(Object other) =>
      other is UiRect &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(x, y, width, height);

  @override
  String toString() => 'UiRect($x, $y, $width x $height)';
}

/// Lays out children inside [bounds] along one axis.
///
/// Each entry of [sizes] is a fixed length, or null for a flexible child that
/// shares what is left equally with the other flexible children. [gap] goes
/// between children and [padding] around all of them. Returns one rect per
/// child; fixed sizes that overflow are not shrunk (the caller decides).
List<UiRect> layoutStack(
  UiRect bounds,
  List<double?> sizes, {
  bool vertical = true,
  double gap = 0,
  double padding = 0,
}) {
  if (sizes.isEmpty) return const [];
  final inner = UiRect(
    bounds.x + padding,
    bounds.y + padding,
    math.max(0, bounds.width - 2 * padding),
    math.max(0, bounds.height - 2 * padding),
  );
  final main = vertical ? inner.height : inner.width;
  final fixed = sizes.fold<double>(0, (a, s) => a + (s ?? 0));
  final flex = sizes.where((s) => s == null).length;
  final free = math.max(0.0, main - fixed - gap * (sizes.length - 1));
  final each = flex == 0 ? 0.0 : free / flex;
  final out = <UiRect>[];
  var cursor = vertical ? inner.y : inner.x;
  for (final s in sizes) {
    final len = s ?? each;
    out.add(
      vertical
          ? UiRect(inner.x, cursor, inner.width, len)
          : UiRect(cursor, inner.y, len, inner.height),
    );
    cursor += len + gap;
  }
  return out;
}

/// Where inside its parent an anchored box sits.
enum UiAnchor {
  topLeft,
  top,
  topRight,
  left,
  center,
  right,
  bottomLeft,
  bottom,
  bottomRight,
}

/// A [width] x [height] box pinned to [anchor] inside [parent], offset by
/// ([dx], [dy]) (positive moves right/down), so a HUD stays put on any
/// screen size.
UiRect anchorRect(
  UiRect parent,
  UiAnchor anchor,
  double width,
  double height, {
  double dx = 0,
  double dy = 0,
}) {
  final col = anchor.index % 3; // 0 left, 1 centre, 2 right
  final row = anchor.index ~/ 3;
  final x = parent.x + (parent.width - width) * col / 2 + dx;
  final y = parent.y + (parent.height - height) * row / 2 + dy;
  return UiRect(x, y, width, height);
}

/// Scroll position and selection for a list of equal-height rows.
///
/// Pure state: feed it drags/wheel/keys, ask it which rows are visible and
/// where to draw them. Dragging with a release velocity coasts and slows
/// by [friction] per second.
class ScrollListModel {
  ScrollListModel({
    required this.itemCount,
    required this.itemHeight,
    required this.viewportHeight,
    this.friction = 6,
  });

  int itemCount;
  final double itemHeight;
  double viewportHeight;

  /// Exponential slow-down of a fling, per second.
  final double friction;

  double _offset = 0;
  double _velocity = 0;
  int? selected;

  double get contentHeight => itemCount * itemHeight;

  /// Furthest the list can scroll.
  double get maxOffset => math.max(0, contentHeight - viewportHeight);

  double get offset => _offset;

  /// Scrolls by [delta], clamped to the content; kills a fling that hit an end.
  void scrollBy(double delta) {
    final next = (_offset + delta).clamp(0, maxOffset).toDouble();
    if (next != _offset + delta) _velocity = 0;
    _offset = next;
  }

  /// Starts a fling at [velocity] (pixels per second, positive = down).
  void fling(double velocity) => _velocity = velocity;

  /// Advances a fling by [dt] seconds.
  void update(double dt) {
    if (_velocity.abs() < 1) {
      _velocity = 0;
      return;
    }
    scrollBy(_velocity * dt);
    _velocity *= math.exp(-friction * dt);
  }

  /// Index range `[first, last]` of rows at least partly visible, or null
  /// for an empty list.
  (int, int)? get visibleRange {
    if (itemCount == 0) return null;
    final first = (_offset / itemHeight).floor();
    final last = ((_offset + viewportHeight) / itemHeight).ceil() - 1;
    return (first, math.min(itemCount - 1, last));
  }

  /// Top of row [index] in viewport space (negative when scrolled past).
  double rowTop(int index) => index * itemHeight - _offset;

  /// Row under a viewport-space y, or null outside the content.
  int? indexAt(double y) {
    final i = ((y + _offset) / itemHeight).floor();
    return i < 0 || i >= itemCount || y < 0 || y >= viewportHeight ? null : i;
  }

  /// Moves the selection by [step] (clamped) and scrolls it into view.
  void moveSelection(int step) {
    if (itemCount == 0) return;
    selected = ((selected ?? (step > 0 ? -1 : itemCount)) + step).clamp(
      0,
      itemCount - 1,
    );
    ensureVisible(selected!);
  }

  /// Scrolls the minimum needed to show row [index] fully.
  void ensureVisible(int index) {
    final top = index * itemHeight;
    if (top < _offset) {
      _offset = top;
    } else if (top + itemHeight > _offset + viewportHeight) {
      _offset = math.min(maxOffset, top + itemHeight - viewportHeight);
    }
  }
}

/// Editing state for a single-line text field: text, caret, optional length
/// limit and character filter. Rendering and the platform keyboard stay in
/// the host; this is the part worth testing.
class TextInputModel {
  TextInputModel({String text = '', this.maxLength, this.allowed})
    : _text = text {
    _caret = _text.length;
  }

  /// Longest text accepted, or null for unlimited.
  final int? maxLength;

  /// Characters accepted when set (for example digits only); others are dropped.
  final RegExp? allowed;

  String _text;
  late int _caret;

  String get text => _text;
  int get caret => _caret;

  /// Inserts [s] at the caret, dropping disallowed characters and anything
  /// beyond [maxLength].
  void insert(String s) {
    var add = allowed == null
        ? s
        : s.split('').where((c) => allowed!.hasMatch(c)).join();
    if (maxLength != null) {
      add = add.substring(
        0,
        math.min(add.length, math.max(0, maxLength! - _text.length)),
      );
    }
    if (add.isEmpty) return;
    _text = _text.substring(0, _caret) + add + _text.substring(_caret);
    _caret += add.length;
  }

  /// Deletes the character before the caret.
  void backspace() {
    if (_caret == 0) return;
    _text = _text.substring(0, _caret - 1) + _text.substring(_caret);
    _caret--;
  }

  /// Deletes the character after the caret.
  void delete() {
    if (_caret >= _text.length) return;
    _text = _text.substring(0, _caret) + _text.substring(_caret + 1);
  }

  /// Moves the caret by [step], clamped to the text.
  void moveCaret(int step) => _caret = (_caret + step).clamp(0, _text.length);

  void home() => _caret = 0;
  void end() => _caret = _text.length;

  void clear() {
    _text = '';
    _caret = 0;
  }
}
