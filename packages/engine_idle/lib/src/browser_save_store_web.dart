import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'session.dart';

/// Keeps the save in the browser's `localStorage` under [key], for a game running on the web where there
/// is no file system.
///
/// `localStorage` holds about 5 MB per origin and can be cleared by the user or refused in private
/// windows; a failed write is swallowed (the game keeps running, the next save tries again) and an
/// unreadable value reads as "no save". Offer `IdleSession.exportCode` as the backup players can keep.
class BrowserSaveStore implements SaveStore {
  BrowserSaveStore([this.key = 'idle_save']);

  final String key;

  JSObject? get _storage {
    try {
      return globalContext.getProperty<JSObject?>('localStorage'.toJS);
    } on Object {
      return null;
    }
  }

  @override
  Map<String, dynamic>? read() {
    try {
      final raw = _storage?.callMethod<JSString?>('getItem'.toJS, key.toJS);
      if (raw == null) return null;
      final json = jsonDecode(raw.toDart);
      return json is Map ? json.cast<String, dynamic>() : null;
    } on Object {
      return null;
    }
  }

  @override
  void write(Map<String, dynamic> save) {
    try {
      _storage?.callMethod<JSAny?>(
        'setItem'.toJS,
        key.toJS,
        jsonEncode(save).toJS,
      );
    } on Object {
      // Quota exceeded or storage disabled: keep playing; the next save tries again.
    }
  }
}
