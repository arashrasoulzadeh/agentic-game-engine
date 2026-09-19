import 'dart:io';

/// Process boundary used by commands so tests can verify their invocations
/// without creating a Flutter project or fetching remote dependencies.
typedef CommandProcessRunner = Future<void> Function(
  String executable,
  List<String> args, {
  String? workingDirectory,
});

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
  final output = stdout.addStream(process.stdout);
  final errors = stderr.addStream(process.stderr);
  final code = await process.exitCode;
  await Future.wait([output, errors]);
  if (code != 0) {
    throw ProcessException(
      executable,
      args,
      'Command failed with exit code $code',
      code,
    );
  }
}
