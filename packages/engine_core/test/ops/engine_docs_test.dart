import 'dart:io';

import 'package:engine_core/engine_core_ops.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late OperationRegistry registry;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('engine_docs_');
    registry = buildRegistry();
    File(p.join(tmp.path, 'concepts', 'ecs.md'))
      ..createSync(recursive: true)
      ..writeAsStringSync('# ECS\n\nEntities and systems.\n');
    File(p.join(tmp.path, 'proposals', 'draft.md'))
      ..createSync(recursive: true)
      ..writeAsStringSync('# Draft\n');
    File(p.join(tmp.path, 'studio', 'qa-level-editor.md'))
      ..createSync(recursive: true)
      ..writeAsStringSync('# QA\n');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  OpContext ctx({String? docs}) => OpContext(
    actor: 'test',
    docsRoot: docs,
  );

  test('without docsRoot returns unsupported', () async {
    final r = await registry.call('engine.docs', {}, ctx());
    expect(r.ok, isFalse);
    expect(r.error!.code, ErrorCode.unsupported);
  });

  test('lists pages excluding drafts and QA checklist', () async {
    final r = await registry.call('engine.docs', {}, ctx(docs: tmp.path));
    expect(r.ok, isTrue, reason: '${r.error}');
    final data = (r.data! as Map).cast<String, Object?>();
    expect(data['pages'], ['concepts/ecs.md']);
    expect(data['count'], 1);
  });

  test('reads one page by path with or without .md', () async {
    final withExt = await registry.call('engine.docs', {
      'page': 'concepts/ecs.md',
    }, ctx(docs: tmp.path));
    expect(withExt.ok, isTrue);
    expect(
      ((withExt.data! as Map)['markdown'] as String),
      contains('Entities and systems'),
    );
    final bare = await registry.call('engine.docs', {
      'page': 'concepts/ecs',
    }, ctx(docs: tmp.path));
    expect(bare.ok, isTrue);
    expect((bare.data! as Map)['page'], 'concepts/ecs.md');
  });

  test('refuses path traversal and excluded pages', () async {
    expect(
      (await registry.call('engine.docs', {
        'page': '../secrets',
      }, ctx(docs: tmp.path))).error!.code,
      ErrorCode.notFound,
    );
    expect(
      (await registry.call('engine.docs', {
        'page': 'proposals/draft',
      }, ctx(docs: tmp.path))).error!.code,
      ErrorCode.notFound,
    );
  });
}
