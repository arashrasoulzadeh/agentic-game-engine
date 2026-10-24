import 'package:engine_core/engine_core_ops.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  test(
    'encode then decode returns the same save, with no project open',
    () async {
      final s = await Scratch.create(open: false);
      final save = {
        'coins': '42',
        'owned': {'cursor': 3},
        'name': 'Zoë',
      };
      final code =
          (await s.map('save.encode', {'save': save}))['code']! as String;
      expect(code, startsWith('GSAVE1.'));
      expect((await s.map('save.decode', {'code': code}))['save'], save);
    },
  );

  test('a damaged code is validation_failed with a readable message', () async {
    final s = await Scratch.create(open: false);
    final code =
        (await s.map('save.encode', {
              'save': {'a': 1},
            }))['code']!
            as String;
    final broken = code.substring(0, code.length - 2) + 'zz';
    final r = await s.call('save.decode', {'code': broken});
    expect(r.error!.code, ErrorCode.validationFailed);
    expect(r.error!.message, isNotEmpty);
    expect(
      await s.failure('save.decode', {'code': 'hello'}),
      ErrorCode.validationFailed,
    );
  });

  test(
    'migrate stamps a current save and refuses gaps and newer saves',
    () async {
      final s = await Scratch.create(open: false);
      final ok = await s.map('save.migrate', {
        'save': {'saveVersion': 2, 'x': 1},
        'toVersion': 2,
      });
      expect((ok['save']! as Map)['saveVersion'], 2);
      expect(
        await s.failure('save.migrate', {
          'save': {'x': 1},
          'toVersion': 2,
        }),
        ErrorCode.validationFailed,
        reason: 'no migration from v1 is registered',
      );
      expect(
        await s.failure('save.migrate', {
          'save': {'saveVersion': 5},
          'toVersion': 2,
        }),
        ErrorCode.validationFailed,
      );
    },
  );
}
