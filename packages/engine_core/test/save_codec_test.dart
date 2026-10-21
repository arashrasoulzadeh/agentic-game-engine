import 'dart:io';

import 'package:engine_core/engine_core.dart';
import 'package:engine_core/engine_core_io.dart';
import 'package:test/test.dart';

void main() {
  group('SaveMigrator', () {
    final migrator = SaveMigrator(
      currentVersion: 3,
      migrations: {
        // v1 -> v2: 'gold' was renamed to 'coins'.
        1: (s) {
          final out = {...s};
          out['coins'] = out.remove('gold');
          return out;
        },
        // v2 -> v3: add a prestige counter.
        2: (s) => {...s, 'prestiges': 0},
      },
    );

    test('a v1 save is upgraded through every step and stamped current', () {
      final up = migrator.migrate({'gold': '500'});
      expect(up, {'coins': '500', 'prestiges': 0, 'saveVersion': 3});
    });

    test('a v2 save only runs the steps it still needs', () {
      final up = migrator.migrate({'saveVersion': 2, 'coins': '9'});
      expect(up, {'coins': '9', 'prestiges': 0, 'saveVersion': 3});
    });

    test(
      'a current save passes through unchanged, and the input is never modified',
      () {
        final input = {'saveVersion': 3, 'coins': '1', 'prestiges': 2};
        expect(migrator.migrate(input), input);
        final old = {'gold': '1'};
        migrator.migrate(old);
        expect(old, {'gold': '1'});
      },
    );

    test('a save from a newer game is refused with a clear message', () {
      expect(
        () => migrator.migrate({'saveVersion': 9}),
        throwsA(
          isA<SaveFormatException>().having(
            (e) => e.message,
            'message',
            contains('newer version'),
          ),
        ),
      );
    });

    test('a missing migration is an error, not a silent skip', () {
      final gap = SaveMigrator(currentVersion: 3, migrations: {1: (s) => s});
      expect(() => gap.migrate({}), throwsA(isA<SaveFormatException>()));
    });

    test('stamp adds the current version to something new', () {
      expect(migrator.stamp({'coins': '1'}), {'coins': '1', 'saveVersion': 3});
    });
  });

  group('SaveCodec', () {
    final save = {
      'saveVersion': 3,
      'coins': '1.5e300',
      'name': 'Ünïcode ✓',
      'nested': {
        'a': [1, 2, 3],
      },
    };

    test(
      'export then import returns the same save, including unicode and nesting',
      () {
        expect(SaveCodec.import(SaveCodec.export(save)), save);
      },
    );

    test('whitespace around a pasted code is ignored', () {
      expect(SaveCodec.import('  \n${SaveCodec.export(save)}\n '), save);
    });

    test('a truncated, edited or foreign code is rejected with a reason', () {
      final code = SaveCodec.export(save);
      final truncated = code.substring(0, code.length - 12);
      final edited = code.replaceFirst('.', '.A');
      for (final bad in [
        truncated,
        edited,
        'hello',
        '',
        'GSAVE1.only-two',
        'OTHER.abc.def',
      ]) {
        expect(
          () => SaveCodec.import(bad),
          throwsA(isA<SaveFormatException>()),
          reason: bad,
        );
      }
      expect(
        () => SaveCodec.import(truncated),
        throwsA(
          isA<SaveFormatException>().having(
            (e) => e.message,
            'message',
            contains('damaged'),
          ),
        ),
      );
    });

    test(
      'a valid checksum over something that is not a save object is rejected',
      () {
        expect(
          () => SaveCodec.import('GSAVE1.WzEsMl0=.00000000'),
          throwsA(isA<SaveFormatException>()),
        );
      },
    );
  });

  group('AtomicSave', () {
    late Directory dir;
    late String path;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('atomic_save');
      path = '${dir.path}/sub/save.json';
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('writes and reads back, creating folders, with no temp file left', () {
      final s = AtomicSave(path);
      expect(s.read(), isNull);
      s.write({'coins': '1'});
      expect(s.read(), {'coins': '1'});
      expect(File('$path.tmp').existsSync(), isFalse);
    });

    test('the previous save is kept as a backup', () {
      final s = AtomicSave(path)
        ..write({'v': 1})
        ..write({'v': 2});
      expect(s.read(), {'v': 2});
      expect(File('$path.bak').existsSync(), isTrue);
    });

    test('a corrupt main file falls back to the last good save', () {
      final s = AtomicSave(path)
        ..write({'v': 1})
        ..write({'v': 2});
      File(path).writeAsStringSync('{ half written');
      expect(s.mainIsReadable, isFalse);
      expect(s.read(), {
        'v': 1,
      }, reason: 'the backup from before the last write');
    });

    test(
      'a crash mid-write (a stray temp file) never disturbs the real save',
      () {
        final s = AtomicSave(path)..write({'v': 1});
        File('$path.tmp').writeAsStringSync('{"v": 2, "half');
        expect(s.read(), {'v': 1});
        s.write({'v': 3});
        expect(s.read(), {'v': 3});
      },
    );

    test('both files unreadable means no save, not an exception', () {
      final s = AtomicSave(path)
        ..write({'v': 1})
        ..write({'v': 2});
      File(path).writeAsStringSync('nope');
      File('$path.bak').writeAsStringSync('nope');
      expect(s.read(), isNull);
    });
  });
}
