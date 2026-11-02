import 'dart:io';

/// How git sees a file, reduced to what a file tree shows.
enum GitChange {
  modified('M'),
  added('A'),
  deleted('D'),
  renamed('R'),
  untracked('?'),
  conflicted('!');

  const GitChange(this.badge);

  /// The one-letter mark shown beside the file.
  final String badge;
}

/// Parses `git status --porcelain` (version 1) into project-relative path -> change. Renames map the new
/// path. Paths git quotes (spaces, non-ASCII) are unquoted; anything unrecognised is skipped.
Map<String, GitChange> parseGitStatus(String porcelain) {
  final out = <String, GitChange>{};
  for (final line in porcelain.split('\n')) {
    if (line.length < 4) continue;
    final x = line[0], y = line[1];
    var path = line.substring(3);
    final arrow = path.indexOf(' -> ');
    if (arrow >= 0) path = path.substring(arrow + 4);
    if (path.startsWith('"') && path.endsWith('"') && path.length >= 2) {
      path = path.substring(1, path.length - 1).replaceAll(r'\"', '"');
    }
    if (path.endsWith('/')) path = path.substring(0, path.length - 1);
    final GitChange? change;
    if (x == 'U' ||
        y == 'U' ||
        (x == 'A' && y == 'A') ||
        (x == 'D' && y == 'D')) {
      change = GitChange.conflicted;
    } else if (x == '?' && y == '?') {
      change = GitChange.untracked;
    } else if (x == 'R' || y == 'R') {
      change = GitChange.renamed;
    } else if (x == 'A') {
      change = GitChange.added;
    } else if (x == 'D' || y == 'D') {
      change = GitChange.deleted;
    } else if (x == 'M' || y == 'M') {
      change = GitChange.modified;
    } else {
      change = null;
    }
    if (change != null && path.isNotEmpty) out[path] = change;
  }
  return out;
}

/// Runs git and returns its standard output, or null if it cannot (git missing, not a repository).
typedef GitRunner =
    Future<String?> Function(List<String> arguments, String workingDirectory);

/// Runs the real `git` in [workingDirectory]; null when git is missing or the
/// command's exit code is not in [okCodes] (`git diff` uses 1 when there is a
/// diff, so callers that want the patch pass `{0, 1}`).
Future<String?> runGit(
  List<String> arguments,
  String workingDirectory, {
  Set<int> okCodes = const {0},
}) async {
  try {
    final r = await Process.run(
      'git',
      arguments,
      workingDirectory: workingDirectory,
    );
    return okCodes.contains(r.exitCode) ? r.stdout as String : null;
  } on Object {
    return null;
  }
}

/// Unified diff for one project-relative [path], or empty when git has nothing
/// to show. Untracked files return their contents prefixed with `untracked`.
Future<String> readGitDiff(
  String projectRoot,
  String path, {
  GitRunner? run,
}) async {
  final runner =
      run ??
      (args, dir) => runGit(args, dir, okCodes: const {0, 1});
  final unstaged = await runner(['diff', '--', path], projectRoot);
  if (unstaged != null && unstaged.trim().isNotEmpty) return unstaged;
  final staged = await runner(['diff', '--cached', '--', path], projectRoot);
  if (staged != null && staged.trim().isNotEmpty) return staged;
  try {
    final file = File('$projectRoot/$path');
    if (file.existsSync()) {
      return 'untracked\n${file.readAsStringSync()}';
    }
  } on Object {
    // Binary or unreadable: still report that git had no textual diff.
  }
  return '';
}

/// Outcome of `git add -A` + `git commit -m` in [projectRoot].
class GitCommitResult {
  final bool ok;
  final String output;

  const GitCommitResult(this.ok, this.output);
}

/// Stages every change in [projectRoot] and commits with [message].
///
/// Empty messages are refused without touching git. A missing git binary or a
/// failed `add`/`commit` (nothing to commit, hook, …) returns [ok] false.
Future<GitCommitResult> commitGitAll(
  String projectRoot,
  String message, {
  GitRunner? run,
}) async {
  final msg = message.trim();
  if (msg.isEmpty) {
    return const GitCommitResult(false, 'Commit message is empty.');
  }
  final runner = run ?? runGit;
  final add = await runner(['add', '-A'], projectRoot);
  if (add == null) {
    return const GitCommitResult(false, 'git add failed.');
  }
  final committed = await runner(['commit', '-m', msg], projectRoot);
  if (committed == null) {
    return const GitCommitResult(false, 'git commit failed.');
  }
  return GitCommitResult(true, committed);
}

/// The changed files in [projectRoot]'s repository, relative to [projectRoot]; empty when it is not a git
/// project. Paths outside the project folder (when it is a subfolder of a larger repository) are dropped.
Future<Map<String, GitChange>> readGitStatus(
  String projectRoot, {
  GitRunner? run,
}) async {
  final runner = run ?? runGit;
  final top = (await runner([
    'rev-parse',
    '--show-toplevel',
  ], projectRoot))?.trim();
  final text = await runner(['status', '--porcelain'], projectRoot);
  if (text == null) return const {};
  final raw = parseGitStatus(text);
  if (top == null || top.isEmpty) return raw;
  // git reports paths relative to the repository root; rebase them onto the project folder.
  var prefix = '';
  final root = Directory(projectRoot).absolute.path;
  if (root.startsWith(top) && root.length > top.length) {
    prefix = '${root.substring(top.length + 1)}/';
  }
  final out = <String, GitChange>{};
  for (final e in raw.entries) {
    if (prefix.isEmpty) {
      out[e.key] = e.value;
    } else if (e.key.startsWith(prefix)) {
      out[e.key.substring(prefix.length)] = e.value;
    }
  }
  return out;
}

/// Whether anything under the folder [relativeDir] is in [changes] (a folder shows a mark when a file inside
/// changed, so a collapsed tree still shows where the work is).
bool folderHasChanges(Map<String, GitChange> changes, String relativeDir) =>
    changes.keys.any((p) => p.startsWith('$relativeDir/'));
