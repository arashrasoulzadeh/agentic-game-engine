import 'dart:async';
import 'dart:io';

import 'package:engine_api/engine_api.dart';
import 'package:engine_core/engine_core_ops.dart';
import 'package:test/test.dart';

void main() {
  late Directory project;
  setUp(() {
    project = Directory.systemTemp.createTempSync('api_cancel');
    File('${project.path}/pubspec.yaml').writeAsStringSync('name: demo\n');
    Directory('${project.path}/assets/levels').createSync(recursive: true);
  });
  tearDown(() => project.deleteSync(recursive: true));

  test('notifications/cancelled stops an in-flight tools/call', () async {
    final session = McpSession(
      buildRegistry(),
      OpContext(project: ProjectRoot(project.path), actor: 'test'),
    );
    final call = session.dispatch(
      'tools/call',
      {
        'name': 'strategy.simulate_turns',
        'arguments': {
          'json': {
            'entities': [
              {
                'name': 'red',
                'components': {
                  'team': {'id': 'red'},
                  'gridPosition': {'col': 0, 'row': 0},
                  'actionPoints': {'max': 4},
                  'unitStats': {'maxHp': 80, 'attack': 1},
                },
              },
              {
                'name': 'blue',
                'components': {
                  'team': {'id': 'blue'},
                  'gridPosition': {'col': 6, 'row': 6},
                  'actionPoints': {'max': 4},
                  'unitStats': {'maxHp': 80, 'attack': 1},
                },
              },
            ],
          },
          'turns': 200,
        },
      },
      id: 42,
    );
    await Future<void>.delayed(Duration.zero);
    await session.dispatch('notifications/cancelled', {'requestId': 42});
    final result = await call as Map;
    expect(result['isError'], isTrue);
    final text = (result['content'] as List).first['text'] as String;
    expect(text, contains('cancelled'));
  });
}
