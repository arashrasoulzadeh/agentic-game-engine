import 'dart:convert';

import 'package:zarvan_schema/zarvan_schema.dart' show didYouMean;

import '../content/prefab_registry.dart';
import '../ecs/world.dart';

/// Runs a command; returns the text to print. Throw [ConsoleError] for a
/// user mistake (its message is shown, no stack trace).
typedef ConsoleHandler = String Function(List<String> args);

/// A mistake in a command line (a bad argument, an unknown entity).
class ConsoleError implements Exception {
  ConsoleError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One command a [DevConsole] understands.
class ConsoleCommand {
  const ConsoleCommand(this.name, this.summary, this.handler, {this.usage});

  final String name;
  final String summary;

  /// Argument synopsis for `help <name>`, e.g. `<id> <x> <y>`.
  final String? usage;
  final ConsoleHandler handler;
}

/// A text console for a running game: type a command, get text back. It knows
/// nothing about the screen (see `DevConsoleOverlay` in `zarvan_flutter` for the
/// on-device view), so it is testable and scriptable.
///
/// Built in: world inspection (`entities`, `inspect`, `systems`, `tick`),
/// editing (`spawn`, `kill`, `teleport`, `set`) and time (`timescale`, `pause`,
/// `resume`, `step`, `hitstop`). Games add their own cheats with
/// [addCommand] (`give gold 100`, `skip_level`).
class DevConsole {
  DevConsole({required this.worldOf, this.prefabs}) {
    _installBuiltIns();
  }

  /// The world the commands act on, read per command (it changes with scenes).
  final World? Function() worldOf;

  /// Prefabs `spawn` can place; null disables the command.
  final PrefabRegistry? prefabs;

  final Map<String, ConsoleCommand> _commands = {};

  /// Every line typed, oldest first (consecutive duplicates collapse).
  final List<String> history = [];

  /// Everything shown: typed lines (prefixed `> `) and their output.
  final List<String> log = [];

  int _cursor = -1;

  /// Command names, sorted.
  List<String> get commandNames => _commands.keys.toList()..sort();

  void addCommand(ConsoleCommand command) => _commands[command.name] = command;

  /// Runs [line] and returns its output (also appended to [log]).
  String run(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return '';
    if (history.isEmpty || history.last != trimmed) history.add(trimmed);
    _cursor = -1;
    log.add('> $trimmed');
    String out;
    try {
      final parts = _split(trimmed);
      final command = _commands[parts.first];
      if (command == null) {
        out =
            'unknown command "${parts.first}"'
            '${didYouMean(parts.first, _commands.keys)}; try help';
      } else {
        out = command.handler(parts.sublist(1));
      }
    } on ConsoleError catch (e) {
      out = 'error: ${e.message}';
    } on Object catch (e) {
      out = 'error: $e';
    }
    if (out.isNotEmpty) log.add(out);
    return out;
  }

  /// Completions for the text typed so far: command names for the first word,
  /// prefab names after `spawn`, component names after `set <id>`.
  List<String> complete(String typed) {
    final endsSpace = typed.endsWith(' ');
    final parts = _split(typed);
    if (parts.isEmpty || (parts.length == 1 && !endsSpace)) {
      final prefix = parts.isEmpty ? '' : parts.first;
      return commandNames.where((c) => c.startsWith(prefix)).toList();
    }
    final prefix = endsSpace ? '' : parts.last;
    final index = endsSpace ? parts.length : parts.length - 1;
    List<String> options = const [];
    if (parts.first == 'spawn' && index == 1) {
      options = prefabs?.names ?? const [];
    } else if (parts.first == 'set' && index == 2) {
      options = worldOf()?.components.all.map((r) => r.name).toList() ?? [];
    } else if (parts.first == 'help' && index == 1) {
      options = commandNames;
    }
    return options.where((o) => o.startsWith(prefix)).toList()..sort();
  }

  /// The previous history entry (arrow up), or null at the start.
  String? previous() {
    if (history.isEmpty) return null;
    _cursor = _cursor < 0
        ? history.length - 1
        : (_cursor - 1).clamp(0, history.length - 1);
    return history[_cursor];
  }

  /// The next history entry (arrow down), or '' when past the newest.
  String next() {
    if (_cursor < 0) return '';
    if (_cursor >= history.length - 1) {
      _cursor = -1;
      return '';
    }
    return history[++_cursor];
  }

