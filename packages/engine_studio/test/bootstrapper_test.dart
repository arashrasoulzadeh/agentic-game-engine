import 'dart:convert';
import 'dart:io';

import 'package:engine_core/engine_core.dart';
import 'package:engine_studio/src/bootstrap/bootstrapper.dart';

import 'support/fake_release_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'everything is missing on first run, and nothing is installed without accepting',
    () async {
      final r = await bootstrapRig();
      r.server
        ..put('templates', 'T1')
        ..put('brushes', 'B1');

      final plan = await r.boot.check();
      expect(plan.problem, PlanProblem.none);
      expect(plan.actionable.map((i) => i.state), [
        ItemState.missing,
        ItemState.missing,
      ]);
      expect(plan.items.every((i) => i.decision == Decision.pending), isTrue);

      final failed = await r.boot.installAccepted(plan.items);
      expect(failed, isEmpty);
      expect(
        r.server.downloads,
        isEmpty,
        reason: 'undecided items are not downloaded',
      );
      expect(r.boot.installed, isEmpty);
    },
  );

  test(
    'accepted items are downloaded, verified, stored, and reported with progress',
    () async {
      final r = await bootstrapRig();
      r.server
        ..put('templates', 'T1')
        ..put('brushes', 'B1');
      final plan = await r.boot.check();
      plan.items[0].decision = Decision.accept;
      plan.items[1].decision = Decision.defer;

      var changes = 0;
      final failed = await r.boot.installAccepted(
        plan.items,
        onChanged: () => changes++,
      );

      expect(failed, isEmpty);
      expect(plan.items[0].status, InstallStatus.installed);
      expect(plan.items[0].progress, 1.0);
      expect(plan.items[1].status, InstallStatus.notStarted);
      expect(
        changes,
        greaterThan(2),
        reason: 'progress is reported while downloading',
      );
      expect(r.boot.fileFor('templates')!.readAsStringSync(), 'T1');
      expect(r.boot.fileFor('brushes'), isNull);
      expect(r.boot.installed, {'templates': sha(utf8.encode('T1'))});
    },
  );

  test(
    'a new version is offered as an update; unchanged items are current',
    () async {
      final r = await bootstrapRig();
      r.server
        ..put('templates', 'T1')
        ..put('brushes', 'B1');
      var plan = await r.boot.check();
      for (final i in plan.items) {
        i.decision = Decision.accept;
      }
      await r.boot.installAccepted(plan.items);

      r.server.put('templates', 'T2');
      plan = await r.boot.check();
      expect(
        {for (final i in plan.items) i.item.name: i.state},
        {'templates': ItemState.updateAvailable, 'brushes': ItemState.current},
      );
      expect(plan.actionable.single.item.name, 'templates');
    },
  );

  test(
    'a corrupt download is rejected and the previous version stays',
    () async {
      final r = await bootstrapRig();
      r.server.put('templates', 'T1');
      var plan = await r.boot.check();
      plan.items.single.decision = Decision.accept;
      await r.boot.installAccepted(plan.items);

      r.server.put('templates', 'T2');
      r.server.files['https://x/templates'] = utf8.encode(
        'tampered',
      ); // bytes no longer match the manifest
      plan = await r.boot.check();
      plan.items.single.decision = Decision.accept;
      final failed = await r.boot.installAccepted(plan.items);

      expect(failed.single.error, contains('checksum mismatch'));
      expect(plan.items.single.status, InstallStatus.failed);
      expect(
        r.boot.fileFor('templates')!.readAsStringSync(),
        'T1',
        reason: 'old version untouched',
      );
      expect(r.boot.installed['templates'], sha(utf8.encode('T1')));
      expect(File('${r.dir.path}/packs/templates.part').existsSync(), isFalse);
    },
  );

  test(
    'a failed download is reported, does not stop the others, and retry works',
    () async {
      final r = await bootstrapRig();
      r.server
        ..put('a', 'A')
        ..put('b', 'B');
      final plan = await r.boot.check();
      for (final i in plan.items) {
        i.decision = Decision.accept;
      }
      r.server.failDownloads = {'https://x/a'};

      final failed = await r.boot.installAccepted(plan.items);
      expect(failed.map((i) => i.item.name), ['a']);
      expect(plan.items[0].error, contains('connection reset'));
      expect(
        plan.items[1].status,
        InstallStatus.installed,
        reason: 'b still went through',
      );

      r.server.failDownloads = {};
      final retry = await r.boot.installAccepted(plan.items);
      expect(retry, isEmpty);
      expect(plan.items[0].status, InstallStatus.installed);
      expect(plan.items[0].error, isNull);
      expect(
        r.server.downloads.where((u) => u.endsWith('/b')).length,
        1,
        reason: 'b was not downloaded again',
      );
    },
  );

  test('a skipped version is not offered again until it changes', () async {
    final r = await bootstrapRig();
    r.server.put('templates', 'T1');
    var plan = await r.boot.check();
    r.boot.skip(plan.items.single);

    plan = await r.boot.check();
    expect(plan.items.single.decision, Decision.skip, reason: 'remembered');
    await r.boot.installAccepted(plan.items);
    expect(r.server.downloads, isEmpty);

    r.server.put('templates', 'T2');
    plan = await r.boot.check();
    expect(
      plan.items.single.decision,
      Decision.pending,
      reason: 'a newer version asks again',
    );
  });

  test(
    'an unsigned or wrongly signed manifest offers nothing and says why',
    () async {
      final r = await bootstrapRig();
      r.server.put('templates', 'T1');
      r.server.unsigned = true;
      var plan = await r.boot.check();
      expect(
        (plan.problem, plan.rejection),
        (PlanProblem.rejected, ManifestRejection.unsigned),
      );
      expect(plan.items, isEmpty);

      final other = await ReleaseManifestSigner.generateKeyPair();
      final forged = FakeReleaseServer(
        (m) => ReleaseManifestSigner.sign(m, other),
      )..put('templates', 'T1');
      final boot = Bootstrapper(
        server: forged,
        verifier: r.boot.verifier,
        cacheDir: r.dir,
      );
      plan = await boot.check();
      expect(
        (plan.problem, plan.rejection),
        (PlanProblem.rejected, ManifestRejection.invalidSignature),
      );
      expect(forged.downloads, isEmpty);
    },
  );

  test(
    'offline: an unreachable server is a plan problem, and cached packs still open',
    () async {
      final r = await bootstrapRig();
      r.server.put('templates', 'T1');
      final plan = await r.boot.check();
      plan.items.single.decision = Decision.accept;
      await r.boot.installAccepted(plan.items);

      r.server.unreachable = true;
      final offline = await r.boot.check();
      expect(offline.problem, PlanProblem.offline);
      expect(offline.detail, contains('no route to host'));
      expect(offline.items, isEmpty);
      expect(
        r.boot.fileFor('templates')!.readAsStringSync(),
        'T1',
        reason: 'the cache serves existing projects',
      );
    },
  );

  test(
    'installed state survives a restart (a new Bootstrapper on the same folder)',
    () async {
      final r = await bootstrapRig();
      r.server.put('templates', 'T1');
      final plan = await r.boot.check();
      plan.items.single.decision = Decision.accept;
      await r.boot.installAccepted(plan.items);

      final again = Bootstrapper(
        server: r.server,
        verifier: r.boot.verifier,
        cacheDir: r.dir,
      );
      expect(again.installed.keys, ['templates']);
      expect((await again.check()).items.single.state, ItemState.current);
    },
  );

  test(
    'item names with spaces and slashes are stored safely inside the cache',
    () async {
      final r = await bootstrapRig();
      r.server.put('default_game template/v2', 'Z');
      final plan = await r.boot.check();
      plan.items.single.decision = Decision.accept;
      await r.boot.installAccepted(plan.items);
      final f = r.boot.fileFor('default_game template/v2')!;
      expect(f.path.startsWith('${r.dir.path}/packs/'), isTrue);
      expect(f.readAsStringSync(), 'Z');
    },
  );
}
