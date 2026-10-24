import 'package:dbus/dbus.dart';

DBusIntrospectArgument _in(String type, String name) => DBusIntrospectArgument(
  DBusSignature(type),
  DBusArgumentDirection.in_,
  name: name,
);

DBusIntrospectArgument _out(String type, String name) => DBusIntrospectArgument(
  DBusSignature(type),
  DBusArgumentDirection.out,
  name: name,
);

DBusIntrospectProperty _prop(String name, String type) =>
    DBusIntrospectProperty(
      name,
      DBusSignature(type),
      access: DBusPropertyAccess.read,
    );

DBusIntrospectSignal _signal(
  String name, [
  List<(String, String)> args = const [],
]) => DBusIntrospectSignal(
  name,
  args: [
    for (final (type, n) in args)
      DBusIntrospectArgument(
        DBusSignature(type),
        DBusArgumentDirection.out,
        name: n,
      ),
  ],
);

/// `org.kde.StatusNotifierItem` as implemented by KDE (plus the
/// `ProvideXdgActivationToken` extension).
final statusNotifierItemInterface = DBusIntrospectInterface(
  'org.kde.StatusNotifierItem',
  methods: [
    DBusIntrospectMethod('ContextMenu', args: [_in('i', 'x'), _in('i', 'y')]),
    DBusIntrospectMethod('Activate', args: [_in('i', 'x'), _in('i', 'y')]),
    DBusIntrospectMethod(
      'SecondaryActivate',
      args: [_in('i', 'x'), _in('i', 'y')],
    ),
    DBusIntrospectMethod(
      'Scroll',
      args: [_in('i', 'delta'), _in('s', 'orientation')],
    ),
    DBusIntrospectMethod(
      'ProvideXdgActivationToken',
      args: [_in('s', 'token')],
    ),
  ],
  signals: [
    _signal('NewTitle'),
    _signal('NewIcon'),
    _signal('NewAttentionIcon'),
    _signal('NewOverlayIcon'),
    _signal('NewToolTip'),
    _signal('NewStatus', [('s', 'status')]),
  ],
  properties: [
    _prop('Category', 's'),
    _prop('Id', 's'),
    _prop('Title', 's'),
    _prop('Status', 's'),
    _prop('WindowId', 'i'),
    _prop('IconThemePath', 's'),
    _prop('Menu', 'o'),
    _prop('ItemIsMenu', 'b'),
    _prop('IconName', 's'),
    _prop('IconPixmap', 'a(iiay)'),
    _prop('OverlayIconName', 's'),
    _prop('OverlayIconPixmap', 'a(iiay)'),
    _prop('AttentionIconName', 's'),
    _prop('AttentionIconPixmap', 'a(iiay)'),
    _prop('AttentionMovieName', 's'),
    _prop('ToolTip', '(sa(iiay)ss)'),
  ],
);

/// `com.canonical.dbusmenu` version 3.
final dbusMenuInterface = DBusIntrospectInterface(
  'com.canonical.dbusmenu',
  methods: [
    DBusIntrospectMethod(
      'GetLayout',
      args: [
        _in('i', 'parentId'),
        _in('i', 'recursionDepth'),
        _in('as', 'propertyNames'),
        _out('u', 'revision'),
        _out('(ia{sv}av)', 'layout'),
      ],
    ),
    DBusIntrospectMethod(
      'GetGroupProperties',
      args: [
        _in('ai', 'ids'),
        _in('as', 'propertyNames'),
        _out('a(ia{sv})', 'properties'),
      ],
    ),
    DBusIntrospectMethod(
      'GetProperty',
      args: [_in('i', 'id'), _in('s', 'name'), _out('v', 'value')],
    ),
    DBusIntrospectMethod(
      'Event',
      args: [
        _in('i', 'id'),
        _in('s', 'eventId'),
        _in('v', 'data'),
        _in('u', 'timestamp'),
      ],
    ),
    DBusIntrospectMethod(
      'EventGroup',
      args: [_in('a(isvu)', 'events'), _out('ai', 'idErrors')],
    ),
    DBusIntrospectMethod(
      'AboutToShow',
      args: [_in('i', 'id'), _out('b', 'needUpdate')],
    ),
    DBusIntrospectMethod(
      'AboutToShowGroup',
      args: [
        _in('ai', 'ids'),
        _out('ai', 'updatesNeeded'),
        _out('ai', 'idErrors'),
      ],
    ),
  ],
  signals: [
    _signal('ItemsPropertiesUpdated', [
      ('a(ia{sv})', 'updatedProps'),
      ('a(ias)', 'removedProps'),
    ]),
    _signal('LayoutUpdated', [('u', 'revision'), ('i', 'parent')]),
    _signal('ItemActivationRequested', [('i', 'id'), ('u', 'timestamp')]),
  ],
  properties: [
    _prop('Version', 'u'),
    _prop('TextDirection', 's'),
    _prop('Status', 's'),
    _prop('IconThemePath', 'as'),
  ],
);
