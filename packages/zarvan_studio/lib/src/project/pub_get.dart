import 'dart:async';
import 'dart:io';

/// What `flutter pub get` printed and how it ended.
class PubGetResult {
  const PubGetResult(this.exitCode, this.output);

  /// 0 on success; -1 if the command could not even be started.
  final int exitCode;

  /// Standard output and standard error, in order of arrival.
  final String output;

  bool get succeeded => exitCode == 0;
}

/// Starts a process. Injected so tests need no Flutter SDK (same shape as `ProcessStarter` in play-test).
typedef PubProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      required String workingDirectory,
    });

/// Runs `flutter pub get` in [projectRoot] and collects its output; never throws. The Flutter command may need to
/// be an absolute path when the studio was started from Finder, which does not inherit the shell's PATH.
Future<PubGetResult> runPubGet(
  String projectRoot, {
  String flutter = 'flutter',
  PubProcessStarter? start,
  Duration timeout = const Duration(minutes: 5),
}) async {
  final starter =
      start ??
      (exe, args, {required workingDirectory}) =>
          Process.start(exe, args, workingDirectory: workingDirectory);
  final Process process;
  try {
    process = await starter(flutter, [
      'pub',
      'get',
    ], workingDirectory: projectRoot);
  } on Object catch (e) {
    return PubGetResult(-1, 'Could not run "$flutter pub get": $e');
  }
  final out = StringBuffer();
  final subs = [
    process.stdout.listen((d) => out.write(String.fromCharCodes(d))),
    process.stderr.listen((d) => out.write(String.fromCharCodes(d))),
  ];
  try {
    final code = await process.exitCode.timeout(timeout);
    await Future.wait([
      for (final s in subs) s.asFuture<void>().catchError((_) {}),
    ]);
    return PubGetResult(code, out.toString());
  } on TimeoutException {
    process.kill();
    return PubGetResult(
      -1,
      '$out\nTimed out after ${timeout.inMinutes} minutes.',
    );
  }
}
