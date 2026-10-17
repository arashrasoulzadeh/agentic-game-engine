/// A fixed-capacity buffer that keeps only the most recent values --
/// what a rolling graph or moving average needs, without the list
/// growing forever or paying `removeAt(0)` on every sample.
class RingBuffer<T> {
  final int capacity;
  final List<T?> _items;
  int _start = 0;
  int _length = 0;

  RingBuffer(this.capacity)
      : assert(capacity > 0, 'capacity must be positive'),
        _items = List<T?>.filled(capacity, null);

  int get length => _length;
  bool get isEmpty => _length == 0;

  /// Appends [value], dropping the oldest once full.
  void add(T value) {
    if (_length < capacity) {
      _items[(_start + _length) % capacity] = value;
      _length++;
    } else {
      _items[_start] = value;
      _start = (_start + 1) % capacity;
    }
  }

  /// The values oldest-first.
  List<T> toList() => [
        for (var i = 0; i < _length; i++) _items[(_start + i) % capacity] as T,
      ];

  T? get last => _length == 0 ? null : _items[(_start + _length - 1) % capacity];

  void clear() {
    _start = 0;
    _length = 0;
    _items.fillRange(0, capacity, null);
  }
}
