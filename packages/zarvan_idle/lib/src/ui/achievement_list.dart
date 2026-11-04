import 'package:flutter/material.dart';

import 'package:zarvan_core/zarvan_core_idle.dart';
import 'idle_controller.dart';
import 'idle_widgets.dart';

/// Every achievement with its progress, unlocked ones first marked done.
class AchievementList extends StatelessWidget {
  const AchievementList({super.key, required this.controller});

  final IdleController controller;

  @override
  Widget build(BuildContext context) {
    return ThrottledListenableBuilder(
      listenable: controller,
      urgentOf: () => controller.urgentGeneration,
      builder: (context, _) {
        final store = controller.world.componentsOf<Achievement>();
        final ids = [for (var i = 0; i < store.length; i++) store.entityAt(i)]
          ..sort();
        return ListView(children: [for (final e in ids) _row(store.get(e)!)]);
      },
    );
  }

  Widget _row(Achievement a) {
    final value = achievementValue(controller.world, a.stat);
    final progress = a.unlocked
        ? 1.0
        : (value / a.atLeast).toDouble().clamp(0.0, 1.0);
    return ListTile(
      key: Key('achievement-${a.id}'),
      leading: Icon(
        a.unlocked ? Icons.emoji_events : Icons.lock_outline,
        semanticLabel: a.unlocked ? 'Unlocked' : 'Locked',
      ),
      title: Text(controller.label(a.id, name: a.name, nameKey: a.nameKey)),
      subtitle: LinearProgressIndicator(value: progress),
      trailing: Text(
        a.unlocked
            ? 'Done'
            : '${controller.format(value)} / ${controller.format(a.atLeast)}',
      ),
    );
  }
}
