import 'component_store.dart';
import 'entity.dart';
import 'world.dart';

/// Read-only joins over component collections.
///
/// Results are lazy and come in the dense order of the smallest collection
/// involved, which is deterministic for a given sequence of spawns and
/// destroys but not sorted by id. Do not destroy entities or add/remove
/// components of the driving type while iterating: collections reorder when
/// something is removed, so entities would be skipped. Queue those changes on
/// [World.commands] instead; in debug builds the iterator asserts when it
/// notices the driving collection changed size.
extension WorldQuery on World {
  /// Every entity that has an [A], as `(id, a)`.
  Iterable<(EntityId, A)> query<A>() => _Query1<A>(componentsOf<A>());

  /// Every entity that has both an [A] and a [B], as `(id, a, b)`.
  Iterable<(EntityId, A, B)> query2<A, B>() =>
      _Query2<A, B>(componentsOf<A>(), componentsOf<B>());

  /// Every entity that has an [A], a [B] and a [C], as `(id, a, b, c)`.
  Iterable<(EntityId, A, B, C)> query3<A, B, C>() =>
      _Query3<A, B, C>(componentsOf<A>(), componentsOf<B>(), componentsOf<C>());
}

// Plain iterators rather than `sync*`: a generator costs roughly an order of
// magnitude more per element (see benchmark/query_benchmark.dart), which
// matters for loops that run every tick.

class _Query1<A> extends Iterable<(EntityId, A)> {
  final ComponentStore<A> _as;
  _Query1(this._as);

  @override
  Iterator<(EntityId, A)> get iterator => _Query1Iterator<A>(_as);
}

class _Query1Iterator<A> implements Iterator<(EntityId, A)> {
  final ComponentStore<A> _as;
  final int _length;
  int _i = -1;
  _Query1Iterator(this._as) : _length = _as.length;

  @override
  late (EntityId, A) current;

  @override
  bool moveNext() {
    assert(_as.length == _length, _mutatedMessage<A>());
    if (++_i >= _as.length) return false;
    current = (_as.entityAt(_i), _as.denseAt(_i));
    return true;
  }
}

class _Query2<A, B> extends Iterable<(EntityId, A, B)> {
  final ComponentStore<A> _as;
  final ComponentStore<B> _bs;
  _Query2(this._as, this._bs);

  @override
  Iterator<(EntityId, A, B)> get iterator => _as.length <= _bs.length
      ? _Query2ByA<A, B>(_as, _bs)
      : _Query2ByB<A, B>(_as, _bs);
}

class _Query2ByA<A, B> implements Iterator<(EntityId, A, B)> {
  final ComponentStore<A> _as;
  final ComponentStore<B> _bs;
  final int _length;
  int _i = -1;
  _Query2ByA(this._as, this._bs) : _length = _as.length;

  @override
  late (EntityId, A, B) current;

  @override
  bool moveNext() {
    assert(_as.length == _length, _mutatedMessage<A>());
    while (++_i < _as.length) {
      final id = _as.entityAt(_i);
      final b = _bs.get(id);
      if (b != null) {
        current = (id, _as.denseAt(_i), b);
        return true;
      }
    }
    return false;
  }
}

class _Query2ByB<A, B> implements Iterator<(EntityId, A, B)> {
  final ComponentStore<A> _as;
  final ComponentStore<B> _bs;
  final int _length;
  int _i = -1;
  _Query2ByB(this._as, this._bs) : _length = _bs.length;

  @override
  late (EntityId, A, B) current;

  @override
  bool moveNext() {
    assert(_bs.length == _length, _mutatedMessage<B>());
    while (++_i < _bs.length) {
      final id = _bs.entityAt(_i);
      final a = _as.get(id);
      if (a != null) {
        current = (id, a, _bs.denseAt(_i));
        return true;
      }
    }
    return false;
  }
}

class _Query3<A, B, C> extends Iterable<(EntityId, A, B, C)> {
  final ComponentStore<A> _as;
  final ComponentStore<B> _bs;
  final ComponentStore<C> _cs;
  _Query3(this._as, this._bs, this._cs);

  @override
  Iterator<(EntityId, A, B, C)> get iterator =>
      _Query3Iterator<A, B, C>(_as, _bs, _cs);
}

class _Query3Iterator<A, B, C> implements Iterator<(EntityId, A, B, C)> {
  final ComponentStore<A> _as;
  final ComponentStore<B> _bs;
  final ComponentStore<C> _cs;
  // 0, 1 or 2: which collection drives (the smallest).
  late final int _driver;
  late final int _length;
  int _i = -1;

  _Query3Iterator(this._as, this._bs, this._cs) {
    final a = _as.length, b = _bs.length, c = _cs.length;
    _driver = (a <= b && a <= c) ? 0 : (b <= c ? 1 : 2);
    _length = _driver == 0 ? a : (_driver == 1 ? b : c);
  }

  @override
  late (EntityId, A, B, C) current;

  int get _driverLength =>
      _driver == 0 ? _as.length : (_driver == 1 ? _bs.length : _cs.length);

  @override
  bool moveNext() {
    assert(
      _driverLength == _length,
      _driver == 0
          ? _mutatedMessage<A>()
          : (_driver == 1 ? _mutatedMessage<B>() : _mutatedMessage<C>()),
    );
    while (++_i < _driverLength) {
      final id = _driver == 0
          ? _as.entityAt(_i)
          : (_driver == 1 ? _bs.entityAt(_i) : _cs.entityAt(_i));
      final a = _driver == 0 ? _as.denseAt(_i) : _as.get(id);
      final b = _driver == 1 ? _bs.denseAt(_i) : _bs.get(id);
      final c = _driver == 2 ? _cs.denseAt(_i) : _cs.get(id);
      if (a != null && b != null && c != null) {
        current = (id, a, b, c);
        return true;
      }
    }
    return false;
  }
}

String _mutatedMessage<T>() =>
    'A $T was added or removed while a world.query was iterating $T. '
    'Collections reorder when something is removed, so entities would be '
    'skipped. Queue the change with world.commands (destroy/set/remove) '
    'and let the step apply it.';
