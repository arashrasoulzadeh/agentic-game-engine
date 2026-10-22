import 'dart:convert';
import 'dart:io';

import 'package:engine_core/engine_core.dart';
import 'package:flutter/material.dart';

import 'graph_editor.dart';
import '../prefs/strings.dart';

/// Pixel spacing between newly-added nodes, so they don't all land on top
/// of each other before the designer drags them apart.
const _newNodeStep = 160.0;
const _nodeWidth = 160.0;
const _portDotSize = 14.0;

/// The graph editor screen (docs/studio/design.md 4.9-4.11): a canvas of draggable
/// node boxes with click-to-connect ports, a params inspector for the
/// selected node, and a validation panel. Opens and saves
/// `GraphDocument.toJson()` at [graphPath].
///
/// The canvas pans (drag the background) and zooms (pinch, scroll wheel, or the
/// +/-/fit buttons). A node follows the pointer at any zoom.
class GraphCanvasScreen extends StatefulWidget {
  final String graphPath;

  /// The kind of graph to start when [graphPath] doesn't exist yet. An existing
  /// file keeps the type it was saved with.
  final GraphType newType;

  const GraphCanvasScreen({
    super.key,
    required this.graphPath,
    this.newType = GraphType.dialogue,
  });

  @override
  State<GraphCanvasScreen> createState() => _GraphCanvasScreenState();
}

class _GraphCanvasScreenState extends State<GraphCanvasScreen> {
  late GraphEditor _editor;
  late String _savedJson;
  final TransformationController _view = TransformationController();

  /// True while a pointer is down on a node. The viewer's own pan/scale
  /// recognizer would otherwise claim the drag before the node's pan recognizer
  /// does (its slop is smaller), so the viewer is switched off for the duration
  /// and the node gets the gesture.
  bool _draggingNode = false;
  static const double _minZoom = 0.25;
  static const double _maxZoom = 2.5;
  late String _addKind;

  /// Why the last export or import failed, shown in a banner; null when fine.
  String? _toolError;

  /// The file the last successful export wrote, relative to the project.
  String? _exportedTo;

  @override
  void initState() {
    super.initState();
    final file = File(widget.graphPath);
    if (file.existsSync()) {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      _editor = GraphEditor.fromDocument(GraphDocument.fromJson(json));
    } else {
      _editor = GraphEditor(type: widget.newType);
    }
    _addKind = _editor.registry.keys.first;
    _savedJson = _encode();
  }

  @override
  void dispose() {
    _view.dispose();
    super.dispose();
  }

  /// Current zoom factor (1 = actual size).
  double get zoom => _view.value.getMaxScaleOnAxis();

  /// Zooms by [factor] about the canvas origin's current screen position, clamped to
  /// the allowed range.
  void zoomBy(double factor) {
    final target = (zoom * factor).clamp(_minZoom, _maxZoom);
    final applied = target / zoom;
    setState(
      () =>
          _view.value = _view.value.clone()
            ..scaleByDouble(applied, applied, applied, 1),
    );
  }

  /// Resets to actual size with the canvas origin at the top-left.
  void resetView() => setState(() => _view.value = Matrix4.identity());

  /// Scales and positions the view so every node is visible.
  void fitToContent(Size viewport) {
    if (_editor.nodes.isEmpty) return resetView();
    var maxX = 0.0, maxY = 0.0;
    for (final o in _editor.layout.values) {
      if (o.dx > maxX) maxX = o.dx;
      if (o.dy > maxY) maxY = o.dy;
    }
    final contentW = maxX + _nodeWidth + 40, contentH = maxY + 160;
    final scale =
        (viewport.width / contentW < viewport.height / contentH
                ? viewport.width / contentW
                : viewport.height / contentH)
            .clamp(_minZoom, 1.0);
    setState(
      () =>
          _view.value = Matrix4.identity()
            ..scaleByDouble(scale, scale, scale, 1),
    );
  }

