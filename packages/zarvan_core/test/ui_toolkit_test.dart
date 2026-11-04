import 'package:test/test.dart';
import 'package:zarvan_core/zarvan_core.dart';

void main() {
  group('layoutStack', () {
    test('flexible children share what fixed ones and gaps leave', () {
      final r = layoutStack(
        const UiRect(0, 0, 100, 200),
        [40, null, null],
        gap: 10,
        padding: 5,
      );
      expect(r[0], const UiRect(5, 5, 90, 40));
      // 190 inner - 40 fixed - 20 gaps = 130 free, 65 each
      expect(r[1], const UiRect(5, 55, 90, 65));
      expect(r[2], const UiRect(5, 130, 90, 65));
    });

    test('horizontal layout and empty input', () {
      final r = layoutStack(const UiRect(10, 0, 90, 20), [
        30,
        null,
      ], vertical: false);
      expect(r[0], const UiRect(10, 0, 30, 20));
      expect(r[1], const UiRect(40, 0, 60, 20));
      expect(layoutStack(const UiRect(0, 0, 1, 1), []), isEmpty);
    });

    test('overflowing fixed sizes are not shrunk and flex gets nothing', () {
      final r = layoutStack(const UiRect(0, 0, 10, 50), [40, 40, null]);
      expect(r[1].bottom, 80);
      expect(r[2].height, 0);
    });
  });

  test('anchorRect pins to corners, edges and centre with an offset', () {
    const p = UiRect(0, 0, 200, 100);
    expect(anchorRect(p, UiAnchor.topLeft, 20, 10), const UiRect(0, 0, 20, 10));
    expect(
      anchorRect(p, UiAnchor.bottomRight, 20, 10, dx: -4, dy: -4),
      const UiRect(176, 86, 20, 10),
    );
    expect(
      anchorRect(p, UiAnchor.center, 20, 10),
      const UiRect(90, 45, 20, 10),
    );
    expect(anchorRect(p, UiAnchor.top, 20, 10).x, 90);
    expect(anchorRect(p, UiAnchor.left, 20, 10).y, 45);
  });

  group('ScrollListModel', () {
    ScrollListModel m() =>
        ScrollListModel(itemCount: 20, itemHeight: 10, viewportHeight: 50);

    test('clamps scrolling and reports the visible range', () {
      final s = m();
      expect(s.visibleRange, (0, 4));
      s.scrollBy(23);
      expect(s.visibleRange, (2, 7));
      s.scrollBy(-999);
      expect(s.offset, 0);
      s.scrollBy(999);
      expect(s.offset, s.maxOffset);
      expect(s.maxOffset, 150);
    });

    test('hit-test maps viewport y to a row', () {
      final s = m()..scrollBy(15);
      expect(s.indexAt(0), 1);
      expect(s.indexAt(49), 6);
      expect(s.indexAt(60), isNull);
      expect(s.rowTop(1), -5);
    });

    test('a fling coasts, slows and stops at the end', () {
      final s = m()..fling(200);
      for (var i = 0; i < 600; i++) {
        s.update(1 / 60);
      }
      expect(s.offset, greaterThan(20));
      expect(s.offset, lessThanOrEqualTo(s.maxOffset));
      final stopped = s.offset;
      s.update(1 / 60);
      expect(s.offset, stopped);
      final e = m()..fling(100000);
      e.update(1);
      expect(e.offset, e.maxOffset);
      e.update(1);
      expect(e.offset, e.maxOffset);
    });

    test('keyboard selection scrolls to keep the row visible', () {
      final s = m();
      for (var i = 0; i < 8; i++) {
        s.moveSelection(1);
      }
      expect(s.selected, 7);
      expect(s.offset, 30);
      s.moveSelection(-100);
      expect(s.selected, 0);
      expect(s.offset, 0);
    });

    test('empty list has no range and ignores selection', () {
      final s = ScrollListModel(
        itemCount: 0,
        itemHeight: 10,
        viewportHeight: 50,
      );
      expect(s.visibleRange, isNull);
      s.moveSelection(1);
      expect(s.selected, isNull);
    });
  });

  group('TextInputModel', () {
    test('inserts at the caret, backspaces and deletes', () {
      final t = TextInputModel(text: 'ac')..moveCaret(-1);
      t.insert('b');
      expect((t.text, t.caret), ('abc', 2));
      t.backspace();
      expect(t.text, 'ac');
      t.delete();
      expect(t.text, 'a');
      t.home();
      t.backspace();
      expect(t.text, 'a');
      t.end();
      expect(t.caret, 1);
      t.clear();
      expect((t.text, t.caret), ('', 0));
    });

    test('respects maxLength and the allowed filter', () {
      final t = TextInputModel(maxLength: 4, allowed: RegExp(r'[0-9]'));
      t.insert('1a2b3c4d5');
      expect(t.text, '1234');
      t.insert('9');
      expect(t.text, '1234');
    });

    test('caret never leaves the text', () {
      final t = TextInputModel(text: 'hi')..moveCaret(99);
      expect(t.caret, 2);
      t.moveCaret(-99);
      expect(t.caret, 0);
    });
  });
}
