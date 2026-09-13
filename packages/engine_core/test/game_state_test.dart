import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

void main() {
  test('GameState defaults to an empty data map', () {
    expect(GameState().data, isEmpty);
  });

  test('GameState seeds initial data when given a map', () {
    final state = GameState({'coinsCollected': 3});
    expect(state.data['coinsCollected'], 3);
  });

  test('GameState.data is mutable in place', () {
    final state = GameState();
    state.data['coinsCollected'] = 1;
    state.data['coinsCollected'] = (state.data['coinsCollected'] as int) + 1;
    expect(state.data['coinsCollected'], 2);
  });

  test('GameState round-trips through toJson/fromJson', () {
    final state = GameState({'coinsCollected': 5, 'unlockedRooms': ['a', 'b']});
    final decoded = GameState.fromJson(state.toJson());
    expect(decoded.data, state.data);
  });
}
