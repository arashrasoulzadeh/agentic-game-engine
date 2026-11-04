import 'package:flutter/material.dart';

import 'package:zarvan_core/zarvan_core_idle.dart';
import 'idle_controller.dart';
import 'idle_widgets.dart';

/// Lifetime / run stats from [IdleStats]: taps, prestiges, play time, and earned totals.
///
/// Empty when the world has no stats entity yet (should not happen after
/// [loadIdleDefinition]).
class StatsPanel extends StatelessWidget {
  const StatsPanel({super.key, required this.controller});

  final IdleController controller;

  @override
  Widget build(BuildContext context) {
    return ThrottledListenableBuilder(
      listenable: controller,
      urgentOf: () => controller.urgentGeneration,
      builder: (context, _) {
        final store = controller.world.componentsOf<IdleStats>();
        if (store.length == 0) return const SizedBox.shrink();
        final s = store.denseAt(0);
        final lifetime = s.lifetimeEarned.entries
            .map((e) => '${controller.format(e.value)} ${e.key}')
            .join(', ');
        final run = s.runEarned.entries
            .map((e) => '${controller.format(e.value)} ${e.key}')
            .join(', ');
        final played = Duration(seconds: s.secondsPlayed.round());
        final playedLabel =
            '${played.inHours}h ${played.inMinutes.remainder(60)}m';
        return Card(
          key: const Key('stats-panel'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Stats', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text('Taps: ${s.taps}', key: const Key('stats-taps')),
                Text(
                  'Prestiges: ${s.prestigeCount}',
                  key: const Key('stats-prestiges'),
                ),
                Text('Played: $playedLabel', key: const Key('stats-played')),
                if (run.isNotEmpty) Text('This run: $run'),
                if (lifetime.isNotEmpty) Text('Lifetime: $lifetime'),
              ],
            ),
          ),
        );
      },
    );
  }
}
