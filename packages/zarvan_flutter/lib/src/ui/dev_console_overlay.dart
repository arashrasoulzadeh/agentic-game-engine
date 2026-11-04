import 'package:flutter/material.dart';
import 'package:zarvan_core/zarvan_core.dart';

/// A drop-down developer console over a [DevConsole].
///
/// Kept thin on purpose: parsing, history and completion live in the
/// Flutter-free [DevConsole] so they stay testable and usable from the CLI;
/// this widget only shows the log and forwards typed lines.
class DevConsoleOverlay extends StatefulWidget {
  /// Creates an overlay driving [console].
  const DevConsoleOverlay({super.key, required this.console});

  /// The console whose log is shown and whose commands are run.
  final DevConsole console;

  @override
  State<DevConsoleOverlay> createState() => _DevConsoleOverlayState();
}

class _DevConsoleOverlayState extends State<DevConsoleOverlay> {
  final _controller = TextEditingController();

  void _submit(String line) {
    setState(() => widget.console.run(line));
    _controller.clear();
  }

  void _complete() {
    final options = widget.console.complete(_controller.text);
    if (options.isEmpty) return;
    final words = _controller.text.split(' ');
    words[words.length - 1] = options.first;
    final text = words.join(' ');
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final log = widget.console.log;
    return Material(
      color: const Color(0xDD000000),
      child: SizedBox(
        height: 220,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                reverse: true,
                children: [
                  for (final line in log.reversed)
                    Text(
                      line,
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    onSubmitted: _submit,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(prefixText: '> '),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_tab, color: Colors.white),
                  tooltip: 'Complete',
                  onPressed: _complete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
