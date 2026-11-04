import 'package:flutter/material.dart';

import 'idle_controller.dart';

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
  String engineCredit = 'Built with ZARVAN',
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
