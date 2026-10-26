import 'dart:convert';

import '../../content/animation_clip_json.dart';
import '../../content/level_format.dart';
import '../context.dart';
import '../operation.dart';
import '../param.dart';
import '../result.dart';

String _requirePath(Map<String, Object?> a) {
  final path = a['path'] as String?;
  if (path == null || path.isEmpty) {
    throw OpError(ErrorCode.invalidParams, 'path is required.');
  }
  if (path.contains('..')) {
    throw OpError(ErrorCode.invalidParams, 'path must not contain "..".');
  }
  return path.replaceAll('\\', '/');
}

Map<String, dynamic> _readRoot(OpContext ctx, String rel) {
  final text = ctx.files.read(ctx.project!.resolve(rel));
  if (text == null) {
    throw OpError(
      ErrorCode.notFound,
      'No file at $rel.',
      hint: 'Create a clip JSON (single clip, name→clip map, or {clips:[…]}).',
    );
  }
  try {
    final decoded = jsonDecode(text);
    if (decoded is! Map && decoded is! List) {
      throw OpError(
        ErrorCode.validationFailed,
        '$rel must be a JSON object.',
      );
    }
    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{'clips': decoded};
  } on OpError {
    rethrow;
  } on Object catch (e) {
    throw OpError(
      ErrorCode.validationFailed,
      '$rel is not valid JSON ($e).',
    );
  }
}

Map<String, Map<String, dynamic>> _libraryFromRoot(Object root) {
  try {
    return parseAnimationClipLibrary(root);
  } on FormatException catch (e) {
    throw OpError(ErrorCode.validationFailed, e.message);
  }
}

Map<String, dynamic> _pickClip(
  Map<String, Map<String, dynamic>> library,
  String? clipName,
) {
  if (library.isEmpty) {
    throw OpError(ErrorCode.notFound, 'No clips in file.');
  }
  if (clipName == null || clipName.isEmpty) {
    if (library.length == 1) return library.values.single;
    throw OpError(
      ErrorCode.invalidParams,
      'clip is required when the file has multiple clips.',
      hint: 'Known: ${library.keys.join(', ')}',
    );
  }
  final clip = library[clipName];
  if (clip == null) {
    throw OpError(
      ErrorCode.notFound,
      'No clip named "$clipName".',
      hint: 'Known: ${library.keys.join(', ')}',
    );
  }
  return clip;
}

