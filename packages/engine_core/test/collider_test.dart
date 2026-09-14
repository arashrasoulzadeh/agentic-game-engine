import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

void main() {
  group('Collider', () {
    test('blocksLight defaults to false and round-trips through toJson/fromJson', () {
      expect(Collider(10).blocksLight, isFalse);

      final blocker = Collider(20, blocksLight: true);
      final restored = Collider.fromJson(blocker.toJson());
      expect(restored.radius, 20);
      expect(restored.blocksLight, isTrue);
    });

    test('fromJson defaults blocksLight to false when absent', () {
      final restored = Collider.fromJson({'radius': 5});
      expect(restored.blocksLight, isFalse);
    });
  });
}
