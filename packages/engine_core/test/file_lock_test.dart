import 'dart:convert';
import 'dart:io';

import 'package:engine_core/engine_core_io.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late String level;
  var clock = DateTime.utc(2026, 1, 1, 12);
  FileLock lock({Duration? stale}) =>
      FileLock(level, staleAfter: stale ?? const Duration(hours: 2), now: () => clock);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('file_lock');
    level = '${dir.path}/one.level.json';
    File(level).writeAsStringSync('{}');
    clock = DateTime.utc(2026, 1, 1, 12);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('an unlocked file can be taken, and others are then told who has it', () {
    final a = lock().acquire('ann@laptop');
    expect(a.acquired, isTrue);
    expect(File('$level.lock').existsSync(), isTrue);

    final b = lock().acquire('bob@desktop');
    expect(b.acquired, isFalse);
    expect(b.holder.owner, 'ann@laptop');
    expect(lock().inspect()!.owner, 'ann@laptop');
  });

  test('the holder can re-acquire (renew) and the time moves forward', () {
    lock().acquire('ann@laptop');
    clock = clock.add(const Duration(hours: 1));
    final again = lock().acquire('ann@laptop');
    expect(again.acquired, isTrue);
    expect(lock().inspect()!.acquiredAt, clock);
  });

  test('a stale lock (a crashed editor) can be taken over; inspect ignores it', () {
    lock().acquire('ann@laptop');
    clock = clock.add(const Duration(hours: 3));
    expect(lock().inspect(), isNull);
    final taken = lock().acquire('bob@desktop');
    expect(taken.acquired, isTrue);
    expect(lock().inspect()!.owner, 'bob@desktop');
  });

  test('only the owner releases; a stranger cannot, unless forcing', () {
    lock().acquire('ann@laptop');
    expect(lock().release('bob@desktop'), isFalse);
    expect(lock().inspect()!.owner, 'ann@laptop');
    expect(lock().release('bob@desktop', force: true), isTrue);
    expect(File('$level.lock').existsSync(), isFalse);

    lock().acquire('ann@laptop');
    expect(lock().release('ann@laptop'), isTrue);
    expect(lock().inspect(), isNull);
    expect(lock().release('ann@laptop'), isTrue, reason: 'releasing nothing is fine');
  });

  test('a corrupt, old lock file does not block anyone', () {
    final f = File('$level.lock')..writeAsStringSync('{ not json');
    f.setLastModifiedSync(DateTime.now().subtract(const Duration(minutes: 5)));
    expect(lock().inspect(), isNull);
    expect(lock().acquire('bob@desktop').acquired, isTrue);
  });

  test('a lock file that is still being written (empty, brand new) is not stolen', () {
    File('$level.lock').writeAsStringSync('');
    final r = lock().acquire('bob@desktop');
    expect(r.acquired, isFalse);
  });

  test('the lock file records owner and acquisition time as JSON', () {
    lock().acquire('ann@laptop');
    final json = jsonDecode(File('$level.lock').readAsStringSync()) as Map<String, dynamic>;
    expect(json['owner'], 'ann@laptop');
    expect(DateTime.parse(json['acquiredAt'] as String), clock);
  });

  test('lockOwner is user@host', () {
    expect(lockOwner(env: {'USER': 'ann'}, hostname: 'laptop'), 'ann@laptop');
    expect(lockOwner(env: {}, hostname: 'h'), 'someone@h');
  });
}
