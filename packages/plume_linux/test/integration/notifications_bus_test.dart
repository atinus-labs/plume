@Tags(['dbus'])
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:dbus/dbus.dart';
import 'package:plume_linux/plume_linux.dart';
import 'package:test/test.dart';

import '../support/private_bus.dart';

/// A minimal `org.freedesktop.Notifications` server.
class FakeNotificationServer extends DBusObject {
  FakeNotificationServer({required this.capabilities, this.specVersion = '1.2'})
    : super(DesktopNotifications.objectPath);

  final List<String> capabilities;
  final String specVersion;
  final notifyCalls = <List<DBusValue>>[];
  final closeCalls = <int>[];
  int nextId = 100;

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    switch (call.name) {
      case 'GetCapabilities':
        return DBusMethodSuccessResponse([DBusArray.string(capabilities)]);
      case 'GetServerInformation':
        return DBusMethodSuccessResponse([
          const DBusString('fake'),
          const DBusString('plume-tests'),
          const DBusString('0.1'),
          DBusString(specVersion),
        ]);
      case 'Notify':
        notifyCalls.add(call.values);
        final replaces = call.values[1].asUint32();
        return DBusMethodSuccessResponse([
          DBusUint32(replaces != 0 ? replaces : nextId++),
        ]);
      case 'CloseNotification':
        final id = call.values[0].asUint32();
        closeCalls.add(id);
        await closed(id, 3);
        return DBusMethodSuccessResponse();
    }
    return DBusMethodErrorResponse.unknownMethod();
  }

  Future<void> signal(String name, List<DBusValue> values) =>
      emitSignal(DesktopNotifications.interfaceName, name, values);

  Future<void> invoke(int id, String key, {String? token}) async {
    if (token != null) {
      await signal('ActivationToken', [DBusUint32(id), DBusString(token)]);
    }
    await signal('ActionInvoked', [DBusUint32(id), DBusString(key)]);
  }

  Future<void> closed(int id, int reason) =>
      signal('NotificationClosed', [DBusUint32(id), DBusUint32(reason)]);
}