  // --- parsing ---

  /// Splits on spaces, keeping `"quoted text"` together.
  static List<String> _split(String line) {
    final out = <String>[];
    final buf = StringBuffer();
    var quoted = false;
    var has = false;
    for (final ch in line.split('')) {
      if (ch == '"') {
        quoted = !quoted;
        has = true;
      } else if (ch == ' ' && !quoted) {
        if (has) out.add(buf.toString());
        buf.clear();
        has = false;
      } else {
        buf.write(ch);
        has = true;
      }
    }
    if (has) out.add(buf.toString());
    return out;
  }

  World _world() {
    final w = worldOf();
    if (w == null) throw ConsoleError('no world is running');
    return w;
  }

  double _num(String s, String what) =>
      double.tryParse(s) ??
      (throw ConsoleError('$what must be a number, got "$s"'));

  int _id(String s) =>
      int.tryParse(s) ??
      (throw ConsoleError('an entity id is a whole number, got "$s"'));

  void _need(List<String> a, int n, String usage) {
    if (a.length < n) throw ConsoleError('usage: $usage');
  }

  // --- built-in commands ---

  void _installBuiltIns() {
    void add(String name, String summary, ConsoleHandler h, {String? usage}) =>
        addCommand(ConsoleCommand(name, summary, h, usage: usage));

    add('help', 'List commands, or describe one', (a) {
      if (a.isNotEmpty) {
        final c = _commands[a.first];
        if (c == null) {
          throw ConsoleError(
            'no command "${a.first}"${didYouMean(a.first, _commands.keys)}',
          );
        }
        return '${c.name}${c.usage == null ? '' : ' ${c.usage}'}: ${c.summary}';
      }
      return commandNames
          .map((n) => '  $n  ${_commands[n]!.summary}')
          .join('\n');
    }, usage: '[command]');

    add('clear', 'Clear the console log', (_) {
      log.clear();
      return '';
    });

    add('echo', 'Print the arguments', (a) => a.join(' '), usage: '<text>');

    add('tick', 'The world tick and time scale', (_) {
      final w = _world();
      return 'tick ${w.tick}, timeScale ${w.timeScale}'
          '${w.isHitStopped ? ' (hit-stop)' : ''}';
    });

    add(
      'timescale',
      'Show or set the time scale (0 pauses, 0.25 slow motion)',
      (a) {
        final w = _world();
        if (a.isEmpty) return 'timeScale ${w.timeScale}';
        final v = _num(a.first, 'timescale');
        if (v < 0) throw ConsoleError('timescale must be 0 or more');
        w.timeScale = v;
        return 'timeScale ${w.timeScale}';
      },
      usage: '[scale]',
    );

    add('pause', 'Freeze simulated time (timescale 0)', (_) {
      _world().timeScale = 0;
      return 'paused';
    });

    add('resume', 'Resume at normal speed (timescale 1)', (_) {
      _world().timeScale = 1;
      return 'timeScale 1.0';
    });

    add(
      'step',
      'Advance the world by N fixed steps (default 1)',
      (a) {
        final w = _world();
        final n = a.isEmpty
            ? 1
            : int.tryParse(a.first) ??
                  (throw ConsoleError('step count must be a whole number'));
        final dt = a.length > 1 ? _num(a[1], 'dt') : 1 / 60;
        for (var i = 0; i < n; i++) {
          w.step(dt);
        }
        return 'stepped $n x ${dt.toStringAsFixed(4)}s, tick ${w.tick}';
      },
      usage: '[count] [dt]',
    );

    add('hitstop', 'Freeze the world for N real seconds', (a) {
      _need(a, 1, 'hitstop <seconds>');
      _world().hitStop(_num(a.first, 'seconds'));
      return 'hit-stop ${a.first}s';
    }, usage: '<seconds>');

    add(
      'entities',
      'Count entities, or list those with a component',
      (a) {
        final w = _world();
        if (a.isEmpty) {
          final counts = w.componentCounts();
          final lines = [
            'entities: ${w.entities.count}',
            for (final e
                in counts.entries.toList()
                  ..sort((x, y) => x.key.compareTo(y.key)))
              '  ${e.key}: ${e.value}',
          ];
          return lines.join('\n');
        }
        final reg = w.components.all.where((r) => r.name == a.first);
        if (reg.isEmpty) {
          throw ConsoleError(
            'no component "${a.first}"${didYouMean(a.first, w.components.all.map((r) => r.name))}',
          );
        }
        final ids = <int>[];
        final store = reg.first.store;
        for (var i = 0; i < store.length; i++) {
          ids.add(store.entityAt(i));
        }
        ids.sort();
        return ids.isEmpty ? '(none)' : ids.join(' ');
      },
      usage: '[component]',
    );

    add('inspect', 'Show every component of an entity as JSON', (a) {
      _need(a, 1, 'inspect <id>');
      final w = _world();
      final id = _id(a.first);
      if (!w.entities.isAlive(id))
        throw ConsoleError('entity $id does not exist');
      return const JsonEncoder.withIndent(
        '  ',
      ).convert(w.components.serializeEntity(id));
    }, usage: '<id>');

    add('systems', 'List the systems in run order', (_) {
      final w = _world();
      return w.systemOrder
          .map((n) => w.isSystemEnabled(n) ? n : '$n (off)')
          .join(' -> ');
    });

    add('spawn', 'Spawn a prefab at a position', (a) {
      final p = prefabs;
      if (p == null) throw ConsoleError('no prefabs are registered');
      _need(a, 1, 'spawn <prefab> [x] [y]');
      if (!p.has(a.first)) {
        throw ConsoleError(
          'no prefab "${a.first}"${didYouMean(a.first, p.names)}; known: ${p.names.join(', ')}',
        );
      }
      final w = _world();
      final x = a.length > 1 ? _num(a[1], 'x') : w.width / 2;
      final y = a.length > 2 ? _num(a[2], 'y') : w.height / 2;
      final inst = p.spawn(w, a.first, x, y);
      return 'spawned ${a.first} as ${inst.ids.join(' ')}';
    }, usage: '<prefab> [x] [y]');

    add('kill', 'Destroy an entity', (a) {
      _need(a, 1, 'kill <id>');
      final w = _world();
      final id = _id(a.first);
      if (!w.entities.isAlive(id))
        throw ConsoleError('entity $id does not exist');
      w.destroy(id);
      return 'destroyed $id';
    }, usage: '<id>');

    add('teleport', 'Move an entity', (a) {
      _need(a, 3, 'teleport <id> <x> <y>');
      final w = _world();
      final id = _id(a.first);
      if (!w.entities.isAlive(id))
        throw ConsoleError('entity $id does not exist');
      final json = w.components.serializeEntity(id);
      if (!json.containsKey('position'))
        throw ConsoleError('entity $id has no position');
      w.components.applyToEntity(id, {
        'position': {
          ...(json['position'] as Map).cast<String, dynamic>(),
          'x': _num(a[1], 'x'),
          'y': _num(a[2], 'y'),
        },
      });
      return 'moved $id to ${a[1]} ${a[2]}';
    }, usage: '<id> <x> <y>');

    add(
      'set',
      'Set one field of an entity\'s component',
      (a) {
        _need(a, 4, 'set <id> <component> <field> <value>');
        final w = _world();
        final id = _id(a.first);
        if (!w.entities.isAlive(id))
          throw ConsoleError('entity $id does not exist');
        final names = w.components.all.map((r) => r.name);
        if (!names.contains(a[1])) {
          throw ConsoleError(
            'no component "${a[1]}"${didYouMean(a[1], names)}',
          );
        }
        final json = w.components.serializeEntity(id);
        final current = json[a[1]];
        if (current is! Map) throw ConsoleError('entity $id has no ${a[1]}');
        final data = current.cast<String, dynamic>();
        if (!data.containsKey(a[2])) {
          throw ConsoleError(
            '${a[1]} has no field "${a[2]}"${didYouMean(a[2], data.keys)}; fields: ${data.keys.join(', ')}',
          );
        }
        data[a[2]] = _value(a[3]);
        w.components.applyToEntity(id, {a[1]: data});
        return '$id.${a[1]}.${a[2]} = ${a[3]}';
      },
      usage: '<id> <component> <field> <value>',
    );
  }

  /// A typed value: number, bool, null, or the text as is.
  static Object? _value(String s) {
    if (s == 'true') return true;
    if (s == 'false') return false;
    if (s == 'null') return null;
    return num.tryParse(s) ?? s;
  }
}
