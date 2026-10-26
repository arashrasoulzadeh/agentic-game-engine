import 'dart:convert';
import 'dart:io';

import 'package:engine_core/engine_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../assets/asset_index.dart';
import '../assets/atlas_view.dart';
import '../prefs/strings.dart';
import 'clip_preview.dart';

/// Whether [path] holds AnimationClip-shaped JSON the clip editor can open.
bool looksLikeAnimationClipFile(String path) {
  if (!path.endsWith('.json')) return false;
  try {
    final text = File(path).readAsStringSync();
    final json = jsonDecode(text);
    parseAnimationClipLibrary(json);
    return true;
  } on Object {
    return false;
  }
}

/// Edits `AnimationClip` JSON on disk: frames, pivots, frameEvents, duration.
///
/// Same JSON the runtime/`animation.*` ops use — save writes the file in place
/// preserving single / map / `{clips:[…]}` form. When [projectRoot] is set,
/// the editor also offers an atlas region picker and a live onion-skin preview.
class ClipEditorScreen extends StatefulWidget {
  final String filePath;

  /// Project root used to resolve declared atlases for preview / region pick.
  /// Null keeps the JSON-only editor (tests / no project context).
  final String? projectRoot;

  const ClipEditorScreen({
    super.key,
    required this.filePath,
    this.projectRoot,
  });

  @override
  State<ClipEditorScreen> createState() => _ClipEditorScreenState();
}

class _ClipEditorScreenState extends State<ClipEditorScreen> {
  late String _form;
  late Map<String, Map<String, dynamic>> _library;
  String? _selectedClip;
  int _selectedFrame = 0;
  String? _error;
  bool _dirty = false;

  /// Session-only atlas for preview / picker (clips don't store atlasId).
  String? _atlasId;
  bool _playing = false;
  bool _onionSkin = true;

