import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

/// A save that could not be read: the message says why, for a player-facing dialog.
class SaveFormatException implements Exception {
  final String message;
  const SaveFormatException(this.message);

  @override
  String toString() => 'SaveFormatException: $message';
}

/// Brings old saves up to the current version so a game update never wipes a player.
///
/// Every save carries a `saveVersion` (a save with none counts as version 1). Register one migration per
/// version step; [migrate] applies them in order until the save reaches [currentVersion]. A save from a
/// **newer** game than this one is refused rather than guessed at.
class SaveMigrator {
  /// The version this build writes and understands.
  final int currentVersion;

  final Map<int, Map<String, dynamic> Function(Map<String, dynamic>)> _steps;

  /// [migrations] maps a version to the function that upgrades a save **from that version to the next**.
  SaveMigrator({
    required this.currentVersion,
    Map<int, Map<String, dynamic> Function(Map<String, dynamic>)> migrations =
        const {},
  }) : _steps = Map.of(migrations);

  /// The upgraded copy of [save] (the input is not modified), stamped with [currentVersion].
  Map<String, dynamic> migrate(Map<String, dynamic> save) {
    var data = (jsonDecode(jsonEncode(save)) as Map).cast<String, dynamic>();
    var version = (data['saveVersion'] as num?)?.toInt() ?? 1;
    if (version > currentVersion) {
      throw SaveFormatException(
        'This save is from a newer version of the game (save v$version, this game reads up to v$currentVersion). Update the game to open it.',
      );
    }
    while (version < currentVersion) {
      final step = _steps[version];
      if (step == null) {
        throw SaveFormatException(
          'No way to upgrade a version $version save (missing migration).',
        );
      }
      data = step(data);
      version++;
      data['saveVersion'] = version;
    }
    data['saveVersion'] = currentVersion;
    return data;
  }

  /// [data] stamped with [currentVersion], ready to store.
  Map<String, dynamic> stamp(Map<String, dynamic> data) => {
    ...data,
    'saveVersion': currentVersion,
  };
}

/// Turns a save into a short text the player can copy to another device, and back.
///
/// The text is `GSAVE1.<payload>.<check>`: the payload is the JSON in URL-safe base64 and the check is the
/// first 8 hex digits of its SHA-256, so a truncated or edited paste is rejected with a clear message
/// instead of loading garbage. It is **not** encrypted or tamper-proof: anyone can edit and re-sign a save.
class SaveCodec {
  const SaveCodec._();

  static const _prefix = 'GSAVE1';

  /// The shareable text for [save].
  static String export(Map<String, dynamic> save) {
    final payload = base64Url.encode(utf8.encode(jsonEncode(save)));
    return '$_prefix.$payload.${_check(payload)}';
  }

  /// The save inside [text], or a [SaveFormatException] explaining what is wrong. Surrounding whitespace
  /// (a paste often adds it) is ignored.
  static Map<String, dynamic> import(String text) {
    final parts = text.trim().split('.');
    if (parts.first != _prefix) {
      throw const SaveFormatException(
        'This is not a save code from this game.',
      );
    }
    if (parts.length != 3) {
      throw const SaveFormatException(
        'The save code is damaged or incomplete. Copy it again.',
      );
    }
    final payload = parts[1];
    if (_check(payload) != parts[2]) {
      throw const SaveFormatException(
        'The save code is damaged or incomplete (checksum mismatch). Copy it again.',
      );
    }
    try {
      final json = jsonDecode(utf8.decode(base64Url.decode(payload)));
      if (json is! Map) throw const FormatException('not an object');
      return json.cast<String, dynamic>();
    } on FormatException {
      throw const SaveFormatException('The save code could not be read.');
    }
  }

  static String _check(String payload) =>
      crypto.sha256.convert(utf8.encode(payload)).toString().substring(0, 8);
}