/// `animation.*`: edit/validate AnimationClip-shaped JSON on disk (IDE/agent
/// foundation — same schema `engine_flutter`'s `AnimationClip` uses).
List<Operation> animationOperations() => [
  Operation(
    name: 'animation.read',
    summary: 'Load AnimationClip JSON from a project path.',
    description:
        'Accepts a single clip object, a name→clip map, or `{ "clips": [ … ] }`. '
        'Returns `{ form, clips, names }` where `clips` is name→clip.',
    kind: OperationKind.read,
    scope: OperationScope.project,
    idempotent: true,
    params: const [
      Param('path', ParamType.string, required: true, positional: true),
    ],
    errors: {
      ErrorCode.notFound: 'File missing.',
      ErrorCode.validationFailed: 'JSON shape is not a clip library.',
    },
    handler: (ctx, a) {
      final rel = _requirePath(a);
      final root = _readRoot(ctx, rel);
      final form = detectAnimationLibraryForm(root);
      final library = _libraryFromRoot(root);
      return OpOutcome.data({
        'path': rel,
        'form': form,
        'names': library.keys.toList()..sort(),
        'clips': library,
      });
    },
  ),
  Operation(
    name: 'animation.validate',
    summary: 'Validate AnimationClip JSON on disk.',
    description:
        'Reports per-clip problems. `ok` is true when every clip passes.',
    kind: OperationKind.read,
    scope: OperationScope.project,
    idempotent: true,
    params: const [
      Param('path', ParamType.string, required: true, positional: true),
    ],
    errors: {
      ErrorCode.notFound: 'File missing.',
    },
    handler: (ctx, a) {
      final rel = _requirePath(a);
      final root = _readRoot(ctx, rel);
      Map<String, Map<String, dynamic>> library;
      try {
        library = parseAnimationClipLibrary(root);
      } on FormatException catch (e) {
        return OpOutcome.data({
          'ok': false,
          'path': rel,
          'problems': [e.message],
          'clips': <String, List<String>>{},
        });
      }
      final byClip = <String, List<String>>{};
      for (final e in library.entries) {
        final problems = validateAnimationClipJson(e.value);
        if (problems.isNotEmpty) byClip[e.key] = problems;
      }
      return OpOutcome.data({
        'ok': byClip.isEmpty,
        'path': rel,
        'clipCount': library.length,
        'clips': byClip,
      });
    },
  ),
  Operation(
    name: 'animation.set_event',
    summary: 'Attach a frameEvents cue to a clip JSON file.',
    description:
        'Ensures `frameEvents` exists, then appends `{type, data}` on '
        '`frame` (0-based). With `replaceType: true`, removes existing cues '
        'of that type on the frame first. Undoable.',
    kind: OperationKind.write,
    scope: OperationScope.project,
    idempotent: false,
    params: const [
      Param('path', ParamType.string, required: true, positional: true),
      Param('frame', ParamType.integer, required: true),
      Param('type', ParamType.string, required: true),
      Param(
        'clip',
        ParamType.string,
        description: 'Clip name when the file holds more than one clip.',
      ),
      Param(
        'data',
        ParamType.object,
        description: 'Optional cue payload (e.g. {"id":"swing"}).',
      ),
      Param(
        'replaceType',
        ParamType.boolean,
        description: 'Replace existing cues of this type on the frame.',
      ),
    ],
    errors: {
      ErrorCode.notFound: 'File or clip missing.',
      ErrorCode.validationFailed: 'Clip JSON invalid.',
      ErrorCode.invalidParams: 'frame out of range or type empty.',
    },
    handler: (ctx, a) {
      final rel = _requirePath(a);
      final frame = a['frame']! as int;
      final type = a['type']! as String;
      final clipName = a['clip'] as String?;
      final data = (a['data'] as Map?)?.cast<String, dynamic>() ?? const {};
      final replaceType = a['replaceType'] as bool? ?? false;

      final before = ctx.files.read(ctx.project!.resolve(rel));
      final root = _readRoot(ctx, rel);
      final form = detectAnimationLibraryForm(root);
      final library = _libraryFromRoot(root);
      final clip = _pickClip(library, clipName);
      final problems = validateAnimationClipJson(clip);
      if (problems.isNotEmpty) {
        throw OpError(
          ErrorCode.validationFailed,
          'Clip "${clip['name']}" is invalid: ${problems.join('; ')}',
        );
      }
      try {
        setClipFrameEvent(
          clip,
          frameIndex: frame,
          type: type,
          data: data,
          replaceType: replaceType,
        );
      } on RangeError catch (e) {
        throw OpError(ErrorCode.invalidParams, '$e');
      } on ArgumentError catch (e) {
        throw OpError(ErrorCode.invalidParams, '$e');
      }

      final key = clipName ?? library.keys.single;
      library[key] = clip;

      final encoded = encodeAnimationClipLibrary(library, form: form);
      final after = encodeLevelJson(encoded);
      return OpOutcome.proposal(
        Proposal([FileChange(path: rel, before: before, after: after)]),
        data: {
          'path': rel,
          'clip': clip['name'],
          'frame': frame,
          'type': type,
          'data': data,
        },
      );
    },
  ),
  Operation(
    name: 'animation.set_pivot',
    summary: 'Set frameOffsetsX/Y for one frame of a clip JSON file.',
    description:
        'Writes per-frame pivot offsets (atlas-pixel space). Pass `offsetX` '
        'and/or `offsetY`. Undoable.',
    kind: OperationKind.write,
    scope: OperationScope.project,
    idempotent: true,
    params: const [
      Param('path', ParamType.string, required: true, positional: true),
      Param('frame', ParamType.integer, required: true),
      Param(
        'clip',
        ParamType.string,
        description: 'Clip name when the file holds more than one clip.',
      ),
      Param('offsetX', ParamType.number),
      Param('offsetY', ParamType.number),
    ],
    errors: {
      ErrorCode.notFound: 'File or clip missing.',
      ErrorCode.invalidParams: 'Need offsetX and/or offsetY; frame in range.',
    },
    handler: (ctx, a) {
      final rel = _requirePath(a);
      final frame = a['frame']! as int;
      final clipName = a['clip'] as String?;
      final offsetX = (a['offsetX'] as num?)?.toDouble();
      final offsetY = (a['offsetY'] as num?)?.toDouble();
      if (offsetX == null && offsetY == null) {
        throw OpError(
          ErrorCode.invalidParams,
          'Provide offsetX and/or offsetY.',
        );
      }

      final before = ctx.files.read(ctx.project!.resolve(rel));
      final root = _readRoot(ctx, rel);
      final form = detectAnimationLibraryForm(root);
      final library = _libraryFromRoot(root);
      final clip = _pickClip(library, clipName);
      try {
        setClipFramePivot(
          clip,
          frameIndex: frame,
          offsetX: offsetX,
          offsetY: offsetY,
        );
      } on RangeError catch (e) {
        throw OpError(ErrorCode.invalidParams, '$e');
      }
      final key = clipName ?? library.keys.single;
      library[key] = clip;
      final after = encodeLevelJson(
        encodeAnimationClipLibrary(library, form: form),
      );
      return OpOutcome.proposal(
        Proposal([FileChange(path: rel, before: before, after: after)]),
        data: {
          'path': rel,
          'clip': clip['name'],
          'frame': frame,
          if (offsetX != null) 'offsetX': offsetX,
          if (offsetY != null) 'offsetY': offsetY,
        },
      );
    },
  ),
  Operation(
    name: 'animation.clear_events',
    summary: 'Clear frameEvents cues on one frame of a clip JSON file.',
    description:
        'Without `type`, clears every cue on the frame. With `type`, removes '
        'only matching cues. Undoable.',
    kind: OperationKind.write,
    scope: OperationScope.project,
    idempotent: true,
    params: const [
      Param('path', ParamType.string, required: true, positional: true),
      Param('frame', ParamType.integer, required: true),
      Param('clip', ParamType.string),
      Param('type', ParamType.string),
    ],
    handler: (ctx, a) {
      final rel = _requirePath(a);
      final frame = a['frame']! as int;
      final clipName = a['clip'] as String?;
      final type = a['type'] as String?;
      final before = ctx.files.read(ctx.project!.resolve(rel));
      final root = _readRoot(ctx, rel);
      final form = detectAnimationLibraryForm(root);
      final library = _libraryFromRoot(root);
      final clip = _pickClip(library, clipName);
      try {
        clearClipFrameEvents(clip, frameIndex: frame, type: type);
      } on RangeError catch (e) {
        throw OpError(ErrorCode.invalidParams, '$e');
      }
      final key = clipName ?? library.keys.single;
      library[key] = clip;
      final after = encodeLevelJson(
        encodeAnimationClipLibrary(library, form: form),
      );
      return OpOutcome.proposal(
        Proposal([FileChange(path: rel, before: before, after: after)]),
        data: {
          'path': rel,
          'clip': clip['name'],
          'frame': frame,
          if (type != null) 'type': type,
        },
      );
    },
  ),
];
