import 'dart:convert';

import 'bt_nodes.dart';
import 'bt_graph_controller.dart';

class BTExport {
  static String exportToJson(BTGraphController controller) {
    final nodeMap = <int, Map<String, dynamic>>{};
    
    for (final node in controller.nodes.values) {
      final json = node.toJson();
      nodeMap[node.id] = json;
    }
    
    final roots = controller.getRoots();
    
    if (roots.isEmpty) {
      return jsonEncode({'type': 'sequence', 'id': 'root', 'children': []});
    }
    
    final rootNodes = roots.map((r) => _buildNodeTree(r, controller, nodeMap)).toList();
    
    if (rootNodes.length == 1) {
      return jsonEncode(rootNodes.first);
    } else {
      return jsonEncode({
        'type': 'sequence',
        'id': 'root',
        'children': rootNodes,
      });
    }
  }

  static Map<String, dynamic> _buildNodeTree(
    BTNodeData node,
    BTGraphController controller,
    Map<int, Map<String, dynamic>> nodeMap,
  ) {
    final json = Map<String, dynamic>.from(nodeMap[node.id]!);
    
    if (node.outputPoints.isNotEmpty) {
      final children = <Map<String, dynamic>>[];
      for (final point in node.outputPoints) {
        if (point.connectedNodeId != null) {
          final childNode = controller.nodes[point.connectedNodeId!];
          if (childNode != null) {
            children.add(_buildNodeTree(childNode, controller, nodeMap));
          }
        }
      }
      if (children.isNotEmpty) {
        json['children'] = children;
      }
    } else if (node is BTLeafNode || node is BTWaitNode) {
    } else if (node.inputPoint != null && node.outputPoints.isNotEmpty) {
      final point = node.outputPoints.first;
      if (point.connectedNodeId != null) {
        final childNode = controller.nodes[point.connectedNodeId!];
        if (childNode != null) {
          json['child'] = _buildNodeTree(childNode, controller, nodeMap);
        }
      }
    }
    
    return json;
  }

  static void importFromJson(BTGraphController controller, String jsonString) {
    final json = jsonDecode(jsonString);
    controller.clear();
    _importNode(json, controller, null);
  }

  static BTNodeData? _importNode(
    Map<String, dynamic> json,
    BTGraphController controller,
    BTNodeData? parent,
  ) {
    final typeStr = json['type'] as String?;
    if (typeStr == null) return null;
    
    final type = BTNodeType.fromString(typeStr);
    if (type == null) return null;
    
    final name = json['id'] as String? ?? type.label;
    final node = controller.addNode(type);
    node.name = name;
    
    _applyNodeProperties(node, json);
    
    if (parent != null) {
      final parentPointIndex = _findAvailableOutputPoint(parent, controller);
      if (parentPointIndex != null) {
        controller.connectionManager.connect(
          fromNodeId: parent.id,
          fromPointIndex: parentPointIndex,
          toNodeId: node.id,
          toPointIndex: 0,
        );
      }
    }
    
    if (json['children'] != null) {
      final children = json['children'] as List;
      for (var i = 0; i < children.length; i++) {
        final childJson = children[i] as Map<String, dynamic>;
        final childNode = _importNode(childJson, controller, node);
        if (childNode != null && i < node.outputPoints.length) {
          controller.connectionManager.connect(
            fromNodeId: node.id,
            fromPointIndex: i,
            toNodeId: childNode.id,
            toPointIndex: 0,
          );
        }
      }
    } else if (json['child'] != null) {
      final childJson = json['child'] as Map<String, dynamic>;
      final childNode = _importNode(childJson, controller, node);
      if (childNode != null && node.outputPoints.isNotEmpty) {
        controller.connectionManager.connect(
          fromNodeId: node.id,
          fromPointIndex: 0,
          toNodeId: childNode.id,
          toPointIndex: 0,
        );
      }
    }
    
    return node;
  }

  static void _applyNodeProperties(BTNodeData node, Map<String, dynamic> json) {
    switch (node.type) {
      case BTNodeType.parallel:
        final pNode = node as BTParallelNode;
        pNode.requiredSuccess = (json['requiredSuccess'] as num?)?.toInt() ?? 1;
        break;
      case BTNodeType.repeater:
        final rNode = node as BTRepeaterNode;
        rNode.count = (json['count'] as num?)?.toInt();
        break;
      case BTNodeType.leaf:
        final lNode = node as BTLeafNode;
        lNode.behaviorId = json['behaviorId'] as String? ?? '';
        break;
      case BTNodeType.wait:
        final wNode = node as BTWaitNode;
        wNode.duration = (json['duration'] as num?)?.toDouble() ?? 1.0;
        break;
      default:
        break;
    }
  }

  static int? _findAvailableOutputPoint(BTNodeData parent, BTGraphController controller) {
    for (var i = 0; i < parent.outputPoints.length; i++) {
      if (parent.outputPoints[i].connectedNodeId == null) {
        return i;
      }
    }
    return null;
  }
}