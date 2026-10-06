import 'dart:io';

import 'package:engine_studio/src/lsp/dart_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('references');
    File(
      '${root.path}/pubspec.yaml',
    ).writeAsStringSync('name: demo\nenvironment:\n  sdk: ^3.0.0\n');
    Directory('${root.path}/lib').createSync();
    File('${root.path}/lib/hero.dart').writeAsStringSync('class Hero {}\n');
  });
  tearDown(() => root.deleteSync(recursive: true));

  test(
    'the real server lists every use of a class across the project',
    () async {
      final session = await DartSession.open(root.path);
      final hero = '${root.path}/lib/hero.dart';
      final use = '${root.path}/lib/use.dart';
      session.openFile(hero, 'class Hero {}\n');
      session.openFile(
        use,
        "import 'hero.dart';\nvoid run() {\n  Hero();\n  Hero();\n}\n",
      );

      List<SourceLocation> found = const [];
      for (var attempt = 0; attempt < 40 && found.length < 3; attempt++) {
        found = await session.referencesAt(hero, 0, 6);
        if (found.length < 3) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }
      final inUse = found.where((r) => r.path.endsWith('use.dart')).length;
      expect(inUse, 2, reason: 'both uses in use.dart are found');
      expect(
        found.any((r) => r.path.endsWith('hero.dart')),
        isTrue,
        reason: 'the declaration is included',
      );
      await session.close();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
