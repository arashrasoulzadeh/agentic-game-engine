import 'package:engine_idle/engine_idle.dart';
import 'package:flutter_test/flutter_test.dart';

/// On the VM `BrowserSaveStore` is the in-memory stand-in; the real `localStorage` version is compiled
/// for the web and exercised against a fake `localStorage` in node (see the commit that added it).
void main() {
  test('reads back what was written, per key', () {
    final a = BrowserSaveStore('game_a');
    final b = BrowserSaveStore('game_b');
    expect(a.read(), isNull);
    a.write({'x': 1});
    expect(a.read(), {'x': 1});
    expect(b.read(), isNull);
    a.write({'x': 2});
    expect(BrowserSaveStore('game_a').read(), {'x': 2});
  });

  test('works as an IdleSession store', () {
    expect(BrowserSaveStore('s'), isA<SaveStore>());
  });
}
