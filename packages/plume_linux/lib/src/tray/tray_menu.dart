import 'package:dbus/dbus.dart';

/// An entry in the tray context menu (served over `com.canonical.dbusmenu`).
class TrayMenuItem {
  /// A clickable entry. [id] is reported back in `TrayMenuItemSelected`.
  ///
  /// Set [checked] to show a checkmark toggle (true/false); leave it `null`
  /// for a plain item. Non-empty [children] make this a submenu.
  const TrayMenuItem({
    required this.id,
    required this.label,
    this.enabled = true,
    this.visible = true,
    this.checked,
    this.iconName,
    this.children = const [],
  }) : isSeparator = false;

  const TrayMenuItem.separator({this.visible = true})
    : id = '',
      label = '',
      enabled = true,
      checked = null,
      iconName = null,
      children = const [],
      isSeparator = true;

  final String id;

  /// Shown verbatim (underscores are escaped, so no mnemonics).
  final String label;
  final bool enabled;
  final bool visible;
  final bool? checked;

  /// Themed icon name, e.g. `mail-unread`.
  final String? iconName;
  final List<TrayMenuItem> children;
  final bool isSeparator;
}

/// A node of the exported dbusmenu tree.
class DbusMenuNode {
  DbusMenuNode(this.id, this.key, this.properties, this.children);

  final int id;

  /// The app-level [TrayMenuItem.id] (`null` for root and separators).
  final String? key;
  final Map<String, DBusValue> properties;
  final List<DbusMenuNode> children;
}

/// What changed after [DbusMenuModel.update].
sealed class DbusMenuChange {
  const DbusMenuChange();
}

/// Nothing to signal.
final class DbusMenuUnchanged extends DbusMenuChange {
  const DbusMenuUnchanged();
}

/// Structure or property keys changed: emit `LayoutUpdated(revision, 0)`.
final class DbusMenuLayoutChanged extends DbusMenuChange {
  const DbusMenuLayoutChanged(this.revision);
  final int revision;
}

/// Same structure, only values changed: emit `ItemsPropertiesUpdated`.
final class DbusMenuPropertiesChanged extends DbusMenuChange {
  const DbusMenuPropertiesChanged(this.updated);

  /// Item id -> changed properties.
  final Map<int, Map<String, DBusValue>> updated;

  /// The `ItemsPropertiesUpdated` arguments `a(ia{sv}) a(ias)`.
  List<DBusValue> toDBus() => [
    DBusArray(
      DBusSignature('(ia{sv})'),
      updated.entries.map(
        (e) => DBusStruct([DBusInt32(e.key), DBusDict.stringVariant(e.value)]),
      ),
    ),
    DBusArray(DBusSignature('(ias)')),
  ];
}

/// The dbusmenu data model: converts [TrayMenuItem]s to a tree with stable
/// integer ids, serialises `GetLayout` / `GetGroupProperties` replies and
/// computes minimal change signals. Pure; no bus access.
class DbusMenuModel {
  DbusMenuModel() {
    _root = DbusMenuNode(0, null, _rootProperties(false), const []);
    _index();
  }

  static final layoutSignature = DBusSignature('(ia{sv}av)');

  int _revision = 1;
  late DbusMenuNode _root;
  final _byId = <int, DbusMenuNode>{};
  final _idsByKey = <String, int>{};
  int _nextId = 1;

  int get revision => _revision;
  DbusMenuNode get root => _root;

  /// The node with [id], or `null`.
  DbusMenuNode? node(int id) => _byId[id];

  /// Replaces the menu with [items] and reports what to signal.
  DbusMenuChange update(List<TrayMenuItem> items) {
    final seen = <String>{};
    final newRoot = DbusMenuNode(
      0,
      null,
      _rootProperties(items.isNotEmpty),
      _build(items, 'root', seen),
    );
    final change = _diff(_root, newRoot);
    _root = newRoot;
    _index();
    if (change is DbusMenuLayoutChanged) {
      _revision++;
      return DbusMenuLayoutChanged(_revision);
    }
    return change;
  }

