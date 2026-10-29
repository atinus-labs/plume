/// Scripts the mail renderer runs in each document, as bodies of async
/// functions receiving `options` (a JSON string) and `documentUri`.
///
/// Messages' own scripts never run; these run through WebKit's API only.
library;

/// Shared helpers, prepended to both scripts.
const _helpers = r'''
const o = JSON.parse(options);
const doc = document, root = doc.documentElement, body = doc.body || root;
function rgba(value) {
  const m = /rgba?\(([^)]+)\)/.exec(value || '');
  if (!m) return null;
  const p = m[1].split(/[\s,\/]+/).filter(Boolean).map(parseFloat);
  return { r: p[0], g: p[1], b: p[2], a: p.length > 3 ? p[3] : 1 };
}
function backgroundOf(el) {
  const cs = getComputedStyle(el);
  const c = rgba(cs.backgroundColor);
  return { color: c && c.a > 0.05 ? c : null, image: cs.backgroundImage !== 'none' };
}
const hex = (c) => '#' + [c.r, c.g, c.b].map((v) => Math.round(v).toString(16).padStart(2, '0')).join('');
async function fontsSettled(ms) {
  void root.offsetHeight;
  if (doc.fonts) await Promise.race([doc.fonts.ready, new Promise((r) => setTimeout(r, ms))]);
}
''';

/// Decides whether the message is designed (paints its own backgrounds:
/// newsletters, receipts) or simple (text that can take the app's colours),
/// and styles it accordingly. Returns `{designed, background}`.
const prepareMailScript = '''$_helpers
const vw = innerWidth;
const isWhite = (c) => c.r > 245 && c.g > 245 && c.b > 245;

let designed = false;
for (const el of [root, body]) {
  const bg = backgroundOf(el);
  if (bg.image || (bg.color && !isWhite(bg.color))) designed = true;
}
if (!designed) {
  for (const el of body.querySelectorAll('*')) {
    const bg = backgroundOf(el);
    const r = el.getBoundingClientRect();
    if ((bg.color || bg.image) && (r.width * r.height >= 10000 || (r.width >= vw * 0.5 && r.height >= 24))) {
      designed = true;
    } else if (el.tagName === 'TABLE' && parseInt(el.getAttribute('width'), 10) >= 400) {
      designed = true; // fixed-width layout
    } else if (el.tagName === 'IMG' && r.width >= 200 && (/^https?:/i.test(el.getAttribute('src') || '') || el.hasAttribute('data-plume-blocked'))) {
      designed = true; // banner or logo from the web
    }
    if (designed) break;
  }
}
''' r'''
if (designed) {
  // Present it on its own page colour: html or body, or a wrapper that
  // spans the width at the top.
  let page = null;
  for (const el of [root, body]) {
    const c = backgroundOf(el).color;
    if (!page && c && c.a > 0.5) page = c;
  }
  if (!page) {
    let checked = 0;
    for (const el of body.querySelectorAll('table, div, center, td, section, main')) {
      if (++checked > 300) break;
      const r = el.getBoundingClientRect();
      if (r.top > 48 || r.width < vw * 0.95) continue;
      const c = backgroundOf(el).color;
      if (c && c.a > 0.5) { page = c; break; }
    }
  }
  page = page || { r: 255, g: 255, b: 255, a: 1 };
  root.style.setProperty('background-color', hex(page), 'important');
  root.style.setProperty('padding', o.padding + 'px', 'important');
  await fontsSettled(1000);
  return JSON.stringify({ designed, background: hex(page) });
}

// Simple mail takes the app's typography and colours.
const t = o.theme;
const style = doc.createElement('style');
style.textContent = `
  html, body { background: ${t.background} !important; color: ${t.text}; }
  body { font-family: "Plume Sans", sans-serif; font-size: ${o.fontSize}px; line-height: ${o.lineHeight}; }
  a:link, a:visited { color: ${t.link}; }
  img { max-width: 100%; height: auto; }
  blockquote { margin: 0 0 0 4px; padding-left: 12px; border-left: 3px solid rgba(128, 128, 128, 0.45); }
  hr { border: 0; border-top: 1px solid rgba(128, 128, 128, 0.35); }
`;
(doc.head || root).prepend(style);

// Text coloured for a white page may be unreadable on the app's: move its
// lightness away from the background, keeping the hue.
function luminance(c) {
  const f = (v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); };
  return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
}
function contrast(a, b) {
  const x = luminance(a), y = luminance(b);
  return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
}
function toHsl(c) {
  const r = c.r / 255, g = c.g / 255, b = c.b / 255;
  const max = Math.max(r, g, b), min = Math.min(r, g, b), l = (max + min) / 2;
  if (max === min) return [0, 0, l];
  const d = max - min, s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
  const h = max === r ? (g - b) / d + (g < b ? 6 : 0) : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
  return [h / 6, s, l];
}
function fromHsl([h, s, l]) {
  if (s === 0) return { r: l * 255, g: l * 255, b: l * 255 };
  const q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q;
  const f = (t) => {
    t = (t + 1) % 1;
    if (t < 1 / 6) return p + (q - p) * 6 * t;
    if (t < 1 / 2) return q;
    if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
    return p;
  };
  return { r: f(h + 1 / 3) * 255, g: f(h) * 255, b: f(h - 1 / 3) * 255 };
}
function readable(fg, bg, minimum) {
  const hsl = toHsl(fg), up = luminance(bg) < 0.5;
  let c = fg;
  for (let i = 0; i < 20 && contrast(c, bg) < minimum; i++) {
    hsl[2] = Math.min(1, Math.max(0, hsl[2] + (up ? 0.05 : -0.05)));
    c = fromHsl(hsl);
  }
  return c;
}
const page = rgba(getComputedStyle(root).backgroundColor) || { r: 255, g: 255, b: 255 };
const themeText = rgba(getComputedStyle(root).color);
function backdrop(el) {
  for (let e = el; e && e !== body && e !== root; e = e.parentElement) {
    const c = backgroundOf(e).color;
    if (c && c.a > 0.5) return c;
  }
  return page;
}
for (const el of [body, ...body.querySelectorAll('*')]) {
  if (![...el.childNodes].some((n) => n.nodeType === 3 && n.data.trim())) continue;
  const cs = getComputedStyle(el);
  const fg = rgba(cs.color);
  if (!fg || fg.a < 0.05) continue;
  const bg = backdrop(el);
  const minimum = parseFloat(cs.fontSize) >= 24 ? 3 : 4.5;
  if (contrast(fg, bg) >= minimum) continue;
  // Near-black becomes the theme's text colour; greys and colours are
  // lightened (or darkened) just enough, keeping hue and hierarchy.
  const [, saturation, lightness] = toHsl(fg);
  const plain = saturation < 0.15 && lightness < 0.25 && bg === page && themeText;
  el.style.setProperty('color', hex(plain ? themeText : readable(fg, bg, minimum)), 'important');
}
await fontsSettled(1000);
return JSON.stringify({ designed, background: t.background });
''';

