import 'package:dbus/dbus.dart';
import 'package:plume_linux/src/tray/tray_menu.dart';
import 'package:test/test.dart';

const _menu = [
  TrayMenuItem(id: 'open', label: 'Open Plume', iconName: 'mail-unread'),
  TrayMenuItem(id: 'sync', label: 'Sync_now', enabled: false),
  TrayMenuItem.separator(),
  TrayMenuItem(id: 'notify', label: 'Notifications', checked: true),
  TrayMenuItem(
    id: 'accounts',
    label: 'Accounts',
    children: [
      TrayMenuItem(id: 'a1', label: 'ada@example.com'),
      TrayMenuItem(id: 'a2', label: 'bob@example.com', visible: false),
    ],
  ),
  TrayMenuItem(id: 'quit', label: 'Quit'),
];

Map<String, DBusValue> props(DBusStruct node) =>
    node.children[1].asStringVariantDict();

List<DBusStruct> kids(DBusStruct node) =>
    node.children[2].asVariantArray().map((v) => v as DBusStruct).toList();

void main() {
  group('DbusMenuModel', () {
    test('serialises the full layout as (ia{sv}av)', () {
      final m = DbusMenuModel()..update(_menu);
      final root = m.layout(0)!;
      expect(root.signature, DBusSignature('(ia{sv}av)'));
      expect(root.children[0], const DBusInt32(0));
      expect(props(root)['children-display'], const DBusString('submenu'));

      final items = kids(root);
      expect(items, hasLength(6));

      final open = props(items[0]);
      expect(open['label'], const DBusString('Open Plume'));
      expect(open['type'], const DBusString('standard'));
      expect(open['enabled'], const DBusBoolean(true));
      expect(open['visible'], const DBusBoolean(true));
      expect(open['icon-name'], const DBusString('mail-unread'));
      expect(open.containsKey('toggle-type'), isFalse);

      final sync = props(items[1]);
      expect(
        sync['label'],
        const DBusString('Sync__now'),
        reason: 'no mnemonic',
      );
      expect(sync['enabled'], const DBusBoolean(false));

      expect(props(items[2])['type'], const DBusString('separator'));
      expect(props(items[2]).containsKey('label'), isFalse);

      final notify = props(items[3]);
      expect(notify['toggle-type'], const DBusString('checkmark'));
      expect(notify['toggle-state'], const DBusInt32(1));

      final accounts = items[4];
      expect(props(accounts)['children-display'], const DBusString('submenu'));
      expect(kids(accounts), hasLength(2));
      expect(props(kids(accounts)[1])['visible'], const DBusBoolean(false));
    });

    test('ids are unique, non-zero and stable across updates', () {
      final m = DbusMenuModel()..update(_menu);
      final ids = <int>{};
      void walk(DbusMenuNode n) {
        expect(ids.add(n.id), isTrue);
        n.children.forEach(walk);
      }

      walk(m.root);
      expect(ids, hasLength(9)); // root + 6 + 2 children
      final quitId = m.root.children.last.id;
      expect(quitId, isNot(0));

      m.update([const TrayMenuItem(id: 'quit', label: 'Quit')]);
      expect(m.root.children.single.id, quitId);
      expect(m.node(quitId)!.key, 'quit');
    });

    test('recursion depth and property filters', () {
      final m = DbusMenuModel()..update(_menu);
      expect(kids(m.layout(0, depth: 0)!), isEmpty);
      final depth1 = m.layout(0, depth: 1)!;
      expect(kids(depth1), hasLength(6));
      expect(kids(kids(depth1)[4]), isEmpty);
      expect(kids(kids(m.layout(0)!)[4]), hasLength(2));

      final filtered = m.layout(0, propertyNames: ['label'])!;
      expect(props(kids(filtered)[0]).keys, ['label']);
      expect(props(kids(filtered)[2]), isEmpty);

      final accountsId = m.root.children[4].id;
      expect(kids(m.layout(accountsId)!), hasLength(2));
      expect(m.layout(9999), isNull);
    });

    test('group properties', () {
      final m = DbusMenuModel()..update(_menu);
      final quit = m.root.children.last.id;
      final g = m.groupProperties([quit, 12345], propertyNames: ['label']);
      expect(g.signature, DBusSignature('a(ia{sv})'));
      expect(g.children, hasLength(1));
      final s = g.children.single.asStruct();
      expect(s[0], DBusInt32(quit));
      expect(s[1].asStringVariantDict(), {'label': const DBusString('Quit')});
      expect(m.groupProperties([]).children, hasLength(9));
    });

    test('value-only changes produce ItemsPropertiesUpdated', () {
      final m = DbusMenuModel()..update(_menu);
      final rev = m.revision;
      final changed = [..._menu];
      changed[3] = const TrayMenuItem(
        id: 'notify',
        label: 'Notifications',
        checked: false,
      );
      changed[1] = const TrayMenuItem(
        id: 'sync',
        label: 'Syncing…',
        enabled: false,
      );
      final change = m.update(changed);
      expect(change, isA<DbusMenuPropertiesChanged>());
      final updated = (change as DbusMenuPropertiesChanged).updated;
      expect(updated, hasLength(2));
      expect(updated[m.root.children[3].id], {
        'toggle-state': const DBusInt32(0),
      });
      expect(updated[m.root.children[1].id], {
        'label': const DBusString('Syncing…'),
      });
      expect(m.revision, rev);
      expect(
        change.toDBus().map((v) => v.signature.value).join(),
        'a(ia{sv})a(ias)',
      );
    });

    test('identical menus are unchanged', () {
      final m = DbusMenuModel()..update(_menu);
      expect(m.update(_menu), isA<DbusMenuUnchanged>());
    });

    test('structural changes bump the revision', () {
      final m = DbusMenuModel()..update(_menu);
      final rev = m.revision;
      final change = m.update([..._menu.take(2)]);
      expect(change, isA<DbusMenuLayoutChanged>());
      expect((change as DbusMenuLayoutChanged).revision, rev + 1);
      expect(m.revision, rev + 1);

      // Adding a checkmark changes the property key set -> layout update.
      final c2 = m.update([
        const TrayMenuItem(
          id: 'open',
          label: 'Open Plume',
          iconName: 'mail-unread',
        ),
        const TrayMenuItem(
          id: 'sync',
          label: 'Sync_now',
          enabled: false,
          checked: true,
        ),
      ]);
      expect(c2, isA<DbusMenuLayoutChanged>());
    });

    test('rejects duplicate and empty ids', () {
      final m = DbusMenuModel();
      expect(
        () => m.update(const [
          TrayMenuItem(id: 'x', label: 'a'),
          TrayMenuItem(id: 'x', label: 'b'),
        ]),
        throwsArgumentError,
      );
      expect(
        () => m.update(const [TrayMenuItem(id: '', label: 'a')]),
        throwsArgumentError,
      );
    });

    test('empty menu has a childless root', () {
      final m = DbusMenuModel();
      final root = m.layout(0)!;
      expect(kids(root), isEmpty);
      expect(props(root), isEmpty);
    });
  });
}
