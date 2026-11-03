import 'dart:io';

import 'package:image/image.dart' as img;
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
      verify: (_, _) => true,
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
      verify: (_, _) => true,
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

  test('a result that fails pixel verification keeps the original', () {
    final input = write('a.png', List.filled(100, 1));
    final output = '${dir.path}/out.png';
    final converted = transformImage(
      input,
      output,
      verify: (_, _) => false,
      encoder: (args) {
        File(args.last).writeAsBytesSync(List.filled(40, 9));
        return 0;
      },
    );
    expect(converted, isFalse);
    expect(File(output).readAsBytesSync(), List.filled(100, 1));
  });

  group('samePixels', () {
    final base = img.Image(width: 2, height: 1, numChannels: 4)
      ..setPixelRgba(0, 0, 10, 20, 30, 255)
      ..setPixelRgba(1, 0, 99, 99, 99, 0);

    final hasCwebp = Process.runSync('which', ['cwebp']).exitCode == 0;

    test(
      'a real cwebp round-trip verifies, hidden colour of transparent pixels aside',
      () {
        final png = '${dir.path}/r.png';
        File(png).writeAsBytesSync(img.encodePng(base));
        final out = '${dir.path}/r.webp';
        expect(transformImage(png, out), isTrue);
        expect(
          samePixels(File(png).readAsBytesSync(), File(out).readAsBytesSync()),
          isTrue,
        );
      },
      skip: hasCwebp ? false : 'cwebp not installed',
    );

    test(
      'a 16-bit png is compared at 8 bits per channel',
      () {
        final wide = img.Image(
          width: 1,
          height: 1,
          numChannels: 4,
          format: img.Format.uint16,
        )..setPixelRgba(0, 0, 65535, 0, 257, 1);
        final path = '${dir.path}/w.png';
        File(path).writeAsBytesSync(img.encodePng(wide));
        final out = '${dir.path}/w.webp';
        expect(transformImage(path, out), isTrue);
      },
      skip: hasCwebp ? false : 'cwebp not installed',
    );

    test('detects a changed visible pixel and a size mismatch', () {
      final changed = img.Image.from(base)..setPixelRgba(0, 0, 11, 20, 30, 255);
      expect(samePixels(img.encodePng(base), img.encodePng(changed)), isFalse);
      expect(samePixels(img.encodePng(base), [1, 2, 3]), isFalse);
    });
  });
}
