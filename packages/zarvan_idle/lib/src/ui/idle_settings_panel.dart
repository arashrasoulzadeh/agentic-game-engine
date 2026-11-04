import 'package:zarvan_core/zarvan_core.dart';
import 'package:flutter/material.dart';

import 'idle_controller.dart';
import 'idle_widgets.dart';

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
