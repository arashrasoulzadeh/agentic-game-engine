/// Web build (no `dart:io`) — memory usage isn't available from Dart on
/// the web platform, so the debug overlay just omits that line.
int? currentMemoryUsageBytes() => null;
