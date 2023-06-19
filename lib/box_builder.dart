import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:quiver/collection.dart';

//  TODO support baselines & GlobalKey
class BoxBuilder extends RenderObjectWidget {
  final BoxChildrenBuilder builder;
  final String name;

  const BoxBuilder({
    required this.builder,
    this.name = '',
    Key key = const ObjectKey(null),
  }) : super(key: key);

  @override
  RenderObjectElement createElement() {
    return BoxBuilderElement(this);
  }

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderBoxBuilder(context as BoxBuilderElement)
      ..builder = builder
      ..boxName = name;
  }

  @override
  void updateRenderObject(BuildContext context, RenderBoxBuilder renderObject) {
    renderObject
      ..builder = builder
      ..boxName = name;
  }
}

extension ListIndexComparator on List<BoxChild> {
  TopToBottom nearerToFarther() {
    final wList = List.of(map((c) => c.widget));
    return (a, b) {
      return wList.indexOf(a) - wList.indexOf(b);
    };
  }
}

typedef BoxChildrenBuilder = Size Function(
    BuildContext context,
    BoxConstraints constraints,
    BuildChild build,
    void Function(TopToBottom compareDistanceToUser) order);

typedef BuildChild = BoxChild Function(Widget widget);

typedef TopToBottom = num Function(Widget target, Widget base);

class BoxChild {
  void layout(BoxConstraints constraints, {bool parentUsesSize = true}) {
    _child.layout(constraints, parentUsesSize: parentUsesSize);
  }

  void dispose() {
    _dispose();
  }

  Size get size => _child.size;

  Offset get offset => (_child.parentData as BoxParentData).offset;

  set offset(Offset to) {
    assert(to.dx.isFinite && to.dy.isFinite);
    _parent.markNeedsPaint();
    (_child.parentData as BoxParentData).offset = to;
  }

  Element get element => _element;

  RenderBox get renderBox => element.findRenderObject() as RenderBox;

  Widget get widget => element.widget;

  Key get key => widget.key ?? _emptyKey;

  BoxChild(this._parent, this._element, this._dispose);

  final RenderObject _parent;
  final Element _element;

  RenderBox get _child => _element.renderObject as RenderBox;
  final void Function() _dispose;
}

extension BoxChildRect on BoxChild {
  Rect get rect =>
      Rect.fromPoints(offset, offset + Offset(size.width, size.height));
}

const ensureFinite = BoxConstraints(maxHeight: 1e10, maxWidth: 1e10);

// TODO support GlobalKey
class BoxBuilderElement extends RenderObjectElement {
  T updateChildrenCallback<T>(
      T Function(BuildChild, void Function(TopToBottom)) cb) {
    // prepareBuild
    {
      final emptyChildrenByKey = _oldChildren;
      assert(emptyChildrenByKey.isEmpty, 'Unexpected children.');
      _oldChildren = _children;
      _children = emptyChildrenByKey;

      _childComparator = null;
      _childrenOrder.clear();
    }

    final result = cb(buildChild, reorderChildren);

    _oldChildren.values.forEach((child) {
      updateChild(child.element, null, null);
    });
    _oldChildren.clear();
    if (_childComparator != null) _childrenOrder.sort(_childComparator);

    for (final key in _children.keys) {
      final childWithKey = _children[key];
      for (final child in childWithKey) {
        assert(!child.renderBox.debugNeedsLayout, 'child needs layout');
      }
    }

    return result;
  }

  @protected
  BoxChild buildChild(Widget widget) {
    final key = widget.key ?? _emptyKey;
    final BoxChild? reusing = () {
      BoxChild? reusing;
      for (final c in _oldChildren[key]) {
        if (Widget.canUpdate(c.widget, widget)) {
          reusing = c;
          break;
        }
      }
      if (reusing == null) return null;
      _oldChildren.remove(reusing.key, reusing);
      return reusing;
    }();

    late final BoxChild child;
    owner?.buildScope(this, () {
      final element = updateChild(reusing?.element, widget, null);
      if (element == null) return;
      child = reusing ??
          BoxChild(renderObject, element, () {
            owner?.buildScope(this, () {
              _children.remove(child.key, child);
              _childrenOrder.remove(child);
              updateChild(child.element, null, null);
            });
          });
    });

    // addChildToChildren
    {
      assert(child.key == key, 'Child should have a key.');
      _children.add(child.key, child);
      _childrenOrder.add(child);
    }

    return child;
  }

  @protected
  void reorderChildren(TopToBottom diff) {
    _childComparator = (a, b) => -diff(a.widget, b.widget).sign.toInt();
    _childrenOrder.sort(_childComparator);
    renderObject.markNeedsPaint();
  }

