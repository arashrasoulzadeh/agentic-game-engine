import 'package:flutter/material.dart';
import 'bt_nodes.dart';

typedef OnNodeTap = void Function();
typedef OnNodeDelete = void Function();
typedef OnNodeDragStart = void Function(Offset pos);
typedef OnNodeConnectStart = void Function(int pointIndex, Offset pos);

class _NodeWidget extends StatelessWidget {
  final BTNodeData node;
  final double zoom;
  final Offset panOffset;
  final bool isSelected;
  final OnNodeTap onTap;
  final OnNodeDelete onDelete;
  final OnNodeDragStart onDragStart;
  final OnNodeConnectStart onConnectStart;

  const _NodeWidget({
    super.key,
    required this.node,
    required this.zoom,
    required this.panOffset,
    required this.isSelected,
    required this.onTap,
    required this.onDelete,
    required this.onDragStart,
    required this.onConnectStart,
  });

  @override
  Widget build(BuildContext context) {
    final rect = _getNodeRect();
    final screenRect = Rect.fromLTWH(
      rect.left * zoom + panOffset.dx,
      rect.top * zoom + panOffset.dy,
      rect.width * zoom,
      rect.height * zoom,
    );

    return Positioned(
      left: screenRect.left,
      top: screenRect.top,
      width: screenRect.width,
      height: screenRect.height,
      child: GestureDetector(
        onTap: onTap,
        onPanStart: (details) => onDragStart(details.localPosition),
        child: _NodeContent(
          node: node,
          zoom: zoom,
          isSelected: isSelected,
          onDelete: onDelete,
          onConnectStart: onConnectStart,
        ),
      ),
    );
  }

  Rect _getNodeRect() {
    return Rect.fromLTWH(
      node.position.dx,
      node.position.dy,
      200,
      _getNodeHeight(),
    );
  }

  double _getNodeHeight() {
    const headerHeight = 40.0;
    const pointHeight = 28.0;
    final pointCount = math.max(
      node.outputPoints.length,
      node.inputPoint != null ? 1 : 0,
    );
    return headerHeight + pointCount * pointHeight;
  }
}

class _NodeContent extends StatelessWidget {
  final BTNodeData node;
  final double zoom;
  final bool isSelected;
  final OnNodeDelete onDelete;
  final OnNodeConnectStart onConnectStart;

