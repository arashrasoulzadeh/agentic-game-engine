import 'package:flutter/material.dart';

import 'package:zarvan_core/zarvan_core_idle.dart';
import 'idle_controller.dart';
import 'idle_widgets.dart';

/// The game's challenges: each with its rules, goal, reward and a Start / Abandon button. Starting one restarts the
/// run, so it asks first (like prestige). Shows nothing when the game has no challenges.
class ChallengePanel extends StatelessWidget {
  const ChallengePanel({super.key, required this.controller});

  final IdleController controller;

  static String _rule(String r) {
    if (r == 'noUpgrades') return 'No upgrades';
    if (r.startsWith('noGenerator:')) return 'No ${r.substring(12)}';
    if (r.startsWith('incomeMultiplier:')) return 'Income x${r.substring(17)}';
    return r;
  }

  @override
  Widget build(BuildContext context) {
    return ThrottledListenableBuilder(
      listenable: controller,
      urgentOf: () => controller.urgentGeneration,
      builder: (context, _) {
        final store = controller.world.componentsOf<Challenge>();
        if (store.length == 0) return const SizedBox.shrink();
        final running = activeChallenge(controller.world);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < store.length; i++)
              _tile(context, store.denseAt(i), running),
          ],
        );
      },
    );
  }

  Widget _tile(BuildContext context, Challenge c, Challenge? running) {
    final value = achievementValue(controller.world, c.goalStat);
    final status = c.completed
        ? 'Completed'
        : c.active
        ? '${controller.format(value)} / ${controller.format(c.goalAtLeast)}'
        : 'Goal ${controller.format(c.goalAtLeast)}';
    return ListTile(
      key: Key('challenge-${c.id}'),
      leading: Icon(
        c.completed ? Icons.emoji_events : Icons.flag_outlined,
        semanticLabel: c.completed ? 'Completed' : 'Challenge',
      ),
      title: Text(c.name ?? c.id),
      subtitle: Text(
        '${c.rules.map(_rule).join(', ')} · reward x${controller.format(c.reward)} · $status',
      ),
      trailing: c.completed
          ? null
          : c.active
          ? TextButton(
              key: Key('challenge-abandon-${c.id}'),
              onPressed: controller.abandonRunningChallenge,
              child: const Text('Abandon'),
            )
          : FilledButton(
              key: Key('challenge-start-${c.id}'),
              onPressed: running != null
                  ? null
                  : () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Start challenge?'),
                          content: const Text(
                            'Your run restarts with the challenge rules.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              child: const Text('Not yet'),
                            ),
                            FilledButton(
                              key: Key('challenge-confirm-${c.id}'),
                              onPressed: () => Navigator.of(ctx).pop(true),
                              child: const Text('Start'),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) controller.startChallengeById(c.id);
                    },
              child: const Text('Start'),
            ),
    );
  }
}
