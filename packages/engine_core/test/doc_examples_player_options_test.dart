// The samples in docs/concepts/settings.md, executed so the guide cannot drift.
import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

void main() {
  test(
    'options load from storage, notify listeners, persist, and clamp',
    () async {
      final storage = InMemoryPlayerOptionsStorage();
      final manager = PlayerOptionsManager(storage);
      final seen = <double>[];
      manager.addListener((o) => seen.add(o.masterVolume));

      await manager.load(); // nothing stored yet: defaults
      expect(manager.options.masterVolume, 1.0);

      await manager.setOption('masterVolume', 0.4);
      await manager.setOption('sfxVolume', 5); // out of range
      expect(manager.getOption('masterVolume'), 0.4);
      expect(manager.options.sfxVolume, 1.0, reason: 'clamped to 0..1');
      expect(seen, containsAllInOrder([1.0, 0.4]));

      // A second manager on the same storage sees what the first saved.
      final next = PlayerOptionsManager(storage);
      await next.load();
      expect(next.options.masterVolume, 0.4);
    },
  );

  test(
    'update changes several things at once; unknown keys go to custom',
    () async {
      final manager = PlayerOptionsManager(InMemoryPlayerOptionsStorage());
      await manager.update((o) => o.copyWith(reduceMotion: true, textScale: 9));
      expect(manager.options.reduceMotion, isTrue);
      expect(manager.options.textScale, 3.0, reason: 'clamped to 0.5..3');

      await manager.setOption('difficulty', 'hard');
      expect(manager.getOption('difficulty'), 'hard');
      expect(manager.options.custom['difficulty'], 'hard');
    },
  );

  test(
    'options round-trip through JSON, with defaults for anything missing',
    () {
      final o = PlayerOptions(
        musicVolume: 0.2,
        colorblindMode: 'deuteranopia',
        keyboardBindings: {'jump': 32},
      );
      final back = PlayerOptions.fromJson(o.toJson());
      expect(back.musicVolume, 0.2);
      expect(back.colorblindMode, 'deuteranopia');
      expect(back.keyboardBindings, {'jump': 32});

      final sparse = PlayerOptions.fromJson({'masterVolume': 0.5});
      expect(sparse.masterVolume, 0.5);
      expect(sparse.dialogueSpeed, 1.0);
      expect(sparse.locale, 'en');
    },
  );
}