  Iterable<RenderBox> get childRenderObjects sync* {
    for (int index = 0; index < _childrenOrder.length; index++) {
      yield _childrenOrder[index].renderBox;
    }
  }

  Iterable<RenderBox> get childRenderObjectsInverse sync* {
    for (int index = _childrenOrder.length - 1; index >= 0; index--) {
      yield _childrenOrder[index].renderBox;
    }
  }

  BoxBuilderElement(RenderObjectWidget widget) : super(widget);

  @override
  BoxBuilder get widget => super.widget as BoxBuilder;

  Comparator<BoxChild>? _childComparator;

  Multimap<Key, BoxChild> _children = Multimap();
  final List<BoxChild> _childrenOrder =
      List.empty(growable: true); // TODO check performance

  Multimap<Key, BoxChild> _oldChildren = Multimap();

  @override
  void insertRenderObjectChild(RenderObject child, Object? slot) {
    renderObject.adoptChild(child);
  }

  @override
  void moveRenderObjectChild(
      RenderObject child, Object? oldSlot, Object? newSlot) {
    throw UnimplementedError();
  }

  @override
  void removeRenderObjectChild(RenderObject child, Object? slot) {
    renderObject.dropChild(child);
  }

  @override
  void forgetChild(Element child) {
    throw UnimplementedError('BoxBuilder does not support GlobalKey for now.');
    super.forgetChild(child);
  }

  @override
  void visitChildren(ElementVisitor visitor) {
    _children.forEach((_, child) => visitor(child.element));
  }

  @override
  void reassemble() {
    renderObject.markNeedsLayout();
    super.reassemble();
  }
}

final _emptyKey = UniqueKey();

class RenderBoxBuilder extends RenderBox {
  BoxChildrenBuilder get builder => _builder;

  set builder(BoxChildrenBuilder to) {
//    if (to == _builder) return;
    _builder = to;
    markNeedsLayout();
  }

  BoxChildrenBuilder _builder = (_, __, ___, ____) => Size.zero;

  @override
  bool hitTest(BoxHitTestResult result, {Offset position = Offset.zero}) {
    for (final child in _container.childRenderObjectsInverse) {
      final childParentData = child.parentData as BoxParentData;
      if (result.addWithPaintOffset(
        offset: childParentData.offset,
        position: position,
        hitTest: (result, transformed) {
          assert(
            transformed == position - childParentData.offset,
            'Real offset $transformed does not meet with expected offset '
            '${position - childParentData.offset} for $child.',
          );
          return child.hitTest(result, position: transformed);
        },
      )) return true;
    }
    return false;
  }

  @override
  void performLayout() {
    invokeLayoutCallback<BoxConstraints>((_) {
      var targetSize = _container.updateChildrenCallback((build, order) {
        return _builder(_container, constraints, build, order);
      });
      if (!targetSize.isFinite) {
        targetSize = ensureFinite.constrain(targetSize);
      }
      if (!sizedByParent) size = targetSize;
    });
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    return size;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    for (final child in _container.childRenderObjects) {
      context.paintChild(
          child, offset + (child.parentData as BoxParentData).offset);
    }
  }

  @override
  void visitChildren(RenderObjectVisitor visitor) {
    _container.childRenderObjects.forEach(visitor);
  }

  @override
  void detach() {
    super.detach();
    _cancelRebuildOn?.call();
    _cancelRebuildOn = null;
    visitChildren((child) => child.detach());
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    visitChildren((child) => child.attach(owner));
  }

  @override
  void redepthChildren() {
    visitChildren((child) => child.redepthChildren());
  }

  void Function()? _cancelRebuildOn;

  String boxName;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    properties..add(StringProperty('boxName', boxName));
    super.debugFillProperties(properties);
  }

  @override
  List<DiagnosticsNode> debugDescribeChildren() {
    final List<DiagnosticsNode> value = <DiagnosticsNode>[];
    visitChildren((child) => value.add(child.toDiagnosticsNode()));
    return value;
  }

  RenderBoxBuilder(this._container, [this.boxName = '']);

  final BoxBuilderElement _container;
}

extension BoxChildAsState on BoxChild {
  T? getState<T extends State>() {
    if (element is! StatefulElement) return null;
    final state = (element as StatefulElement).state;
    if (state is! T) return null;
    return state;
  }

  State? get state =>
      element is StatefulElement ? (element as StatefulElement).state : null;
}

extension BoxChildAsRenderBox on BoxChild {
  T? getRenderObject<T extends RenderBox>() {
    final renderObject = element.renderObject;
    if (renderObject is! T) return null;
    return renderObject;
  }
}