  List<DbusMenuNode> _build(
    List<TrayMenuItem> items,
    String parentKey,
    Set<String> seen,
  ) {
    final nodes = <DbusMenuNode>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final String internalKey;
      if (item.isSeparator) {
        internalKey = '\u0000sep:$parentKey:$i';
      } else {
        if (item.id.isEmpty) {
          throw ArgumentError('TrayMenuItem.id must not be empty');
        }
        if (!seen.add(item.id)) {
          throw ArgumentError('Duplicate TrayMenuItem.id "${item.id}"');
        }
        internalKey = item.id;
      }
      final id = _idsByKey[internalKey] ??= _nextId++;
      nodes.add(
        DbusMenuNode(
          id,
          item.isSeparator ? null : item.id,
          itemProperties(item),
          item.isSeparator ? const [] : _build(item.children, item.id, seen),
        ),
      );
    }
    return nodes;
  }

  /// The dbusmenu properties for one item. `label`, `enabled`, `visible` and
  /// `type` are always explicit so value-only updates never need
  /// `removedProps`, which some hosts ignore.
  static Map<String, DBusValue> itemProperties(TrayMenuItem item) {
    if (item.isSeparator) {
      return {
        'type': const DBusString('separator'),
        'visible': DBusBoolean(item.visible),
      };
    }
    return {
      'type': const DBusString('standard'),
      'label': DBusString(item.label.replaceAll('_', '__')),
      'enabled': DBusBoolean(item.enabled),
      'visible': DBusBoolean(item.visible),
      if (item.iconName != null && item.iconName!.isNotEmpty)
        'icon-name': DBusString(item.iconName!),
      if (item.checked != null) ...{
        'toggle-type': const DBusString('checkmark'),
        'toggle-state': DBusInt32(item.checked! ? 1 : 0),
      },
      if (item.children.isNotEmpty)
        'children-display': const DBusString('submenu'),
    };
  }

  static Map<String, DBusValue> _rootProperties(bool hasChildren) => {
    if (hasChildren) 'children-display': const DBusString('submenu'),
  };

  void _index() {
    _byId.clear();
    void walk(DbusMenuNode n) {
      _byId[n.id] = n;
      n.children.forEach(walk);
    }

    walk(_root);
  }

  static DbusMenuChange _diff(DbusMenuNode a, DbusMenuNode b) {
    final updated = <int, Map<String, DBusValue>>{};
    bool walk(DbusMenuNode x, DbusMenuNode y) {
      if (x.id != y.id || x.children.length != y.children.length) return false;
      final xk = x.properties.keys.toSet();
      final yk = y.properties.keys.toSet();
      if (xk.length != yk.length || !xk.containsAll(yk)) return false;
      final changed = <String, DBusValue>{};
      y.properties.forEach((k, v) {
        if (x.properties[k] != v) changed[k] = v;
      });
      if (changed.isNotEmpty) updated[y.id] = changed;
      for (var i = 0; i < x.children.length; i++) {
        if (!walk(x.children[i], y.children[i])) return false;
      }
      return true;
    }

    if (!walk(a, b)) return const DbusMenuLayoutChanged(0);
    if (updated.isEmpty) return const DbusMenuUnchanged();
    return DbusMenuPropertiesChanged(updated);
  }

  /// `GetLayout(parentId, recursionDepth, propertyNames)` reply value
  /// `(ia{sv}av)`, or `null` if [parentId] is unknown.
  ///
  /// [depth] -1 means unlimited, 0 means the node without children.
  DBusStruct? layout(
    int parentId, {
    int depth = -1,
    List<String> propertyNames = const [],
  }) {
    final node = _byId[parentId];
    if (node == null) return null;
    return _layout(node, depth, propertyNames);
  }

  DBusStruct _layout(DbusMenuNode node, int depth, List<String> names) {
    final Iterable<DBusValue> children = depth == 0
        ? const <DBusValue>[]
        : node.children.map(
            // DBusArray.variant wraps each child in a variant itself.
            (c) => _layout(c, depth < 0 ? -1 : depth - 1, names),
          );
    return DBusStruct([
      DBusInt32(node.id),
      DBusDict.stringVariant(_filter(node.properties, names)),
      DBusArray.variant(children),
    ]);
  }

  static Map<String, DBusValue> _filter(
    Map<String, DBusValue> props,
    List<String> names,
  ) {
    if (names.isEmpty) return props;
    return {
      for (final n in names)
        if (props.containsKey(n)) n: props[n]!,
    };
  }

  /// `GetGroupProperties(ids, propertyNames)` reply value `a(ia{sv})`.
  /// An empty [ids] list means every item. Unknown ids are skipped.
  DBusArray groupProperties(
    List<int> ids, {
    List<String> propertyNames = const [],
  }) {
    final nodes = ids.isEmpty
        ? _byId.values
        : ids.map((id) => _byId[id]).whereType<DbusMenuNode>();
    return DBusArray(
      DBusSignature('(ia{sv})'),
      nodes.map(
        (n) => DBusStruct([
          DBusInt32(n.id),
          DBusDict.stringVariant(_filter(n.properties, propertyNames)),
        ]),
      ),
    );
  }
}