  String _encode() =>
      const JsonEncoder.withIndent('  ').convert(_editor.document.toJson());

  bool get _dirty => _encode() != _savedJson;

  void _save() {
    final target = File(widget.graphPath);
    // A new graph lives in a graphs/ folder that may not exist yet.
    target.parent.createSync(recursive: true);
    final temp = File('${widget.graphPath}.tmp')
      ..writeAsStringSync(_encode(), flush: true);
    temp.renameSync(target.path);
    setState(() => _savedJson = _encode());
  }

  /// The project folder this graph belongs to: the parent of its `graphs/` folder,
  /// or its own folder if it lives elsewhere.
  Directory get _projectRoot {
    final parent = File(widget.graphPath).parent;
    return parent.path.split(Platform.pathSeparator).last == 'graphs'
        ? parent.parent
        : parent;
  }

  /// Compiles the graph to engine JSON and writes it to `assets/ai/<name>.json`,
  /// which a game loads with `BTNode.fromJson` / `StateMachine.fromJson`. A compile
  /// error is shown instead of writing anything.
  void _export() {
    try {
      final name = File(
        widget.graphPath,
      ).uri.pathSegments.last.replaceAll(RegExp(r'\.json$'), '');
      final json = _editor.compile(id: name, resolveTree: _resolveTree);
      if (json == null) return;
      final target = File('${_projectRoot.path}/assets/ai/$name.json')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(json)}\n',
        );
      setState(() {
        _toolError = null;
        _exportedTo = 'assets/ai/${target.uri.pathSegments.last}';
      });
    } on GraphCompileException catch (e) {
      setState(() {
        _toolError = e.message;
        _exportedTo = null;
      });
    }
  }

  /// A state's `behaviorTreeGraph`, compiled: the referenced behavior-tree graph file
  /// loaded and compiled, or null if it is missing or doesn't compile (the state is
  /// then exported without a tree).
  Map<String, dynamic>? _resolveTree(String relativePath) {
    try {
      final file = File('${_projectRoot.path}/$relativePath');
      final doc = GraphDocument.fromJson(
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
      );
      return GraphEditor.fromDocument(doc).compile();
    } on Object {
      return null;
    }
  }

  Future<void> _import() async {
    final path = await showDialog<String>(
      context: context,
      builder: (context) => const _ImportPathDialog(),
    );
    if (path == null || path.trim().isEmpty) return;
    final file = File('${_projectRoot.path}/${path.trim()}');
    String? error;
    try {
      error = _editor.importBehaviorTree(
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
      );
    } on FileSystemException {
      error = '${path.trim()} could not be read';
    } on FormatException {
      error = '${path.trim()} is not valid JSON';
    } on TypeError {
      error = '${path.trim()} is not a behavior tree';
    }
    setState(() => _toolError = error);
  }

  void _addNode() {
    final index = _editor.nodes.length;
    setState(() {
      final node = _editor.addNode(
        _addKind,
        Offset(40 + (index % 4) * _newNodeStep, 40 + (index ~/ 4) * 120),
      );
      _editor.select(node.id);
    });
  }

  void _clickPort(String nodeId, String port, {required bool isOutput}) {
    setState(() => _editor.clickPort(nodeId, port, isOutput: isOutput));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final issues = _editor.validate();
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Flexible(
              child: Text(
                widget.graphPath.split(Platform.pathSeparator).last,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_dirty)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Text('•', key: Key('graph-dirty')),
              ),
          ],
        ),
        actions: [
          IconButton(
            key: const Key('graph-save'),
            tooltip: StudioStrings.t('graph.save'),
            onPressed: _dirty ? _save : null,
            icon: const Icon(Icons.save_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          // The tools live in a scrollable row of their own, not in the AppBar:
          // inside the project window this screen gets a narrow pane, and a dozen
          // AppBar actions overflowed it.
          SingleChildScrollView(
            key: const Key('graph-toolbar'),
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: DropdownButton<String>(
                    key: const Key('graph-add-kind'),
                    value: _addKind,
                    items: [
                      for (final kind in _editor.registry.keys)
                        DropdownMenuItem(value: kind, child: Text(kind)),
                    ],
                    onChanged: (v) => setState(() => _addKind = v!),
                  ),
                ),
                IconButton(
                  key: const Key('graph-add-node'),
                  tooltip: StudioStrings.t('graph.addNode'),
                  onPressed: _addNode,
                  icon: const Icon(Icons.add_box_outlined),
                ),
                if (_editor.type != GraphType.dialogue)
                  IconButton(
                    key: const Key('graph-export'),
                    tooltip: StudioStrings.t('graph.export'),
                    onPressed: _export,
                    icon: const Icon(Icons.output),
                  ),
                if (_editor.type == GraphType.behaviorTree)
                  IconButton(
                    key: const Key('graph-import'),
                    tooltip: StudioStrings.t('graph.importTooltip'),
                    onPressed: _import,
                    icon: const Icon(Icons.input),
                  ),
                IconButton(
                  key: const Key('graph-zoom-out'),
                  tooltip: StudioStrings.t('graph.zoomOut'),
                  onPressed: () => zoomBy(1 / 1.25),
                  icon: const Icon(Icons.zoom_out),
                ),
                IconButton(
                  key: const Key('graph-zoom-in'),
                  tooltip: StudioStrings.t('graph.zoomIn'),
                  onPressed: () => zoomBy(1.25),
                  icon: const Icon(Icons.zoom_in),
                ),
                IconButton(
                  key: const Key('graph-zoom-fit'),
                  tooltip: StudioStrings.t('graph.fit'),
                  onPressed: () => fitToContent(MediaQuery.sizeOf(context)),
                  icon: const Icon(Icons.fit_screen_outlined),
                ),
              ],
            ),
          ),
          if (_toolError != null)
            Container(
              key: const Key('graph-tool-error'),
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: theme.colorScheme.errorContainer,
              child: Text(
                _toolError!,
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
          if (_exportedTo != null)
            Container(
              key: const Key('graph-exported'),
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: theme.colorScheme.secondaryContainer,
              child: Text('Exported to $_exportedTo'),
            ),
          if (_editor.lastError != null)
            Container(
              key: const Key('graph-port-error'),
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: theme.colorScheme.errorContainer,
              child: Text(
                _editor.lastError!,
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
          Expanded(
            child: Row(
              children: [
                Expanded(child: _canvas(context)),
                VerticalDivider(width: 1, color: theme.dividerColor),
                SizedBox(width: 280, child: _inspector(context)),
              ],
            ),
          ),
          if (issues.isNotEmpty) _validationPanel(context, issues),
        ],
      ),
    );
  }

  Widget _canvas(BuildContext context) {
    final maxX = _editor.layout.values.fold(
      600.0,
      (m, o) => o.dx > m ? o.dx : m,
    );
    final maxY = _editor.layout.values.fold(
      600.0,
      (m, o) => o.dy > m ? o.dy : m,
    );
    return ClipRect(
      child: InteractiveViewer(
        key: const Key('graph-canvas-viewer'),
        transformationController: _view,
        panEnabled: !_draggingNode,
        scaleEnabled: !_draggingNode,
        constrained: false,
        boundaryMargin: const EdgeInsets.all(2000),
        minScale: _minZoom,
        maxScale: _maxZoom,
        child: SizedBox(
          key: const Key('graph-canvas'),
          width: maxX + 240,
          height: maxY + 160,
          child: Stack(
            children: [
              CustomPaint(
                size: Size(maxX + 240, maxY + 160),
                painter: _EdgesPainter(editor: _editor),
              ),
              for (final node in _editor.nodes) _nodeBox(context, node),
            ],
          ),
        ),
      ),
    );
  }

  Widget _nodeBox(BuildContext context, GraphNode node) {
    final theme = Theme.of(context);
    final position = _editor.layout[node.id] ?? Offset.zero;
    final kind = _editor.registry[node.kind];
    final outputs = _outputPortsOf(node, kind);
    final selected = _editor.selectedNodeId == node.id;
    return Positioned(
      left: position.dx,
      top: position.dy,
      child: Listener(
        onPointerDown: (_) => setState(() => _draggingNode = true),
        onPointerUp: (_) => setState(() => _draggingNode = false),
        onPointerCancel: (_) => setState(() => _draggingNode = false),
        child: GestureDetector(
          key: Key('graph-node-${node.id}'),
          onTap: () => setState(() => _editor.select(node.id)),
          // The pointer delta is in screen pixels; the node lives in canvas units.
          onPanUpdate: (details) => setState(
            () => _editor.moveNode(node.id, position + details.delta / zoom),
          ),
          child: Container(
            width: _nodeWidth,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              border: Border.all(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.dividerColor,
                width: selected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  node.kind == node.id
                      ? node.kind
                      : '${node.kind} (${node.id})',
                  style: theme.textTheme.labelMedium,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                for (final input in kind?.inputs ?? const [])
                  _portRow(node.id, input.name, isOutput: false),
                for (final output in outputs)
                  _portRow(node.id, output, isOutput: true),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<String> _outputPortsOf(GraphNode node, NodeKind? kind) {
    if (node.kind == 'choice') {
      final choices = node.params['choices'] as List? ?? const [];
      return [for (final c in choices) (c as Map)['id'] as String];
    }
    return [for (final port in kind?.outputs ?? const []) port.name];
  }

  Widget _portRow(String nodeId, String portName, {required bool isOutput}) {
    final armed = _editor.armedOutput == (nodeId, portName);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: isOutput
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!isOutput)
            _portDot(nodeId, portName, isOutput: false, armed: armed),
          if (!isOutput) const SizedBox(width: 4),
          Text(portName, style: const TextStyle(fontSize: 11)),
          if (isOutput) const SizedBox(width: 4),
          if (isOutput)
            _portDot(nodeId, portName, isOutput: true, armed: armed),
        ],
      ),
    );
  }

  Widget _portDot(
    String nodeId,
    String portName, {
    required bool isOutput,
    required bool armed,
  }) {
    return GestureDetector(
      key: Key('graph-port-$nodeId-$portName-${isOutput ? 'out' : 'in'}'),
      onTap: () => _clickPort(nodeId, portName, isOutput: isOutput),
      child: Container(
        width: _portDotSize,
        height: _portDotSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: armed
              ? Colors.amber
              : (isOutput ? Colors.lightBlue : Colors.green),
        ),
      ),
    );
  }

  Widget _inspector(BuildContext context) {
    final nodeId = _editor.selectedNodeId;
    if (nodeId == null) {
      return Center(
        key: Key('graph-no-selection'),
        child: Text(StudioStrings.t('graph.selectNode')),
      );
    }
    final node = _editor.nodeById(nodeId);
    if (node == null) return const SizedBox.shrink();
    final kind = _editor.registry[node.kind];
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(node.kind, style: Theme.of(context).textTheme.titleMedium),
          Text(node.id, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              children: [
                for (final field in kind?.paramsSchema ?? const [])
                  _paramField(node, field),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _paramField(GraphNode node, FieldSchema field) {
    final current = node.params[field.name] ?? field.defaultValue;
    Widget control;
    switch (field.type) {
      case FieldType.bool:
        control = Switch(
          key: Key('graph-field-${field.name}'),
          value: current == true,
          onChanged: (v) => setState(() {
            _editor.setParams(node.id, {...node.params, field.name: v});
          }),
        );
      case FieldType.list:
      case FieldType.object:
        control = SelectableText(
          jsonEncode(current),
          key: Key('graph-field-${field.name}'),
        );
      default:
        control = TextFormField(
          key: Key('graph-field-${field.name}'),
          initialValue: current?.toString() ?? '',
          decoration: InputDecoration(labelText: field.name, isDense: true),
          onFieldSubmitted: (text) => setState(() {
            _editor.setParams(node.id, {
              ...node.params,
              field.name: field.type == FieldType.double
                  ? double.tryParse(text) ?? text
                  : text,
            });
          }),
        );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: control,
    );
  }

  Widget _validationPanel(BuildContext context, List<GraphIssue> issues) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('graph-validation-panel'),
      constraints: const BoxConstraints(maxHeight: 140),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final issue in issues)
            ListTile(
              dense: true,
              key: Key('graph-issue-${issue.nodeId}-${issue.kind}'),
              leading: Icon(
                Icons.error_outline,
                color: theme.colorScheme.error,
              ),
              title: Text(issue.message),
              onTap: issue.nodeId == null
                  ? null
                  : () => setState(() => _editor.select(issue.nodeId)),
            ),
        ],
      ),
    );
  }
}

