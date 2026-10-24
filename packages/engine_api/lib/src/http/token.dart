import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// A fresh bearer token: 32 random bytes, base64url without padding (43 characters).
String generateToken() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// Compares in time independent of where the strings differ, so a wrong token leaks nothing about a right one.
bool tokensMatch(String a, String b) {
  final x = utf8.encode(a), y = utf8.encode(b);
  var diff = x.length ^ y.length;
  for (var i = 0; i < x.length && i < y.length; i++) {
    diff |= x[i] ^ y[i];
  }
  return diff == 0;
}

/// The token to use: [explicit] when given, else the one stored in `<project>/.studio/api-token`, else a new one
/// (stored there with owner-only permissions when there is a project). [rotate] replaces a stored token.
String resolveToken({
  String? explicit,
  String? projectRoot,
  bool rotate = false,
}) {
  if (explicit != null && explicit.isNotEmpty) return explicit;
  if (projectRoot == null) return generateToken();
  final file = File('$projectRoot/.studio/api-token');
  if (!rotate && file.existsSync()) {
    final stored = file.readAsStringSync().trim();
    if (stored.isNotEmpty) return stored;
  }
  final token = generateToken();
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(token);
  if (!Platform.isWindows) Process.runSync('chmod', ['600', file.path]);
  return token;
}
