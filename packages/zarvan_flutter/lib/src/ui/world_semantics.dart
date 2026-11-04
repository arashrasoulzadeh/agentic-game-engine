import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:zarvan_core/zarvan_core.dart';

import '../rendering/camera.dart';
import '../rendering/text.dart' as eng;

/// One thing a screen reader can find: a button or a line of text, with its
/// on-screen rectangle.
class SemanticTarget {
  const SemanticTarget({
    required this.label,
    required this.rect,
    this.actionId,
  });

  /// What the reader announces.
  final String label;

  /// Where it is on screen, in logical pixels.
  final Rect rect;

  /// Set for buttons: the id passed to the activate callback on a double-tap.
  final String? actionId;

  bool get isButton => actionId != null;
}

/// Reads [world] and returns what assistive technology should expose, in
/// reading order (top to bottom, then left to right).
///
/// The engine draws to a canvas, which a screen reader cannot see into, so
/// this rebuilds the same information from components: each `Button` (with
/// its `ButtonHitBox`) is labelled by the `Text` entity sitting inside its
/// box, falling back to its action id; remaining `Text` becomes read-only
/// lines (HUD, titles). Text with an empty string is skipped.
List<SemanticTarget> semanticTargets(
  World world,
  Camera camera,
  Size viewport,
) {
  final positions = world.componentsOf<Position>();
  final texts = world.componentsOf<eng.Text>();
  final buttons = world.componentsOf<Button>();
  final boxes = world.componentsOf<ButtonHitBox>();

  Offset screenOf(EntityId id, bool screenSpace) {
    final p = positions.get(id)!;
    return screenSpace
        ? Offset(p.x, p.y)
        : camera.worldToScreen(p.x, p.y, viewport);
  }

  final used = <EntityId>{};
  final out = <SemanticTarget>[];
  for (var i = 0; i < buttons.length; i++) {
    final id = buttons.entityAt(i);
    final box = boxes.get(id);
    if (positions.get(id) == null || box == null) continue;
    final centre = screenOf(id, false);
    final w = box.width * camera.zoom;
    final h = box.height * camera.zoom;
    final rect = Rect.fromCenter(center: centre, width: w, height: h);
    String? label;
    for (var t = 0; t < texts.length; t++) {
      final tid = texts.entityAt(t);
      if (positions.get(tid) == null) continue;
      final txt = texts.denseAt(t);
      if (rect.contains(screenOf(tid, txt.screenSpace)) &&
          txt.text.isNotEmpty) {
        label = txt.text;
        used.add(tid);
        break;
      }
    }
    out.add(
      SemanticTarget(
        label: label ?? buttons.denseAt(i).actionId,
        rect: rect,
        actionId: buttons.denseAt(i).actionId,
      ),
    );
  }
  for (var t = 0; t < texts.length; t++) {
    final tid = texts.entityAt(t);
    final txt = texts.denseAt(t);
    if (used.contains(tid) || txt.text.isEmpty || positions.get(tid) == null) {
      continue;
    }
    final c = screenOf(tid, txt.screenSpace);
    final w =
        (txt.maxWidth ?? txt.text.length * txt.fontSize * 0.6) *
        (txt.screenSpace ? 1 : camera.zoom);
    final h = txt.fontSize * (txt.screenSpace ? 1 : camera.zoom) * 1.3;
    out.add(
      SemanticTarget(
        label: txt.text,
        rect: Rect.fromCenter(center: c, width: w, height: h),
      ),
    );
  }
  out.sort((a, b) {
    final dy = a.rect.top.compareTo(b.rect.top);
    return dy != 0 ? dy : a.rect.left.compareTo(b.rect.left);
  });
  return out;
}

/// Lays invisible [Semantics] nodes over [child] (normally an `EngineView`)
/// so TalkBack and VoiceOver can read and activate the engine's menus and HUD.
///
/// [worldOf] and [cameraOf] are read each refresh; [onActivate] receives a
/// button's action id when the reader double-taps it. Refreshes only run
/// while assistive navigation is on, so there is no cost for other players.
class WorldSemantics extends StatefulWidget {
  const WorldSemantics({
    super.key,
    required this.worldOf,
    required this.cameraOf,
    required this.onActivate,
    required this.child,
    this.refresh = const Duration(milliseconds: 500),
  });

  final World? Function() worldOf;
  final Camera Function() cameraOf;
  final void Function(String actionId) onActivate;
  final Widget child;

  /// How often the node list is rebuilt while a reader is active.
  final Duration refresh;

  @override
  State<WorldSemantics> createState() => _WorldSemanticsState();
}

class _WorldSemanticsState extends State<WorldSemantics> {
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final on = MediaQuery.maybeOf(context)?.accessibleNavigation ?? false;
    if (on && _timer == null) {
      _timer = Timer.periodic(widget.refresh, (_) {
        if (mounted) setState(() {});
      });
    } else if (!on) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final on = MediaQuery.maybeOf(context)?.accessibleNavigation ?? false;
    final world = widget.worldOf();
    if (!on || world == null) return widget.child;
    return LayoutBuilder(
      builder: (context, c) {
        final targets = semanticTargets(
          world,
          widget.cameraOf(),
          Size(c.maxWidth, c.maxHeight),
        );
        return Stack(
          fit: StackFit.passthrough,
          children: [
            ExcludeSemantics(child: widget.child),
            for (final t in targets)
              Positioned.fromRect(
                rect: t.rect,
                child: Semantics(
                  label: t.label,
                  button: t.isButton,
                  onTap: t.isButton
                      ? () => widget.onActivate(t.actionId!)
                      : null,
                  child: const SizedBox.expand(),
                ),
              ),
          ],
        );
      },
    );
  }
}
