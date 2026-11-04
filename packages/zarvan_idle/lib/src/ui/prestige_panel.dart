import 'package:zarvan_core/zarvan_core.dart';
import 'package:flutter/material.dart';

import 'package:zarvan_core/zarvan_core_idle.dart';
import 'idle_controller.dart';
import 'idle_widgets.dart';

/// What prestiging would give right now, the bonus already held, and a button to do it.
///
/// Prestige throws the run away, so the button asks for confirmation first; nothing is hidden when the
/// game has no prestige rule (the panel is simply empty).
class PrestigePanel extends StatelessWidget {
  const PrestigePanel({super.key, required this.controller, this.ruleId});

  final IdleController controller;

  /// Which prestige layer this panel shows (`PrestigeRule.id`); null is the first. A game with several layers
  /// shows one panel per layer; keys of a non-default layer end in `-<id>`.
  final String? ruleId;

  @override
  Widget build(BuildContext context) {
    return ThrottledListenableBuilder(
      listenable: controller,
      urgentOf: () => controller.urgentGeneration,
      builder: (context, _) {
        final rule = prestigeRuleOf(controller.world, ruleId);
        if (rule == null) return const SizedBox.shrink();
        Key k(String base) =>
            Key(rule.id == 'prestige' ? base : '$base-${rule.id}');
        final gain = prestigeGainNow(controller.world, rule.id);
        final held = controller.wallet.of(rule.currency);
        final bonus = held * BigNumber.from(rule.bonusPerUnit);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You hold ${controller.format(held)} ${rule.currency} '
              '(+${controller.format(bonus * BigNumber.from(100))}% income)',
              key: k('prestige-held'),
            ),
            Text(
              gain < BigNumber.one
                  ? 'Earn more ${rule.basedOn} to prestige.'
                  : 'Prestige now for +${controller.format(gain)} ${rule.currency}.',
              key: k('prestige-gain'),
            ),
            FilledButton(
              key: k('prestige-button'),
              onPressed: gain < BigNumber.one
                  ? null
                  : () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          key: k('prestige-confirm'),
                          title: const Text('Prestige?'),
                          content: Text(
                            'Your run resets. You keep ${rule.currency}, achievements and statistics.',
                          ),
                          actions: [
                            TextButton(
                              key: k('prestige-cancel'),
                              onPressed: () => Navigator.of(ctx).pop(false),
                              child: const Text('Not yet'),
                            ),
                            FilledButton(
                              key: k('prestige-confirm-yes'),
                              onPressed: () => Navigator.of(ctx).pop(true),
                              child: const Text('Prestige'),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) controller.prestige(rule.id);
                    },
              child: const Text('Prestige'),
            ),
          ],
        );
      },
    );
  }
}
