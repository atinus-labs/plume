// Guards the pieces desktops need to offer Plume as the email app and hand it
// `mailto:` links. Losing any of them silently breaks link handling: KDE and
// GNOME only list apps whose entry declares the scheme, and the runner drops
// arguments it does not handle.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plume_linux/plume_linux.dart';

void main() {
  final entry = File('linux/data/org.atinus.plume.desktop').readAsStringSync();
  String? value(String key) =>
      RegExp('^${RegExp.escape(key)}=(.*)\$', multiLine: true).firstMatch(entry.split('\n[').first)?.group(1);

  test('the desktop entry declares the mailto handler', () {
    expect(desktopEntryList(entry, 'MimeType'), contains(mailtoSchemeHandler));
    expect(desktopEntryList(entry, 'Categories'), contains('Email'));
    expect(value('Exec'), anyOf(contains('%u'), contains('%U')), reason: 'the link must reach the command line');
    expect(value('NoDisplay'), isNot('true'));
    expect(value('Hidden'), isNot('true'));
  });

  test('every Exec line starts with "plume" so install.sh can rewrite it', () {
    final execs = RegExp(r'^Exec=(.*)$', multiLine: true).allMatches(entry).map((m) => m.group(1)!);
    expect(execs, isNotEmpty);
    for (final exec in execs) {
      expect(exec, startsWith('plume'));
    }
  });

  test('the desktop entry passes desktop-file-validate', () {
    final result = Process.runSync('desktop-file-validate', ['linux/data/org.atinus.plume.desktop']);
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
  }, skip: _onPath('desktop-file-validate') ? false : 'desktop-file-validate is not installed');

  test('the GTK runner accepts links and forwards them to the running instance', () {
    final app = File('linux/runner/my_application.cc').readAsStringSync();
    expect(app, contains('G_APPLICATION_HANDLES_OPEN'));
    expect(app, contains('->open = my_application_open'));
    expect(app, contains('g_application_open('));
    final window = File('linux/runner/main_window.cc').readAsStringSync();
    expect(window, contains('"takeOpenUris"'));
    expect(window, contains('"onOpenUris"'));
  });
}

bool _onPath(String tool) =>
    (Platform.environment['PATH'] ?? '').split(':').any((dir) => File('$dir/$tool').existsSync());
