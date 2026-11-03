import 'dart:convert';

import 'session.dart';

/// [CloudSaveStore] over HTTP(S) with injected transport so the same class
/// works on IO, web, and in tests.
///
/// Wire [getBody] / [putBody] to `HttpClient`, `package:http`, Game Center /
/// Play Games cloud blobs, or your own backend. See the idle-games guide's
/// cloud-save walkthrough.
class HttpCloudSaveStore implements CloudSaveStore {
  /// Creates a store at [uri]. [getBody] returns null when the remote is empty
  /// (404); [putBody] replaces the remote document with JSON text.
  HttpCloudSaveStore({
    required this.uri,
    required this.getBody,
    required this.putBody,
  });

  /// Remote save document location.
  final Uri uri;

  /// `GET` body, or null if missing.
  final Future<String?> Function(Uri uri) getBody;

  /// `PUT`/`POST` the JSON [body].
  final Future<void> Function(Uri uri, String body) putBody;

  @override
  Future<Map<String, dynamic>?> fetch() async {
    final body = await getBody(uri);
    if (body == null || body.isEmpty) return null;
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const FormatException('Cloud save is not a JSON object.');
    }
    return decoded.cast<String, dynamic>();
  }

  @override
  Future<void> push(Map<String, dynamic> save) =>
      putBody(uri, jsonEncode(save));
}
