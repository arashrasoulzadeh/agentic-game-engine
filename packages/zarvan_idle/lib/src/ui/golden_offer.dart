import 'package:flutter/material.dart';

import 'package:zarvan_core/zarvan_core_idle.dart';
import 'idle_controller.dart';
import 'idle_widgets.dart';

/// The "golden cookie": a button that appears while a golden offer is showing, with the seconds left, and gives
/// its reward when pressed. Shows nothing otherwise (and in games without golden events). Describe the reward
/// to the player with [describe]; the default names the kind.
class GoldenOffer extends StatelessWidget {
  const GoldenOffer({
    super.key,
    required this.controller,
    this.describe,
    this.onClaimed,
  });

  final IdleController controller;

  /// Text for a reward, shown after claiming (via [onClaimed]) or on the button; default `Boost` / `Bonus`.
  final String Function(GoldenReward reward)? describe;

  /// Called with the reward just given.
  final void Function(GoldenReward reward)? onClaimed;

  @override
  Widget build(BuildContext context) {
    return ThrottledListenableBuilder(
      listenable: controller,
      urgentOf: () => controller.urgentGeneration,
      builder: (context, _) {
        final store = controller.world.componentsOf<GoldenEvents>();
        if (store.length == 0) return const SizedBox.shrink();
        final g = store.denseAt(0);
        final offered = g.offered;
        if (offered == null) return const SizedBox.shrink();
        final reward = g.rewards[offered];
        return FilledButton.icon(
          key: const Key('golden-offer'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFFFC107),
            foregroundColor: Colors.black,
          ),
          onPressed: () {
            final given = controller.claimGoldenOffer();
            if (given != null) onClaimed?.call(given);
          },
          icon: const Icon(Icons.auto_awesome),
          label: Text(
            '${describe?.call(reward) ?? (reward.kind == 'boost' ? 'Boost' : 'Bonus')} · ${g.offerRemaining.ceil()}s',
          ),
        );
      },
    );
  }
}