/// Draws a line between each connected pair of ports. Port screen positions
/// are approximated from node layout rather than measured render boxes — a
/// node's a fixed width and its ports stack top to bottom in a known order,
/// so this is exact for this screen's own fixed node layout, not a general
/// "ask the render tree" solution.
class _EdgesPainter extends CustomPainter {
  final GraphEditor editor;

  const _EdgesPainter({required this.editor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x99FFFFFF)
      ..strokeWidth = 2;
    for (final edge in editor.edges) {
      final from = _portPosition(edge.fromNode, edge.fromPort, isOutput: true);
      final to = _portPosition(edge.toNode, edge.toPort, isOutput: false);
      if (from == null || to == null) continue;
      canvas.drawLine(from, to, paint);
    }
  }

  Offset? _portPosition(
    String nodeId,
    String portName, {
    required bool isOutput,
  }) {
    final base = editor.layout[nodeId];
    if (base == null) return null;
    final node = editor.nodeById(nodeId);
    if (node == null) return null;
    final kind = editor.registry[node.kind];
    final ports = isOutput
        ? (node.kind == 'choice'
              ? [
                  for (final c in (node.params['choices'] as List? ?? const []))
                    (c as Map)['id'] as String,
                ]
              : [for (final p in kind?.outputs ?? const []) p.name])
        : [for (final p in kind?.inputs ?? const []) p.name];
    final index = ports.indexOf(portName);
    if (index < 0) return null;
    // Header line + each port row before this one, matching _nodeBox's layout.
    final rowsBefore = isOutput ? (kind?.inputs.length ?? 0) + index : index;
    final y = base.dy + 24 + rowsBefore * 20 + 10;
    final x = isOutput ? base.dx + _nodeWidth - 6 : base.dx + 6;
    return Offset(x, y);
  }

  @override
  bool shouldRepaint(covariant _EdgesPainter oldDelegate) => true;
}

/// Asks for a project-relative path. Owns its text controller so it is disposed
/// with the dialog's own element, after the closing animation - disposing it from
/// the caller as soon as `showDialog` returned left the still-animating field
/// using a dead controller.
class _ImportPathDialog extends StatefulWidget {
  const _ImportPathDialog();

  @override
  State<_ImportPathDialog> createState() => _ImportPathDialogState();
}

class _ImportPathDialogState extends State<_ImportPathDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(StudioStrings.t('graph.importTitle')),
      content: TextField(
        key: const Key('graph-import-path'),
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          hintText: StudioStrings.t('graph.importHint'),
        ),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(StudioStrings.t('common.cancel')),
        ),
        TextButton(
          key: const Key('graph-import-confirm'),
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(StudioStrings.t('graph.import')),
        ),
      ],
    );
  }
}
