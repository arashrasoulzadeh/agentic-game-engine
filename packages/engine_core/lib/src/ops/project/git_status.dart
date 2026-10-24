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

/// Runs the real `git` in [workingDirectory]; null when git is missing or the command fails.
Future<String?> runGit(List<String> arguments, String workingDirectory) async {
  try {
    final r = await Process.run(
      'git',
      arguments,
      workingDirectory: workingDirectory,
    );
    return r.exitCode == 0 ? r.stdout as String : null;
  } on Object {
    return null;
  }
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
