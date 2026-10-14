import 'dart:io';
import 'dart:convert';

/// Runs `game_agent studio ...` as a subprocess and captures stdout/stderr/exit code.
Future<StudioResult> runStudioCapture(List<String> args) async {
  // Find the game_agent.dart script. When running `dart test`, Platform.script
  // points to the test file, so we need to navigate to the package's bin/.
  final pkgRoot = Directory.current;
  final binScript = File('${pkgRoot.path}/bin/game_agent.dart');
  if (!await binScript.exists()) {
    throw StateError('Could not find game_agent.dart at ${binScript.path}');
  }
  return _runProcess([binScript.path, ...args]);
}

Future<StudioResult> _runProcess(List<String> args) async {
  print('Running: ${Platform.resolvedExecutable} ${args.join(' ')}');
  final process = await Process.start(
    Platform.resolvedExecutable,
    args,
    runInShell: false,
  );
  
  final stdout = StringBuffer();
  final stderr = StringBuffer();
  
  process.stdout.transform(utf8.decoder).listen(stdout.write);
  process.stderr.transform(utf8.decoder).listen(stderr.write);
  
  final exitCode = await process.exitCode;
  
  if (exitCode != 0 && exitCode != 1) {
    print('STDOUT: ${stdout.toString()}');
    print('STDERR: ${stderr.toString()}');
  }
  
  return StudioResult(exitCode, stdout.toString(), stderr.toString());
}

class StudioResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  StudioResult(this.exitCode, this.stdout, this.stderr);
}