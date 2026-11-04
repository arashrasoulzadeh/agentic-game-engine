import 'package:zarvan_core/zarvan_core.dart';
import 'package:flutter/material.dart';

import 'package:zarvan_core/zarvan_core_idle.dart';
import 'idle_controller.dart';
import 'idle_list_panel.dart';

/// Paid time skips from the definition's `"timeWarps"` block.
class TimeWarpPanel extends StatelessWidget {
  const TimeWarpPanel({super.key, required this.controller});

  final IdleController controller;

  @override
  Widget build(BuildContext context) => IdleListPanel(
    controller: controller,
    title: 'Time warp',
    keyPrefix: 'timewarp',
    idsOf: () => controller.timeWarpIds,
    rowFor: _row,
  );

  Widget _row(EntityId entity) {
    final o = controller.world.componentsOf<TimeWarpOffer>().get(entity)!;
    final cost = costText(controller, o.cost);
    final can = controller.wallet.canAfford(o.cost);
    final hours = o.seconds / 3600;
    final label = hours >= 1
        ? '${hours == hours.roundToDouble() ? hours.toInt() : hours.toStringAsFixed(1)}h'
        : '${o.seconds}s';
    return ListTile(
      key: Key('timewarp-${o.id}'),
      title: Text(controller.label(o.id, name: o.name, nameKey: o.nameKey)),
      subtitle: Text('Skip $label of income · $cost'),
      trailing: FilledButton.tonal(
        key: Key('buy-timewarp-${o.id}'),
        onPressed: can ? () => controller.buyTimeWarpById(entity) : null,
        child: const Text('Warp'),
      ),
    );
  }
}
