import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'bt_nodes.dart';
import 'bt_graph_controller.dart';
import 'bt_connections.dart';

typedef OnNodeSelected = void Function(BTNodeData? node);
typedef OnNodeDeleted = void Function(BTNodeData node);

class BTGraphCanvas extends StatefulWidget {
  final BTGraphController controller;
  final OnNodeSelected onNodeSelected;
  final OnNodeDeleted onNodeDeleted;
  final BTNodeData? selectedNode;

  const BTGraphCanvas({
    super.key,
    required this.controller,
    required this.onNodeSelected,
    required this.onNodeDeleted,
    this.selectedNode,
  });

  @override
  State<BTGraphCanvas> createState() => _BTGraphCanvasState();
}

class _BTGraphCanvasState extends State<BTGraphCanvas> {
  final TransformationController _transformationController = TransformationController();
  double _zoom = 1.0;
  Offset _panOffset = Offset.zero;
  
  bool _isConnecting = false;
  int? _connectFromNodeId;
  int? _connectFromPointIndex;
  Offset? _connectCurrentPos;
  
  BTNodeData? _draggingNode;
  Offset? _dragStartPosition;
  
  bool _isSelecting = false;
  Offset? _selectionStart;
  Offset? _selectionEnd;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _handlePanStart(DragStartDetails details) {
    final localPos = _getLocalPosition(details.localPosition);
    
    final hitPoint = _hitTestConnectionPoint(localPos);
    if (hitPoint != null) {
      _startConnection(hitPoint.nodeId, hitPoint.pointIndex, localPos);
      return;
    }
    
    final hitNode = _hitTestNode(localPos);
    if (hitNode != null) {
      _startDrag(hitNode, localPos);
      return;
    }
    
    _startSelection(localPos);
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    final localPos = _getLocalPosition(details.localPosition);
    
    if (_isConnecting) {
      setState(() {
        _connectCurrentPos = localPos;
      });
      return;
    }
    
    if (_draggingNode != null) {
      _updateDrag(localPos);
      return;
    }
    
    if (_isSelecting) {
      setState(() {
        _selectionEnd = localPos;
      });
      return;
    }
    
    _panOffset += details.delta;
    _transformationController.value = Matrix4.identity()
      ..translate(_panOffset.dx, _panOffset.dy)
      ..scale(_zoom);
  }

  void _handlePanEnd(DragEndDetails details) {
    final localPos = _getLocalPosition(details.localPosition);
    
    if (_isConnecting) {
      _endConnection(localPos);
      return;
    }
    
    if (_draggingNode != null) {
      _endDrag();
      return;
    }
    
    if (_isSelecting) {
      _endSelection();
      return;
    }
  }

  void _handlePanCancel() {
    _cancelConnection();
    _cancelDrag();
    _cancelSelection();
  }

  void _startConnection(int nodeId, int pointIndex, Offset pos) {
    setState(() {
      _isConnecting = true;
      _connectFromNodeId = nodeId;
      _connectFromPointIndex = pointIndex;
      _connectCurrentPos = pos;
    });
  }

  void _endConnection(Offset pos) {
    final hitPoint = _hitTestConnectionPoint(pos);
    if (hitPoint != null && hitPoint.nodeId != _connectFromNodeId) {
      widget.controller.connectionManager.connect(
        fromNodeId: _connectFromNodeId!,
        fromPointIndex: _connectFromPointIndex!,
        toNodeId: hitPoint.nodeId,
        toPointIndex: hitPoint.pointIndex,
      );
    }
    _cancelConnection();
  }

  void _cancelConnection() {
    setState(() {
      _isConnecting = false;
      _connectFromNodeId = null;
      _connectFromPointIndex = null;
      _connectCurrentPos = null;
    });
  }

  void _startDrag(BTNodeData node, Offset pos) {
    setState(() {
      _draggingNode = node;
      _dragStartPosition = pos;
      node.selected = true;
    });
    widget.onNodeSelected(node);
    widget.controller.moveToFront(node.id);
  }

  void _updateDrag(Offset pos) {
    if (_draggingNode == null || _dragStartPosition == null) return;
    
    final delta = (pos - _dragStartPosition!) / _zoom;
    setState(() {
      _draggingNode!.position += delta;
    });
  }

  void _endDrag() {
    setState(() {
      _draggingNode = null;
      _dragStartPosition = null;
    });
  }

  void _cancelDrag() {
    setState(() {
      _draggingNode = null;
      _dragStartPosition = null;
    });
  }