void main() {
  if (!dbusDaemonAvailable) {
    test('notifications integration', () {}, skip: 'dbus-daemon not installed');
    return;
  }

  late PrivateBus bus;

  setUp(() async => bus = await PrivateBus.start());
  tearDown(() => bus.stop());

  test('reports unavailable without a server', () async {
    final n = DesktopNotifications(bus: bus.client());
    expect(await n.initialize(), isFalse);
    expect(n.isAvailable, isFalse);
    expect(n.capabilities, isEmpty);
    expect(
      () => n.show(const NotificationRequest(summary: 'x')),
      throwsA(isA<NotificationsUnavailableException>()),
    );
    await n.dispose();
  });

  test('reports unavailable when the bus itself is unreachable', () async {
    final n = DesktopNotifications(
      bus: DBusClient(DBusAddress('unix:path=/nonexistent/plume-test-bus')),
      callTimeout: const Duration(seconds: 1),
    );
    expect(await n.initialize(), isFalse);
    await n.dispose();
  });

  group('with a server', () {
    late FakeNotificationServer server;
    late DesktopNotifications n;

    setUp(() async {
      server = FakeNotificationServer(
        capabilities: [
          'actions',
          'body',
          'body-markup',
          'persistence',
          'inline-reply',
        ],
      );
      await serve(bus, DesktopNotifications.busName, server);
      n = DesktopNotifications(bus: bus.client());
      expect(await n.initialize(), isTrue);
    });

    tearDown(() => n.dispose());

    test('reads capabilities and server info', () {
      expect(n.isAvailable, isTrue);
      expect(n.supportsActions, isTrue);
      expect(n.supportsBodyMarkup, isTrue);
      expect(n.supportsInlineReply, isTrue);
      expect(n.serverInfo!.name, 'fake');
      expect(n.serverInfo!.specVersion, '1.2');
    });

    test('sends a full Notify call', () async {
      final rgba = Uint8List(4 * 4 * 4)..fillRange(0, 64, 255);
      final id = await n.show(
        NotificationRequest(
          summary: 'Ada Lovelace',
          body: 'Re: <engine> & notes',
          appIcon: 'mail-unread',
          image: NotificationImage.rgba(rgba, width: 4, height: 4),
          actions: const [
            NotificationAction.byDefault(),
            NotificationAction('archive', 'Archive'),
          ],
          category: NotificationCategories.emailArrived,
          urgency: NotificationUrgency.normal,
          soundName: NotificationRequest.soundNewEmail,
        ),
      );
      expect(id, 100);
      final v = server.notifyCalls.single;
      expect(v[0].asString(), 'Plume');
      expect(v[2].asString(), 'mail-unread');
      expect(v[3].asString(), 'Ada Lovelace');
      expect(v[4].asString(), 'Re: &lt;engine&gt; &amp; notes');
      expect(v[5].asStringArray(), ['default', 'Open', 'archive', 'Archive']);
      final hints = v[6].asStringVariantDict();
      expect(
        hints['desktop-entry'],
        const DBusString('org.atinus.plume'),
      );
      expect(hints['category'], const DBusString('email.arrived'));
      expect(hints['urgency'], const DBusByte(1));
      expect(hints['sound-name'], const DBusString('message-new-email'));
      expect(hints['image-data']!.signature, DBusSignature('(iiibiiay)'));
      expect(v[7].asInt32(), -1);

      // Replacing keeps the id.
      expect(
        await n.show(const NotificationRequest(summary: 'x', replacesId: 100)),
        100,
      );
    });

    test('attaches the activation token to the next ActionInvoked', () async {
      final id = await n.show(const NotificationRequest(summary: 'x'));
      final events = <NotificationEvent>[];
      final sub = n.events.listen(events.add);
      await server.invoke(id, 'default', token: 'xdg-token-123');
      await server.invoke(id, 'archive');
      await eventually(() => events.length == 2);
      final first = events[0] as NotificationActionInvoked;
      expect(first.id, id);
      expect(first.key, 'default');
      expect(first.activationToken, 'xdg-token-123');
      final second = events[1] as NotificationActionInvoked;
      expect(second.activationToken, isNull, reason: 'tokens are single-use');
      await sub.cancel();
    });

    test('ignores signals for ids it did not create', () async {
      final mine = await n.show(const NotificationRequest(summary: 'x'));
      final events = <NotificationEvent>[];
      final sub = n.events.listen(events.add);
      await server.invoke(4242, 'default', token: 'foreign');
      await server.closed(4242, 2);
      await server.signal('NotificationReplied', [
        const DBusUint32(4242),
        const DBusString('nope'),
      ]);
      await server.invoke(mine, 'default');
      await eventually(() => events.isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(events, hasLength(1));
      expect(events.single.id, mine);
      await sub.cancel();
    });

    test('closed and replied events', () async {
      final a = await n.show(const NotificationRequest(summary: 'a'));
      final b = await n.show(const NotificationRequest(summary: 'b'));
      final events = <NotificationEvent>[];
      final sub = n.events.listen(events.add);
      await server.signal('NotificationReplied', [
        DBusUint32(a),
        const DBusString('Thanks!'),
      ]);
      await server.closed(a, 2);
      await n.close(b);
      await eventually(() => events.length == 3);
      expect((events[0] as NotificationReplied).text, 'Thanks!');
      expect(
        (events[1] as NotificationClosed).reason,
        NotificationCloseReason.dismissed,
      );
      expect(events[2].id, b);
      expect(
        (events[2] as NotificationClosed).reason,
        NotificationCloseReason.closedByCall,
      );
      expect(server.closeCalls, [b]);

      // After closing, the id is no longer tracked.
      await server.invoke(a, 'default');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(events, hasLength(3));
      await sub.cancel();
    });
  });

  test('drops actions and markup escaping for minimal servers', () async {
    final server = FakeNotificationServer(capabilities: ['body']);
    await serve(bus, DesktopNotifications.busName, server);
    final n = DesktopNotifications(bus: bus.client());
    expect(await n.initialize(), isTrue);
    await n.show(
      const NotificationRequest(
        summary: 's',
        body: 'a & b',
        actions: [NotificationAction.byDefault()],
      ),
    );
    final v = server.notifyCalls.single;
    expect(v[4].asString(), 'a & b');
    expect(v[5].asStringArray(), isEmpty);
    await n.dispose();
  });

  test('handles server restarts', () async {
    final first = FakeNotificationServer(capabilities: ['body', 'actions']);
    final firstConn = await serve(bus, DesktopNotifications.busName, first);
    final n = DesktopNotifications(bus: bus.client());
    expect(await n.initialize(), isTrue);
    final id = await n.show(const NotificationRequest(summary: 'x'));
    final events = <NotificationEvent>[];
    final sub = n.events.listen(events.add);

    await firstConn.close();
    await eventually(() => !n.isAvailable);
    await eventually(() => events.isNotEmpty);
    expect(
      (events.single as NotificationClosed).reason,
      NotificationCloseReason.undefined,
    );
    expect(events.single.id, id);

    final second = FakeNotificationServer(
      capabilities: ['body', 'persistence'],
    );
    await serve(bus, DesktopNotifications.busName, second);
    await eventually(() => n.isAvailable);
    expect(n.capabilities, {'body', 'persistence'});
    await sub.cancel();
    await n.dispose();
  });
}
