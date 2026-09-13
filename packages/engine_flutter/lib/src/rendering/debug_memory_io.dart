import 'dart:io';

/// Android/iOS/desktop build — resident set size, the closest
/// single-number proxy for "how much memory is this process using"
/// available without pulling in VM-service/observatory machinery.
int? currentMemoryUsageBytes() => ProcessInfo.currentRss;
