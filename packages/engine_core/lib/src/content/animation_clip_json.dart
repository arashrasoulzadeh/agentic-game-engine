/// Pure-JSON helpers for `AnimationClip`-shaped maps (no Flutter).
///
/// The runtime type lives in `engine_flutter`; agents/CLI/studio edit the
/// same JSON shape here so they never need a Flutter dependency. A clip
/// object must have `name` (string) and `frameRegions` (string list);
/// optional `frameDurationSeconds`, `loop`, `frameOffsetsX`/`Y`,
/// `frameEvents`.

/// True when [json] looks like a single clip (`name` + `frameRegions`).
bool isAnimationClipJson(Object? json) {
  if (json is! Map) return false;
  return json['name'] is String && json['frameRegions'] is List;
}

/// Validates a single clip map. Returns human-readable problems (empty =
/// ok). Does not mutate [json].
List<String> validateAnimationClipJson(Map<String, dynamic> json) {
  final problems = <String>[];
  if (json['name'] is! String || (json['name'] as String).isEmpty) {
    problems.add('name must be a non-empty string');
  }
  final regions = json['frameRegions'];
  if (regions is! List || regions.isEmpty) {
    problems.add('frameRegions must be a non-empty list of strings');
  } else {
    for (var i = 0; i < regions.length; i++) {
      if (regions[i] is! String) {
        problems.add('frameRegions[$i] must be a string');
      }
    }
  }
  final n = regions is List ? regions.length : 0;
  void checkOffsets(String key) {
    final v = json[key];
    if (v == null) return;
    if (v is! List) {
      problems.add('$key must be a list');
      return;
    }
    if (n > 0 && v.length != n) {
      problems.add('$key length ${v.length} != frameRegions length $n');
    }
    for (var i = 0; i < v.length; i++) {
      if (v[i] is! num) problems.add('$key[$i] must be a number');
    }
  }

  checkOffsets('frameOffsetsX');
  checkOffsets('frameOffsetsY');

  final events = json['frameEvents'];
  if (events != null) {
    if (events is! List) {
      problems.add('frameEvents must be a list');
    } else {
      if (n > 0 && events.length != n) {
        problems.add(
          'frameEvents length ${events.length} != frameRegions length $n',
        );
      }
      for (var i = 0; i < events.length; i++) {
        final frame = events[i];
        if (frame is! List) {
          problems.add('frameEvents[$i] must be a list');
          continue;
        }
        for (var j = 0; j < frame.length; j++) {
          final e = frame[j];
          if (e is! Map || e['type'] is! String) {
            problems.add('frameEvents[$i][$j] must be {type, data?}');
          }
        }
      }
    }
  }

  if (json.containsKey('frameDurationSeconds') &&
      json['frameDurationSeconds'] is! num) {
    problems.add('frameDurationSeconds must be a number');
  }
  if (json.containsKey('loop') && json['loop'] is! bool) {
    problems.add('loop must be a bool');
  }
  return problems;
}

/// Normalizes a file body into `name → clip` maps.
///
/// Accepts: one clip object; a map of named clips; `{ "clips": [ ... ] }`.
Map<String, Map<String, dynamic>> parseAnimationClipLibrary(Object? json) {
  if (json == null) {
    throw FormatException('animation JSON is null');
  }
  if (isAnimationClipJson(json)) {
    final clip = Map<String, dynamic>.from(json as Map);
    return {clip['name'] as String: clip};
  }
  if (json is! Map) {
    throw FormatException('animation JSON must be an object');
  }
  final root = Map<String, dynamic>.from(json);
  if (root['clips'] is List) {
    final out = <String, Map<String, dynamic>>{};
    for (final item in root['clips'] as List) {
      if (!isAnimationClipJson(item)) {
        throw FormatException('clips[] entry is not a clip object');
      }
      final clip = Map<String, dynamic>.from(item as Map);
      out[clip['name'] as String] = clip;
    }
    return out;
  }
  final out = <String, Map<String, dynamic>>{};
  for (final e in root.entries) {
    if (!isAnimationClipJson(e.value)) {
      throw FormatException('"${e.key}" is not a clip object');
    }
    out[e.key] = Map<String, dynamic>.from(e.value as Map);
  }
  return out;
}

