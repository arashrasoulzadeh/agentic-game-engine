import 'package:flutter/material.dart';
import 'package:zarvan_core/zarvan_core.dart';

import 'idle_controller.dart';
import 'idle_widgets.dart';

/// A titled list of rows over an [IdleController]: the frame the research and
/// time-warp panels share. Shows nothing when [idsOf] is empty, rebuilds with
/// the controller (throttled, like every idle widget), and keys the empty
/// state and title as `<keyPrefix>-empty` / `<keyPrefix>-title` so tests and
/// games can find them.
class IdleListPanel extends StatelessWidget {
  const IdleListPanel({
    super.key,
    required this.controller,
    required this.title,
    required this.keyPrefix,
    required this.idsOf,
    required this.rowFor,
  });

  final IdleController controller;
  final String title;
  final String keyPrefix;

  /// The entities to list, read on every rebuild.
  final List<EntityId> Function() idsOf;
  final Widget Function(EntityId entity) rowFor;

  @override
  Widget build(BuildContext context) {
    return ThrottledListenableBuilder(
      listenable: controller,
      urgentOf: () => controller.urgentGeneration,
      builder: (context, _) {
        final ids = idsOf();
        if (ids.isEmpty) return SizedBox.shrink(key: Key('$keyPrefix-empty'));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Text(
                title,
                key: Key('$keyPrefix-title'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final e in ids) rowFor(e),
          ],
        );
      },
    );
  }
}

/// `"10 coins, 2 gems"` for a cost map, numbers in the controller's style.
String costText(IdleController controller, Map<String, BigNumber> cost) => cost
    .entries
    .map((c) => '${controller.format(c.value)} ${c.key}')
    .join(', ');
