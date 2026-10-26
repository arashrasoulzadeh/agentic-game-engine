import 'package:flutter/material.dart';

import '../prefs/strings.dart';

/// Horizontal frame strip with a compact event-marker lane under each cell.
///
/// Selecting a frame reports via [onSelectFrame]. Tapping an empty marker
/// slot calls [onAddEventAt] so the editor can attach the current type/data
/// draft without leaving the timeline. (No double-tap — that delays single
/// taps in tests and feels sluggish in the editor.)
class ClipEventTimeline extends StatelessWidget {
  final List<String> regions;
  final List<List<Map<String, dynamic>>> frameEvents;
  final int selectedFrame;
  final ValueChanged<int> onSelectFrame;
  final ValueChanged<int>? onAddEventAt;

  const ClipEventTimeline({
    super.key,
    required this.regions,
    required this.frameEvents,
    required this.selectedFrame,
    required this.onSelectFrame,
    this.onAddEventAt,
  });

  static Color colorForType(String type) {
    switch (type) {
      case 'sfx':
        return const Color(0xFF4FC3F7);
      case 'hitbox_on':
      case 'hitbox_off':
        return const Color(0xFFFF8A65);
      case 'shake':
        return const Color(0xFFFFD54F);
      case 'particle':
        return const Color(0xFF81C784);
      default:
        return const Color(0xFFB39DDB);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          StudioStrings.t('clip.timeline'),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 88,
          child: ListView.builder(
            key: const Key('clip-frames'),
            scrollDirection: Axis.horizontal,
            itemCount: regions.length,
            itemBuilder: (context, i) {
              final selected = i == selectedFrame;
              final events = i < frameEvents.length
                  ? frameEvents[i]
                  : const <Map<String, dynamic>>[];
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Material(
                  color: selected
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    key: Key('clip-frame-$i'),
                    width: 72,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => onSelectFrame(i),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    '$i',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    regions[i],
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          _EventLane(
                            frameIndex: i,
                            events: events,
                            onAdd: onAddEventAt,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (regions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 10,
              runSpacing: 2,
              children: [
                for (final e in const [
                  ('sfx', 'sfx'),
                  ('hitbox', 'hitbox_on'),
                  ('shake', 'shake'),
                  ('particle', 'particle'),
                  ('other', 'custom'),
                ])
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: colorForType(e.$2),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(e.$1, style: theme.textTheme.labelSmall),
                    ],
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _EventLane extends StatelessWidget {
  final int frameIndex;
  final List<Map<String, dynamic>> events;
  final ValueChanged<int>? onAdd;

  const _EventLane({
    required this.frameIndex,
    required this.events,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 16,
      child: Row(
        children: [
          Expanded(
            child: events.isEmpty
                ? Tooltip(
                    message: StudioStrings.t('clip.timelineAddHint'),
                    child: InkWell(
                      key: Key('clip-timeline-add-$frameIndex'),
                      onTap: onAdd == null ? null : () => onAdd!(frameIndex),
                      child: Container(
                        height: 10,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: Theme.of(context).dividerColor,
                          ),
                        ),
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var e = 0; e < events.length; e++)
                          Padding(
                            padding: const EdgeInsets.only(right: 3),
                            child: Tooltip(
                              message: '${events[e]['type']}',
                              child: Container(
                                key: Key('clip-timeline-mark-$frameIndex-$e'),
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: ClipEventTimeline.colorForType(
                                    '${events[e]['type']}',
                                  ),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
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
