import 'package:engine_core/engine_core_ops.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('level.*', () {
    test('level.list shows entities, tile maps and lock state', () async {
      final s = await Scratch.create();
      final list = ((await s.data('level.list'))! as List).cast<Map>();
      final byPath = {for (final l in list) l['path']: l};
      expect(byPath['assets/levels/level1.json']!['entities'], 3);
      expect(byPath['assets/levels/level1.json']!['hasTileMap'], isTrue);
      expect(byPath['assets/levels/empty.json']!['entities'], 0);
      s.write(
        'assets/levels/level1.json.lock',
        '{"owner":"someone@x","acquiredAt":"${DateTime.now().toUtc().toIso8601String()}"}',
      );
      final again = ((await s.data('level.list'))! as List).cast<Map>();
      expect(
        again.firstWhere(
          (l) => l['path'] == 'assets/levels/level1.json',
        )['lockedBy'],
        'someone@x',
      );
    });

    test(
      'level.read returns the level, one entity, selected components and pages',
      () async {
        final s = await Scratch.create();
        final all = await s.map('level.read', {
          'path': 'assets/levels/level1.json',
        });
        expect((all['entities']! as List).length, 3);
        expect(all['total'], 3);
        final one = await s.map('level.read', {
          'path': 'assets/levels/level1.json',
          'entity': 'player',
        });
        expect(((one['entities']! as List).single as Map)['name'], 'player');
        final onlyTiles = await s.map('level.read', {
          'path': 'assets/levels/level1.json',
          'entity': 'ground',
          'components': ['tileMap'],
        });
        expect(
          (((onlyTiles['entities']! as List).single as Map)['components']
                  as Map)
              .keys,
          ['tileMap'],
        );
        final page = await s.map('level.read', {
          'path': 'assets/levels/level1.json',
          'entityOffset': 1,
          'entityLimit': 1,
        });
        expect(((page['entities']! as List).single as Map)['name'], 'player');
        expect(page['total'], 3);
      },
    );

    test(
      'level.read errors: missing file, missing entity, escaping path',
      () async {
        final s = await Scratch.create();
        expect(
          await s.failure('level.read', {'path': 'assets/levels/nope.json'}),
          ErrorCode.notFound,
        );
        expect(
          await s.failure('level.read', {
            'path': 'assets/levels/level1.json',
            'entity': 'ghost',
          }),
          ErrorCode.notFound,
        );
        expect(
          await s.failure('level.read', {'path': '../outside.json'}),
          ErrorCode.invalidParams,
        );
        expect(
          await s.failure('level.read', {'path': '/etc/passwd'}),
          ErrorCode.invalidParams,
        );
      },
    );

    test(
      'level.validate checks a file or inline JSON and needs one of them',
      () async {
        final s = await Scratch.create();
        expect(
          (await s.map('level.validate', {
            'path': 'assets/levels/level1.json',
          }))['ok'],
          isTrue,
        );
        final bad = await s.map('level.validate', {
          'path': 'assets/levels/broken.json',
        });
        expect(bad['ok'], isFalse);
        expect((bad['errors']! as List).single, contains('x.position'));
        expect(
          (await s.map('level.validate', {
            'json': {'entities': []},
          }))['ok'],
          isTrue,
        );
        expect(
          (await s.map('level.validate', {
            'json': {'nope': 1},
          }))['ok'],
          isFalse,
        );
        expect(await s.failure('level.validate'), ErrorCode.invalidParams);
      },
    );

    test('level.validate with inline JSON needs no project', () async {
      final s = await Scratch.create(open: false);
      expect(
        (await s.map('level.validate', {
          'json': {'entities': []},
        }))['ok'],
        isTrue,
      );
      expect(
        await s.failure('level.validate', {
          'path': 'assets/levels/level1.json',
        }),
        ErrorCode.notFound,
      );
    });

    test('level.diff compares files or inline levels', () async {
      final s = await Scratch.create();
      final same = await s.map('level.diff', {
        'a': 'assets/levels/level1.json',
        'b': 'assets/levels/level1.json',
      });
      expect(same['isEmpty'], isTrue);
      expect(same['text'], 'No differences.');
      final d = await s.map('level.diff', {
        'a': 'assets/levels/empty.json',
        'b': 'assets/levels/level1.json',
      });
      expect(d['isEmpty'], isFalse);
      expect(((d['diff']! as Map)['added'] as List).length, 3);
      final moved = await s.map('level.diff', {
        'aJson': Scratch.level1,
        'bJson': {
          'entities': [
            for (final e in Scratch.level1['entities']!)
              e['name'] == 'player'
                  ? {
                      'name': 'player',
                      'components': {
                        'position': {'x': 99.0, 'y': 8.0},
                      },
                    }
                  : e,
          ],
        },
      });
      expect(moved['text'], contains('~ player.position.x: 24.0 -> 99.0'));
      expect(
        await s.failure('level.diff', {'a': 'assets/levels/level1.json'}),
        ErrorCode.invalidParams,
      );
      expect(
        await s.failure('level.diff', {'aJson': 5, 'bJson': {}}),
        ErrorCode.validationFailed,
      );
    });

    test('level.lock_status reports no lock, then a lock', () async {
      final s = await Scratch.create();
      expect(
        (await s.map('level.lock_status', {
          'path': 'assets/levels/level1.json',
        }))['locked'],
        isFalse,
      );
      s.write(
        'assets/levels/level1.json.lock',
        '{"owner":"a@b","acquiredAt":"${DateTime.now().toUtc().toIso8601String()}"}',
      );
      final r = await s.map('level.lock_status', {
        'path': 'assets/levels/level1.json',
      });
      expect((r['locked'], r['owner']), (true, 'a@b'));
    });
  });

  group('schema.*', () {
    test('components can be listed and filtered', () async {
      final s = await Scratch.create(open: false);
      final all = ((await s.data('schema.components'))! as List).cast<Map>();
      expect(all.length, greaterThan(50));
      expect(all.map((c) => c['name']), contains('position'));
      final f =
          ((await s.data('schema.components', {'filter': 'GENERATOR'}))!
                  as List)
              .cast<Map>();
      expect(f.map((c) => c['name']), contains('generator'));
      expect(
        f.every(
          (c) => (c['name'] as String).toLowerCase().contains('generator'),
        ),
        isTrue,
      );
    });

    test(
      'schema.component describes fields, template and JSON Schema',
      () async {
        final s = await Scratch.create(open: false);
        final c = await s.map('schema.component', {'name': 'position'});
        expect(((c['fields']! as List).first as Map)['name'], 'x');
        expect(c['template'], {'x': 0.0, 'y': 0.0});
        expect((c['jsonSchema']! as Map)['title'], 'position');
        expect(
          await s.failure('schema.component', {'name': 'nonsense'}),
          ErrorCode.notFound,
        );
        expect((await s.map('schema.template', {'name': 'position'})), {
          'x': 0.0,
          'y': 0.0,
        });
      },
    );

    test('schema.idle_game returns the whole-file definition schema', () async {
      final s = await Scratch.create(open: false);
      final schema = await s.map('schema.idle_game');
      expect(schema['title'], 'idle_game');
      expect(schema['type'], 'object');
      final props = schema['properties']! as Map;
      expect(props.keys, containsAll(['resources', 'generators', 'upgrades', 'prestiges', 'offline']));
    });

    test('schema.validate_component agrees with level validation', () async {
      final s = await Scratch.create(open: false);
      expect(
        (await s.map('schema.validate_component', {
          'name': 'position',
          'value': {'x': 1, 'y': 2},
        }))['ok'],
        isTrue,
      );
      final bad = await s.map('schema.validate_component', {
        'name': 'position',
        'value': {'x': 'left', 'y': 2},
      });
      expect(bad['ok'], isFalse);
      expect((bad['errors']! as List).single, isNot(contains('probe')));
      expect(
        await s.failure('schema.validate_component', {
          'name': 'position',
          'value': 3,
        }),
        ErrorCode.invalidParams,
      );
      expect(
        await s.failure('schema.validate_component', {
          'name': 'zzz',
          'value': {},
        }),
        ErrorCode.notFound,
      );
    });
  });

  group('idle.*', () {
    test(
      'idle.validate lists problems with paths, for a file or inline',
      () async {
        final s = await Scratch.create();
        expect(
          (await s.map('idle.validate', {
            'path': 'assets/idle_game.json',
          }))['ok'],
          isTrue,
        );
        final bad = await s.map('idle.validate', {
          'json': {
            'generators': [
              {'id': 'a'},
              {'id': 'a'},
            ],
          },
        });
        expect(bad['ok'], isFalse);
        expect(bad['problems'], contains('generators[0].cost is required'));
        expect(bad['problems'], contains('generators[1].id "a" is used twice'));
        expect(await s.failure('idle.validate'), ErrorCode.invalidParams);
        expect(
          await s.failure('idle.validate', {'path': 'assets/missing.json'}),
          ErrorCode.notFound,
        );
      },
    );

    test('idle.simulate is deterministic and reports milestones', () async {
      final s = await Scratch.create();
      final a = await s.map('idle.simulate', {
        'path': 'assets/idle_game.json',
        'days': 1,
      });
      final b = await s.map('idle.simulate', {
        'path': 'assets/idle_game.json',
        'days': 1,
      });
      expect(a, b);
      expect(a['purchases'], greaterThan(5));
      expect((a['milestones']! as List), isNotEmpty);
      expect(a['text'], startsWith('Simulated '));
      expect(
        await s.failure('idle.simulate', {
          'json': {
            'generators': [
              {'id': 'x'},
            ],
          },
        }),
        ErrorCode.validationFailed,
      );
      expect(
        await s.failure('idle.simulate', {
          'path': 'assets/idle_game.json',
          'days': 0,
        }),
        ErrorCode.invalidParams,
      );
    });

    test('idle.format_number writes numbers in every style', () async {
      final s = await Scratch.create(open: false);
      Future<String> fmt(String v, [String style = 'suffix']) async =>
          (await s.map('idle.format_number', {
                'value': v,
                'style': style,
              }))['text']!
              as String;
      expect(await fmt('1234567'), '1.23M');
      expect(await fmt('1234567', 'scientific'), '1.23e6');
      expect(await fmt('1234567', 'grouped'), '1,234,567');
      expect(
        await s.failure('idle.format_number', {'value': 'abc'}),
        ErrorCode.invalidParams,
      );
    });
  });

  group('release.*', () {
    test(
      'release.plan returns the command and withholds secret contents',
      () async {
        final s = await Scratch.create(open: false);
        final plain = await s.map('release.plan', {'platform': 'android'});
        expect(plain['ok'], isTrue);
        expect(
          plain['command'],
          containsAll(['flutter', 'build', 'appbundle']),
        );
        final signed = await s.map('release.plan', {
          'platform': 'android',
          'keystorePath': '/k.jks',
          'keystorePassword': 'hunter2',
          'keyAlias': 'a',
          'keyPassword': 'hunter3',
          'gradleText': 'reads key.properties',
        });
        expect(signed['ok'], isTrue);
        expect(signed.toString(), isNot(contains('hunter')));
        expect(
          ((signed['writes']! as List).single as Map)['path'],
          'android/key.properties',
        );
        final ios = await s.map('release.plan', {
          'platform': 'ios',
          'noCodesign': true,
        });
        expect(ios['command'], containsAll(['ipa', '--no-codesign']));
        expect(
          (await s.map('release.plan', {
            'platform': 'android',
            'keystorePath': '/k.jks',
          }))['ok'],
          isFalse,
        );
      },
    );

    test('release.build is declared but unsupported without the CLI', () async {
      final s = await Scratch.create();
      expect(s.registry.lookup('release.build')!.requiresFlutter, isTrue);
      expect(await s.failure('release.build'), ErrorCode.unsupported);
    });
  });

  test(
    'every read operation example on the real registry runs against a project',
    () async {
      final s = await Scratch.create();
      for (final op in s.registry.all.where(
        (o) => o.kind == OperationKind.read,
      )) {
        for (final ex in op.examples) {
          final r = await s.call(op.name, ex.args);
          expect(r.ok, isTrue, reason: '${op.name} ${ex.title}: ${r.error}');
          for (final e in (ex.expect ?? const {}).entries) {
            expect(
              (r.data! as Map)[e.key],
              e.value,
              reason: '${op.name} ${e.key}',
            );
          }
        }
      }
    },
  );

  test(
    'idle.best_purchase recommends the generator and honours owned counts',
    () async {
      final s = await Scratch.create();
      final first = await s.map('idle.best_purchase', {
        'path': 'assets/idle_game.json',
      });
      expect(first['id'], 'cursor');
      expect(first['isUpgrade'], false);
      expect(first['cost'], '15');
      final more = await s.map('idle.best_purchase', {
        'path': 'assets/idle_game.json',
        'owned': {'cursor': 10},
      });
      expect(
        more['cost'],
        isNot('15'),
        reason: 'the price grows with copies owned',
      );
      expect(
        await s.failure('idle.best_purchase', {
          'json': {'generators': 5},
        }),
        ErrorCode.validationFailed,
      );
    },
  );

  test('idle.state shows the start, then what a simulated hour buys', () async {
    final s = await Scratch.create();
    final start = await s.map('idle.state', {'path': 'assets/idle_game.json'});
    expect((start['wallet']! as Map)['coins'], '15');
    expect((start['owned']! as Map)['cursor'], 0);
    final later = await s.map('idle.state', {
      'path': 'assets/idle_game.json',
      'afterSeconds': 3600,
    });
    expect((later['owned']! as Map)['cursor'], greaterThan(5));
    expect((later['incomePerSecond']! as Map)['coins'], isNot('0'));
    expect(
      await s.failure('idle.state', {
        'json': {'generators': 5},
      }),
      ErrorCode.validationFailed,
    );
  });
}
