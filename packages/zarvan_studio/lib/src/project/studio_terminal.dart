import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../prefs/strings.dart';

/// How a studio terminal starts a process. Same injectability shape as
/// pub-get's starter so widget tests never need a real shell.
typedef TerminalProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      required String workingDirectory,
    });

/// One shell command run in a project folder, with a live transcript.
class TerminalSession {
  TerminalSession({
    required this.command,
    required this.workingDirectory,
    TerminalProcessStarter? start,
  }) : _start =
           start ??
           ((exe, args, {required workingDirectory}) => Process.start(
             exe,
             args,
             workingDirectory: workingDirectory,
           ));

  final String command;
  final String workingDirectory;
  final TerminalProcessStarter _start;

  final StringBuffer _output = StringBuffer();
  final _outputController = StreamController<String>.broadcast();
  Process? _process;
  int? exitCode;
  bool _running = false;

  Stream<String> get output => _outputController.stream;
  String get transcript => _output.toString();
  bool get isRunning => _running;

  /// Runs [command] via `/bin/sh -c` in [workingDirectory].
  Future<void> run() async {
    if (_running) return;
    _running = true;
    exitCode = null;
    _append('\$ $command\n');
    try {
      final process = await _start('/bin/sh', [
        '-c',
        command,
      ], workingDirectory: workingDirectory);
      _process = process;
      final subs = <StreamSubscription<List<int>>>[
        process.stdout.listen(_onBytes),
        process.stderr.listen(_onBytes),
      ];
      final code = await process.exitCode;
      for (final s in subs) {
        await s.cancel();
      }
      exitCode = code;
      _append('\n[exit $code]\n');
    } on Object catch (e) {
      exitCode = -1;
      _append('\n[failed to start: $e]\n');
    } finally {
      _running = false;
      _process = null;
      if (!_outputController.isClosed) {
        _outputController.add(transcript);
      }
    }
  }

  void kill() => _process?.kill();

  void dispose() {
    kill();
    _outputController.close();
  }

  void _onBytes(List<int> bytes) {
    _append(utf8.decode(bytes, allowMalformed: true));
  }

  void _append(String chunk) {
    _output.write(chunk);
    if (!_outputController.isClosed) {
      _outputController.add(transcript);
    }
  }
}

/// Bottom drawer: type a command, run it in the project root, stream output.
class StudioTerminalPanel extends StatefulWidget {
  final String projectRoot;
  final VoidCallback onClose;
  final TerminalProcessStarter? processStarter;

  const StudioTerminalPanel({
    super.key,
    required this.projectRoot,
    required this.onClose,
    this.processStarter,
  });

  @override
  State<StudioTerminalPanel> createState() => _StudioTerminalPanelState();
}

class _StudioTerminalPanelState extends State<StudioTerminalPanel> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  TerminalSession? _session;
  StreamSubscription<String>? _sub;
  String _transcript = '';
  bool _running = false;

  @override
  void dispose() {
    _sub?.cancel();
    _session?.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final command = _input.text.trim();
    if (command.isEmpty || _running) return;
    await _sub?.cancel();
    _session?.dispose();
    final session = TerminalSession(
      command: command,
      workingDirectory: widget.projectRoot,
      start: widget.processStarter,
    );
    _session = session;
    setState(() {
      _running = true;
      _transcript = '';
    });
    _sub = session.output.listen((text) {
      if (!mounted) return;
      setState(() => _transcript = text);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    });
    await session.run();
    if (!mounted) return;
    setState(() {
      _running = false;
      _transcript = session.transcript;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      child: SizedBox(
        height: 220,
        child: Column(
          key: const Key('studio-terminal'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              dense: true,
              title: Text(StudioStrings.t('terminal.title')),
              subtitle: Text(
                widget.projectRoot,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_running)
                    IconButton(
                      key: const Key('terminal-kill'),
                      tooltip: StudioStrings.t('terminal.kill'),
                      onPressed: () => _session?.kill(),
                      icon: const Icon(Icons.stop_circle_outlined),
                    ),
                  IconButton(
                    key: const Key('terminal-close'),
                    tooltip: StudioStrings.t('project.close'),
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ColoredBox(
                color: const Color(0xFF1E1E1E),
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.all(8),
                  children: [
                    SelectableText(
                      _transcript.isEmpty
                          ? StudioStrings.t('terminal.empty')
                          : _transcript,
                      key: const Key('terminal-output'),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Color(0xFFE0E0E0),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('terminal-input'),
                      controller: _input,
                      enabled: !_running,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: StudioStrings.t('terminal.hint'),
                        border: const OutlineInputBorder(),
                      ),
                      style: const TextStyle(fontFamily: 'monospace'),
                      onSubmitted: (_) => _run(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    key: const Key('terminal-run'),
                    tooltip: StudioStrings.t('terminal.run'),
                    onPressed: _running ? null : _run,
                    icon: const Icon(Icons.play_arrow),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