  void _startSelection(Offset pos) {
    setState(() {
      _isSelecting = true;
      _selectionStart = pos;
      _selectionEnd = pos;
      widget.onNodeSelected(null);
    });
  }

  void _endSelection() {
    if (_selectionStart != null && _selectionEnd != null) {
      final rect = Rect.fromPoints(_selectionStart!, _selectionEnd!);
      for (final node in widget.controller.nodes.values) {
        final nodeRect = _getNodeRect(node);
        if (rect.overlaps(nodeRect)) {
          node.selected = true;
        } else {
          node.selected = false;
        }
      }
    }
    setState(() {
      _isSelecting = false;
      _selectionStart = null;
      _selectionEnd = null;
    });
  }

  void _cancelSelection() {
    setState(() {
      _isSelecting = false;
      _selectionStart = null;
      _selectionEnd = null;
    });
  }

  Offset _getLocalPosition(Offset globalPos) {
    final renderBox = context.findRenderObject() as RenderBox;
    final localPos = renderBox.globalToLocal(globalPos);
    return (localPos - _panOffset) / _zoom;
  }

  void _handleScale(ScaleUpdateDetails details) {
    if (details.pointerCount == 2) {
      setState(() {
        _zoom = (_zoom * details.scale).clamp(0.1, 5.0);
        _transformationController.value = Matrix4.identity()
          ..translate(_panOffset.dx, _panOffset.dy)
          ..scale(_zoom);
      });
    }
  }

  _HitTestResult? _hitTestNode(Offset pos) {
    final nodes = widget.controller.getNodesInOrder().reversed;
    for (final node in nodes) {
      final rect = _getNodeRect(node);
      if (rect.contains(pos)) {
        return _HitTestResult.node(node.id);
      }
    }
    return null;
  }

  _HitTestResult? _hitTestConnectionPoint(Offset pos) {
    const pointRadius = 12.0;
    for (final node in widget.controller.nodes.values) {
      if (node.inputPoint != null) {
        final pointPos = _getInputPointPosition(node);
        if ((pointPos - pos).distance < pointRadius) {
          return _HitTestResult.inputPoint(node.id, 0);
        }
      }
      
      for (var i = 0; i < node.outputPoints.length; i++) {
        final pointPos = _getOutputPointPosition(node, i);
        if ((pointPos - pos).distance < pointRadius) {
          return _HitTestResult.outputPoint(node.id, i);
        }
      }
    }
    return null;
  }

  Offset _getInputPointPosition(BTNodeData node) {
    final rect = _getNodeRect(node);
    return Offset(rect.left, rect.top + rect.height / 2);
  }

  Offset _getOutputPointPosition(BTNodeData node, int index) {
    final rect = _getNodeRect(node);
    if (node.outputPoints.length == 1) {
      return Offset(rect.right, rect.top + rect.height / 2);
    }
    final spacing = rect.height / (node.outputPoints.length + 1);
    return Offset(rect.right, rect.top + spacing * (index + 1));
  }

  Rect _getNodeRect(BTNodeData node) {
    return Rect.fromLTWH(
      node.position.dx,
      node.position.dy,
      200,
      _getNodeHeight(node),
    );
  }

