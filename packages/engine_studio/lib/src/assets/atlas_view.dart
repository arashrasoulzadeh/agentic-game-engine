import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:engine_flutter/engine_flutter.dart' show SpriteAtlas;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'asset_index.dart';
import '../prefs/strings.dart';

/// A sprite sheet's contents: one tile per packed sprite, drawn from the sheet and
/// labelled with the name a level refers to it by. Tapping a tile reports it, which is
/// what turns this into a picker.
class AtlasView extends StatefulWidget {
  final String projectRoot;
  final AtlasInfo atlas;

  /// Called with the sprite name when a tile is tapped. Null makes the view read-only.
  final ValueChanged<String>? onSelect;

  /// The sprite to highlight.
  final String? selected;

  const AtlasView({
    super.key,
    required this.projectRoot,
    required this.atlas,
    this.onSelect,
    this.selected,
  });

  @override
  State<AtlasView> createState() => _AtlasViewState();
}

class _AtlasViewState extends State<AtlasView> {
  SpriteAtlas? _sheet;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AtlasView old) {
    super.didUpdateWidget(old);
    if (old.atlas.image != widget.atlas.image ||
        old.atlas.manifest != widget.atlas.manifest) {
      _sheet = null;
      _error = null;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final bytes = File(
        p.join(widget.projectRoot, widget.atlas.image),
      ).readAsBytesSync();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final manifest =
          jsonDecode(
                File(
                  p.join(widget.projectRoot, widget.atlas.manifest),
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _sheet = SpriteAtlas.fromManifest(frame.image, manifest));
    } on Object catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not read ${widget.atlas.image}: $e');
      }
    }
  }

  @override
  void dispose() {
    _sheet?.image.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sheet = _sheet;
    if (_error != null) {
      return Center(key: const Key('atlas-error'), child: Text(_error!));
    }
    if (sheet == null) return const Center(child: CircularProgressIndicator());
    final theme = Theme.of(context);
    final names = widget.atlas.regions
        .where(sheet.regions.containsKey)
        .toList();
    return SingleChildScrollView(
      key: const Key('atlas-grid'),
      padding: const EdgeInsets.all(8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final name in names)
            InkWell(
              key: Key('sprite-$name'),
              onTap: widget.onSelect == null
                  ? null
                  : () => widget.onSelect!(name),
              child: Container(
                width: 88,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: widget.selected == name
                        ? theme.colorScheme.primary
                        : theme.dividerColor,
                    width: widget.selected == name ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 80,
                      height: 64,
                      child: CustomPaint(
                        painter: _SpritePainter(
                          sheet.image,
                          sheet.regions[name]!,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      name,
                      style: theme.textTheme.labelSmall,
                      overflow: TextOverflow.ellipsis,
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

/// Draws one region of the sheet, scaled to fit and centered, with pixels left crisp -
/// pixel art blurred by smoothing is not what the game will show.
class _SpritePainter extends CustomPainter {
  _SpritePainter(this.image, this.region);

  final ui.Image image;
  final Rect region;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = (size.width / region.width < size.height / region.height)
        ? size.width / region.width
        : size.height / region.height;
    final w = region.width * scale, h = region.height * scale;
    canvas.drawImageRect(
      image,
      region,
      Rect.fromLTWH((size.width - w) / 2, (size.height - h) / 2, w, h),
      Paint()..filterQuality = FilterQuality.none,
    );
  }

  @override
  bool shouldRepaint(_SpritePainter old) =>
      old.image != image || old.region != region;
}

/// Opens a dialog to choose a sprite from the project's declared atlases and returns
/// `(atlasId, spriteName)`, or null if cancelled. Undeclared atlases are not offered:
/// a level can only refer to an atlas the project declares.
Future<(String, String)?> showSpritePicker(
  BuildContext context, {
  required String projectRoot,
  required AssetIndex index,
  String? currentAtlas,
  String? currentRegion,
}) {
  final declared = index.atlases.where((a) => a.declared).toList();
  return showDialog<(String, String)>(
    context: context,
    builder: (context) => _SpritePickerDialog(
      projectRoot: projectRoot,
      atlases: declared,
      initialAtlas: currentAtlas,
      currentRegion: currentRegion,
    ),
  );
}

class _SpritePickerDialog extends StatefulWidget {
  final String projectRoot;
  final List<AtlasInfo> atlases;
  final String? initialAtlas;
  final String? currentRegion;

  const _SpritePickerDialog({
    required this.projectRoot,
    required this.atlases,
    required this.initialAtlas,
    required this.currentRegion,
  });

  @override
  State<_SpritePickerDialog> createState() => _SpritePickerDialogState();
}

class _SpritePickerDialogState extends State<_SpritePickerDialog> {
  AtlasInfo? _atlas;

  @override
  void initState() {
    super.initState();
    for (final a in widget.atlases) {
      if (a.id == widget.initialAtlas) _atlas = a;
    }
    _atlas ??= widget.atlases.isEmpty ? null : widget.atlases.first;
  }

  @override
  Widget build(BuildContext context) {
    final atlas = _atlas;
    return AlertDialog(
      title: Text(StudioStrings.t('atlas_view.pick_a_sprite')),
      content: SizedBox(
        width: 520,
        height: 420,
        child: atlas == null
            ? const Center(
                key: Key('picker-empty'),
                child: Text(
                  'No atlases are declared. Add them to assets/studio_atlases.json '
                  'to pick sprites here.',
                  textAlign: TextAlign.center,
                ),
              )
            : Column(
                children: [
                  DropdownButton<AtlasInfo>(
                    key: const Key('picker-atlas'),
                    value: atlas,
                    isExpanded: true,
                    items: [
                      for (final a in widget.atlases)
                        DropdownMenuItem(
                          value: a,
                          child: Text('${a.id}  (${a.regions.length} sprites)'),
                        ),
                    ],
                    onChanged: (a) => setState(() => _atlas = a),
                  ),
                  Expanded(
                    child: AtlasView(
                      projectRoot: widget.projectRoot,
                      atlas: atlas,
                      selected: atlas.id == widget.initialAtlas
                          ? widget.currentRegion
                          : null,
                      onSelect: (name) =>
                          Navigator.pop(context, (atlas.id, name)),
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          key: const Key('picker-cancel'),
          onPressed: () => Navigator.pop(context),
          child: Text(StudioStrings.t('common.cancel')),
        ),
      ],
    );
  }
}
