import 'package:zarvan_core/zarvan_core.dart';
import 'package:flutter/material.dart';

import 'package:zarvan_core/zarvan_core_idle.dart';
import 'idle_controller.dart';
import 'idle_widgets.dart';

/// Research tree: buy nodes to [grantTech] unlocks that gate generators / upgrades.
class ResearchPanel extends StatelessWidget {
  const ResearchPanel({super.key, required this.controller});

  final IdleController controller;

  @override
  Widget build(BuildContext context) {
    return ThrottledListenableBuilder(
      listenable: controller,
      urgentOf: () => controller.urgentGeneration,
      builder: (context, _) {
        final ids = controller.researchIds;
        if (ids.isEmpty) {
          return const SizedBox.shrink(key: Key('research-empty'));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Text(
                'Research',
                key: const Key('research-title'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final e in ids) _row(e),
          ],
        );
      },
    );
  }

  Widget _row(EntityId entity) {
    final n = controller.world.componentsOf<ResearchNode>().get(entity)!;
    final locked = missingTech(
      controller.world,
      controller.team,
      n.requires,
    ).isNotEmpty;
    final cost = n.cost.entries
        .map((c) => '${controller.format(c.value)} ${c.key}')
        .join(', ');
    final can = !n.purchased && !locked && controller.wallet.canAfford(n.cost);
    return ListTile(
      key: Key('research-${n.id}'),
      title: Text(controller.label(n.id, name: n.name, nameKey: n.nameKey)),
      subtitle: Text(
        n.purchased
            ? 'Researched · unlocks ${n.unlocks.join(', ')}'
            : locked
            ? 'Locked: needs ${n.requires.join(', ')}'
            : 'Unlocks ${n.unlocks.join(', ')} · $cost',
      ),
      trailing: n.purchased
          ? const Icon(Icons.check)
          : FilledButton.tonal(
              key: Key('buy-research-${n.id}'),
              onPressed: can ? () => controller.buyResearchById(entity) : null,
              child: const Text('Research'),
            ),
    );
  }
}