  final _durationController = TextEditingController();
  final _regionController = TextEditingController();
  final _offsetXController = TextEditingController();
  final _offsetYController = TextEditingController();
  final _eventTypeController = TextEditingController(text: 'sfx');
  final _eventDataController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _durationController.dispose();
    _regionController.dispose();
    _offsetXController.dispose();
    _offsetYController.dispose();
    _eventTypeController.dispose();
    _eventDataController.dispose();
    super.dispose();
  }

  Map<String, dynamic>? get _clip =>
      _selectedClip == null ? null : _library[_selectedClip];

  void _load() {
    try {
      final text = File(widget.filePath).readAsStringSync();
      final json = jsonDecode(text);
      _form = detectAnimationLibraryForm(json);
      _library = parseAnimationClipLibrary(json);
      _selectedClip = _library.keys.isEmpty
          ? null
          : (_library.keys.toList()..sort()).first;
      _selectedFrame = 0;
      _error = null;
      _dirty = false;
      _playing = false;
      _syncControllers();
      setState(() {});
    } on Object catch (e) {
      setState(() => _error = '$e');
    }
  }

  void _syncControllers() {
    final clip = _clip;
    if (clip == null) return;
    _durationController.text =
        '${(clip['frameDurationSeconds'] as num?)?.toDouble() ?? 0.1}';
    final regions = (clip['frameRegions'] as List?)?.cast<String>() ?? const [];
    if (_selectedFrame >= regions.length) _selectedFrame = 0;
    if (regions.isEmpty) {
      _offsetXController.text = '0';
      _offsetYController.text = '0';
      return;
    }
    ensureFrameOffsets(clip, 'frameOffsetsX');
    ensureFrameOffsets(clip, 'frameOffsetsY');
    ensureFrameEvents(clip);
    final ox = (clip['frameOffsetsX'] as List)[_selectedFrame] as num;
    final oy = (clip['frameOffsetsY'] as List)[_selectedFrame] as num;
    _offsetXController.text = '$ox';
    _offsetYController.text = '$oy';
  }

  void _markDirty() => setState(() => _dirty = true);

  void _save() {
    final clip = _clip;
    if (clip == null) return;
    final duration = double.tryParse(_durationController.text.trim());
    if (duration == null || duration <= 0) {
      setState(() => _error = StudioStrings.t('clip.badDuration'));
      return;
    }
    clip['frameDurationSeconds'] = duration;
    try {
      final encoded = encodeAnimationClipLibrary(_library, form: _form);
      final text = encodeLevelJson(encoded);
      File(widget.filePath).writeAsStringSync(text);
      setState(() {
        _dirty = false;
        _error = null;
      });
    } on Object catch (e) {
      setState(() => _error = '$e');
    }
  }

  void _selectClip(String name) {
    setState(() {
      _selectedClip = name;
      _selectedFrame = 0;
      _playing = false;
      _syncControllers();
    });
  }

  void _selectFrame(int index) {
    setState(() {
      _selectedFrame = index;
      _playing = false;
      _syncControllers();
    });
  }

  void _addFrame() {
    final clip = _clip;
    if (clip == null) return;
    final region = _regionController.text.trim();
    if (region.isEmpty) return;
    final regions = List<String>.from(clip['frameRegions'] as List? ?? []);
    regions.add(region);
    clip['frameRegions'] = regions;
    ensureFrameOffsets(clip, 'frameOffsetsX');
    ensureFrameOffsets(clip, 'frameOffsetsY');
    ensureFrameEvents(clip);
    _regionController.clear();
    _selectedFrame = regions.length - 1;
    _markDirty();
    _syncControllers();
  }

  Future<void> _pickRegion({bool replaceSelected = false}) async {
    final root = widget.projectRoot;
    if (root == null || !mounted) return;
    final regions =
        (_clip?['frameRegions'] as List?)?.cast<String>() ?? const <String>[];
    final currentRegion = replaceSelected
        ? (regions.isEmpty
            ? null
            : regions[_selectedFrame.clamp(0, regions.length - 1)])
        : (_regionController.text.trim().isEmpty
            ? null
            : _regionController.text.trim());
    final picked = await showSpritePicker(
      context,
      projectRoot: root,
      index: AssetIndex.scan(root),
      currentAtlas: _atlasId,
      currentRegion: currentRegion,
    );
    if (picked == null || !mounted) return;
    setState(() => _atlasId = picked.$1);
    if (replaceSelected) {
      final clip = _clip;
      if (clip == null) return;
      final regions = List<String>.from(clip['frameRegions'] as List? ?? []);
      if (regions.isEmpty) {
        regions.add(picked.$2);
        clip['frameRegions'] = regions;
        ensureFrameOffsets(clip, 'frameOffsetsX');
        ensureFrameOffsets(clip, 'frameOffsetsY');
        ensureFrameEvents(clip);
        _selectedFrame = 0;
      } else {
        regions[_selectedFrame.clamp(0, regions.length - 1)] = picked.$2;
        clip['frameRegions'] = regions;
      }
      _markDirty();
      _syncControllers();
    } else {
      _regionController.text = picked.$2;
      setState(() {});
    }
  }

  void _removeFrame() {
    final clip = _clip;
    if (clip == null) return;
    final regions = List<String>.from(clip['frameRegions'] as List? ?? []);
    if (regions.isEmpty) return;
    final i = _selectedFrame.clamp(0, regions.length - 1);
    regions.removeAt(i);
    final ox = List<double>.from(
      (clip['frameOffsetsX'] as List?)?.map((e) => (e as num).toDouble()) ?? [],
    );
    final oy = List<double>.from(
      (clip['frameOffsetsY'] as List?)?.map((e) => (e as num).toDouble()) ?? [],
    );
    final ev = List<List<Map<String, dynamic>>>.from(
      ((clip['frameEvents'] as List?) ?? []).map(
        (f) => [
          for (final e in (f as List)) Map<String, dynamic>.from(e as Map),
        ],
      ),
    );
    if (i < ox.length) ox.removeAt(i);
    if (i < oy.length) oy.removeAt(i);
    if (i < ev.length) ev.removeAt(i);
    clip['frameRegions'] = regions;
    clip['frameOffsetsX'] = ox;
    clip['frameOffsetsY'] = oy;
    clip['frameEvents'] = ev;
    _selectedFrame = regions.isEmpty ? 0 : i.clamp(0, regions.length - 1);
    _markDirty();
    _syncControllers();
  }

  void _applyPivot() {
    final clip = _clip;
    if (clip == null) return;
    final ox = double.tryParse(_offsetXController.text.trim());
    final oy = double.tryParse(_offsetYController.text.trim());
    if (ox == null || oy == null) {
      setState(() => _error = StudioStrings.t('clip.badPivot'));
      return;
    }
    setClipFramePivot(
      clip,
      frameIndex: _selectedFrame,
      offsetX: ox,
      offsetY: oy,
    );
    _markDirty();
  }

  void _addEvent() {
    final clip = _clip;
    if (clip == null) return;
    final type = _eventTypeController.text.trim();
    if (type.isEmpty) return;
    Map<String, dynamic> data = const {};
    final raw = _eventDataController.text.trim();
    if (raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) {
          setState(() => _error = StudioStrings.t('clip.badEventData'));
          return;
        }
        data = Map<String, dynamic>.from(decoded);
      } on Object {
        setState(() => _error = StudioStrings.t('clip.badEventData'));
        return;
      }
    }
    setClipFrameEvent(
      clip,
      frameIndex: _selectedFrame,
      type: type,
      data: data,
    );
    _eventDataController.clear();
    _markDirty();
  }

  void _removeEvent(int index) {
    final clip = _clip;
    if (clip == null) return;
    final frames = ensureFrameEvents(clip);
    if (index < 0 || index >= frames[_selectedFrame].length) return;
    frames[_selectedFrame].removeAt(index);
    _markDirty();
  }

  void _toggleLoop(bool? value) {
    final clip = _clip;
    if (clip == null || value == null) return;
    clip['loop'] = value;
    _markDirty();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && _library.isEmpty) {
      return Center(
        key: const Key('clip-error'),
        child: Text(_error!),
      );
    }
    final clip = _clip;
    final names = _library.keys.toList()..sort();
    final regions =
        (clip?['frameRegions'] as List?)?.cast<String>() ?? const <String>[];
    final events = (clip != null && regions.isNotEmpty)
        ? ensureFrameEvents(clip)[_selectedFrame.clamp(0, regions.length - 1)]
        : const <Map<String, dynamic>>[];

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
      },
      child: Column(
        key: const Key('clip-editor'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  Text(
                    StudioStrings.t('clip.title'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(width: 12),
                  if (_dirty)
                    Text(
                      StudioStrings.t('clip.unsaved'),
                      key: const Key('clip-dirty'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  const Spacer(),
                  IconButton(
                    key: const Key('clip-save'),
                    tooltip: StudioStrings.t('clip.save'),
                    onPressed: _save,
                    icon: const Icon(Icons.save_outlined),
                  ),
                ],
              ),
            ),
          ),
          if (_error != null)
            Material(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(_error!, key: const Key('clip-banner-error')),
              ),
            ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (names.length > 1)
                  SizedBox(
                    width: 160,
                    child: ListView(
                      key: const Key('clip-list'),
                      children: [
                        for (final name in names)
                          ListTile(
                            key: Key('clip-pick-$name'),
                            dense: true,
                            selected: name == _selectedClip,
                            title: Text(name),
                            onTap: () => _selectClip(name),
                          ),
                      ],
                    ),
                  ),
                Expanded(
                  child: clip == null
                      ? Center(child: Text(StudioStrings.t('clip.empty')))
                      : _buildClipBody(context, clip, regions, events),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClipBody(
    BuildContext context,
    Map<String, dynamic> clip,
    List<String> regions,
    List<Map<String, dynamic>> events,
  ) {
    final root = widget.projectRoot;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 120,
                      child: TextField(
                        key: const Key('clip-duration'),
                        controller: _durationController,
                        decoration: InputDecoration(
                          labelText: StudioStrings.t('clip.duration'),
                          isDense: true,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => _markDirty(),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Checkbox(
                      key: const Key('clip-loop'),
                      value: clip['loop'] as bool? ?? true,
                      onChanged: _toggleLoop,
                    ),
                    Text(StudioStrings.t('clip.loop')),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  StudioStrings.t('clip.frames'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                SizedBox(
                  height: 56,
                  child: ListView.builder(
                    key: const Key('clip-frames'),
                    scrollDirection: Axis.horizontal,
                    itemCount: regions.length,
                    itemBuilder: (context, i) {
                      final selected = i == _selectedFrame;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          key: Key('clip-frame-$i'),
                          label: Text('$i:${regions[i]}'),
                          selected: selected,
                          onSelected: (_) => _selectFrame(i),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('clip-region-input'),
                        controller: _regionController,
                        decoration: InputDecoration(
                          labelText: StudioStrings.t('clip.regionName'),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _addFrame(),
                      ),
                    ),
                    if (root != null)
                      IconButton(
                        key: const Key('clip-pick-region'),
                        tooltip: StudioStrings.t('clip.pickRegion'),
                        onPressed: () => _pickRegion(),
                        icon: const Icon(Icons.grid_on_outlined),
                      ),
                    IconButton(
                      key: const Key('clip-add-frame'),
                      tooltip: StudioStrings.t('clip.addFrame'),
                      onPressed: _addFrame,
                      icon: const Icon(Icons.add),
                    ),
                    if (root != null)
                      IconButton(
                        key: const Key('clip-replace-region'),
                        tooltip: StudioStrings.t('clip.replaceRegion'),
                        onPressed: () => _pickRegion(replaceSelected: true),
                        icon: const Icon(Icons.image_search_outlined),
                      ),
                    IconButton(
                      key: const Key('clip-remove-frame'),
                      tooltip: StudioStrings.t('clip.removeFrame'),
                      onPressed: regions.isEmpty ? null : _removeFrame,
                      icon: const Icon(Icons.remove),
                    ),
                  ],
                ),
                if (regions.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    StudioStrings.t('clip.pivot'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Row(
                    children: [
                      SizedBox(
                        width: 100,
                        child: TextField(
                          key: const Key('clip-offset-x'),
                          controller: _offsetXController,
                          decoration: const InputDecoration(
                            labelText: 'X',
                            isDense: true,
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 100,
                        child: TextField(
                          key: const Key('clip-offset-y'),
                          controller: _offsetYController,
                          decoration: const InputDecoration(
                            labelText: 'Y',
                            isDense: true,
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                        ),
                      ),
                      TextButton(
                        key: const Key('clip-apply-pivot'),
                        onPressed: _applyPivot,
                        child: Text(StudioStrings.t('clip.applyPivot')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    StudioStrings.t('clip.events'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Expanded(
                    child: ListView.builder(
                      key: const Key('clip-events'),
                      itemCount: events.length,
                      itemBuilder: (context, i) {
                        final e = events[i];
                        final data = e['data'];
                        return ListTile(
                          key: Key('clip-event-$i'),
                          dense: true,
                          title: Text('${e['type']}'),
                          subtitle: data == null ? null : Text('$data'),
                          trailing: IconButton(
                            key: Key('clip-event-remove-$i'),
                            icon: const Icon(Icons.close),
                            onPressed: () => _removeEvent(i),
                          ),
                        );
                      },
                    ),
                  ),
                  Row(
                    children: [
                      SizedBox(
                        width: 100,
                        child: TextField(
                          key: const Key('clip-event-type'),
                          controller: _eventTypeController,
                          decoration: InputDecoration(
                            labelText: StudioStrings.t('clip.eventType'),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          key: const Key('clip-event-data'),
                          controller: _eventDataController,
                          decoration: InputDecoration(
                            labelText: StudioStrings.t('clip.eventData'),
                            isDense: true,
                            hintText: '{"id":"swing"}',
                          ),
                        ),
                      ),
                      IconButton(
                        key: const Key('clip-add-event'),
                        tooltip: StudioStrings.t('clip.addEvent'),
                        onPressed: _addEvent,
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (root != null) ...[
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        StudioStrings.t('clip.preview'),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const Spacer(),
                      IconButton(
                        key: const Key('clip-pick-atlas'),
                        tooltip: StudioStrings.t('clip.pickAtlas'),
                        onPressed: () => _pickRegion(),
                        icon: const Icon(Icons.collections_outlined),
                      ),
                      IconButton(
                        key: const Key('clip-onion'),
                        tooltip: StudioStrings.t('clip.onionSkin'),
                        onPressed: () =>
                            setState(() => _onionSkin = !_onionSkin),
                        icon: Icon(
                          _onionSkin
                              ? Icons.filter_none
                              : Icons.filter_none_outlined,
                        ),
                        color: _onionSkin
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      IconButton(
                        key: const Key('clip-play'),
                        tooltip: _playing
                            ? StudioStrings.t('clip.pause')
                            : StudioStrings.t('clip.play'),
                        onPressed: regions.isEmpty
                            ? null
                            : () => setState(() => _playing = !_playing),
                        icon: Icon(
                          _playing ? Icons.pause : Icons.play_arrow,
                        ),
                      ),
                    ],
                  ),
                  if (_atlasId != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        StudioStrings.t(
                          'clip.atlasLabel',
                          {'id': _atlasId!},
                        ),
                        key: const Key('clip-atlas-label'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  Expanded(
                    child: ClipPreview(
                      key: const Key('clip-preview-widget'),
                      projectRoot: root,
                      clip: clip,
                      atlasId: _atlasId,
                      selectedFrame: _selectedFrame,
                      playing: _playing,
                      onionSkin: _onionSkin,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
