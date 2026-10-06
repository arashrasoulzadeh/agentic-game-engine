import 'dart:convert';

/// Encodes level JSON in the one format every tool writes: two-space indent, one
/// key per line, keys in the order they were written. Using a single encoder is
/// what makes a save from the studio and a CLI export produce identical bytes for
/// the same data, so a diff shows only real changes.
String encodeLevelJson(Object? json) =>
    const JsonEncoder.withIndent('  ').convert(json);
