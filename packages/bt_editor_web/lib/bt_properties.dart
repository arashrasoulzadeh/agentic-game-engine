import 'package:flutter/material.dart';
import 'bt_nodes.dart';

typedef OnPropertyChanged = void Function();
typedef OnNodeDelete = void Function();

class BTPropertiesPanel extends StatelessWidget {
  final BTNodeData node;
  final OnPropertyChanged onChanged;
  final OnNodeDelete onDelete;

  const BTPropertiesPanel({
    super.key,
    required this.node,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(node.type.icon, color: node.type.color, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Properties',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: onDelete,
                  tooltip: 'Delete node',
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildBasicProperties(context),
                  const SizedBox(height: 24),
                  _buildNodeSpecificProperties(context),
                  const SizedBox(height: 24),
                  _buildConnectionInfo(context),
                  const SizedBox(height: 24),
                  _buildValidation(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBasicProperties(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Basic', style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
        )),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: node.name,
          decoration: const InputDecoration(
            labelText: 'Node Name',
            hintText: 'Enter name...',
            isDense: true,
          ),
          onChanged: (v) {
            node.name = v;
            onChanged();
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: node.id.toString(),
          decoration: const InputDecoration(
            labelText: 'Node ID',
            hintText: 'Auto-generated',
            isDense: true,
          ),
          readOnly: true,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Text('Position: ', style: Theme.of(context).textTheme.bodySmall),
            Text(
              '(${node.position.dx.toStringAsFixed(1)}, ${node.position.dy.toStringAsFixed(1)})',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ],
        const SizedBox(height: 4),
        Row(
          children: [
            Text('Type: ', style: Theme.of(context).textTheme.bodySmall),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: node.type.color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                node.type.label,
                style: TextStyle(
                  color: node.type.color,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      );
  }

  Widget _buildNodeSpecificProperties(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Configuration', style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
        )),
        const SizedBox(height: 12),
        switch (node.type) {
          BTNodeType.sequence => _SequenceProperties(node: node as BTSequenceNode, onChanged: onChanged),
          BTNodeType.selector => _SelectorProperties(node: node as BTSelectorNode, onChanged: onChanged),
          BTNodeType.parallel => _ParallelProperties(node: node as BTParallelNode, onChanged: onChanged),
          BTNodeType.repeater => _RepeaterProperties(node: node as BTRepeaterNode, onChanged: onChanged),
          BTNodeType.leaf => _LeafProperties(node: node as BTLeafNode, onChanged: onChanged),
          BTNodeType.wait => _WaitProperties(node: node as BTWaitNode, onChanged: onChanged),
          _ => const SizedBox.shrink(),
        },
      ],
    );
  }

  Widget _buildConnectionInfo(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Connections', style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
        )),
        const SizedBox(height: 12),
        if (node.inputPoint != null) ...[
          _ConnectionInfoRow(
            label: 'Input',
            connected: node.inputPoint!.connectedNodeId != null,
            onTap: () {},
          ),
          const SizedBox(height: 8),
        ],
        if (node.outputPoints.isNotEmpty) ...[
          for (var i = 0; i < node.outputPoints.length; i++) ...[
            _ConnectionInfoRow(
              label: 'Output ${i + 1} (${node.outputPoints[i].name})',
              connected: node.outputPoints[i].connectedNodeId != null,
              onTap: () {},
            ),
            const SizedBox(height: 8),
          ],
        ],
        if (node.inputPoint == null && node.outputPoints.isEmpty) ...[
          Text(
            'No connections',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildValidation(BuildContext context) {
    final error = node.validate();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Validation', style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
        )),
        const SizedBox(height: 12),
        if (error != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    error,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline, color: Colors.green, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Node configuration is valid',
                  style: const TextStyle(color: Colors.green),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ConnectionInfoRow extends StatelessWidget {
  final String label;
  final bool connected;
  final VoidCallback onTap;

  const _ConnectionInfoRow({
    super.key,
    required this.label,
    required this.connected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Row(
          children: [
            Icon(
              connected ? Icons.link : Icons.link_off,
              size: 16,
              color: connected ? Colors.green : Colors.grey,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: connected 
                      ? Theme.of(context).colorScheme.onSurface
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (connected)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Connected',
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SequenceProperties extends StatelessWidget {
  final BTSequenceNode node;
  final VoidCallback onChanged;

  const _SequenceProperties({
    super.key,
    required this.node,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Child Count: '),
            Expanded(
              child: Slider(
                value: node.childCount.toDouble(),
                min: 1,
                max: 10,
                divisions: 9,
                label: node.childCount.toString(),
                onChanged: (v) {
                  node.childCount = v.round();
                  onChanged();
                },
              ),
            ),
            SizedBox(
              width: 40,
              child: Text(
                node.childCount.toString(),
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SelectorProperties extends StatelessWidget {
  final BTSelectorNode node;
  final VoidCallback onChanged;

  const _SelectorProperties({
    super.key,
    required this.node,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Child Count: '),
            Expanded(
              child: Slider(
                value: node.childCount.toDouble(),
                min: 1,
                max: 10,
                divisions: 9,
                label: node.childCount.toString(),
                onChanged: (v) {
                  node.childCount = v.round();
                  onChanged();
                },
              ),
            ),
            SizedBox(
              width: 40,
              child: Text(
                node.childCount.toString(),
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ParallelProperties extends StatelessWidget {
  final BTParallelNode node;
  final VoidCallback onChanged;

  const _ParallelProperties({
    super.key,
    required this.node,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Child Count: '),
            Expanded(
              child: Slider(
                value: node.childCount.toDouble(),
                min: 1,
                max: 10,
                divisions: 9,
                label: node.childCount.toString(),
                onChanged: (v) {
                  node.childCount = v.round();
                  onChanged();
                },
              ),
            ),
            SizedBox(
              width: 40,
              child: Text(
                node.childCount.toString(),
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Text('Required Success: '),
            Expanded(
              child: Slider(
                value: node.requiredSuccess.toDouble(),
                min: 1,
                max: node.childCount.toDouble(),
                divisions: node.childCount - 1,
                label: '${node.requiredSuccess}/${node.childCount}',
                onChanged: (v) {
                  node.requiredSuccess = v.round();
                  onChanged();
                },
              ),
            ),
            SizedBox(
              width: 40,
              child: Text(
                '${node.requiredSuccess}/${node.childCount}',
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RepeaterProperties extends StatelessWidget {
  final BTRepeaterNode node;
  final VoidCallback onChanged;

  const _RepeaterProperties({
    super.key,
    required this.node,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<int?>(
          value: node.count,
          decoration: const InputDecoration(
            labelText: 'Repeat Count',
            isDense: true,
          ),
          items: [
            const DropdownMenuItem(value: null, child: Text('Infinite (until failure)')),
            ...List.generate(10, (i) => DropdownMenuItem(
              value: i + 1,
              child: Text('${i + 1} times'),
            )),
          ],
          onChanged: (v) {
            node.count = v;
            onChanged();
          },
        ),
      ],
    );
  }
}

class _LeafProperties extends StatelessWidget {
  final BTLeafNode node;
  final VoidCallback onChanged;

  const _LeafProperties({
    super.key,
    required this.node,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: node.behaviorId,
      decoration: const InputDecoration(
        labelText: 'Behavior ID',
        hintText: 'e.g., patrol, attack, move_to',
        isDense: true,
      ),
      onChanged: (v) {
        node.behaviorId = v;
        onChanged();
      },
    );
  }
}

class _WaitProperties extends StatelessWidget {
  final BTWaitNode node;
  final VoidCallback onChanged;

  const _WaitProperties({
    super.key,
    required this.node,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Duration (seconds): '),
            Expanded(
              child: Slider(
                value: node.duration,
                min: 0.1,
                max: 60.0,
                divisions: 599,
                label: '${node.duration.toStringAsFixed(1)}s',
                onChanged: (v) {
                  node.duration = v;
                  onChanged();
                },
              ),
            ),
            SizedBox(
              width: 50,
              child: Text(
                '${node.duration.toStringAsFixed(1)}s',
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ],
    );
  }
}