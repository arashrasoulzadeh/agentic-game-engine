// Mirrors docs/examples/talk-to-npc.md; keep the two in sync.
import 'package:zarvan_core/zarvan_core.dart';
import 'package:test/test.dart';

void main() {
  late World world;
  late DialogueRunner runner;
  late EntityId player;
  var talking = false;

  setUp(() {
    world = World(width: 400, height: 200);
    registerCoreComponents(world);
    world.spawnWith([
      GameState({'name': 'Mira'}),
    ]);

    player = world.spawnAt(0, 0);
    world.setName(player, 'player');
    final elder = world.spawnAt(20, 0);
    world.setName(elder, 'elder');

    final graph = DialogueGraph.fromJson({
      'startNodeId': 'greet',
      'nodes': {
        'greet': {
          'id': 'greet',
          'textKey': 'elder.greet',
          'choices': [
            {
              'textKey': 'elder.accept',
              'onSelectEvent': 'quest_accepted',
              'nextNodeId': 'thanks',
            },
            {'textKey': 'elder.decline', 'onSelectEvent': 'quest_declined'},
          ],
        },
        'thanks': {'id': 'thanks', 'textKey': 'elder.thanks', 'choices': []},
      },
    });
    talking = false;
    runner = DialogueRunner(
      graph: graph,
      onEnded: () => talking = false,
      stringTable: StringTable({
        'elder.greet': {'en': 'Will you help us, {name}?'},
        'elder.accept': {'en': 'Gladly'},
        'elder.decline': {'en': 'Not now'},
        'elder.thanks': {'en': 'Bless you.'},
      }),
    );
    world.addSystemFn('talk', (world, dt) {
      if (talking) return;
      final me = world.getComponent<Position>(world.find('player')!)!;
      final near = world.findNear(
        me.x,
        me.y,
        32,
        exclude: world.find('player'),
      );
      if (near.contains(world.find('elder'))) {
        runner.reset();
        talking = true;
      }
    });
  });

  test('walking up to the elder starts the conversation', () {
    expect(talking, isFalse, reason: 'nothing started yet');
    world.getComponent<Position>(player)!.x = 10;
    world.step(1 / 60);
    expect(talking, isTrue);
    expect(runner.currentText(WorldView(world)), 'Will you help us, Mira?');
  });

  test('staying far away never starts it', () {
    world.getComponent<Position>(player)!.x = -300;
    world.step(1 / 60);
    expect(talking, isFalse);
  });

  test('accepting emits the event the game reacts to', () {
    var questActive = false;
    world.events.on<String>((event) {
      if (event == 'quest_accepted') questActive = true;
    });
    world.getComponent<Position>(player)!.x = 10;
    world.step(1 / 60);
    runner.advance(world, 0);
    world.step(1 / 60);
    expect(questActive, isTrue);
    expect(runner.currentText(WorldView(world)), 'Bless you.');
  });

  test('declining ends it, and it can start again next time', () {
    world.getComponent<Position>(player)!.x = 10;
    world.step(1 / 60);
    runner.advance(world, 1);
    expect(talking, isFalse, reason: 'the choice ended it');
    world.getComponent<Position>(player)!.x = 12;
    world.step(1 / 60);
    expect(talking, isTrue, reason: 'still near, so it restarts');
  });
}
