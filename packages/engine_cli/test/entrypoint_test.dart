import 'dart:io';

import '../bin/game_agent.dart' as cli;
import 'package:test/test.dart';

void main() {
  test('entrypoint propagates lint failures and clears a previous exit code', () async {
    final tmp = Directory.systemTemp.createTempSync('cli_entry_');
    final oldExitCode = exitCode;
    try {
      await cli.main(['lint', '${tmp.path}/missing.json']);
      expect(exitCode, 1);
      final level = File('${tmp.path}/level.json')..writeAsStringSync('{"entities": []}');
      await cli.main(['lint', level.path]);
      expect(exitCode, 0);
    } finally {
      exitCode = oldExitCode;
      tmp.deleteSync(recursive: true);
    }
  });
}
