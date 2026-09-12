import 'dart:io';

/// Runs [executable] with [args] in [workingDirectory], streaming its
/// stdout/stderr straight to this process's so the user sees exactly what
/// `flutter`/`git` are doing — no silent CLI wrapper magic.
Future<void> runStreamed(
  String executable,
  List<String> args, {
  String? workingDirectory,
}) async {
  final process = await Process.start(
    executable,
    args,
    workingDirectory: workingDirectory,
    runInShell: true,
  );
  stdout.addStream(process.stdout);
  stderr.addStream(process.stderr);
  final code = await process.exitCode;
  if (code != 0) {
    throw ProcessException(
      executable,
      args,
      'Command failed with exit code $code',
      code,
    );
  }
}
