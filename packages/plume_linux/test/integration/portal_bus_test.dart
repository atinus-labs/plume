@Tags(['dbus'])
library;

import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:plume_linux/plume_linux.dart';
import 'package:test/test.dart';

import '../support/private_bus.dart';

/// `org.freedesktop.portal.Settings` (v2 with ReadOne, or v1 with Read only)
/// plus `org.freedesktop.portal.Background`.
class FakePortal extends DBusObject {
  FakePortal({required this.values, this.hasReadOne = true})
    : super(PortalAppearance.portalPath);

  final Map<String, DBusValue> values;
  final bool hasReadOne;
  final backgroundRequests = <Map<String, DBusValue>>[];
  bool grantAutostart = true;

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface == 'org.freedesktop.portal.Background' &&
        call.name == 'RequestBackground') {
      final options = call.values[1].asStringVariantDict();
      backgroundRequests.add(options);
      final sender = call.sender!.substring(1).replaceAll('.', '_');
      final handle = DBusObjectPath(
        '/org/freedesktop/portal/desktop/request/$sender/'
        '${options['handle_token']!.asString()}',
      );
      // Answer asynchronously, like a real portal after its dialog.
      Future<void>.delayed(const Duration(milliseconds: 30), () {
        client!.emitSignal(
          destination: call.sender,
          path: handle,
          interface: 'org.freedesktop.portal.Request',
          name: 'Response',
          values: [
            DBusUint32(grantAutostart ? 0 : 1),
            DBusDict.stringVariant({
              'background': const DBusBoolean(true),
              'autostart': DBusBoolean(
                grantAutostart && options['autostart']!.asBoolean(),
              ),
            }),
          ],
        );
      });
      return DBusMethodSuccessResponse([handle]);
    }
    if (call.interface != PortalAppearance.settingsInterface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    final ns = call.values[0].asString();
    final key = call.values[1].asString();
    final value = ns == PortalAppearance.namespace ? values[key] : null;
    switch (call.name) {
      case 'ReadOne' when hasReadOne:
        return value == null
            ? DBusMethodErrorResponse('org.freedesktop.portal.Error.NotFound')
            : DBusMethodSuccessResponse([DBusVariant(value)]);
      case 'Read':
        return value == null
            ? DBusMethodErrorResponse('org.freedesktop.portal.Error.NotFound')
            : DBusMethodSuccessResponse([DBusVariant(DBusVariant(value))]);
    }
    return DBusMethodErrorResponse.unknownMethod();
  }

  Future<void> change(String key, DBusValue value) {
    values[key] = value;
    return emitSignal(PortalAppearance.settingsInterface, 'SettingChanged', [
      const DBusString(PortalAppearance.namespace),
      DBusString(key),
      DBusVariant(value),
    ]);
  }
}

DBusStruct _rgb(double r, double g, double b) =>
    DBusStruct([DBusDouble(r), DBusDouble(g), DBusDouble(b)]);

void main() {
  if (!dbusDaemonAvailable) {
    test('portal integration', () {}, skip: 'dbus-daemon not installed');
    return;
  }

  late PrivateBus bus;
  setUp(() async => bus = await PrivateBus.start());
  tearDown(() => bus.stop());

  group('PortalAppearance', () {
    test('no portal: unavailable, no preference', () async {
      final a = PortalAppearance(bus: bus.client());
      expect(await a.initialize(), isFalse);
      expect(a.colorScheme, ColorSchemePreference.noPreference);
      expect(a.accentColor, isNull);
      expect(a.contrast, ContrastPreference.noPreference);
      await a.dispose();
    });

    for (final readOne in [true, false]) {
      test('reads values via ${readOne ? 'ReadOne' : 'legacy Read'}', () async {
        await serve(
          bus,
          PortalAppearance.portalName,
          FakePortal(
            hasReadOne: readOne,
            values: {
              'color-scheme': const DBusUint32(1),
              'accent-color': _rgb(0.2, 0.4, 0.6),
              'contrast': const DBusUint32(1),
            },
          ),
        );
        final a = PortalAppearance(bus: bus.client());
        expect(await a.initialize(), isTrue);
        expect(a.colorScheme, ColorSchemePreference.dark);
        expect(a.accentColor, const AccentColor(0.2, 0.4, 0.6));
        expect(a.accentColor!.toArgb32(), 0xFF336699);
        expect(a.contrast, ContrastPreference.high);
        await a.dispose();
      });
    }

    test('missing and out-of-range values mean unset', () async {
      await serve(
        bus,
        PortalAppearance.portalName,
        FakePortal(
          values: {
            'color-scheme': const DBusUint32(2),
            'accent-color': _rgb(-1, 0.5, 2),
          },
        ),
      );
      final a = PortalAppearance(bus: bus.client());
      expect(await a.initialize(), isTrue);
      expect(a.colorScheme, ColorSchemePreference.light);
      expect(a.accentColor, isNull);
      expect(a.contrast, ContrastPreference.noPreference);
      await a.dispose();
    });

    test('follows SettingChanged', () async {
      final portal = FakePortal(values: {'color-scheme': const DBusUint32(0)});
      await serve(bus, PortalAppearance.portalName, portal);
      final a = PortalAppearance(bus: bus.client());
      await a.initialize();
      final changes = <AppearanceSettings>[];
      a.changes.listen(changes.add);
      await portal.change('color-scheme', const DBusUint32(1));
      await portal.change('color-scheme', const DBusUint32(1)); // duplicate
      await portal.change('accent-color', _rgb(1, 0, 0));
      await portal.change('accent-color', _rgb(5, 5, 5)); // reset
      await eventually(() => changes.length == 3);
      expect(changes[0].colorScheme, ColorSchemePreference.dark);
      expect(changes[1].accentColor, const AccentColor(1, 0, 0));
      expect(changes[2].accentColor, isNull);
      expect(a.current, changes.last);
      await a.dispose();
    });
  });

  group('Autostart in Flatpak', () {
    late Directory tmp;
    setUp(() async => tmp = await Directory.systemTemp.createTemp('plume_fp_'));
    tearDown(() => tmp.delete(recursive: true));

    test('uses the Background portal', () async {
      final portal = FakePortal(values: {});
      await serve(bus, PortalAppearance.portalName, portal);
      final a = Autostart(
        executable: '/app/bin/plume',
        configHome: tmp.path,
        isFlatpak: true,
        bus: bus.client(),
        environment: DesktopEnvironment.fromEnvironment({
          'XDG_CURRENT_DESKTOP': 'GNOME',
        }),
      );
      expect(await a.isEnabled(), isFalse);
      await a.enable();
      expect(await a.isEnabled(), isTrue);
      final req = portal.backgroundRequests.single;
      expect(req['autostart'], const DBusBoolean(true));
      expect(req['commandline']!.asStringArray(), [
        '/app/bin/plume',
        '--background',
      ]);
      expect(
        File(a.desktopFilePath).existsSync(),
        isFalse,
        reason: 'the portal writes the host-side file',
      );

      await a.disable();
      expect(await a.isEnabled(), isFalse);
      expect(
        portal.backgroundRequests.last['autostart'],
        const DBusBoolean(false),
      );

      portal.grantAutostart = false;
      await expectLater(a.enable(), throwsA(isA<AutostartException>()));
      expect(await a.isEnabled(), isFalse);
    });
  });
}
