import 'package:engine_core/engine_core_ops.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  test('i18n.keys reports empty catalogs with a hint', () async {
    final s = await Scratch.create();
    final r = await s.map('i18n.keys');
    expect(r['ok'], isTrue);
    expect(r['locales'], isEmpty);
    expect(r['hint'], contains('assets/i18n'));
  });

  test('i18n.set creates a locale file and is undoable', () async {
    final s = await Scratch.create();
    final set = await s.map('i18n.set', {
      'locale': 'en',
      'key': 'menu.start',
      'text': 'Start',
      'apply': true,
    });
    expect(set['created'], isTrue);
    expect(set['path'], 'assets/i18n/en.json');
    expect(s.read('assets/i18n/en.json'), contains('"menu.start"'));
    expect(s.read('assets/i18n/en.json'), contains('"Start"'));

    await s.map('i18n.set', {
      'locale': 'en',
      'key': 'menu.start',
      'text': 'Begin',
      'apply': true,
    });
    expect(s.read('assets/i18n/en.json'), contains('"Begin"'));

    await s.map('undo.undo', {'apply': true});
    expect(s.read('assets/i18n/en.json'), contains('"Start"'));
  });

  test('i18n.keys finds missing translations and placeholder mismatches', () async {
    final s = await Scratch.create();
    s.write(
      'assets/i18n/en.json',
      '{\n  "menu.start": "Start",\n  "hud.score": "Score: {points}"\n}\n',
    );
    s.write(
      'assets/i18n/fa.json',
      '{\n  "menu.start": "شروع",\n  "hud.score": "امتیاز: {score}"\n}\n',
    );
    final r = await s.map('i18n.keys');
    expect(r['ok'], isFalse);
    expect(r['locales'], ['en', 'fa']);
    expect(r['keys'], ['hud.score', 'menu.start']);
    expect(r['missing'], isEmpty);
    final mismatches = (r['placeholderMismatches'] as List).cast<Map>();
    expect(mismatches, hasLength(1));
    expect(mismatches.single['key'], 'hud.score');

    await s.map('i18n.set', {
      'locale': 'en',
      'key': 'hud.only_en',
      'text': 'English only',
      'apply': true,
    });
    final focused = await s.map('i18n.keys', {'locale': 'fa'});
    expect((focused['missing'] as Map)['fa'], ['hud.only_en']);
  });

  test('i18n.keys with an unknown locale is not_found', () async {
    final s = await Scratch.create();
    s.write('assets/i18n/en.json', '{"a": "A"}');
    expect(await s.failure('i18n.keys', {'locale': 'zz'}), ErrorCode.notFound);
  });
}
