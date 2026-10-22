import 'package:engine_core/engine_core.dart';
import 'package:flutter/material.dart';

import 'package:engine_core/engine_core_idle.dart';
import 'idle_controller.dart';

/// The resources the player holds and what they earn per second.
///
/// Rebuilds when the controller notifies (about ten times a second), reading amounts straight from the
/// wallet; each value is formatted with the controller's [IdleController.style].
class ResourceHeader extends StatelessWidget {
  const ResourceHeader({
    super.key,
    required this.controller,
    this.resources = const ['coins'],
  });

  final IdleController controller;
  final List<String> resources;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Wrap(
        spacing: 16,
        children: [
          for (final r in resources)
            Semantics(
              label:
                  '$r: ${controller.format(controller.wallet.of(r))}, '
                  '${controller.format(controller.wallet.rateOf(r))} per second',
              child: ExcludeSemantics(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      controller.format(controller.wallet.of(r)),
                      key: Key('amount-$r'),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Text(
                      '$r  ·  ${controller.format(controller.wallet.rateOf(r))}/s',
                      key: Key('rate-$r'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A scrolling list of the game's generators with buy buttons (×1, ×10, ×100, Max).
///
/// It is a lazily built list, so hundreds of generators cost only the rows on screen. A button is enabled
/// only if that many are affordable, and "locked" generators (a missing technology) say so instead of
/// offering a purchase that would fail.
class GeneratorList extends StatelessWidget {
  const GeneratorList({super.key, required this.controller});

  final IdleController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final ids = controller.generatorIds;
        return ListView.builder(
          itemCount: ids.length,
          itemBuilder: (context, i) =>
              GeneratorRow(controller: controller, entity: ids[i]),
        );
      },
    );
  }
}

/// One generator: name, owned, what one makes, and the buy buttons.
class GeneratorRow extends StatelessWidget {
  const GeneratorRow({
    super.key,
    required this.controller,
    required this.entity,
  });

  final IdleController controller;
  final EntityId entity;

  @override
  Widget build(BuildContext context) {
    final g = controller.world.storeOf<Generator>().get(entity);
    if (g == null) return const SizedBox.shrink();
    final wallet = controller.wallet;
    final locked = missingTech(
      controller.world,
      controller.team,
      g.requires,
    ).isNotEmpty;
    final atMax = g.maxOwned != null && g.owned >= g.maxOwned!;
    final money = wallet.of(g.costResource);

    Widget button(String label, int? count) {
      final room = g.maxOwned == null ? (1 << 30) : g.maxOwned! - g.owned;
      final n = count ?? g.cost.maxAffordable(g.owned, money, limit: room);
      final price = count == null
          ? g.cost.totalCost(g.owned, n)
          : g.cost.totalCost(g.owned, count);
      final affordable =
          !locked &&
          !atMax &&
          n > 0 &&
          (count == null || (count <= room && money >= price));
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: FilledButton.tonal(
          key: Key('buy-${g.id}-$label'),
          onPressed: affordable
              ? () => controller.buy(entity, count: count)
              : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label),
              if (n > 0 || count != null)
                Text(
                  controller.format(price),
                  style: const TextStyle(fontSize: 11),
                ),
            ],
          ),
        ),
      );
    }

    final perUnit = g.output.entries
        .map((e) => '${controller.format(e.value)} ${e.key}/s')
        .join(', ');
    return Semantics(
      container: true,
      label: '${g.name ?? g.id}, ${g.owned} owned${locked ? ', locked' : ''}',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      g.name ?? g.id,
                      key: Key('name-${g.id}'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    '${g.owned}${g.maxOwned == null ? '' : ' / ${g.maxOwned}'}',
                    key: Key('owned-${g.id}'),
                  ),
                ],
              ),
              Text(perUnit.isEmpty ? '—' : '$perUnit each'),
              if (g.nextMilestone != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Next bonus: ×${controller.format(g.nextMilestone!.multiplier)} at ${g.nextMilestone!.owned} '
                        '(${g.nextMilestone!.owned - g.owned} to go)',
                        key: Key('milestone-${g.id}'),
                        style: const TextStyle(fontSize: 12),
                      ),
                      LinearProgressIndicator(
                        key: Key('milestone-bar-${g.id}'),
                        value: g.owned / g.nextMilestone!.owned,
                      ),
                    ],
                  ),
                ),
              if (locked)
                Text(
                  'Locked: needs ${g.requires.join(', ')}',
                  key: Key('locked-${g.id}'),
                ),
              const SizedBox(height: 4),
              Wrap(
                children: [
                  button('×1', 1),
                  button('×10', 10),
                  button('×100', 100),
                  button('Max', null),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A scrolling list of one-time upgrades with a buy button each.
class UpgradeList extends StatelessWidget {
  const UpgradeList({super.key, required this.controller});

  final IdleController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final ids = controller.upgradeIds;
        return ListView.builder(
          itemCount: ids.length,
          itemBuilder: (context, i) {
            final e = ids[i];
            final u = controller.world.storeOf<Upgrade>().get(e)!;
            final locked = missingTech(
              controller.world,
              controller.team,
              u.requires,
            ).isNotEmpty;
            final cost = u.cost.entries
                .map((c) => '${controller.format(c.value)} ${c.key}')
                .join(', ');
            final can =
                !u.purchased && !locked && controller.wallet.canAfford(u.cost);
            return ListTile(
              key: Key('upgrade-${u.id}'),
              title: Text(u.name ?? u.id),
              subtitle: Text(
                u.purchased
                    ? 'Bought'
                    : locked
                    ? 'Locked: needs ${u.requires.join(', ')}'
                    : '×${controller.format(u.multiplier)} ${u.target}  ·  $cost',
              ),
              trailing: u.purchased
                  ? const Icon(Icons.check)
                  : FilledButton.tonal(
                      key: Key('buy-upgrade-${u.id}'),
                      onPressed: can
                          ? () => controller.buyUpgradeById(e)
                          : null,
                      child: const Text('Buy'),
                    ),
            );
          },
        );
      },
    );
  }
}

