import 'dart:io';

/// Runs `cwebp` with [args]; returns its exit code. Injectable so tests need
/// no encoder installed.
typedef WebpEncoder = int Function(List<String> args);

int _runCwebp(List<String> args) {
  try {
    return Process.runSync('cwebp', args).exitCode;
  } on ProcessException {
    return -1;
  }
}

/// Flutter asset transformer body: writes [output] as the smallest valid form
/// of the image at [input].
///
/// A `.png` becomes lossless WebP when `cwebp` is available and the result is
/// smaller; anything else (other formats, a missing encoder, a larger result)
/// is copied unchanged, so a build never fails or grows because of this step.
/// The asset keeps its name: Flutter's image codecs detect the format from the
/// bytes, so a WebP stored under a `.png` path loads exactly like the PNG.
/// Returns true when [output] holds WebP.
bool transformImage(
  String input,
  String output, {
  WebpEncoder encoder = _runCwebp,
}) {
  if (input.toLowerCase().endsWith('.png')) {
    final code = encoder([
      '-lossless',
      '-z',
      '6',
      '-quiet',
      input,
      '-o',
      output,
    ]);
    if (code == 0 &&
        File(output).existsSync() &&
        File(output).lengthSync() < File(input).lengthSync()) {
      return true;
    }
  }
  File(input).copySync(output);
  return false;
}
