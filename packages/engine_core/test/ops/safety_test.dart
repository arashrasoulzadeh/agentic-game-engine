import 'dart:convert';

import 'package:engine_core/engine_core_ops.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const levelA =
    '{"entities": [{"name": "player", "components": {"position": {"x": 1, "y": 2}}}]}';

/// A project in memory and a registry with fake operations that propose file changes.
class Rig {
  Rig({bool readOnly = false, DateTime? now})
    : clockTime = now ?? DateTime.utc(2026, 1, 1, 12) {
    files = MemoryFiles({p.join(root, 'assets/levels/a.json'): levelA});
    ctx = OpContext(
      project: ProjectRoot(root),
      files: files,
      clock: () => clockTime,
      policy: Policy(readOnly: readOnly),
      lockOwner: 'me@host',
      actor: 'test',
    );
    registry = OperationRegistry([
      _writeOp(
        't.edit',
        OperationKind.write,
        (a) => [
          FileChange(
            path: 'assets/levels/a.json',
            before: _read(),
            after: a['after'] as String,
          ),
        ],
      ),
      _writeOp(
        't.remove',
        OperationKind.destructive,
        (a) => [
          FileChange(
            path: 'assets/levels/a.json',
            before: _read(),
            after: null,
          ),
        ],
      ),
      _writeOp(
        't.two',
        OperationKind.write,
        (a) => [
          FileChange(
            path: 'assets/levels/a.json',
            before: _read(),
            after: a['after'] as String,
          ),
          FileChange(path: 'assets/levels/b.json', before: null, after: levelA),
        ],
      ),
      ...undoOperations(),
    ], finisher: SafetyPipeline(secret: List.filled(32, 7)).finish);
  }

  static const root = '/proj';
  DateTime clockTime;
  late MemoryFiles files;
  late OpContext ctx;
  late OperationRegistry registry;

  String? _read() => files.read(p.join(root, 'assets/levels/a.json'));
  String? read(String rel) => files.read(p.join(root, rel));

  Operation _writeOp(
    String name,
    OperationKind kind,
    List<FileChange> Function(Map<String, Object?>) changes,
  ) => Operation(
    name: name,
    summary: 's',
    description: 'd',
    kind: kind,
    scope: OperationScope.project,
    params: const [Param('after', ParamType.string)],
    handler: (c, a) =>
        OpOutcome.proposal(Proposal(changes(a)), data: {'ok': true}),
  );

  Future<OpResult> call(String name, [Map<String, Object?> args = const {}]) =>
      registry.call(name, args, ctx);
}

String level(num x) =>
    '{"entities": [{"name": "player", "components": {"position": {"x": $x, "y": 2}}}]}';

