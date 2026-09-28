import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

int _nextId = 1;
int _generateId() => _nextId++;

abstract class BTNodeData extends ChangeNotifier {
  final int id;
  String name;
  Offset position;
  final BTNodeType type;
  bool _selected = false;

  BTNodeData({
    required this.type,
    required this.name,
    Offset? position,
    int? id,
  }) : id = id ?? _generateId(),
       position = position ?? Offset.zero;

  bool get selected => _selected;
  set selected(bool value) {
    if (_selected != value) {
      _selected = value;
      notifyListeners();
    }
  }

  BTConnectionPoint? get inputPoint;
  List<BTConnectionPoint> get outputPoints;

  Map<String, dynamic> toJson();
  BTNodeData copy();
  String? validate();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BTNodeData && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

enum BTNodeType {
  sequence('Sequence', 'Composite', Icons.list_numbered_rtl, Colors.blue),
  selector('Selector', 'Composite', Icons.call_split, Colors.green),
  parallel('Parallel', 'Composite', Icons.compare_arrows, Colors.orange),
  inverter('Inverter', 'Decorator', Icons.swap_vert, Colors.purple),
  repeater('Repeater', 'Decorator', Icons.replay, Colors.deepPurple),
  succeeder('Succeeder', 'Decorator', Icons.check_circle, Colors.teal),
  failer('Failer', 'Decorator', Icons.cancel, Colors.red),
  leaf('Leaf', 'Leaf', Icons.bolt, Colors.amber),
  wait('Wait', 'Leaf', Icons.timer, Colors.cyan);

  const BTNodeType(
    this.label,
    this.category,
    this.icon,
    this.color,
  );

  final String label;
  final String category;
  final IconData icon;
  final Color color;

  static BTNodeType? fromString(String type) {
    for (final t in BTNodeType.values) {
      if (t.name == type) return t;
    }
    return null;
  }
}

class BTConnectionPoint {
  final String name;
  final bool isInput;
  final int maxConnections;
  int? connectedNodeId;
  int? connectedPointIndex;

  BTConnectionPoint({
    required this.name,
    required this.isInput,
    this.maxConnections = 1,
    this.connectedNodeId,
    this.connectedPointIndex,
  });
}

class BTSequenceNode extends BTNodeData {
  int _childCount = 2;
  int get childCount => _childCount;
  set childCount(int value) {
    _childCount = value.clamp(1, 10);
    notifyListeners();
  }

  BTSequenceNode({super.position, super.id})
      : super(type: BTNodeType.sequence, name: 'Sequence');

  @override
  BTConnectionPoint? get inputPoint => null;

  @override
  List<BTConnectionPoint> get outputPoints => List.generate(
        childCount,
        (i) => BTConnectionPoint(
          name: 'child$i',
          isInput: false,
          maxConnections: 1,
        ),
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'sequence',
        'id': name,
        'children': outputPoints
            .map((p) => p.connectedNodeId != null
                ? {'ref': p.connectedNodeId}
                : null)
            .whereType<Map<String, dynamic>>()
            .toList(),
      };

  @override
  BTNodeData copy() => BTSequenceNode(position: position, id: id)
    ..childCount = childCount;

  @override
  String? validate() {
    if (childCount < 1) return 'Sequence needs at least 1 child';
    return null;
  }
}

class BTSelectorNode extends BTNodeData {
  int _childCount = 2;
  int get childCount => _childCount;
  set childCount(int value) {
    _childCount = value.clamp(1, 10);
    notifyListeners();
  }

  BTSelectorNode({super.position, super.id})
      : super(type: BTNodeType.selector, name: 'Selector');

  @override
  BTConnectionPoint? get inputPoint => null;

  @override
  List<BTConnectionPoint> get outputPoints => List.generate(
        childCount,
        (i) => BTConnectionPoint(
          name: 'child$i',
          isInput: false,
          maxConnections: 1,
        ),
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'selector',
        'id': name,
        'children': outputPoints
            .map((p) => p.connectedNodeId != null
                ? {'ref': p.connectedNodeId}
                : null)
            .whereType<Map<String, dynamic>>()
            .toList(),
      };

  @override
  BTNodeData copy() => BTSelectorNode(position: position, id: id)
    ..childCount = childCount;

