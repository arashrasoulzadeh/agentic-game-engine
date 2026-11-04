import 'package:zarvan_core/zarvan_core.dart';
import 'package:flutter/material.dart';

import 'package:zarvan_core/zarvan_core_idle.dart';
import 'idle_controller.dart';
import 'idle_widgets.dart';

/// Battle-pass track from the definition's `"seasonPass"` block.
class SeasonPassPanel extends StatelessWidget {
  const SeasonPassPanel({super.key, required this.controller});

  final IdleController controller;

  @override
  Widget build(BuildContext context) {
    return ThrottledListenableBuilder(
      listenable: controller,
      urgentOf: () => controller.urgentGeneration,
      builder: (context, _) {
        final store = controller.world.componentsOf<SeasonPass>();
        if (store.length == 0) {
          return const SizedBox.shrink(key: Key('season-pass-empty'));
        }
        final pass = store.denseAt(0);
        final xp = achievementValue(controller.world, pass.xpStat);
        return Card(
          key: const Key('season-pass'),
          margin: const EdgeInsets.all(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  controller.label(
                    pass.id,
                    name: pass.name,
                    nameKey: pass.nameKey,
                  ),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  'XP (${pass.xpStat}): ${controller.format(xp)}',
                  key: const Key('season-pass-xp'),
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < pass.tiers.length; i++) _tier(pass, i, xp),
                if (pass.claimed < pass.tiers.length)
                  FilledButton(
                    key: const Key('season-pass-claim'),
                    onPressed: () {
                      final n = claimSeasonPass(
                        controller.world,
                        controller.wallet,
                        team: controller.team,
                      );
                      if (n > 0) controller.refresh();
                    },
                    child: const Text('Claim rewards'),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _tier(SeasonPass pass, int i, BigNumber xp) {
    final t = pass.tiers[i];
    final done = i < pass.claimed;
    final ready = !done && xp >= t.at;
    final parts = <String>[
      if (t.grant.isNotEmpty)
        t.grant.entries
            .map((e) => '+${controller.format(e.value)} ${e.key}')
            .join(', '),
      if (t.multiplier != null) '×${controller.format(t.multiplier!)} income',
      if (t.tech != null) 'tech ${t.tech}',
    ];
    return ListTile(
      key: Key('season-tier-$i'),
      dense: true,
      leading: Icon(
        done
            ? Icons.check_circle
            : ready
            ? Icons.card_giftcard
            : Icons.lock_outline,
      ),
      title: Text('Tier ${i + 1} · at ${controller.format(t.at)}'),
      subtitle: Text(parts.isEmpty ? '—' : parts.join(' · ')),
    );
  }
}