/// Ensures [clip] has a `frameEvents` list sized to `frameRegions`.
List<List<Map<String, dynamic>>> ensureFrameEvents(
  Map<String, dynamic> clip,
) {
  final n = (clip['frameRegions'] as List).length;
  final raw = clip['frameEvents'];
  final frames = <List<Map<String, dynamic>>>[];
  if (raw is List) {
    for (var i = 0; i < n; i++) {
      if (i < raw.length && raw[i] is List) {
        frames.add([
          for (final e in raw[i] as List)
            Map<String, dynamic>.from(e as Map),
        ]);
      } else {
        frames.add([]);
      }
    }
  } else {
    for (var i = 0; i < n; i++) {
      frames.add([]);
    }
  }
  clip['frameEvents'] = frames;
  return frames;
}

/// Ensures [clip] has [key] (`frameOffsetsX`/`frameOffsetsY`) sized to
/// `frameRegions`, defaulting missing entries to `0`.
List<double> ensureFrameOffsets(Map<String, dynamic> clip, String key) {
  final n = (clip['frameRegions'] as List).length;
  final raw = clip[key];
  final out = <double>[];
  if (raw is List) {
    for (var i = 0; i < n; i++) {
      out.add(i < raw.length ? (raw[i] as num).toDouble() : 0);
    }
  } else {
    for (var i = 0; i < n; i++) {
      out.add(0);
    }
  }
  clip[key] = out;
  return out;
}

/// Appends (or replaces all cues of [type] when [replaceType] is true) a
/// cue on [frameIndex]. Mutates [clip].
void setClipFrameEvent(
  Map<String, dynamic> clip, {
  required int frameIndex,
  required String type,
  Map<String, dynamic> data = const {},
  bool replaceType = false,
}) {
  final regions = clip['frameRegions'] as List?;
  if (regions == null || frameIndex < 0 || frameIndex >= regions.length) {
    throw RangeError.index(frameIndex, regions ?? const [], 'frameIndex');
  }
  if (type.isEmpty) {
    throw ArgumentError('type must not be empty');
  }
  final frames = ensureFrameEvents(clip);
  final frame = frames[frameIndex];
  if (replaceType) {
    frame.removeWhere((e) => e['type'] == type);
  }
  frame.add({
    'type': type,
    if (data.isNotEmpty) 'data': Map<String, dynamic>.from(data),
  });
}

/// Clears cues on [frameIndex] (or only those with [type] when set).
void clearClipFrameEvents(
  Map<String, dynamic> clip, {
  required int frameIndex,
  String? type,
}) {
  final regions = clip['frameRegions'] as List?;
  if (regions == null || frameIndex < 0 || frameIndex >= regions.length) {
    throw RangeError.index(frameIndex, regions ?? const [], 'frameIndex');
  }
  final frames = ensureFrameEvents(clip);
  if (type == null) {
    frames[frameIndex] = [];
  } else {
    frames[frameIndex].removeWhere((e) => e['type'] == type);
  }
}

/// Writes pivot offsets for [frameIndex]. Mutates [clip].
void setClipFramePivot(
  Map<String, dynamic> clip, {
  required int frameIndex,
  double? offsetX,
  double? offsetY,
}) {
  final regions = clip['frameRegions'] as List?;
  if (regions == null || frameIndex < 0 || frameIndex >= regions.length) {
    throw RangeError.index(frameIndex, regions ?? const [], 'frameIndex');
  }
  if (offsetX != null) {
    ensureFrameOffsets(clip, 'frameOffsetsX')[frameIndex] = offsetX;
  }
  if (offsetY != null) {
    ensureFrameOffsets(clip, 'frameOffsetsY')[frameIndex] = offsetY;
  }
}

/// Serializes a library back to the shape it was loaded as when possible.
Object encodeAnimationClipLibrary(
  Map<String, Map<String, dynamic>> library, {
  required String form,
}) {
  switch (form) {
    case 'single':
      if (library.length != 1) {
        throw StateError('single form requires exactly one clip');
      }
      return library.values.single;
    case 'clips':
      return {
        'clips': [for (final c in library.values) c],
      };
    case 'map':
    default:
      return {for (final e in library.entries) e.key: e.value};
  }
}

/// Detects which library form [json] used.
String detectAnimationLibraryForm(Object? json) {
  if (isAnimationClipJson(json)) return 'single';
  if (json is Map && json['clips'] is List) return 'clips';
  return 'map';
}