/// The "while you were away" dialog content for an [OfflineSummary]. Pops `true` if the player doubled
/// the reward through [onDouble], `false` if they just collected.
class OfflineSummaryDialog extends StatelessWidget {
  const OfflineSummaryDialog({
    super.key,
    required this.summary,
    required this.format,
    this.onDouble,
  });

  final OfflineSummary summary;

  /// Offers "double it": shown only when set. It should present the reward (an ad, say) and complete with
  /// true if the player earned it; the dialog then closes and the game pays the bonus (see
  /// `IdleSession.doubleOffline`). The engine does not know about ad networks.
  final Future<bool> Function()? onDouble;

  /// How to write each earned amount (usually `controller.format`).
  final String Function(BigNumber) format;

  static String _duration(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${d.inMinutes}m';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('offline-summary'),
      title: const Text('While you were away'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'You were gone ${_duration(summary.credit.away)}'
            '${summary.credit.capped ? ' (earnings capped at ${_duration(summary.credit.credited)})' : ''}.',
            key: const Key('offline-time'),
          ),
          const SizedBox(height: 8),
          for (final e in summary.gained.entries)
            Text(
              '+${format(e.value)} ${e.key}',
              key: Key('offline-gain-${e.key}'),
            ),
        ],
      ),
      actions: [
        if (onDouble != null)
          TextButton(
            key: const Key('offline-double'),
            onPressed: () async {
              final navigator = Navigator.of(context);
              if (await onDouble!()) navigator.pop(true);
            },
            child: const Text('Double it'),
          ),
        TextButton(
          key: const Key('offline-collect'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Collect'),
        ),
      ],
    );
  }
}
