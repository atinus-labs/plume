/// The small pages shown in the browser tab at the end of sign-in.
library;

String successPage({required String email}) => _page(
      title: 'Signed in to Plume',
      icon: _checkIcon,
      heading: "You're signed in",
      lines: ['Plume can now access ${_escape(email)}.', 'You can close this tab and return to Plume.'],
      tone: 'ok',
    );

String failurePage({required String reason}) => _page(
      title: 'Sign-in failed',
      icon: _crossIcon,
      heading: 'Sign-in did not complete',
      lines: [_escape(reason), 'You can close this tab and return to Plume to try again.'],
      tone: 'error',
    );

String _escape(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&#39;');

const _checkIcon =
    '<svg viewBox="0 0 24 24" width="28" height="28" aria-hidden="true"><path fill="currentColor" d="M9 16.2 4.8 12l-1.4 1.4L9 19 21 7l-1.4-1.4z"/></svg>';
const _crossIcon =
    '<svg viewBox="0 0 24 24" width="28" height="28" aria-hidden="true"><path fill="currentColor" d="M19 6.4 17.6 5 12 10.6 6.4 5 5 6.4 10.6 12 5 17.6 6.4 19 12 13.4 17.6 19 19 17.6 13.4 12z"/></svg>';

String _page({
  required String title,
  required String icon,
  required String heading,
  required List<String> lines,
  required String tone,
}) =>
    '''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark">
<title>$title</title>
<style>
:root {
  color-scheme: light dark;
  --bg: #fef7ff; --fg: #1d1b20; --muted: #49454f;
  --ok-bg: #e8def8; --ok-fg: #4f378b; --error-bg: #f9dedc; --error-fg: #8c1d18;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #141218; --fg: #e6e0e9; --muted: #cac4d0;
    --ok-bg: #4a4458; --ok-fg: #e8def8; --error-bg: #601410; --error-fg: #f9dedc;
  }
}
* { box-sizing: border-box; }
html, body { height: 100%; margin: 0; }
body {
  display: flex; align-items: center; justify-content: center;
  background: var(--bg); color: var(--fg);
  font: 16px/1.5 system-ui, -apple-system, "Segoe UI", Roboto, Cantarell, "Noto Sans", sans-serif;
  -webkit-font-smoothing: antialiased;
}
main { max-width: 26rem; padding: 2rem; text-align: center; }
.icon {
  width: 64px; height: 64px; margin: 0 auto 1.5rem; border-radius: 22px;
  display: flex; align-items: center; justify-content: center;
}
.ok { background: var(--ok-bg); color: var(--ok-fg); }
.error { background: var(--error-bg); color: var(--error-fg); }
h1 { font-size: 1.5rem; font-weight: 500; letter-spacing: -0.01em; margin: 0 0 0.75rem; }
p { margin: 0.25rem 0; color: var(--muted); overflow-wrap: anywhere; }
</style>
</head>
<body>
<main>
<div class="icon $tone">$icon</div>
<h1>$heading</h1>
${lines.map((l) => '<p>$l</p>').join('\n')}
</main>
</body>
</html>
''';
