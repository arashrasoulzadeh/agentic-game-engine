import 'dart:convert';

/// The JSON object inside one text frame of a socket transport, or null if the frame is not a JSON object
/// (a binary frame, broken JSON, an array). Transports count and drop such frames instead of throwing, so
/// a misbehaving peer cannot crash the other side. Shared by the `dart:io` and browser transports so both
/// agree on what a valid message is.
Map<String, dynamic>? decodeNetFrame(Object? data) {
  if (data is! String) return null;
  try {
    final decoded = jsonDecode(data);
    return decoded is Map ? decoded.cast<String, dynamic>() : null;
  } on FormatException {
    return null;
  }
}

/// The text frame that carries [message] (the inverse of [decodeNetFrame]).
String encodeNetFrame(Map<String, dynamic> message) => jsonEncode(message);
