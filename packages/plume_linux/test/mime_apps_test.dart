import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:plume_linux/plume_linux.dart';
import 'package:test/test.dart';

const _id = 'org.atinus.plume.desktop';

void main() {
  late Directory tmp;

  setUp(() async => tmp = await Directory.systemTemp.createTemp('plume_mime_'));
  tearDown(() => tmp.delete(recursive: true));

  String path(String relative) => p.join(tmp.path, relative);

  void write(String relative, String contents) {
    final f = File(path(relative));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(contents);
  }

  String read(String relative) => File(path(relative)).readAsStringSync();

  MimeApps apps({String desktop = 'KDE'}) => MimeApps(
    environment: {'XDG_CURRENT_DESKTOP': desktop, 'HOME': tmp.path},
    configHome: path('config'),
    configDirs: [path('etc')],
    dataHome: path('data'),
    dataDirs: [path('usr')],
    refreshKdeCache: false,
  );

  void install(String id, {String root = 'data', String mime = 'x-scheme-handler/mailto;'}) =>
      write('$root/applications/$id', '[Desktop Entry]\nType=Application\nName=X\nExec=x %u\nMimeType=$mime\n');

  group('handler entry', () {
    test('missing, outdated and ok', () {
      expect(apps().handlerEntryStatus(_id, mailtoSchemeHandler), HandlerEntryStatus.missing);
      install(_id, mime: '');
      expect(apps().handlerEntryStatus(_id, mailtoSchemeHandler), HandlerEntryStatus.missingMimeType);
      install(_id);
      expect(apps().handlerEntryStatus(_id, mailtoSchemeHandler), HandlerEntryStatus.ok);
    });

    test('user entries shadow system ones and vendor dirs resolve', () {
      install(_id, root: 'usr');
      install(_id, mime: 'text/plain;');
      expect(apps().handlerEntryStatus(_id, mailtoSchemeHandler), HandlerEntryStatus.missingMimeType);
      write('usr/applications/kde/thunderbird.desktop', '[Desktop Entry]\n');
      expect(apps().findDesktopEntry('kde-thunderbird.desktop'), path('usr/applications/kde/thunderbird.desktop'));
    });
  });

  group('defaultFor', () {
    test('nothing configured', () {
      expect(apps().defaultFor(mailtoSchemeHandler), isNull);
    });

    test('follows the lookup order and skips uninstalled entries', () {
      install('firefox.desktop', root: 'usr');
      install(_id);
      write('usr/applications/mimeapps.list', '[Default Applications]\nx-scheme-handler/mailto=firefox.desktop;\n');
      expect(apps().defaultFor(mailtoSchemeHandler), 'firefox.desktop');

      write('config/mimeapps.list', '[Default Applications]\nx-scheme-handler/mailto=gone.desktop;$_id;\n');
      expect(apps().defaultFor(mailtoSchemeHandler), _id);

      write('config/kde-mimeapps.list', '[Default Applications]\nx-scheme-handler/mailto=firefox.desktop\n');
      expect(apps().defaultFor(mailtoSchemeHandler), 'firefox.desktop');
      // Another desktop does not read KDE's list.
      expect(apps(desktop: 'Hyprland').defaultFor(mailtoSchemeHandler), _id);
    });

    test('ignores other sections and comments', () {
      install(_id);
      write(
        'config/mimeapps.list',
        '# x-scheme-handler/mailto=$_id;\n[Added Associations]\nx-scheme-handler/mailto=$_id;\n',
      );
      expect(apps().defaultFor(mailtoSchemeHandler), isNull);
    });
  });

  group('setDefault', () {
    test('creates the user list', () async {
      install(_id);
      await apps().setDefault(mailtoSchemeHandler, _id);
      expect(
        read('config/mimeapps.list'),
        '[Default Applications]\nx-scheme-handler/mailto=$_id;\n\n'
        '[Added Associations]\nx-scheme-handler/mailto=$_id;\n',
      );
      expect(apps().defaultFor(mailtoSchemeHandler), _id);
    });

    test('keeps everything else in place', () async {
      install(_id);
      write(
        'config/mimeapps.list',
        '[Added Associations]\n'
            'text/plain=org.kde.kwrite.desktop;\n'
            'x-scheme-handler/mailto=firefox.desktop;$_id;\n'
            '\n'
            '# managed by hand\n'
            '[Default Applications]\n'
            'text/plain=org.kde.kwrite.desktop;\n'
            'x-scheme-handler/mailto=firefox.desktop;\n'
            '\n'
            '[Removed Associations]\n'
            'x-scheme-handler/mailto=$_id;\n',
      );
      await apps().setDefault(mailtoSchemeHandler, _id);
      expect(
        read('config/mimeapps.list'),
        '[Added Associations]\n'
        'text/plain=org.kde.kwrite.desktop;\n'
        'x-scheme-handler/mailto=$_id;firefox.desktop;\n'
        '\n'
        '# managed by hand\n'
        '[Default Applications]\n'
        'text/plain=org.kde.kwrite.desktop;\n'
        'x-scheme-handler/mailto=$_id;\n'
        '\n'
        '[Removed Associations]\n',
      );
    });

    test('inserts before the blank line that ends a section', () async {
      write('config/mimeapps.list', '[Default Applications]\ntext/plain=a.desktop;\n\n[Other]\nk=v\n');
      await apps().setDefault(mailtoSchemeHandler, _id);
      expect(
        read('config/mimeapps.list'),
        startsWith('[Default Applications]\ntext/plain=a.desktop;\nx-scheme-handler/mailto=$_id;\n\n[Other]\nk=v\n'),
      );
    });

    test('overrides desktop-specific lists that name another app', () async {
      install(_id);
      write('config/kde-mimeapps.list', '[Default Applications]\nx-scheme-handler/mailto=firefox.desktop;\n');
      write('config/gnome-mimeapps.list', '[Default Applications]\nx-scheme-handler/mailto=firefox.desktop;\n');
      await apps().setDefault(mailtoSchemeHandler, _id);
      expect(read('config/kde-mimeapps.list'), contains('x-scheme-handler/mailto=$_id;'));
      // Only the current desktop's list is touched.
      expect(read('config/gnome-mimeapps.list'), contains('=firefox.desktop;'));
      expect(apps().defaultFor(mailtoSchemeHandler), _id);
    });

    test('writes through a symlinked list', () async {
      write('dotfiles/mimeapps.list', '[Default Applications]\n');
      Directory(path('config')).createSync(recursive: true);
      Link(path('config/mimeapps.list')).createSync(path('dotfiles/mimeapps.list'));
      await apps().setDefault(mailtoSchemeHandler, _id);
      expect(FileSystemEntity.isLinkSync(path('config/mimeapps.list')), isTrue);
      expect(read('dotfiles/mimeapps.list'), contains('x-scheme-handler/mailto=$_id;'));
    });
  });

  test('environment defaults follow the base directory spec', () {
    final a = MimeApps(environment: {'HOME': '/home/u', 'XDG_CONFIG_HOME': 'relative', 'XDG_DATA_DIRS': ''});
    expect(a.configHome, '/home/u/.config');
    expect(a.configDirs, ['/etc/xdg']);
    expect(a.dataHome, '/home/u/.local/share');
    expect(a.dataDirs, ['/usr/local/share', '/usr/share']);
    expect(a.desktops, isEmpty);
    expect(MimeApps(environment: {'XDG_CURRENT_DESKTOP': 'ubuntu:GNOME'}).desktops, ['ubuntu', 'gnome']);
  });
}
