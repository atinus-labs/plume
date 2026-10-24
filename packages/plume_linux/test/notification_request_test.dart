import 'dart:typed_data';

import 'package:dbus/dbus.dart';
import 'package:plume_linux/plume_linux.dart';
import 'package:plume_linux/src/notifications/notification_request.dart';
import 'package:test/test.dart';

const _allCaps = {
  'actions',
  'body',
  'body-markup',
  'body-hyperlinks',
  'persistence',
  'inline-reply',
};

NotifyArguments build(
  NotificationRequest r, {
  Set<String> caps = _allCaps,
  String spec = '1.2',
}) => NotifyArguments.build(
  r,
  capabilities: caps,
  appName: 'Plume',
  defaultDesktopEntry: 'org.atinus.plume',
  specVersion: spec,
);

void main() {
  group('markup', () {
    test('escapes & < > only', () {
      expect(
        escapeNotificationMarkup('Tom & Jerry <tom@example.com> "hi" \'x\''),
        'Tom &amp; Jerry &lt;tom@example.com&gt; "hi" \'x\'',
      );
      expect(escapeNotificationMarkup('plain'), 'plain');
      expect(escapeNotificationMarkup('&amp;'), '&amp;amp;');
      expect(escapeNotificationMarkup('emoji 📬 <b>'), 'emoji 📬 &lt;b&gt;');
    });

    test('strips markup to plain text', () {
      expect(
        stripNotificationMarkup(
          '<b>Bold</b> &amp; <a href="x">link</a><br/>line &#x1F4EC; &#65;',
        ),
        'Bold & link\nline 📬 A',
      );
      expect(stripNotificationMarkup('a &lt;b&gt; c'), 'a <b> c');
    });
  });

  group('NotifyArguments.build', () {
    test('escapes plain bodies on body-markup servers', () {
      final a = build(
        const NotificationRequest(summary: 'S <x>', body: 'A & B <c>'),
      );
      expect(a.body, 'A &amp; B &lt;c&gt;');
      expect(a.summary, 'S <x>', reason: 'summary is never markup');
    });

    test('passes plain bodies through without body-markup', () {
      final a = build(
        const NotificationRequest(summary: 's', body: 'A & B <c>'),
        caps: {'body'},
      );
      expect(a.body, 'A & B <c>');
    });

    test('pre-marked-up bodies pass through or get stripped', () {
      const r = NotificationRequest(
        summary: 's',
        body: '<b>Hi</b> &amp; bye',
        bodyIsMarkup: true,
      );
      expect(build(r).body, '<b>Hi</b> &amp; bye');
      expect(build(r, caps: {'body'}).body, 'Hi & bye');
    });

    test('actions are flattened and only sent with the actions capability', () {
      const r = NotificationRequest(
        summary: 's',
        actions: [
          NotificationAction.byDefault(),
          NotificationAction('archive', 'Archive'),
        ],
      );
      expect(build(r).actions, ['default', 'Open', 'archive', 'Archive']);
      expect(build(r, caps: {'body'}).actions, isEmpty);
    });

    test('standard hints', () {
      final a = build(
        const NotificationRequest(
          summary: 's',
          category: NotificationCategories.emailArrived,
          urgency: NotificationUrgency.critical,
          soundName: NotificationRequest.soundNewEmail,
          resident: true,
          transient: true,
          suppressSound: true,
        ),
      );
      expect(
        a.hints['desktop-entry'],
        const DBusString('org.atinus.plume'),
      );
      expect(a.hints['category'], const DBusString('email.arrived'));
      expect(a.hints['urgency'], const DBusByte(2));
      expect(a.hints['sound-name'], const DBusString('message-new-email'));
      expect(a.hints['resident'], const DBusBoolean(true));
      expect(a.hints['transient'], const DBusBoolean(true));
      expect(a.hints['suppress-sound'], const DBusBoolean(true));
    });

    test('desktop-entry override, extra hints win', () {
      final a = build(
        NotificationRequest(
          summary: 's',
          desktopEntry: 'other.App',
          extraHints: {
            'x-custom': const DBusString('1'),
            'category': const DBusString('im'),
          },
          category: 'email',
        ),
      );
      expect(a.hints['desktop-entry'], const DBusString('other.App'));
      expect(a.hints['x-custom'], const DBusString('1'));
      expect(a.hints['category'], const DBusString('im'));
    });

    test('image-data hint name follows the spec version', () {
      final r = NotificationRequest(
        summary: 's',
        image: NotificationImage.rgba(Uint8List(4), width: 1, height: 1),
      );
      expect(build(r).hints.keys, contains('image-data'));
      expect(build(r, spec: '1.1').hints.keys, contains('image_data'));
      expect(build(r, spec: '1.0').hints.keys, contains('icon_data'));
      expect(
        build(r).hints['image-data']!.signature,
        DBusSignature('(iiibiiay)'),
      );
    });

    test('image paths and app icons become file URIs', () {
      final a = build(
        const NotificationRequest(
          summary: 's',
          appIcon: '/opt/plume/icon 1.png',
          image: NotificationImage.path('/tmp/avatar.png'),
        ),
      );
      expect(a.appIcon, 'file:///opt/plume/icon%201.png');
      expect(a.hints['image-path'], const DBusString('file:///tmp/avatar.png'));
      expect(
        build(const NotificationRequest(summary: 's', appIcon: 'mail-unread'))
            .appIcon,
        'mail-unread',
      );
    });

    test('timeouts', () {
      expect(build(const NotificationRequest(summary: 's')).expireTimeout, -1);
      expect(
        build(const NotificationRequest(summary: 's', timeout: Duration.zero))
            .expireTimeout,
        0,
      );
      expect(
        build(
          const NotificationRequest(
            summary: 's',
            timeout: Duration(seconds: 7),
          ),
        ).expireTimeout,
        7000,
      );
    });

    test('inline reply only with the capability', () {
      const r = NotificationRequest(
        summary: 's',
        inlineReply: NotificationInlineReply(placeholder: 'Reply to Ada'),
      );
      final a = build(r);
      expect(a.actions, ['inline-reply', 'Reply']);
      expect(
        a.hints['x-kde-reply-placeholder-text'],
        const DBusString('Reply to Ada'),
      );
      expect(build(r, caps: {'actions'}).actions, isEmpty);
    });

    test('serialises to the Notify signature', () {
      final values = build(
        const NotificationRequest(summary: 's', replacesId: 42),
      ).toDBus();
      expect(values.map((v) => v.signature.value).join(), 'susssasa{sv}i');
      expect(values[1], const DBusUint32(42));
      expect(values[0], const DBusString('Plume'));
    });
  });
}
