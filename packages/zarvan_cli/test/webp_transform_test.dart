import 'dart:io';

import 'package:zarvan_cli/src/webp_transform.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('webp'));
  tearDown(() => dir.deleteSync(recursive: true));

  String write(String name, List<int> bytes) {
    final f = File('${dir.path}/$name')..writeAsBytesSync(bytes);
    return f.path;
  }

  test('a png smaller as webp is replaced by the encoder output', () {
    final input = write('a.png', List.filled(100, 1));
    final output = '${dir.path}/out.png';
    final converted = transformImage(
      input,
      output,
      encoder: (args) {
        expect(args, containsAll(['-lossless', input]));
        File(args.last).writeAsBytesSync(List.filled(40, 9));
        return 0;
      },
    );
    expect(converted, isTrue);
    expect(File(output).lengthSync(), 40);
  });

  test('a larger webp result keeps the original bytes', () {
    final input = write('a.png', List.filled(10, 1));
    final output = '${dir.path}/out.png';
    final converted = transformImage(
      input,
      output,
      encoder: (args) {
        File(args.last).writeAsBytesSync(List.filled(50, 9));
        return 0;
      },
    );
    expect(converted, isFalse);
    expect(File(output).readAsBytesSync(), List.filled(10, 1));
  });

  test('a missing or failing encoder copies the input', () {
    final input = write('a.png', [1, 2, 3]);
    final output = '${dir.path}/out.png';
    expect(transformImage(input, output, encoder: (_) => -1), isFalse);
    expect(File(output).readAsBytesSync(), [1, 2, 3]);
  });

  test('non-png files (json manifests, jpgs) are copied untouched', () {
    final input = write('a.json', [123, 125]);
    final output = '${dir.path}/o.json';
    final converted = transformImage(
      input,
      output,
      encoder: (_) => fail('must not encode a json file'),
    );
    expect(converted, isFalse);
    expect(File(output).readAsBytesSync(), [123, 125]);
  });
}
