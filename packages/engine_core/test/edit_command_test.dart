import 'dart:convert';

import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

LevelDocument _doc() => LevelDocument.fromJson({
  'entities': [
    {
      'name': 'player',
      'components': {
        'position': {'x': 1.0, 'y': 2.0},
      },
    },
    {
      'name': 'crate',
      'components': {
        'pushable': {'pushSpeed': 2.5},
      },
    },
  ],
});

String _snapshot(LevelDocument doc) => jsonEncode(doc.toJson());

/// Applies [command], then reverts it, and checks the document is back to
/// exactly the state it started in.
void _expectApplyThenRevertRestores(EditCommand command, LevelDocument doc) {
  final before = _snapshot(doc);
  command.apply(doc);
  expect(
    _snapshot(doc),
    isNot(before),
    reason: '${command.label} changed nothing',
  );
  command.revert(doc);
  expect(
    _snapshot(doc),
    before,
    reason: '${command.label} did not revert exactly',
  );
}

void main() {
  group('entity commands', () {
    test('AddEntityCommand appends by default and reverts exactly', () {
      final doc = _doc();
      _expectApplyThenRevertRestores(
        AddEntityCommand(LevelEntity(name: 'coin')),
        doc,
      );
    });

    test('AddEntityCommand honors an explicit index', () {
      final doc = _doc();
      AddEntityCommand(LevelEntity(name: 'coin'), index: 0).apply(doc);
      expect(doc.entities.first.name, 'coin');
    });

    test('RemoveEntityCommand removes and reverts to the same position', () {
      final doc = _doc();
      final command = RemoveEntityCommand(doc.entities.first);
      _expectApplyThenRevertRestores(command, doc);
    });

    test('RemoveEntityCommand puts the entity back at its original index', () {
      final doc = _doc();
      final middle = LevelEntity(name: 'middle');
      doc.entities.insert(1, middle);
      final command = RemoveEntityCommand(middle);
      command.apply(doc);
      command.revert(doc);
      expect(doc.entities[1], same(middle));
    });
  });

  group('SetComponentFieldCommand', () {
    test('changes an existing field and reverts it', () {
      final doc = _doc();
      final player = doc.entities.first;
      _expectApplyThenRevertRestores(
        SetComponentFieldCommand(
          entity: player,
          component: 'position',
          field: 'x',
          value: 99.0,
        ),
        doc,
      );
    });

    test('adds a new field to an existing component and reverts it', () {
      final doc = _doc();
      _expectApplyThenRevertRestores(
        SetComponentFieldCommand(
          entity: doc.entities.first,
          component: 'position',
          field: 'z',
          value: 3.0,
        ),
        doc,
      );
    });

    test('creates a missing component and reverts by removing it again', () {
      final doc = _doc();
      final crate = doc.entities[1];
      _expectApplyThenRevertRestores(
        SetComponentFieldCommand(
          entity: crate,
          component: 'sprite',
          field: 'atlasId',
          value: 'crates',
        ),
        doc,
      );
      expect(crate.components.containsKey('sprite'), isFalse);
    });
  });

  group('CommandHistory', () {
    test('undo reverts the latest command, redo re-applies it', () {
      final doc = _doc();
      final history = CommandHistory(doc);
      history.execute(AddEntityCommand(LevelEntity(name: 'coin')));
      expect(doc.entities, hasLength(3));

      history.undo();
      expect(doc.entities, hasLength(2));

      history.redo();
      expect(doc.entities, hasLength(3));
    });

    test('undo and redo walk the stack in order', () {
      final doc = _doc();
      final history = CommandHistory(doc);
      history.execute(AddEntityCommand(LevelEntity(name: 'a')));
      history.execute(AddEntityCommand(LevelEntity(name: 'b')));

      history.undo();
      expect(doc.entities.last.name, 'a');
      history.undo();
      expect(doc.entities.last.name, 'crate');
    });

    test('a new edit after an undo discards the redo stack', () {
      final doc = _doc();
      final history = CommandHistory(doc);
      history.execute(AddEntityCommand(LevelEntity(name: 'a')));
      history.undo();
      expect(history.canRedo, isTrue);

      history.execute(AddEntityCommand(LevelEntity(name: 'b')));
      expect(history.canRedo, isFalse);
    });

    test('undo and redo with nothing to do are no-ops', () {
      final doc = _doc();
      final history = CommandHistory(doc);
      final before = _snapshot(doc);
      history.undo();
      history.redo();
      expect(_snapshot(doc), before);
      expect(history.undoLabel, isNull);
      expect(history.redoLabel, isNull);
    });

    test('labels describe the next undo and redo', () {
      final doc = _doc();
      final history = CommandHistory(doc);
      history.execute(AddEntityCommand(LevelEntity(name: 'coin')));
      expect(history.undoLabel, 'Add entity coin');
      history.undo();
      expect(history.redoLabel, 'Add entity coin');
    });
  });
}
