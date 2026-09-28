import 'bt_nodes.dart';

class BTConnectionManager {
  final Map<int, BTNodeData> _nodes = {};
  final List<BTConnection> _connections = [];

  void registerNode(BTNodeData node) {
    _nodes[node.id] = node;
  }

  void unregisterNode(int nodeId) {
    _nodes.remove(nodeId);
    _connections.removeWhere((c) =>
        c.fromNodeId == nodeId || c.toNodeId == nodeId);
    for (final node in _nodes.values) {
      if (node.inputPoint?.connectedNodeId == nodeId) {
        node.inputPoint!.connectedNodeId = null;
        node.inputPoint!.connectedPointIndex = null;
      }
      for (var i = 0; i < node.outputPoints.length; i++) {
        if (node.outputPoints[i].connectedNodeId == nodeId) {
          node.outputPoints[i].connectedNodeId = null;
          node.outputPoints[i].connectedPointIndex = null;
        }
      }
    }
  }

  bool connect({
    required int fromNodeId,
    required int fromPointIndex,
    required int toNodeId,
    required int toPointIndex,
  }) {
    final fromNode = _nodes[fromNodeId];
    final toNode = _nodes[toNodeId];
    if (fromNode == null || toNode == null) return false;

    if (fromPointIndex >= fromNode.outputPoints.length) return false;
    if (toPointIndex >= (toNode.inputPoint != null ? 1 : 0)) return false;

    final fromPoint = fromNode.outputPoints[fromPointIndex];
    final toPoint = toNode.inputPoint!;

    if (fromPoint.connectedNodeId != null &&
        fromPoint.maxConnections == 1) return false;
    if (toPoint.connectedNodeId != null) return false;

    if (_wouldCreateCycle(fromNodeId, toNodeId)) return false;

    fromPoint.connectedNodeId = toNodeId;
    fromPoint.connectedPointIndex = toPointIndex;
    toPoint.connectedNodeId = fromNodeId;
    toPoint.connectedPointIndex = fromPointIndex;

    _connections.add(BTConnection(
      fromNodeId: fromNodeId,
      fromPointIndex: fromPointIndex,
      toNodeId: toNodeId,
      toPointIndex: toPointIndex,
    ));

    fromNode.notifyListeners();
    toNode.notifyListeners();
    return true;
  }

  bool _wouldCreateCycle(int fromNodeId, int toNodeId) {
    if (fromNodeId == toNodeId) return true;
    
    final visited = <int>{};
    final stack = [toNodeId];
    
    while (stack.isNotEmpty) {
      final current = stack.removeLast();
      if (current == fromNodeId) return true;
      if (visited.contains(current)) continue;
      visited.add(current);
      
      final node = _nodes[current];
      if (node == null) continue;
      
      for (final point in node.outputPoints) {
        if (point.connectedNodeId != null) {
          stack.add(point.connectedNodeId!);
        }
      }
    }
    
    return false;
  }

  void disconnect({
    required int fromNodeId,
    required int fromPointIndex,
  }) {
    final fromNode = _nodes[fromNodeId];
    if (fromNode == null) return;
    
    if (fromPointIndex >= fromNode.outputPoints.length) return;
    
    final fromPoint = fromNode.outputPoints[fromPointIndex];
    if (fromPoint.connectedNodeId == null) return;
    
    final toNodeId = fromPoint.connectedNodeId!;
    final toPointIndex = fromPoint.connectedPointIndex!;
    
    final toNode = _nodes[toNodeId];
    if (toNode != null && toNode.inputPoint != null) {
      toNode.inputPoint!.connectedNodeId = null;
      toNode.inputPoint!.connectedPointIndex = null;
      toNode.notifyListeners();
    }
    
    fromPoint.connectedNodeId = null;
    fromPoint.connectedPointIndex = null;
    fromNode.notifyListeners();
    
    _connections.removeWhere((c) =>
        c.fromNodeId == fromNodeId &&
        c.fromPointIndex == fromPointIndex);
  }

  List<BTConnection> get connections => List.unmodifiable(_connections);

  BTConnection? getConnection(int fromNodeId, int fromPointIndex) {
    try {
      return _connections.firstWhere(
        (c) => c.fromNodeId == fromNodeId && c.fromPointIndex == fromPointIndex,
      );
    } catch (_) {
      return null;
    }
  }

  void clear() {
    _connections.clear();
    for (final node in _nodes.values) {
      if (node.inputPoint != null) {
        node.inputPoint!.connectedNodeId = null;
        node.inputPoint!.connectedPointIndex = null;
      }
      for (final point in node.outputPoints) {
        point.connectedNodeId = null;
        point.connectedPointIndex = null;
      }
    }
  }
}

class BTConnection {
  final int fromNodeId;
  final int fromPointIndex;
  final int toNodeId;
  final int toPointIndex;

  BTConnection({
    required this.fromNodeId,
    required this.fromPointIndex,
    required this.toNodeId,
    required this.toPointIndex,
  });
}