  const _NodeContent({
    super.key,
    required this.node,
    required this.zoom,
    required this.isSelected,
    required this.onDelete,
    required this.onConnectStart,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nodeColor = node.type.color;
    
    return Container(
      width: 200,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSelected 
              ? nodeColor 
              : theme.colorScheme.outlineVariant,
          width: isSelected ? 2 : 1,
        ),
        boxShadow: isSelected ? [
          BoxShadow(
            color: nodeColor.withValues(alpha: 0.3),
            blurRadius: 8,
            spreadRadius: 2,
          ),
        ] : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: nodeColor.withValues(alpha: 0.15),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                Icon(node.type.icon, color: nodeColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    node.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: nodeColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isSelected)
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: onDelete,
                    tooltip: 'Delete node',
                  ),
              ],
            ),
          ),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (node.inputPoint != null)
                  _ConnectionPoint(
                    isInput: true,
                    node: node,
                    pointIndex: 0,
                    zoom: zoom,
                    onConnectStart: onConnectStart,
                    isConnected: node.inputPoint!.connectedNodeId != null,
                  )
                else
                  const SizedBox(width: 16),
                
                Expanded(
                  child: _buildNodeBody(context),
                ),
                
                if (node.outputPoints.isNotEmpty)
                  Column(
                    children: node.outputPoints.asMap().entries.map((entry) {
                      final i = entry.key;
                      final point = entry.value;
                      return _ConnectionPoint(
                        isInput: false,
                        node: node,
                        pointIndex: i,
                        zoom: zoom,
                        onConnectStart: onConnectStart,
                        isConnected: point.connectedNodeId != null,
                      );
                    }).toList(),
                  )
                else
                  const SizedBox(width: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNodeBody(BuildContext context) {
    final theme = Theme.of(context);
    
    switch (node.type) {
      case BTNodeType.sequence:
        return _SequenceBody(node: node as BTSequenceNode);
      case BTNodeType.selector:
        return _SelectorBody(node: node as BTSelectorNode);
      case BTNodeType.parallel:
        return _ParallelBody(node: node as BTParallelNode);
      case BTNodeType.repeater:
        return _RepeaterBody(node: node as BTRepeaterNode);
      case BTNodeType.leaf:
        return _LeafBody(node: node as BTLeafNode);
      case BTNodeType.wait:
        return _WaitBody(node: node as BTWaitNode);
      default:
        return Container(
          padding: const EdgeInsets.all(12),
          child: Center(
            child: Text(
              node.type.label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
    }
  }
}

class _ConnectionPoint extends StatelessWidget {
  final bool isInput;
  final BTNodeData node;
  final int pointIndex;
  final double zoom;
  final OnNodeConnectStart onConnectStart;
  final bool isConnected;

  const _ConnectionPoint({
    super.key,
    required this.isInput,
    required this.node,
    required this.pointIndex,
    required this.zoom,
    required this.onConnectStart,
    required this.isConnected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isConnected ? Colors.cyanAccent : node.type.color;
    
    return GestureDetector(
      onPanStart: (details) => onConnectStart(pointIndex, details.localPosition),
      child: Container(
        width: 16,
        alignment: Alignment.center,
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: isConnected ? color : Colors.transparent,
            border: Border.all(
              color: color,
              width: 2 / zoom,
            ),
            shape: isInput ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: isInput ? null : BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

class _SequenceBody extends StatelessWidget {
  final BTSequenceNode node;
  const _SequenceBody({required this.node});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('→ '),
              Expanded(
                child: Text(
                  'Children: ${node.childCount}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Count: '),
              Expanded(
                child: Slider(
                  value: node.childCount.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  label: node.childCount.toString(),
                  onChanged: (v) => node.childCount = v.round(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SelectorBody extends StatelessWidget {
  final BTSelectorNode node;
  const _SelectorBody({required this.node});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('? '),
              Expanded(
                child: Text(
                  'Children: ${node.childCount}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Count: '),
              Expanded(
                child: Slider(
                  value: node.childCount.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  label: node.childCount.toString(),
                  onChanged: (v) => node.childCount = v.round(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ParallelBody extends StatelessWidget {
  final BTParallelNode node;
  const _ParallelBody({required this.node});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('∥ '),
              Expanded(
                child: Text(
                  'Children: ${node.childCount}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Count: '),
              Expanded(
                child: Slider(
                  value: node.childCount.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  label: node.childCount.toString(),
                  onChanged: (v) => node.childCount = v.round(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Required: '),
              Expanded(
                child: Slider(
                  value: node.requiredSuccess.toDouble(),
                  min: 1,
                  max: node.childCount.toDouble(),
                  divisions: node.childCount - 1,
                  label: '${node.requiredSuccess}/${node.childCount}',
                  onChanged: (v) => node.requiredSuccess = v.round(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RepeaterBody extends StatelessWidget {
  final BTRepeaterNode node;
  const _RepeaterBody({required this.node});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('⟳ '),
              Expanded(
                child: Text(
                  node.count != null 
                      ? 'Count: ${node.count}'
                      : 'Infinite (until failure)',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Count: '),
              Expanded(
                child: DropdownButtonFormField<int?>(
                  value: node.count,
                  decoration: const InputDecoration(isDense: true),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Infinite')),
                    ...List.generate(10, (i) => DropdownMenuItem(
                      value: i + 1,
                      child: Text('${i + 1}'),
                    )),
                  ],
                  onChanged: (v) => node.count = v,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LeafBody extends StatelessWidget {
  final BTLeafNode node;
  const _LeafBody({required this.node});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: TextField(
        decoration: const InputDecoration(
          labelText: 'Behavior ID',
          hintText: 'e.g., patrol, attack, move_to',
          isDense: true,
        ),
        style: Theme.of(context).textTheme.bodySmall,
        onChanged: (v) => node.behaviorId = v,
        controller: TextEditingController(text: node.behaviorId),
      ),
    );
  }
}

class _WaitBody extends StatelessWidget {
  final BTWaitNode node;
  const _WaitBody({required this.node});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Text('Duration: '),
          Expanded(
            child: Slider(
              value: node.duration,
              min: 0.1,
              max: 60.0,
              divisions: 599,
              label: '${node.duration.toStringAsFixed(1)}s',
              onChanged: (v) => node.duration = v,
            ),
          ),
          SizedBox(
            width: 50,
            child: Text(
              '${node.duration.toStringAsFixed(1)}s',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}