  double _getNodeHeight(BTNodeData node) {
    const headerHeight = 40.0;
    const pointHeight = 28.0;
    final pointCount = math.max(
      node.outputPoints.length,
      node.inputPoint != null ? 1 : 0,
    );
    return headerHeight + pointCount * pointHeight;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          if (event.kind == PointerDeviceKind.mouse) {
            final ctrlPressed = HardwareKeyboard.instance.isControlPressed;
            if (ctrlPressed) {
              setState(() {
                final zoomFactor = event.scrollDelta.dy < 0 ? 1.1 : 0.9;
                _zoom = (_zoom * zoomFactor).clamp(0.1, 5.0);
                _transformationController.value = Matrix4.identity()
                  ..translate(_panOffset.dx, _panOffset.dy)
                  ..scale(_zoom);
              });
            } else {
              setState(() {
                _panOffset += Offset(-event.scrollDelta.dx, -event.scrollDelta.dy);
                _transformationController.value = Matrix4.identity()
                  ..translate(_panOffset.dx, _panOffset.dy)
                  ..scale(_zoom);
              });
            }
          }
        }
      },
      child: GestureDetector(
        onPanStart: _handlePanStart,
        onPanUpdate: _handlePanUpdate,
        onPanEnd: _handlePanEnd,
        onPanCancel: _handlePanCancel,
        onScaleStart: (_) {},
        onScaleUpdate: _handleScale,
        onScaleEnd: (_) {},
        child: Stack(
          children: [
            CustomPaint(
              size: Size.infinite,
              painter: _GridPainter(zoom: _zoom, panOffset: _panOffset),
            ),
            CustomPaint(
              size: Size.infinite,
              painter: _ConnectionsPainter(
                controller: widget.controller,
                zoom: _zoom,
                panOffset: _panOffset,
                connectingFrom: _isConnecting
                    ? (_connectFromNodeId!, _connectFromPointIndex!, _connectCurrentPos!)
                    : null,
              ),
            ),
            if (_isSelecting && _selectionStart != null && _selectionEnd != null)
              CustomPaint(
                size: Size.infinite,
                painter: _SelectionBoxPainter(
                  start: _selectionStart!,
                  end: _selectionEnd!,
                  zoom: _zoom,
                  panOffset: _panOffset,
                ),
              ),
            ...widget.controller.getNodesInOrder().map((node) {
              return _NodeWidget(
                key: ValueKey(node.id),
                node: node,
                zoom: _zoom,
                panOffset: _panOffset,
                isSelected: widget.selectedNode == node,
                onTap: () {
                  widget.onNodeSelected(node);
                  widget.controller.moveToFront(node.id);
                },
                onDelete: () => widget.onNodeDeleted(node),
                onDragStart: (pos) => _startDrag(node, pos),
                onConnectStart: (pointIndex, pos) => _startConnection(node.id, pointIndex, pos),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _HitTestResult {
  final int nodeId;
  final int pointIndex;
  final bool isInput;

  _HitTestResult.node(this.nodeId)
      : pointIndex = -1,
        isInput = false;

  _HitTestResult.inputPoint(this.nodeId, this.pointIndex)
      : isInput = true;

  _HitTestResult.outputPoint(this.nodeId, this.pointIndex)
      : isInput = false;
}

class _GridPainter extends CustomPainter {
  final double zoom;
  final Offset panOffset;

  _GridPainter({required this.zoom, required this.panOffset});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.03)
      ..strokeWidth = 1 / zoom;

    const gridSize = 50.0;
    final scaledGridSize = gridSize * zoom;
    
    final startX = (-panOffset.dx / zoom).floorToDouble();
    final startY = (-panOffset.dy / zoom).floorToDouble();
    final endX = startX + size.width / zoom;
    final endY = startY + size.height / zoom;

    for (double x = (startX / gridSize).floor() * gridSize; x <= endX; x += gridSize) {
      final screenX = (x * zoom + panOffset.dx);
      canvas.drawLine(
        Offset(screenX, 0),
        Offset(screenX, size.height),
        paint,
      );
    }

    for (double y = (startY / gridSize).floor() * gridSize; y <= endY; y += gridSize) {
      final screenY = (y * zoom + panOffset.dy);
      canvas.drawLine(
        Offset(0, screenY),
        Offset(size.width, screenY),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate is _GridPainter &&
        (oldDelegate.zoom != zoom || oldDelegate.panOffset != panOffset);
  }
}

class _ConnectionsPainter extends CustomPainter {
  final BTGraphController controller;
  final double zoom;
  final Offset panOffset;
  final (int, int, Offset)? connectingFrom;

  _ConnectionsPainter({
    required this.controller,
    required this.zoom,
    required this.panOffset,
    this.connectingFrom,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = 2 / zoom
      ..style = PaintingStyle.stroke;

    final selectedPaint = Paint()
      ..color = Colors.cyanAccent
      ..strokeWidth = 3 / zoom
      ..style = PaintingStyle.stroke;

    for (final conn in controller.connectionManager.connections) {
      final fromNode = controller.nodes[conn.fromNodeId];
      final toNode = controller.nodes[conn.toNodeId];
      if (fromNode == null || toNode == null) continue;

      final fromPos = _getOutputPointPos(fromNode, conn.fromPointIndex);
      final toPos = _getInputPointPos(toNode);

      _drawBezierCurve(canvas, fromPos, toPos, paint);
    }

    if (connectingFrom != null) {
      final (fromNodeId, fromPointIndex, currentPos) = connectingFrom!;
      final fromNode = controller.nodes[fromNodeId];
      if (fromNode != null) {
        final fromPos = _getOutputPointPos(fromNode, fromPointIndex);
        final paint = Paint()
          ..color = Colors.cyanAccent.withValues(alpha: 0.5)
          ..strokeWidth = 2 / zoom
          ..style = PaintingStyle.stroke;
        _drawBezierCurve(canvas, fromPos, currentPos, paint);
      }
    }
  }

  void _drawBezierCurve(Canvas canvas, Offset from, Offset to, Paint paint) {
    final controlOffset = (to.dx - from.dx) / 2;
    final path = Path()
      ..moveTo(from.dx, from.dy)
      ..cubicTo(
        from.dx + controlOffset, from.dy,
        to.dx - controlOffset, to.dy,
        to.dx, to.dy,
      );
    canvas.drawPath(path, paint);
    
    final arrowPaint = Paint()
      ..color = paint.color
      ..style = PaintingStyle.fill;
    
    final t = 0.9;
    final p1 = _cubicPoint(from, to, controlOffset, t - 0.01);
    final p2 = _cubicPoint(from, to, controlOffset, t);
    final angle = math.atan2(p2.dy - p1.dy, p2.dx - p1.dx);
    
    final arrowSize = 8 / zoom;
    final arrowPath = Path()
      ..moveTo(p2.dx, p2.dy)
      ..lineTo(
        p2.dx - arrowSize * math.cos(angle - math.pi / 6),
        p2.dy - arrowSize * math.sin(angle - math.pi / 6),
      )
      ..lineTo(
        p2.dx - arrowSize * math.cos(angle + math.pi / 6),
        p2.dy - arrowSize * math.sin(angle + math.pi / 6),
      )
      ..close();
    canvas.drawPath(arrowPath, arrowPaint);
  }

  Offset _cubicPoint(Offset from, Offset to, double controlOffset, double t) {
    final cx1 = from.dx + controlOffset;
    final cx2 = to.dx - controlOffset;
    final u = 1 - t;
    final uu = u * u;
    final uuu = uu * u;
    final tt = t * t;
    final ttt = tt * t;
    
    return Offset(
      uuu * from.dx + 3 * uu * t * cx1 + 3 * u * tt * cx2 + ttt * to.dx,
      uuu * from.dy + 3 * uu * t * from.dy + 3 * u * tt * to.dy + ttt * to.dy,
    );
  }

  Offset _getOutputPointPos(BTNodeData node, int index) {
    final rect = _getNodeRect(node);
    if (node.outputPoints.length == 1) {
      return Offset(rect.right, rect.top + rect.height / 2);
    }
    final spacing = rect.height / (node.outputPoints.length + 1);
    return Offset(rect.right, rect.top + spacing * (index + 1));
  }

  Offset _getInputPointPos(BTNodeData node) {
    final rect = _getNodeRect(node);
    return Offset(rect.left, rect.top + rect.height / 2);
  }

  Rect _getNodeRect(BTNodeData node) {
    return Rect.fromLTWH(
      node.position.dx * zoom + panOffset.dx,
      node.position.dy * zoom + panOffset.dy,
      200 * zoom,
      _getNodeHeight(node) * zoom,
    );
  }

  double _getNodeHeight(BTNodeData node) {
    const headerHeight = 40.0;
    const pointHeight = 28.0;
    final pointCount = math.max(
      node.outputPoints.length,
      node.inputPoint != null ? 1 : 0,
    );
    return headerHeight + pointCount * pointHeight;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate is _ConnectionsPainter &&
        (oldDelegate.zoom != zoom || 
         oldDelegate.panOffset != panOffset ||
         oldDelegate.connectingFrom != connectingFrom);
  }
}

class _SelectionBoxPainter extends CustomPainter {
  final Offset start;
  final Offset end;
  final double zoom;
  final Offset panOffset;

  _SelectionBoxPainter({
    required this.start,
    required this.end,
    required this.zoom,
    required this.panOffset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromPoints(start, end);
    final screenRect = Rect.fromLTWH(
      rect.left * zoom + panOffset.dx,
      rect.top * zoom + panOffset.dy,
      rect.width * zoom,
      rect.height * zoom,
    );

    final paint = Paint()
      ..color = Colors.cyanAccent.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;
    
    final borderPaint = Paint()
      ..color = Colors.cyanAccent
      ..strokeWidth = 1 / zoom
      ..style = PaintingStyle.stroke;

    canvas.drawRect(screenRect, paint);
    canvas.drawRect(screenRect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate is _SelectionBoxPainter &&
        (oldDelegate.start != start || 
         oldDelegate.end != end ||
         oldDelegate.zoom != zoom ||
         oldDelegate.panOffset != panOffset);
  }
}