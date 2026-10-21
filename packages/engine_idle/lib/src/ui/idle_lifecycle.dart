import 'package:engine_core/engine_core.dart';
import 'package:flutter/widgets.dart';

import '../session.dart';

/// Connects the app's lifecycle to an [IdleSession]: saving and stopping the clock when the app goes to
/// the background, and on return paying out the time away and handing the summary to [onAway] (usually to
/// show an `OfflineSummaryDialog`).
///
/// Wrap your game screen in it. On web, where background tabs are throttled rather than frozen, resuming
/// is the only moment progress can be reliably settled, which is exactly what this does.
class IdleLifecycleHost extends StatefulWidget {
  const IdleLifecycleHost({
    super.key,
    required this.session,
    required this.child,
    this.onAway,
  });

  final IdleSession session;
  final Widget child;

  /// Called with what was earned while away (only when something was).
  final void Function(OfflineSummary summary)? onAway;

  @override
  State<IdleLifecycleHost> createState() => _IdleLifecycleHostState();
}

class _IdleLifecycleHostState extends State<IdleLifecycleHost>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        widget.session.onPause();
      case AppLifecycleState.resumed:
        final summary = widget.session.onResume();
        if (summary != null) widget.onAway?.call(summary);
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
