import 'package:engine_core/engine_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:engine_core/engine_core_idle.dart';
import '../session.dart';
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
        final store = controller.world.storeOf<Achievement>();
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

/// Player-facing settings for an idle game: number format, optional audio volumes
/// via [options], and a plain statement of the offline-progress rules so the cap
/// is never a surprise.
///
/// Persist style / separator across launches by wiring [onStyleChanged] and
/// [onDecimalSeparatorChanged] (e.g. into `PlayerOptions` custom keys). When
/// [options] is set, master / SFX volume sliders write through it immediately.
class IdleSettingsPanel extends StatelessWidget {
  const IdleSettingsPanel({
    super.key,
    required this.controller,
    this.offline = const OfflineConfig(),
    this.options,
    this.onStyleChanged,
    this.onDecimalSeparatorChanged,
  });

  final IdleController controller;

  /// The offline rules to describe (usually the session's).
  final OfflineConfig offline;

  /// When set, shows master / SFX volume sliders bound to [PlayerOptions].
  final PlayerOptionsManager? options;

  /// Called after the player picks a [NumberStyle] (persist here).
  final void Function(NumberStyle style)? onStyleChanged;

  /// Called after the player picks a decimal mark (`.` or `,`).
  final void Function(String separator)? onDecimalSeparatorChanged;

  static const _labels = {
    NumberStyle.suffix: '1.5M',
    NumberStyle.scientific: '1.5e6',
    NumberStyle.engineering: '1.5e6 (eng)',
    NumberStyle.grouped: '1,500,000',
  };

  @override
  Widget build(BuildContext context) {
    return ThrottledListenableBuilder(
      listenable: controller,
      urgentOf: () => controller.urgentGeneration,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Number format'),
          SegmentedButton<NumberStyle>(
            key: const Key('settings-number-style'),
            segments: [
              for (final e in _labels.entries)
                ButtonSegment(
                  value: e.key,
                  label: Text(e.value),
                  tooltip: e.key.name,
                ),
            ],
            selected: {controller.style},
            onSelectionChanged: (s) {
              final style = s.first;
              controller.setStyle(style);
              onStyleChanged?.call(style);
            },
          ),
          const SizedBox(height: 12),
          const Text('Decimal mark'),
          SegmentedButton<String>(
            key: const Key('settings-decimal-separator'),
            segments: const [
              ButtonSegment(value: '.', label: Text('1.5'), tooltip: 'dot'),
              ButtonSegment(value: ',', label: Text('1,5'), tooltip: 'comma'),
            ],
            selected: {controller.decimalSeparator},
            onSelectionChanged: (s) {
              final sep = s.first;
              controller.setDecimalSeparator(sep);
              onDecimalSeparatorChanged?.call(sep);
            },
          ),
          if (options != null) ...[
            const SizedBox(height: 16),
            _IdleAudioSettings(options: options!),
          ],
          const SizedBox(height: 12),
          Text(
            'While you are away you earn ${(offline.efficiency * 100).round()}% '
            'of your income, for up to ${offline.cap.inHours} hours.',
            key: const Key('settings-offline-notice'),
          ),
        ],
      ),
    );
  }
}

/// Listens to [PlayerOptionsManager] so volume sliders rebuild after async saves.
class _IdleAudioSettings extends StatefulWidget {
  const _IdleAudioSettings({required this.options});

  final PlayerOptionsManager options;

  @override
  State<_IdleAudioSettings> createState() => _IdleAudioSettingsState();
}

class _IdleAudioSettingsState extends State<_IdleAudioSettings> {
  @override
  void initState() {
    super.initState();
    widget.options.addListener(_onOptions);
  }

