import 'package:engine_core/engine_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:engine_core/engine_core_idle.dart';
import '../session.dart';
import 'idle_controller.dart';

/// What prestiging would give right now, the bonus already held, and a button to do it.
///
/// Prestige throws the run away, so the button asks for confirmation first; nothing is hidden when the
/// game has no prestige rule (the panel is simply empty).
class PrestigePanel extends StatelessWidget {
  const PrestigePanel({super.key, required this.controller});

  final IdleController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final rules = controller.world.storeOf<PrestigeRule>();
        if (rules.length == 0) return const SizedBox.shrink();
        final rule = rules.denseAt(0);
        final gain = prestigeGainNow(controller.world);
        final held = controller.wallet.of(rule.currency);
        final bonus = held * BigNumber.from(rule.bonusPerUnit);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You hold ${controller.format(held)} ${rule.currency} '
              '(+${controller.format(bonus * BigNumber.from(100))}% income)',
              key: const Key('prestige-held'),
            ),
            Text(
              gain < BigNumber.one
                  ? 'Earn more ${rule.basedOn} to prestige.'
                  : 'Prestige now for +${controller.format(gain)} ${rule.currency}.',
              key: const Key('prestige-gain'),
            ),
            FilledButton(
              key: const Key('prestige-button'),
              onPressed: gain < BigNumber.one
                  ? null
                  : () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          key: const Key('prestige-confirm'),
                          title: const Text('Prestige?'),
                          content: Text(
                            'Your run resets. You keep ${rule.currency}, achievements and statistics.',
                          ),
                          actions: [
                            TextButton(
                              key: const Key('prestige-cancel'),
                              onPressed: () => Navigator.of(ctx).pop(false),
                              child: const Text('Not yet'),
                            ),
                            FilledButton(
                              key: const Key('prestige-confirm-yes'),
                              onPressed: () => Navigator.of(ctx).pop(true),
                              child: const Text('Prestige'),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) controller.prestige();
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
    return ListenableBuilder(
      listenable: controller,
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
    return ListenableBuilder(
      listenable: controller,
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
