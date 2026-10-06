import 'dart:convert';

import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

void main() {
  test('encodes with two-space indent and keeps the data', () {
    final data = {
      'entities': [
        {'name': 'player'},
      ],
    };
    final text = encodeLevelJson(data);
    expect(text, contains('\n  "entities"'));
    expect(jsonDecode(text), data);
  });

  test('the same data always encodes to the same bytes', () {
    final data = LevelDocument.fromJson({
      'entities': [
        {
          'components': {
            'position': {'x': 1.0, 'y': 2.0},
          },
        },
      ],
    }).toJson();
    expect(
      encodeLevelJson(data),
      encodeLevelJson(jsonDecode(encodeLevelJson(data))),
    );
  });
}