  @override
  void didUpdateWidget(covariant _IdleAudioSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.options != widget.options) {
      oldWidget.options.removeListener(_onOptions);
      widget.options.addListener(_onOptions);
    }
  }

  @override
  void dispose() {
    widget.options.removeListener(_onOptions);
    super.dispose();
  }

  void _onOptions(PlayerOptions _) {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.options.options;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Audio'),
        Row(
          children: [
            const SizedBox(width: 120, child: Text('Master volume')),
            Expanded(
              child: Slider(
                key: const Key('settings-master-volume'),
                value: o.masterVolume.clamp(0.0, 1.0),
                onChanged: (v) => widget.options.setOption('masterVolume', v),
              ),
            ),
          ],
        ),
        Row(
          children: [
            const SizedBox(width: 120, child: Text('SFX volume')),
            Expanded(
              child: Slider(
                key: const Key('settings-sfx-volume'),
                value: o.sfxVolume.clamp(0.0, 1.0),
                onChanged: (v) => widget.options.setOption('sfxVolume', v),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Material pause sheet: resume, jump to settings, or open credits.
///
/// Call [IdleController.stop] before showing and [IdleController.start] after
/// it closes so the economy freezes while the menu is up.
Future<void> showIdlePauseMenu(
  BuildContext context, {
  required VoidCallback onSettings,
  required VoidCallback onCredits,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const Key('pause-resume'),
            leading: const Icon(Icons.play_arrow),
            title: const Text('Resume'),
            onTap: () => Navigator.of(ctx).pop(),
          ),
          ListTile(
            key: const Key('pause-settings'),
            leading: const Icon(Icons.settings),
            title: const Text('Settings'),
            onTap: () {
              Navigator.of(ctx).pop();
              onSettings();
            },
          ),
          ListTile(
            key: const Key('pause-credits'),
            leading: const Icon(Icons.info_outline),
            title: const Text('Credits'),
            onTap: () {
              Navigator.of(ctx).pop();
              onCredits();
            },
          ),
        ],
      ),
    ),
  );
}

/// Simple credits dialog for Material idle shells (platformer uses [CreditsScene]).
Future<void> showIdleCredits(
  BuildContext context, {
  required String gameTitle,
  String engineCredit = 'Built with agentic-game-engine',
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const Key('idle-credits'),
      title: Text(gameTitle),
      content: Text(engineCredit),
      actions: [
        TextButton(
          key: const Key('idle-credits-close'),
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

/// Move a game between devices by text: shows the current save code with a copy button, and a field to
/// paste another device's code and load it.
///
/// A damaged, foreign or too-new code is explained in the player's words and leaves the current game
/// untouched (see [IdleSession.importCode]).
class SaveCodePanel extends StatefulWidget {
  const SaveCodePanel({super.key, required this.session});

  final IdleSession session;

  @override
  State<SaveCodePanel> createState() => _SaveCodePanelState();
}

class _SaveCodePanelState extends State<SaveCodePanel> {
  final _input = TextEditingController();
  String? _code;
  String? _message;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _export() => setState(() {
    _code = widget.session.exportCode();
    _message = null;
  });

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _code!));
    if (mounted) setState(() => _message = 'Copied.');
  }

  void _import() {
    try {
      widget.session.importCode(_input.text);
      setState(() => _message = 'Game loaded.');
    } on SaveFormatException catch (e) {
      setState(() => _message = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton(
          key: const Key('save-export'),
          onPressed: _export,
          child: const Text('Show my save code'),
        ),
        if (_code != null) ...[
          SelectableText(_code!, key: const Key('save-code')),
          TextButton(
            key: const Key('save-copy'),
            onPressed: _copy,
            child: const Text('Copy'),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          key: const Key('save-input'),
          controller: _input,
          decoration: const InputDecoration(labelText: 'Paste a save code'),
        ),
        FilledButton(
          key: const Key('save-import'),
          onPressed: _import,
          child: const Text('Load this code'),
        ),
        if (_message != null) Text(_message!, key: const Key('save-message')),
      ],
    );
  }
}

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
        final store = controller.world.storeOf<GoldenEvents>();
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
        final store = controller.world.storeOf<Challenge>();
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
        final store = controller.world.storeOf<IdleStats>();
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
    final n = controller.world.storeOf<ResearchNode>().get(entity)!;
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
        final store = controller.world.storeOf<SeasonPass>();
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

/// Paid time skips from the definition's `"timeWarps"` block.
class TimeWarpPanel extends StatelessWidget {
  const TimeWarpPanel({super.key, required this.controller});

  final IdleController controller;

  @override
  Widget build(BuildContext context) {
    return ThrottledListenableBuilder(
      listenable: controller,
      urgentOf: () => controller.urgentGeneration,
      builder: (context, _) {
        final ids = controller.timeWarpIds;
        if (ids.isEmpty) {
          return const SizedBox.shrink(key: Key('timewarp-empty'));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Text(
                'Time warp',
                key: const Key('timewarp-title'),
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
    final o = controller.world.storeOf<TimeWarpOffer>().get(entity)!;
    final cost = o.cost.entries
        .map((c) => '${controller.format(c.value)} ${c.key}')
        .join(', ');
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