void main() {
  group('write operations', () {
    test(
      'apply by default, record an undo entry and report a level diff',
      () async {
        final r = Rig();
        final res = await r.call('t.edit', {'after': level(5)});
        expect(res.ok, isTrue, reason: '${res.error}');
        expect(r.read('assets/levels/a.json'), level(5));
        expect(res.undoId, startsWith('000001-20260101T120000Z-t.edit'));
        final diff = res.diff!['files'] as List;
        expect((diff.single as Map)['change'], 'modified');
        expect(
          ((diff.single as Map)['text'] as String),
          contains('~ player.position.x'),
        );
      },
    );

    test('apply:false previews and writes nothing', () async {
      final r = Rig();
      final res = await r.call('t.edit', {'after': level(5), 'apply': false});
      expect((res.data! as Map)['preview'], isTrue);
      expect((res.data! as Map).containsKey('confirmation'), isFalse);
      expect(r.read('assets/levels/a.json'), levelA);
      expect(res.undoId, isNull);
    });

    test(
      'a result that fails validation writes nothing and lists the problems',
      () async {
        final r = Rig();
        final res = await r.call('t.edit', {
          'after':
              '{"entities": [{"name": "x", "components": {"position": {"x": "left", "y": 0}}}]}',
        });
        expect(res.error!.code, ErrorCode.validationFailed);
        expect(
          (res.error!.details!['problems'] as List).single,
          contains('x.position'),
        );
        expect(r.read('assets/levels/a.json'), levelA);
        final broken = await r.call('t.edit', {'after': '{not json'});
        expect(broken.error!.code, ErrorCode.validationFailed);
      },
    );

    test('an unchanged proposal is a no-op that says so', () async {
      final r = Rig();
      final res = await r.call('t.edit', {'after': levelA});
      expect(res.ok, isTrue);
      expect(res.warnings, contains('nothing changed'));
      expect(r.ctx.undoLog().list(), isEmpty);
    });

    test('read-only refuses before anything is proposed', () async {
      final r = Rig(readOnly: true);
      expect(
        (await r.call('t.edit', {'after': level(5)})).error!.code,
        ErrorCode.readOnly,
      );
      expect(r.read('assets/levels/a.json'), levelA);
    });

    test(
      'two files are written together, and a failure on the second restores the first',
      () async {
        final r = Rig();
        r.files.failWrites.add(p.join(Rig.root, 'assets/levels/b.json'));
        final res = await r.call('t.two', {'after': level(9)});
        expect(res.error!.code, ErrorCode.ioError);
        expect(r.read('assets/levels/a.json'), levelA, reason: 'rolled back');
        expect(r.read('assets/levels/b.json'), isNull);
      },
    );
  });

  group('destructive operations', () {
    test(
      'without a confirmation the call returns a preview and a token, and writes nothing',
      () async {
        final r = Rig();
        final res = await r.call('t.remove');
        final d = res.data! as Map;
        expect(d['preview'], isTrue);
        expect(d['confirmation'], isA<String>());
        expect(d['expiresAt'], '2026-01-01T12:05:00.000Z');
        expect(
          ((d['diff'] as Map)['files'] as List).single['change'],
          'deleted',
        );
        expect(r.read('assets/levels/a.json'), levelA);
      },
    );

    test(
      'apply:true without a token is refused with the preview inside the error',
      () async {
        final r = Rig();
        final res = await r.call('t.remove', {'apply': true});
        expect(res.error!.code, ErrorCode.confirmationRequired);
        expect(
          (res.error!.details!['preview'] as Map)['confirmation'],
          isA<String>(),
        );
        expect(r.read('assets/levels/a.json'), levelA);
      },
    );

    test(
      'the token applies exactly that change, once, and records undo',
      () async {
        final r = Rig();
        final token =
            ((await r.call('t.remove')).data! as Map)['confirmation']!
                as String;
        final res = await r.call('t.remove', {'confirmation': token});
        expect(res.ok, isTrue, reason: '${res.error}');
        expect(r.read('assets/levels/a.json'), isNull);
        expect(res.undoId, isNotNull);
        final again = await r.call('t.remove', {'confirmation': token});
        expect(
          again.error!.code,
          ErrorCode.confirmationStale,
          reason: 'the file is already gone, so the preview no longer matches',
        );
      },
    );

    test('a token goes stale when a touched file changes in between', () async {
      final r = Rig();
      final token =
          ((await r.call('t.remove')).data! as Map)['confirmation']! as String;
      r.files.files[p.join(Rig.root, 'assets/levels/a.json')] = level(77);
      expect(
        (await r.call('t.remove', {'confirmation': token})).error!.code,
        ErrorCode.confirmationStale,
      );
      expect(r.read('assets/levels/a.json'), level(77));
    });

    test('a token expires', () async {
      final r = Rig();
      final token =
          ((await r.call('t.remove')).data! as Map)['confirmation']! as String;
      r.clockTime = r.clockTime.add(const Duration(minutes: 6));
      expect(
        (await r.call('t.remove', {'confirmation': token})).error!.code,
        ErrorCode.confirmationStale,
      );
    });

    test(
      'a token from another call, a tampered token and garbage are refused',
      () async {
        final r = Rig();
        final token =
            ((await r.call('t.remove')).data! as Map)['confirmation']!
                as String;
        expect(
          (await r.call('t.edit', {
            'after': level(1),
            'confirmation': token,
          })).error,
          isNull,
          reason: 'writes ignore tokens',
        );
        final other = Rig();
        final foreign =
            ((await other.call('t.remove')).data! as Map)['confirmation']!
                as String;
        expect(
          foreign,
          token,
          reason: 'same secret and state in this test rig, so the same token',
        );
        final raw = utf8.decode(base64Url.decode(base64Url.normalize(token)));
        final tampered = base64Url.encode(
          utf8.encode(raw.replaceFirst('t.remove', 't.remave')),
        );
        expect(
          (await r.call('t.remove', {'confirmation': tampered})).error!.code,
          ErrorCode.invalidParams,
        );
        expect(
          (await r.call('t.remove', {'confirmation': 'garbage'})).error!.code,
          ErrorCode.invalidParams,
        );
      },
    );

    test('a token made with other arguments does not apply', () async {
      final r = Rig();
      final differentArgs = OperationRegistry([
        Operation(
          name: 't.rm',
          summary: 's',
          description: 'd',
          kind: OperationKind.destructive,
          scope: OperationScope.project,
          params: const [Param('which', ParamType.string)],
          handler: (c, a) => OpOutcome.proposal(
            Proposal([
              FileChange(
                path: 'assets/levels/a.json',
                before: levelA,
                after: null,
              ),
            ]),
          ),
        ),
      ], finisher: SafetyPipeline(secret: List.filled(32, 7)).finish);
      final token =
          ((await differentArgs.call('t.rm', {'which': 'a'}, r.ctx)).data!
                  as Map)['confirmation']!
              as String;
      expect(
        (await differentArgs.call('t.rm', {
          'which': 'b',
          'confirmation': token,
        }, r.ctx)).error!.code,
        ErrorCode.invalidParams,
      );
      expect(
        (await differentArgs.call('t.rm', {
          'which': 'a',
          'confirmation': token,
        }, r.ctx)).ok,
        isTrue,
      );
    });
  });

  group('undo', () {
    test(
      'undo restores the bytes, redo re-applies them, list shows the entries',
      () async {
        final r = Rig();
        await r.call('t.edit', {'after': level(5)});
        await r.call('t.edit', {'after': level(6)});
        final list = (await r.call('undo.list')).data! as List;
        expect(list.length, 2);
        expect((list.first as Map)['op'], 't.edit');

        expect((await r.call('undo.undo')).ok, isTrue);
        expect(r.read('assets/levels/a.json'), level(5));
        expect((await r.call('undo.undo')).ok, isTrue);
        expect(r.read('assets/levels/a.json'), levelA);
        expect((await r.call('undo.undo')).error!.code, ErrorCode.notFound);

        expect((await r.call('undo.redo')).ok, isTrue);
        expect(r.read('assets/levels/a.json'), level(5));
        expect((await r.call('undo.redo')).ok, isTrue);
        expect(r.read('assets/levels/a.json'), level(6));
        expect((await r.call('undo.redo')).error!.code, ErrorCode.notFound);
        expect(
          ((await r.call('undo.list')).data! as List).length,
          2,
          reason: 'undo and redo are not new entries',
        );
      },
    );

    test('undoing a deletion brings the file back', () async {
      final r = Rig();
      final token =
          ((await r.call('t.remove')).data! as Map)['confirmation']! as String;
      await r.call('t.remove', {'confirmation': token});
      expect((await r.call('undo.undo')).ok, isTrue);
      expect(r.read('assets/levels/a.json'), levelA);
    });

    test(
      'undo refuses when a file changed afterwards, unless forced',
      () async {
        final r = Rig();
        await r.call('t.edit', {'after': level(5)});
        r.files.files[p.join(Rig.root, 'assets/levels/a.json')] = level(99);
        final res = await r.call('undo.undo');
        expect(res.error!.code, ErrorCode.conflict);
        expect(res.error!.details!['files'], ['assets/levels/a.json']);
        expect((await r.call('undo.undo', {'force': true})).ok, isTrue);
        expect(r.read('assets/levels/a.json'), levelA);
      },
    );

    test('a specific id, unknown ids and double undo are handled', () async {
      final r = Rig();
      final id = (await r.call('t.edit', {'after': level(5)})).undoId!;
      expect(
        (await r.call('undo.undo', {'id': 'nope'})).error!.code,
        ErrorCode.notFound,
      );
      expect(
        (await r.call('undo.redo', {'id': id})).error!.code,
        ErrorCode.conflict,
        reason: 'not undone yet',
      );
      expect((await r.call('undo.undo', {'id': id})).ok, isTrue);
      expect(
        (await r.call('undo.undo', {'id': id})).error!.code,
        ErrorCode.conflict,
      );
    });

    test('the journal keeps only the last N entries', () async {
      final r = Rig();
      final small = OpContext(
        project: r.ctx.project,
        files: r.files,
        clock: () => r.clockTime,
        lockOwner: 'me',
        undoKeep: 3,
      );
      for (var i = 0; i < 6; i++) {
        await r.registry.call('t.edit', {'after': level(100 + i)}, small);
      }
      final list = small.undoLog().list(limit: 100);
      expect(list.length, 3);
      expect(list.first.id, startsWith('000006-'));
      expect(list.last.id, startsWith('000004-'));
    });

    test('undo is blocked in read-only mode and needs a project', () async {
      final r = Rig(readOnly: true);
      expect((await r.call('undo.undo')).error!.code, ErrorCode.readOnly);
      expect(
        (await r.registry.call('undo.list', {}, OpContext())).error!.code,
        ErrorCode.notFound,
      );
    });
  });
}
