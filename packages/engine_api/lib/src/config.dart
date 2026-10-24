import 'dart:io';

import 'package:yaml/yaml.dart';

/// Thrown for a config file that cannot be used; the message says which key.
class ConfigException implements Exception {
  ConfigException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Turns the contents of `engine_api.yaml` into the command-line flags that mean the same thing.
///
/// Going through flags keeps one source of truth for defaults and validation, and lets real flags override the file
/// (they are appended after these). Unknown keys are errors so a typo cannot silently leave a restriction off.
List<String> configToArgs(String yamlText) {
  final Object? doc;
  try {
    doc = loadYaml(yamlText);
  } on YamlException catch (e) {
    throw ConfigException('engine_api.yaml is not valid YAML: ${e.message}');
  }
  if (doc == null) return const [];
  if (doc is! Map) throw ConfigException('engine_api.yaml must be a mapping.');
  final out = <String>[];
  final known = {
    'project',
    'readOnly',
    'bind',
    'port',
    'allowedOrigins',
    'operations',
    'limits',
    'log',
  };
  for (final k in doc.keys) {
    if (!known.contains(k))
      throw ConfigException('Unknown key "$k" in engine_api.yaml.');
  }
  void scalar(String flag, Object? v) {
    if (v != null)
      out
        ..add('--$flag')
        ..add('$v');
  }

  scalar('project', doc['project']);
  if (doc['readOnly'] == true) out.add('--read-only');
  scalar('bind', doc['bind']);
  scalar('port', doc['port']);
  for (final o in (doc['allowedOrigins'] as List? ?? const [])) {
    out
      ..add('--allow-origin')
      ..add('$o');
  }
  final ops = doc['operations'];
  if (ops != null) {
    if (ops is! Map) throw ConfigException('"operations" must be a mapping.');
    for (final k in ops.keys) {
      if (k != 'allow' && k != 'deny')
        throw ConfigException('Unknown key "operations.$k".');
    }
    for (final g in (ops['allow'] as List? ?? const [])) {
      out
        ..add('--allow')
        ..add('$g');
    }
    for (final g in (ops['deny'] as List? ?? const [])) {
      out
        ..add('--deny')
        ..add('$g');
    }
  }
  final limits = doc['limits'];
  if (limits != null) {
    if (limits is! Map) throw ConfigException('"limits" must be a mapping.');
    for (final k in limits.keys) {
      if (!{'maxResultBytes', 'requestsPerMinute'}.contains(k)) {
        throw ConfigException('Unknown key "limits.$k".');
      }
    }
    scalar('max-result-bytes', limits['maxResultBytes']);
    scalar('requests-per-minute', limits['requestsPerMinute']);
  }
  final log = doc['log'];
  if (log != null) {
    if (log is! Map) throw ConfigException('"log" must be a mapping.');
    scalar('log', log['file']);
  }
  return out;
}

/// The config flags for [projectRoot] (or the explicit [path]); empty when there is no file.
List<String> loadConfigArgs({String? path, String? projectRoot}) {
  final file = File(path ?? '${projectRoot ?? '.'}/engine_api.yaml');
  if (!file.existsSync()) {
    if (path != null)
      throw ConfigException('Config file $path does not exist.');
    return const [];
  }
  return configToArgs(file.readAsStringSync());
}