  @override
  String? validate() {
    if (childCount < 1) return 'Selector needs at least 1 child';
    return null;
  }
}

class BTParallelNode extends BTNodeData {
  int _childCount = 2;
  int _requiredSuccess = 1;
  int get childCount => _childCount;
  int get requiredSuccess => _requiredSuccess;
  set childCount(int value) {
    _childCount = value.clamp(1, 10);
    _requiredSuccess = math.min(_requiredSuccess, _childCount);
    notifyListeners();
  }
  set requiredSuccess(int value) {
    _requiredSuccess = value.clamp(1, _childCount);
    notifyListeners();
  }

  BTParallelNode({super.position, super.id})
      : super(type: BTNodeType.parallel, name: 'Parallel');

  @override
  BTConnectionPoint? get inputPoint => null;

  @override
  List<BTConnectionPoint> get outputPoints => List.generate(
        childCount,
        (i) => BTConnectionPoint(
          name: 'child$i',
          isInput: false,
          maxConnections: 1,
        ),
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'parallel',
        'id': name,
        'requiredSuccess': requiredSuccess,
        'children': outputPoints
            .map((p) => p.connectedNodeId != null
                ? {'ref': p.connectedNodeId}
                : null)
            .whereType<Map<String, dynamic>>()
            .toList(),
      };

  @override
  BTNodeData copy() => BTParallelNode(position: position, id: id)
    ..childCount = childCount
    ..requiredSuccess = requiredSuccess;

  @override
  String? validate() {
    if (childCount < 1) return 'Parallel needs at least 1 child';
    if (requiredSuccess < 1 || requiredSuccess > childCount) {
      return 'Required success must be between 1 and child count';
    }
    return null;
  }
}

class BTInverterNode extends BTNodeData {
  BTInverterNode({super.position, super.id})
      : super(type: BTNodeType.inverter, name: 'Inverter');

  @override
  BTConnectionPoint? get inputPoint => BTConnectionPoint(
        name: 'child',
        isInput: true,
        maxConnections: 1,
      );

  @override
  List<BTConnectionPoint> get outputPoints => [
        BTConnectionPoint(
          name: 'child',
          isInput: false,
          maxConnections: 1,
        ),
      ];

  @override
  Map<String, dynamic> toJson() => {
        'type': 'inverter',
        'id': name,
        'child': outputPoints.first.connectedNodeId != null
            ? {'ref': outputPoints.first.connectedNodeId}
            : null,
      };

  @override
  BTNodeData copy() => BTInverterNode(position: position, id: id);

  @override
  String? validate() {
    if (outputPoints.first.connectedNodeId == null) {
      return 'Inverter needs a child';
    }
    return null;
  }
}

class BTRepeaterNode extends BTNodeData {
  int? _count;
  int? get count => _count;
  set count(int? value) {
    _count = value;
    notifyListeners();
  }

  BTRepeaterNode({super.position, super.id})
      : super(type: BTNodeType.repeater, name: 'Repeater');

  @override
  BTConnectionPoint? get inputPoint => BTConnectionPoint(
        name: 'child',
        isInput: true,
        maxConnections: 1,
      );

  @override
  List<BTConnectionPoint> get outputPoints => [
        BTConnectionPoint(
          name: 'child',
          isInput: false,
          maxConnections: 1,
        ),
      ];

  @override
  Map<String, dynamic> toJson() => {
        'type': 'repeater',
        'id': name,
        if (count != null) 'count': count,
        'child': outputPoints.first.connectedNodeId != null
            ? {'ref': outputPoints.first.connectedNodeId}
            : null,
      };

  @override
  BTNodeData copy() => BTRepeaterNode(position: position, id: id)
    ..count = count;

  @override
  String? validate() {
    if (outputPoints.first.connectedNodeId == null) {
      return 'Repeater needs a child';
    }
    return null;
  }
}

class BTSucceederNode extends BTNodeData {
  BTSucceederNode({super.position, super.id})
      : super(type: BTNodeType.succeeder, name: 'Succeeder');

  @override
  BTConnectionPoint? get inputPoint => BTConnectionPoint(
        name: 'child',
        isInput: true,
        maxConnections: 1,
      );

