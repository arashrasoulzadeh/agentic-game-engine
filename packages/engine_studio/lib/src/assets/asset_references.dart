import 'package:engine_core/engine_core.dart';

/// Finds level references to sprites and atlases that don't exist: a `sprite` whose
/// `atlasId` isn't a declared atlas or whose `region` isn't in it, and a `tileMap`
/// whose `atlasId` or per-tile regions are missing.
///
/// This is separate from `LevelValidator`, which is schema-only and knows nothing of
/// the project's art. The issues use the same `LevelIssue` type so the problems panel
/// shows them like any other and a click selects the offending entity ("jump to
/// reference").
///
/// [atlasRegions] maps each declared atlas id to its sprite names; null means the
/// project declares none, in which case there is nothing to check against and the
/// result is empty rather than a wall of false errors.
List<LevelIssue> checkAssetReferences(
  LevelDocument document,
  Map<String, Set<String>>? atlasRegions,
) {
  if (atlasRegions == null) return const [];
  final issues = <LevelIssue>[];

  LevelIssue error(
    int index,
    LevelEntity e,
    String component,
    String message,
  ) => LevelIssue(
    entityIndex: index,
    entityName: e.name,
    component: component,
    message: message,
    severity: IssueSeverity.error,
  );

  void check(
    int index,
    LevelEntity e,
    String component,
    String? atlasId,
    Iterable<String> regions,
  ) {
    if (atlasId == null || atlasId.isEmpty) return;
    final known = atlasRegions[atlasId];
    if (known == null) {
      issues.add(
        error(
          index,
          e,
          component,
          'atlas "$atlasId" is not declared in assets/studio_atlases.json',
        ),
      );
      return;
    }
    for (final region in regions) {
      if (region.isEmpty) continue;
      if (!known.contains(region)) {
        issues.add(
          error(
            index,
            e,
            component,
            'atlas "$atlasId" has no sprite named "$region"',
          ),
        );
      }
    }
  }

  for (var i = 0; i < document.entities.length; i++) {
    final e = document.entities[i];
    final sprite = e.components['sprite'];
    if (sprite != null) {
      check(i, e, 'sprite', sprite['atlasId'] as String?, [
        if (sprite['region'] is String) sprite['region'] as String,
      ]);
    }
    final map = e.components['tileMap'];
    if (map != null) {
      final regions = map['regionByTileId'];
      check(i, e, 'tileMap', map['atlasId'] as String?, [
        if (regions is Map)
          for (final v in regions.values)
            if (v is String) v,
      ]);
    }
  }
  return issues;
}
