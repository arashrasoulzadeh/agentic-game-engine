import 'dart:convert';

import 'package:zarvan_core/zarvan_core.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

/// Loads level JSON from the app's asset bundle. `zarvan_core` is Flutter-free
/// and cannot touch assets, so the one-liner `Level.loadInto(world, json)`
/// needs this to get its `json` in a scene's `populate`:
///
/// ```dart
/// final named = await LevelAsset.load(world, 'assets/levels/1.json');
/// ```
class LevelAsset {
  const LevelAsset._();

  /// The decoded JSON object at [asset]. Throws [LevelLoadException], naming the
  /// asset, when the text is not a JSON object, instead of a bare cast error.
  static Future<Map<String, dynamic>> read(
    String asset, {
    AssetBundle? bundle,
  }) async {
    final text = await (bundle ?? rootBundle).loadString(asset);
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException catch (e) {
      throw LevelLoadException('$asset is not valid JSON (${e.message})');
    }
    if (json is! Map<String, dynamic>) {
      throw LevelLoadException('$asset must contain a JSON object');
    }
    return json;
  }

  /// Reads [asset] and loads it into [world] (see [Level.loadInto]), returning
  /// the named entities. [strict] lists every bad component instead of
  /// skipping unknown ones.
  static Future<Map<String, EntityId>> load(
    World world,
    String asset, {
    bool strict = false,
    AssetBundle? bundle,
  }) async =>
      Level.loadInto(world, await read(asset, bundle: bundle), strict: strict);
}
