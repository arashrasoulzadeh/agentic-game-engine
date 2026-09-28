import 'package:flutter/material.dart';
import 'bt_nodes.dart';
import 'bt_connections.dart';

class BTGraphController extends ChangeNotifier {
  final Map<int, BTNodeData> _nodes = {};
  final BTConnectionManager _connectionManager = BTConnectionManager();
  final List<int> _nodeOrder = [];

  Map<int, BTNodeData> get nodes => Map.unmodifiable(_nodes);
  BTConnectionManager get connectionManager => _connectionManager;

  BTNodeData addNode(BTNodeType type, {Offset? position}) {
    final node = createNode(type, position: position);
    _nodes[node.id] = node;
    _nodeOrder.add(node.id);
    _connectionManager.registerNode(node);
    node.addListener(_onNodeChanged);
    notifyListeners();
    return node;
  }

  void removeNode(int nodeId) {
    final node = _nodes.remove(nodeId);
    if (node == null) return;
    _nodeOrder.remove(nodeId);
    node.removeListener(_onNodeChanged);
    _connectionManager.unregisterNode(nodeId);
    notifyListeners();
  }

  BTNodeData? getNode(int id) => _nodes[id];

  List<BTNodeData> getRoots() {
    return _nodes.values.where((node) {
      if (node.inputPoint == null) return true;
      return node.inputPoint!.connectedNodeId == null;
    }).toList();
  }

  void clear() {
    for (final node in _nodes.values) {
      node.removeListener(_onNodeChanged);
    }
    _nodes.clear();
    _nodeOrder.clear();
    _connectionManager.clear();
    notifyListeners();
  }

  List<BTNodeData> getNodesInOrder() {
    return _nodeOrder.map((id) => _nodes[id]!).whereType<BTNodeData>().toList();
  }

  void moveToFront(int nodeId) {
    _nodeOrder.remove(nodeId);
    _nodeOrder.add(nodeId);
    notifyListeners();
  }

  void _onNodeChanged() {
    notifyListeners();
  }

  List<String> validate() {
    final errors = <String>[];
    
    for (final node in _nodes.values) {
      final error = node.validate();
      if (error != null) {
        errors.add('Node ${node.name} (${node.id}): $error');
      }
    }
    
    if (_hasCycles()) {
      errors.add('Graph contains cycles');
    }
    
    final roots = getRoots();
    if (roots.length > 1) {
      errors.add('Warning: Multiple root nodes (${roots.length})');
    } else if (roots.isEmpty && _nodes.isNotEmpty) {
      errors.add('No root node found');
    }
    
    return errors;
  }

  bool _hasCycles() {
    final visited = <int>{};
    final recStack = <int>{};
    
    bool dfs(int nodeId) {
      if (recStack.contains(nodeId)) return true;
      if (visited.contains(nodeId)) return false;
      
      visited.add(nodeId);
      recStack.add(nodeId);
      
      final node = _nodes[nodeId];
      if (node != null) {
        for (final point in node.outputPoints) {
          if (point.connectedNodeId != null) {
            if (dfs(point.connectedNodeId!)) return true;
          }
        }
      }
      
      recStack.remove(nodeId);
      return false;
    }
    
    for (final nodeId in _nodes.keys) {
      if (!visited.contains(nodeId)) {
        if (dfs(nodeId)) return true;
      }
    }
    
    return false;
  }

  @override
  void dispose() {
    for (final node in _nodes.values) {
      node.removeListener(_onNodeChanged);
    }
    super.dispose();
  }
}