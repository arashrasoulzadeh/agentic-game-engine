import 'package:zarvan_core/zarvan_core.dart';
import 'package:test/test.dart';

void main() {
  test('BT factories build the same JSON as the long forms', () {
    final short = BT.selector([
      BT.sequence([BT.leaf('chase'), BT.wait(0.5)]),
      BT.repeat(3, BT.not(BT.leaf('x'))),
      BT.forever(BT.leaf('idle')),
      BT.cooldown(2, 'shoot'),
      BT.timeout(1, BT.leaf('y')),
      BT.parallel([BT.leaf('a'), BT.leaf('b')], requiredSuccess: 2),
      BT.random([BT.leaf('p'), BT.leaf('q')]),
    ]);
    final long = BTSelector(
      children: [
        BTSequence(
          children: [
            BTLeaf(behaviorId: 'chase'),
            BTWait(duration: 0.5),
          ],
        ),
        BTRepeater(
          child: BTInverter(child: BTLeaf(behaviorId: 'x')),
          count: 3,
        ),
        BTRepeater(child: BTLeaf(behaviorId: 'idle')),
        BTCooldown(behaviorId: 'shoot', cooldownDuration: 2),
        BTTimeout(child: BTLeaf(behaviorId: 'y'), timeoutDuration: 1),
        BTParallel(
          children: [
            BTLeaf(behaviorId: 'a'),
            BTLeaf(behaviorId: 'b'),
          ],
          requiredSuccess: 2,
        ),
        BTRandomSelector(
          children: [
            BTLeaf(behaviorId: 'p'),
            BTLeaf(behaviorId: 'q'),
          ],
        ),
      ],
    );
    expect(short.toJson(), long.toJson());
  });

  test('registerFn registers an inline behavior that decides', () {
    final world = World(width: 10, height: 10);
    final registry = BehaviorRegistry();
    final id = world.spawn();
    registry.registerFn('idle', (view, self) => NoOpAction());
    final action = registry.resolve('idle').decide(WorldView(world), id);
    expect(action, isA<NoOpAction>());
  });

  test('blackboard has, inc and remove', () {
    final world = World(width: 10, height: 10);
    final ctx = BTContext(WorldView(world), world.spawn());
    expect(ctx.has('n'), isFalse);
    expect(ctx.inc('n'), 1);
    expect(ctx.inc('n', 4), 5);
    expect(ctx.has('n'), isTrue);
    ctx.remove('n');
    expect(ctx.has('n'), isFalse);
  });
}
