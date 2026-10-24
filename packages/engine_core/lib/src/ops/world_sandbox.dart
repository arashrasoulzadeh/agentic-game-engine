import '../ecs/world.dart';

/// Headless, in-memory worlds an agent can build from a level, step, inspect and patch without touching any file.
///
/// Held by the [OpContext] so every transport of one server shares them. A world is capped (a loaded level can be
/// big) and dropped after [ttl] of not being used, so an agent that forgets to discard cannot leak memory.
class WorldSandbox {
  WorldSandbox({this.maxWorlds = 4, this.ttl = const Duration(minutes: 10)});

  final int maxWorlds;
  final Duration ttl;
  final Map<String, _Slot> _slots = {};
  int _next = 1;

  /// Stores [world] and returns its id, or null when the cap is reached after dropping expired worlds.
  String? add(World world, DateTime now) {
    _expire(now);
    if (_slots.length >= maxWorlds) return null;
    final id = 'w${_next++}';
    _slots[id] = _Slot(world, now);
    return id;
  }

  /// The world with [id] (refreshing its idle timer), or null if unknown or expired.
  World? get(String id, DateTime now) {
    _expire(now);
    final slot = _slots[id];
    if (slot == null) return null;
    slot.lastUsed = now;
    return slot.world;
  }

  bool discard(String id) => _slots.remove(id) != null;

  int get count => _slots.length;

  void _expire(DateTime now) =>
      _slots.removeWhere((_, s) => now.difference(s.lastUsed) > ttl);
}

class _Slot {
  _Slot(this.world, this.lastUsed);
  final World world;
  DateTime lastUsed;
}
