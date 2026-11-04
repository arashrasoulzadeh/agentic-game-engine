import 'package:zarvan_core/zarvan_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../session.dart';

/// Move a game between devices by text: shows the current save code with a copy button, and a field to
/// paste another device's code and load it.
///
/// A damaged, foreign or too-new code is explained in the player's words and leaves the current game
/// untouched (see [IdleSession.importCode]).
class SaveCodePanel extends StatefulWidget {
  const SaveCodePanel({super.key, required this.session});

  final IdleSession session;

  @override
  State<SaveCodePanel> createState() => _SaveCodePanelState();
}

class _SaveCodePanelState extends State<SaveCodePanel> {
  final _input = TextEditingController();
  String? _code;
  String? _message;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _export() => setState(() {
    _code = widget.session.exportCode();
    _message = null;
  });

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _code!));
    if (mounted) setState(() => _message = 'Copied.');
  }

  void _import() {
    try {
      widget.session.importCode(_input.text);
      setState(() => _message = 'Game loaded.');
    } on SaveFormatException catch (e) {
      setState(() => _message = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton(
          key: const Key('save-export'),
          onPressed: _export,
          child: const Text('Show my save code'),
        ),
        if (_code != null) ...[
          SelectableText(_code!, key: const Key('save-code')),
          TextButton(
            key: const Key('save-copy'),
            onPressed: _copy,
            child: const Text('Copy'),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          key: const Key('save-input'),
          controller: _input,
          decoration: const InputDecoration(labelText: 'Paste a save code'),
        ),
        FilledButton(
          key: const Key('save-import'),
          onPressed: _import,
          child: const Text('Load this code'),
        ),
        if (_message != null) Text(_message!, key: const Key('save-message')),
      ],
    );
  }
}
