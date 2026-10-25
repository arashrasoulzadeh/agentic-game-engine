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
      title: Text(a.name ?? a.id),
      subtitle: LinearProgressIndicator(value: progress),
      trailing: Text(
        a.unlocked
            ? 'Done'
            : '${controller.format(value)} / ${controller.format(a.atLeast)}',
      ),
    );
  }
}

/// Player-facing settings for an idle game: how big numbers are written, and a plain statement of the
/// offline-progress rules so the cap is never a surprise.
class IdleSettingsPanel extends StatelessWidget {
  const IdleSettingsPanel({
    super.key,
    required this.controller,
    this.offline = const OfflineConfig(),
  });

  final IdleController controller;

  /// The offline rules to describe (usually the session's).
  final OfflineConfig offline;

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
            onSelectionChanged: (s) => controller.setStyle(s.first),
          ),
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
