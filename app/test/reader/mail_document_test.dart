import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:plume/src/ui/reader/mail_document.dart';

void main() {
  test('puts the content security policy first, after a doctype', () {
    final doc = buildMailDocument('<!DOCTYPE html><html><head></head><body>Hi</body></html>', allowRemote: false);
    expect(doc.html, startsWith('<!DOCTYPE html><meta http-equiv="Content-Security-Policy"'));
    expect(doc.html, contains('img-src data: plume:;'));

    final fragment = buildMailDocument('<p>Hi</p>', allowRemote: false);
    expect(fragment.html, startsWith('<meta http-equiv="Content-Security-Policy"'));
  });

  test('allows remote content in the policy only when asked', () {
    final doc = buildMailDocument('<p>Hi</p>', allowRemote: true);
    expect(doc.html, contains('img-src data: plume: https: http:;'));
  });

  test('blocks remote images, keeping their size, and drops tracking pixels', () {
    final doc = buildMailDocument(
      '<img src="https://example.com/hero.png" width="600" height="120" loading="lazy">'
      '<img src="https://example.com/open.gif" width="1" height="1">'
      '<img src="https://example.com/px.gif" style="width:1px;height:1px">',
      allowRemote: false,
    );
    expect(doc.hasRemoteContent, isTrue);
    expect(doc.html, isNot(contains('example.com')));
    expect(doc.html, contains("width='600' height='120'"));
    expect(doc.html, contains('data-plume-blocked'));
    expect(doc.html, isNot(contains('loading=')));
  });

  test('does not count tracking pixels as remote content', () {
    final doc = buildMailDocument('<p>Hi</p><img src="https://t.example/o.gif" width="1" height="1">', allowRemote: false);
    expect(doc.hasRemoteContent, isFalse);
  });

  test('keeps remote images when allowed', () {
    final doc = buildMailDocument('<img src="https://example.com/hero.png" width="600">', allowRemote: true);
    expect(doc.html, contains('src="https://example.com/hero.png"'));
  });

  test('inlines cid: parts, matching Content-IDs loosely', () {
    final bytes = Uint8List.fromList([1, 2, 3]);
    expect(referencedContentIds('<img src="cid:Logo%40x"><td background="cid:bg@x">'), {'logo@x', 'bg@x'});
    final doc = buildMailDocument(
      '<img src="cid:Logo%40x"><td background="cid:bg@x">',
      allowRemote: false,
      inlineParts: {
        normalizeContentId('<logo@x>'): (mimeType: 'image/png', bytes: bytes),
        'bg@x': (mimeType: 'image/gif', bytes: bytes),
      },
    );
    expect(doc.html, contains('src="data:image/png;base64,AQID"'));
    expect(doc.html, contains('background="data:image/gif;base64,AQID"'));
  });

  test('removes scripts, refreshes and charset declarations', () {
    final doc = buildMailDocument(
      '<meta http-equiv="refresh" content="0;url=https://x"><meta charset="windows-1252">'
      '<script>alert(1)</script><p>Hi</p>',
      allowRemote: false,
    );
    expect(doc.html, isNot(contains('alert')));
    expect(doc.html, isNot(contains('refresh')));
    expect(doc.html, isNot(contains('windows-1252')));
  });

  test('lays designed mail out in its light colour scheme', () {
    final doc = buildMailDocument(
      '<style>@media (prefers-color-scheme: dark) { a { color: white } } '
      '@media (prefers-color-scheme: light) { a { color: black } }</style>',
      allowRemote: false,
    );
    expect(doc.html, contains('@media (max-width: 0px) { a { color: white } }'));
    expect(doc.html, contains('@media (min-width: 0px) { a { color: black } }'));
  });
}
