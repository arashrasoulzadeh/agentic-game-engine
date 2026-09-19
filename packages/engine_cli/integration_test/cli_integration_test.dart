import 'dart:io';
import 'package:engine_cli/src/create_command.dart';
import 'package:engine_cli/src/lint_command.dart';
import 'package:engine_cli/src/pack_assets_command.dart';
import 'package:engine_cli/src/upgrade_command.dart';
import 'package:engine_cli/src/template.dart';
import 'package:test/test.dart';

@Tags(const ['integration'])
void main() {
  group('CLI integration', () {
    late Directory tmp;
    late String originalDir;

    setUp(() {
      originalDir = Directory.current.path;
      tmp = Directory.systemTemp.createTempSync('cli_integration_');
    });

    tearDown(() {
      Directory.current = originalDir;
      tmp.deleteSync(recursive: true);
    });

    test('create -> lint -> pack-assets -> upgrade full workflow', () async {
      // 1. Create a game project
      final projectDir = Directory('${tmp.path}/my_game');
      
      var calls = <List<Object?>>[];
      Future<int> mockProcess(String exe, List<String> args, {String? wd}) async {
        calls.add([exe, args, wd]);
        if (args.first == 'create') {
          Directory('${wd}/${args.last}').createSync(recursive: true);
        }
        return 0;
      }

      final runner = _createRunner(mockProcess);
      expect(await runner.run(['create', 'my_game', '--output-dir', tmp.path]), 0);

      final pubspec = File('${tmp.path}/my_game/pubspec.yaml');
      expect(pubspec.existsSync(), isTrue);
      expect(pubspec.readAsStringSync(), contains('engine_core'));
      expect(pubspec.readAsStringSync(), contains('engine_flutter'));
      expect(pubspec.readAsStringSync(), contains('engine_platformer'));

      // 2. Lint a level file
      final levelFile = File('${tmp.path}/my_game/assets/levels/level1.json');
      levelFile.createSync(recursive: true);
      levelFile.writeAsStringSync('''
{
  "entities": [
    {
      "name": "tileMap",
      "components": {
        "position": {"x": 0, "y": 0},
        "tileMap": {
          "tileWidth": 32, "tileHeight": 32,
          "legend": {".": 0, "#": 1},
          "rows": ["##########", "..........", "..........", "##########"],
          "solidTileIds": [1]
        }
      }
    },
    {
      "name": "player",
      "components": {
        "position": {"x": 100, "y": 100},
        "velocity": {"x": 0, "y": 0}
      }
    }
  ]
}
''');

      final lintRunner = _createLintRunner();
      expect(await lintRunner.run(['lint', levelFile.path]), 0);

      // 3. Pack assets
      final assetsDir = Directory('${tmp.path}/my_game/assets/images');
      assetsDir.createSync(recursive: true);
      
      // Create a simple test image
      _writeTestPng('${assetsDir.path}/player.png', 32, 32);
      _writeTestPng('${assetsDir.path}/enemy.png', 32, 32);

      final packRunner = _createPackRunner();
      final outImage = '${tmp.path}/my_game/assets/atlas.png';
      final outManifest = '${tmp.path}/my_game/assets/atlas.json';
      
      expect(await packRunner.run([
        'pack-assets',
        '--input', assetsDir.path,
        '--output-image', outImage,
        '--output-manifest', outManifest,
      ]), 0);

      expect(File(outImage).existsSync(), isTrue);
      expect(File(outManifest).existsSync(), isTrue);
      
      final manifest = File(outManifest).readAsStringSync();
      expect(manifest, contains('player'));
      expect(manifest, contains('enemy'));

      // 4. Upgrade the project
      Directory.current = '${tmp.path}/my_game';
      final upgradeRunner = _createUpgradeRunner(mockProcess);
      expect(await upgradeRunner.run(['upgrade', '--ref', 'v0.2.0']), 0);
      
      final upgradedPubspec = pubspec.readAsStringSync();
      expect(upgradedPubspec, contains('ref: v0.2.0'));
    });

    test('lint --render produces valid PNG from level JSON', () async {
      final levelFile = File('${tmp.path}/level.json');
      levelFile.writeAsStringSync('''
{
  "entities": [
    {
      "name": "tileMap",
      "components": {
        "position": {"x": 0, "y": 0},
        "tileMap": {
          "tileWidth": 32, "tileHeight": 32,
          "legend": {".": 0, "#": 1, "^": 2},
          "rows": ["########", "........", "........", "########"],
          "solidTileIds": [1],
          "oneWayTileIds": [2]
        }
      }
    }
  ]
}
''');

      final outPng = '${tmp.path}/render.png';
      final runner = _createLintRunner();
      
      expect(await runner.run(['lint', levelFile.path, '--render', outPng]), 0);
      expect(File(outPng).existsSync(), isTrue);
      
      final bytes = File(outPng).readAsBytesSync();
      // PNG signature
      expect(bytes.take(8).toList(), [137, 80, 78, 71, 13, 10, 26, 10]);
    });

    test('template processing handles all placeholder types', () {
      final templateDir = Directory('${tmp.path}/template');
      templateDir.createSync(recursive: true);
      
      File('${templateDir.path}/pubspec.yaml.tmpl')
        ..writeAsStringSync('name: {{name}}\nversion: {{version}}\ndescription: {{description}}');
      File('${templateDir.path}/README.md.tmpl')
        ..writeAsStringSync('# {{name}}\n\n{{description}}');
      
      final outputDir = Directory('${tmp.path}/output');
      outputDir.createSync();
      
      copyTemplate(templateDir, outputDir, {
        'name': 'my_game',
        'version': '1.0.0',
        'description': 'A test game',
      });
      
      expect(File('${outputDir.path}/pubspec.yaml').readAsStringSync(), 
          'name: my_game\nversion: 1.0.0\ndescription: A test game');
      expect(File('${outputDir.path}/README.md').readAsStringSync(),
          '# my_game\n\nA test game');
    });
  });
}

CommandRunner<int> _createRunner(Future<int> Function(String, List<String>, {String?}) runProcess) {
  return CommandRunner<int>('game_agent', 'test')
    ..addCommand(CreateCommand(
      runProcess: runProcess,
      findTemplate: (name) => Directory('packages/engine_cli/templates/default_game').absolute,
    ));
}

CommandRunner<int> _createLintRunner() {
  return CommandRunner<int>('game_agent', 'test')
    ..addCommand(LintCommand());
}

CommandRunner<int> _createPackRunner() {
  return CommandRunner<int>('game_agent', 'test')
    ..addCommand(PackAssetsCommand());
}

CommandRunner<int> _createUpgradeRunner(Future<int> Function(String, List<String>, {String?}) runProcess) {
  return CommandRunner<int>('game_agent', 'test')
    ..addCommand(UpgradeCommand(runProcess: runProcess));
}

void _writeTestPng(String path, int width, int height) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(255, 0, 0, 255));
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(image));
}

import 'package:image/image.dart' as img;