  @override
  List<BTConnectionPoint> get outputPoints => [
        BTConnectionPoint(
          name: 'child',
          isInput: false,
          maxConnections: 1,
        ),
      ];

  @override
  Map<String, dynamic> toJson() => {
        'type': 'succeeder',
        'id': name,
        'child': outputPoints.first.connectedNodeId != null
            ? {'ref': outputPoints.first.connectedNodeId}
            : null,
      };

  @override
  BTNodeData copy() => BTSucceederNode(position: position, id: id);

  @override
  String? validate() {
    if (outputPoints.first.connectedNodeId == null) {
      return 'Succeeder needs a child';
    }
    return null;
  }
}

class BTFailerNode extends BTNodeData {
  BTFailerNode({super.position, super.id})
      : super(type: BTNodeType.failer, name: 'Failer');

  @override
  BTConnectionPoint? get inputPoint => BTConnectionPoint(
        name: 'child',
        isInput: true,
        maxConnections: 1,
      );

  @override
  List<BTConnectionPoint> get outputPoints => [
        BTConnectionPoint(
          name: 'child',
          isInput: false,
          maxConnections: 1,
        ),
      ];

  @override
  Map<String, dynamic> toJson() => {
        'type': 'failer',
        'id': name,
        'child': outputPoints.first.connectedNodeId != null
            ? {'ref': outputPoints.first.connectedNodeId}
            : null,
      };

  @override
  BTNodeData copy() => BTFailerNode(position: position, id: id);

  @override
  String? validate() {
    if (outputPoints.first.connectedNodeId == null) {
      return 'Failer needs a child';
    }
    return null;
  }
}

class BTLeafNode extends BTNodeData {
  String _behaviorId = '';
  String get behaviorId => _behaviorId;
  set behaviorId(String value) {
    _behaviorId = value;
    notifyListeners();
  }

  BTLeafNode({super.position, super.id})
      : super(type: BTNodeType.leaf, name: 'Leaf');

  @override
  BTConnectionPoint? get inputPoint => BTConnectionPoint(
        name: 'in',
        isInput: true,
        maxConnections: 1,
      );

  @override
  List<BTConnectionPoint> get outputPoints => [];

  @override
  Map<String, dynamic> toJson() => {
        'type': 'leaf',
        'id': name,
        'behaviorId': behaviorId,
      };

  @override
  BTNodeData copy() => BTLeafNode(position: position, id: id)
    ..behaviorId = behaviorId;

  @override
  String? validate() {
    if (behaviorId.isEmpty) return 'Leaf needs a behavior ID';
    return null;
  }
}

class BTWaitNode extends BTNodeData {
  double _duration = 1.0;
  double get duration => _duration;
  set duration(double value) {
    _duration = value.clamp(0.01, 3600.0);
    notifyListeners();
  }

  BTWaitNode({super.position, super.id})
      : super(type: BTNodeType.wait, name: 'Wait');

  @override
  BTConnectionPoint? get inputPoint => BTConnectionPoint(
        name: 'in',
        isInput: true,
        maxConnections: 1,
      );

  @override
  List<BTConnectionPoint> get outputPoints => [];

  @override
  Map<String, dynamic> toJson() => {
        'type': 'wait',
        'id': name,
        'duration': duration,
      };

  @override
  BTNodeData copy() => BTWaitNode(position: position, id: id)
    ..duration = duration;

  @override
  String? validate() => null;
}

BTNodeData createNode(BTNodeType type, {Offset? position, int? id}) {
  switch (type) {
    case BTNodeType.sequence:
      return BTSequenceNode(position: position, id: id);
    case BTNodeType.selector:
      return BTSelectorNode(position: position, id: id);
    case BTNodeType.parallel:
      return BTParallelNode(position: position, id: id);
    case BTNodeType.inverter:
      return BTInverterNode(position: position, id: id);
    case BTNodeType.repeater:
      return BTRepeaterNode(position: position, id: id);
    case BTNodeType.succeeder:
      return BTSucceederNode(position: position, id: id);
    case BTNodeType.failer:
      return BTFailerNode(position: position, id: id);
    case BTNodeType.leaf:
      return BTLeafNode(position: position, id: id);
    case BTNodeType.wait:
      return BTWaitNode(position: position, id: id);
  }
}