/// Collects what the reader overlays on the rendered pixels, in CSS pixels
/// of the final layout: the text (to select and copy it) and the links.
/// Returns `{runs, links}`.
const collectMailScript = '''$_helpers''' r'''
await fontsSettled(1500);
const sx = scrollX, sy = scrollY;
const docW = root.scrollWidth, docH = root.scrollHeight;
const round = (v) => Math.round(v * 100) / 100;

// Visible area of each element's content, after ancestors' overflow clips.
const clips = new Map();
function clipOf(el) {
  if (!el || el === root || el === doc) return { l: 0, t: 0, r: docW, b: docH };
  let c = clips.get(el);
  if (c) return c;
  c = clipOf(el.parentElement);
  const cs = getComputedStyle(el);
  if (cs.overflowX !== 'visible' || cs.overflowY !== 'visible') {
    const r = el.getBoundingClientRect();
    c = { l: Math.max(c.l, r.left + sx), t: Math.max(c.t, r.top + sy), r: Math.min(c.r, r.right + sx), b: Math.min(c.b, r.bottom + sy) };
  }
  clips.set(el, c);
  return c;
}
function clipped(rect, el) {
  const c = clipOf(el);
  const l = Math.max(rect.left + sx, c.l), t = Math.max(rect.top + sy, c.t);
  const r = Math.min(rect.right + sx, c.r), b = Math.min(rect.bottom + sy, c.b);
  return r - l >= 1 && b - t >= 1 ? [l, t, r - l, b - t] : null;
}
const alphas = new Map();
function alphaOf(el) {
  if (!el || el.nodeType !== 1) return 1;
  let a = alphas.get(el);
  if (a === undefined) {
    a = parseFloat(getComputedStyle(el).opacity) * alphaOf(el.parentElement);
    alphas.set(el, a);
  }
  return a;
}
function visible(el, cs) {
  if (cs.visibility !== 'visible' || alphaOf(el) < 0.05) return false;
  const color = rgba(cs.color);
  return !(color && color.a < 0.05) && parseFloat(cs.fontSize) >= 3;
}

// Text runs: a text node's words on one line, with the separator to put
// before the run when copying (a line or paragraph break, or a tab between
// table cells).
const BLOCK = /^(block|list-item|table|table-cell|table-row|table-caption|flex|grid|flow-root)$/;
const PARAGRAPH = /^(P|H[1-6]|BLOCKQUOTE|UL|OL|TABLE|PRE)$/;
const blocks = new Map();
function blockOf(el) {
  for (let e = el; e && e !== root; e = e.parentElement) {
    let isBlock = blocks.get(e);
    if (isBlock === undefined) {
      isBlock = BLOCK.test(getComputedStyle(e).display);
      blocks.set(e, isBlock);
    }
    if (isBlock) return e;
  }
  return root;
}
const isCell = (e) => e !== root && getComputedStyle(e).display === 'table-cell';
function familiesOf(cs) {
  return cs.fontFamily.split(',').map((f) => f.trim().replace(/^["']|["']$/g, '')).filter((f) => f && f !== 'Plume Sans').slice(0, 4);
}

const runs = [];
const range = doc.createRange();
let lastBlock = null, lastRun = null, pendingBreak = '';
const walker = doc.createTreeWalker(body, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT);
for (let node = walker.nextNode(); node && runs.length < 20000; node = walker.nextNode()) {
  if (node.nodeType === 1) {
    if (node.tagName === 'BR') pendingBreak = '\n';
    continue;
  }
  const text = node.data;
  if (!text.trim()) continue;
  const el = node.parentElement;
  if (!el) continue;
  const cs = getComputedStyle(el);
  if (!visible(el, cs)) continue;
  const pre = /^pre/.test(cs.whiteSpace);
  const block = blockOf(el);
  let separator = pendingBreak;
  if (lastBlock && block !== lastBlock) {
    if (isCell(block) && isCell(lastBlock) && block.parentElement === lastBlock.parentElement) separator = '\t';
    else separator = PARAGRAPH.test(block.tagName) || PARAGRAPH.test(lastBlock.tagName) ? '\n\n' : '\n';
  }
  // Collapsed white space between inline elements still separates words.
  if (!pre && !separator && lastRun && /^\s/.test(text) && !/\s$/.test(lastRun.t)) lastRun.t += ' ';
  const style = { s: round(parseFloat(cs.fontSize)), w: parseInt(cs.fontWeight, 10) || 400, i: cs.fontStyle !== 'normal', f: familiesOf(cs) };
  let first = true;

  const emit = (piece, rect) => {
    const r = clipped(rect, el);
    if (!r) return;
    if (!pre) piece = piece.replace(/\s+/g, ' ');
    const sameLine = lastRun && !first && lastRun.node === node &&
      Math.abs(r[1] - lastRun.r[1]) < lastRun.r[3] * 0.5 && r[0] >= lastRun.r[0] + lastRun.r[2] - 2;
    if (sameLine) {
      lastRun.t += piece;
      const right = Math.max(lastRun.r[0] + lastRun.r[2], r[0] + r[2]);
      const bottom = Math.max(lastRun.r[1] + lastRun.r[3], r[1] + r[3]);
      lastRun.r[1] = Math.min(lastRun.r[1], r[1]);
      lastRun.r[2] = right - lastRun.r[0];
      lastRun.r[3] = bottom - lastRun.r[1];
      return;
    }
    lastRun = { node, t: piece, r, b: first ? separator : (pre ? '' : ''), ...style };
    runs.push(lastRun);
    first = false;
    separator = '';
    pendingBreak = '';
  };

  const tokens = pre ? /\S+[^\S\n]*|\n/g : /\S+\s*/g;
  for (let m = tokens.exec(text); m; m = tokens.exec(text)) {
    if (m[0] === '\n') {
      if (!first) { separator = '\n'; first = true; }
      continue;
    }
    const start = m.index, wordEnd = start + m[0].trimEnd().length;
    range.setStart(node, start);
    range.setEnd(node, wordEnd);
    const rects = range.getClientRects();
    if (rects.length === 0) continue;
    if (rects.length === 1) {
      emit(m[0], rects[0]);
      continue;
    }
    // A word broken across lines: split it where the line changes.
    let pieceStart = start, pieceRect = null;
    for (let i = start; i < wordEnd; i++) {
      range.setStart(node, i);
      range.setEnd(node, i + 1);
      const r = range.getBoundingClientRect();
      if (pieceRect && Math.abs(r.top - pieceRect.top) > pieceRect.height * 0.5) {
        emit(text.slice(pieceStart, i), pieceRect);
        pieceStart = i;
        pieceRect = null;
      }
      pieceRect = pieceRect ? new DOMRect(Math.min(pieceRect.left, r.left), Math.min(pieceRect.top, r.top),
        Math.max(pieceRect.right, r.right) - Math.min(pieceRect.left, r.left),
        Math.max(pieceRect.bottom, r.bottom) - Math.min(pieceRect.top, r.top)) : r;
    }
    if (pieceRect) emit(text.slice(pieceStart, start + m[0].length), pieceRect);
  }
  if (!first) lastBlock = block;
}

// Links, with the boxes of everything inside them (images, block children).
const links = [];
for (const a of body.querySelectorAll('a[href], area[href]')) {
  const cs = getComputedStyle(a);
  if (cs.visibility !== 'visible' || alphaOf(a) < 0.05) continue;
  const rects = [];
  for (const e of [a, ...[...a.querySelectorAll('*')].slice(0, 40)]) {
    for (const r of e.getClientRects()) {
      const c = clipped(r, e.parentElement || e);
      if (c) rects.push(c.map(round));
    }
  }
  if (rects.length) links.push({ h: a.href, t: a.title || '', r: rects.slice(0, 60) });
}

for (const run of runs) {
  delete run.node;
  run.r = run.r.map(round);
}
return JSON.stringify({ runs, links });
''';
