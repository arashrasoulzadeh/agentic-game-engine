import 'package:engine_studio/src/lsp/edits.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  _planTests();
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

void _planTests() {
  group('planRename', () {
    test('splits the current file\'s edits from the others', () {
      final plan = planRename(
        {
          '/a.dart': [const TextEdit(0, 0, 0, 4, 'Champ')],
          '/b.dart': [const TextEdit(1, 0, 1, 4, 'Champ')],
        },
        '/a.dart',
        'Hero stays here\n',
      );
      expect(plan.currentFileText, 'Champ stays here\n');
      expect(plan.otherFiles.keys, ['/b.dart']);
    });

    test(
      'the current file not being in the edits gives a null text, not a crash',
      () {
        final plan = planRename({'/b.dart': []}, '/a.dart', 'unchanged');
        expect(plan.currentFileText, isNull);
        expect(plan.otherFiles.keys, ['/b.dart']);
      },
    );
  });
}
