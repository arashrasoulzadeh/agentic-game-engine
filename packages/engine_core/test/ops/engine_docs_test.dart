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

  test('without docsRoot returns bundled curated pages with markdown', () async {
    final r = await registry.call('engine.docs', {}, ctx());
    expect(r.ok, isTrue, reason: '${r.error}');
    final data = (r.data! as Map).cast<String, Object?>();
    expect(data['source'], 'bundled');
    expect(data['docsUrl'], kEngineDocsUrl);
    expect(data['pages'], kRemoteDocsPages);
    expect(data['bundled'], isTrue);
    final page = await registry.call('engine.docs', {
      'page': 'getting-started',
    }, ctx());
    expect(page.ok, isTrue);
    final body = (page.data! as Map).cast<String, Object?>();
    expect(body['source'], 'bundled');
    expect(body['url'], contains('getting-started'));
    expect(body['markdown'], contains('Getting started'));
  });

  test('bundled_docs.g.dart matches docs/ for every curated page', () {
    final docsRoot = Directory(
      p.normalize(p.join(Directory.current.path, '..', '..', 'docs')),
    );
    for (final rel in kRemoteDocsPages) {
      final onDisk = File(p.join(docsRoot.path, rel)).readAsStringSync();
      expect(
        kBundledDocs[rel],
        onDisk,
        reason: 'Run: cd packages/engine_core && dart run tool/gen_bundled_docs.dart',
      );
    }
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
