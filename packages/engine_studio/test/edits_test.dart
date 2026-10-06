import 'package:engine_studio/src/lsp/edits.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a single edit replaces the text between two positions', () {
    expect(
      applyEdits('void main(){}\n', [const TextEdit(0, 12, 0, 12, '\n  ')]),
      'void main(){\n  }\n',
    );
  });

  test(
    'several edits apply correctly, later ones first, so earlier positions hold',
    () {
      const source = 'a=1;\nb=2;\n';
      final formatted = applyEdits(source, [
        const TextEdit(0, 1, 0, 2, ' = '),
        const TextEdit(1, 1, 1, 2, ' = '),
      ]);
      expect(formatted, 'a = 1;\nb = 2;\n');
    },
  );

  test('an edit on the last line with no trailing newline still applies', () {
    expect(applyEdits('x', [const TextEdit(0, 1, 0, 1, ';')]), 'x;');
  });

  test('no edits leaves the text alone', () {
    expect(applyEdits('same', []), 'same');
  });
}
