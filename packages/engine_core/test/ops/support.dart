import 'dart:convert';
import 'dart:io';

import 'package:engine_core/engine_core_ops.dart';
import 'package:test/test.dart';

/// A throwaway game project on disk, built from code so the fixture cannot drift from what the engine expects.
class Scratch {
  Scratch._(this.dir, this.registry, this.ctx);

  final Directory dir;
  final OperationRegistry registry;
  final OpContext ctx;

  String get root => ctx.project?.root ?? dir.path;

  static const level1 = {
    'entities': [
      {
        'name': 'ground',
        'components': {
          'position': {'x': 0.0, 'y': 0.0},
          'tileMap': {
            'cols': 4,
            'rows': 2,
            'tileWidth': 16.0,
            'tileHeight': 16.0,
            'solidTileIds': [1],
            'tiles': [0, 0, 0, 0, 1, 1, 1, 1],
          },
        },
      },
      {
        'name': 'player',
        'components': {
          'position': {'x': 24.0, 'y': 8.0},
        },
      },
      {
        'name': 'coin_1',
        'components': {
          'position': {'x': 40.0, 'y': 8.0},
        },
      },
    ],
  };

  static const idleGame = {
    'resources': {
      'coins': {'start': '15'},
    },
    'generators': [
      {
        'id': 'cursor',
        'cost': {'type': 'geometric', 'base': '15', 'growth': 1.15},
        'output': {'coins': '0.5'},
      },
    ],
  };

  static Future<Scratch> create({
    bool open = true,
    bool readOnly = false,
    DateTime Function()? clock,
    Policy? policy,
  }) async {
    final dir = Directory.systemTemp.createTempSync('ops_project');
    addTearDown(() => dir.deleteSync(recursive: true));
    void write(String rel, String content) {
      final f = File('${dir.path}/$rel')..parent.createSync(recursive: true);
      f.writeAsStringSync(content);
    }

    write(
      'pubspec.yaml',
      'name: ops_demo\nversion: 1.2.3\nenvironment:\n  sdk: ^3.9.0\ndependencies:\n  flutter:\n    sdk: flutter\n  engine_core:\n    git:\n      url: x\n      ref: main\n',
    );
    write('lib/main.dart', 'class Hero {}\n');
    write(
      'assets/levels/level1.json',
      const JsonEncoder.withIndent('  ').convert(level1),
    );
    write('assets/levels/empty.json', '{"entities": []}');
    write(
      'assets/levels/broken.json',
      '{"entities": [{"name": "x", "components": {"position": {"x": "left", "y": 0}}}]}',
    );
    write('graphs/graph1.json', '{"type":"dialogue","nodes":[],"edges":[]}');
    write('assets/idle_game.json', jsonEncode(idleGame));
    final ctx = OpContext(
      project: open ? ProjectRoot(dir.path) : null,
      policy: policy ?? Policy(readOnly: readOnly),
      clock: clock,
      lockOwner: 'tester@host',
      actor: 'test',
    );
    return Scratch._(dir, buildRegistry(), ctx);
  }

  Future<OpResult> call(String name, [Map<String, Object?> args = const {}]) =>
      registry.call(name, args, ctx);

  /// Calls [name], expecting success, and returns the result data.
  Future<Object?> data(
    String name, [
    Map<String, Object?> args = const {},
  ]) async {
    final r = await call(name, args);
    expect(r.ok, isTrue, reason: '$name: ${r.error}');
    return r.data;
  }

  Future<Map<String, Object?>> map(
    String name, [
    Map<String, Object?> args = const {},
  ]) async => ((await data(name, args))! as Map).cast<String, Object?>();

  Future<ErrorCode?> failure(
    String name, [
    Map<String, Object?> args = const {},
  ]) async {
    final r = await call(name, args);
    expect(r.ok, isFalse, reason: '$name should fail');
    return r.error!.code;
  }

  String read(String rel) => File('${dir.path}/$rel').readAsStringSync();
  bool exists(String rel) => File('${dir.path}/$rel').existsSync();
  void write(String rel, String text) => File('${dir.path}/$rel')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(text);
}
