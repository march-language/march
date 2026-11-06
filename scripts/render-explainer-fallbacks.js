#!/usr/bin/env node
// render-explainer-fallbacks.js: the static image behind each figure of the scrolling
// explainers (docs/protocol-to-cluster.md, docs/deploy-authority.md), for a reader
// without JavaScript or a figure that failed.
//
//     node scripts/render-explainer-fallbacks.js            write docs/assets/explainer/fallback/*.svg
//     node scripts/render-explainer-fallbacks.js --check    exit 1 if a fresh render would differ
//
// Each image is drawn by the page's own code, so it cannot drift from the live figure:
// the SVG figures by their builders (figures.js), and the canvas simulations by their
// renderers (draw.js) replayed into a context that writes SVG instead of pixels. An
// <img> cannot see the page's stylesheet or its `--mx-*` variables, so every image
// carries its own background, its own colours and a style rule for each class it uses.
// The palette is the site's dark theme; the dark panel reads in the light theme too.
'use strict';
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.join(__dirname, '..');
const ASSETS = path.join(ROOT, 'docs/assets/explainer');
for (const f of ['scroll', 'story', 'rng', 'figures', 'figures-authority', 'sim-cluster', 'sim-mailbox', 'sim-release',
  'sim-topology', 'draw', 'draw-authority', 'chapters', 'chapters-authority']) {
  require(path.join(ASSETS, f + '.js'));
}
const ME = globalThis.MarchExplainer;

const PALETTE = { paper: '#07101a', ink: '#cce5f5', dim: '#3f6f94', muted: '#6b9bbe', border: '#0f2438', accent: '#ff6b5e' };
const WIDTH = 680;

// The figure rules of docs/_includes/explainer.html, with the palette in place of variables.
const STYLE = [
  `.mx-ink{fill:${PALETTE.ink}}`, `.mx-dim{fill:${PALETTE.dim}}`,
  `.mx-line{stroke:${PALETTE.dim};stroke-width:1;fill:none}`,
  `.mx-label{fill:${PALETTE.muted};font:12px system-ui,-apple-system,sans-serif}`,
  `.mx-label-strong{fill:${PALETTE.ink};font:600 13px system-ui,-apple-system,sans-serif}`,
  `.mx-mono{font-family:ui-monospace,Menlo,monospace}`,
  `.mx-srcline{fill:${PALETTE.ink}}`, `.mx-state{fill:${PALETTE.accent}}`, `.mx-fn{fill:${PALETTE.dim}}`,
  `.mx-changed{fill:${PALETTE.accent}}`,
  `.mx-cell{fill:none;stroke:${PALETTE.dim};stroke-width:1}`,
  `.mx-lit{fill:${PALETTE.ink};stroke:${PALETTE.ink}}`, `.mx-wrong{fill:${PALETTE.accent};stroke:${PALETTE.accent}}`,
  `.mx-ping{fill:none;stroke:${PALETTE.muted};stroke-width:1}`, `.mx-failed{stroke:${PALETTE.accent};stroke-width:2}`,
  `.mx-accent-text{fill:${PALETTE.accent}}`, `.mx-host{fill:none;stroke:${PALETTE.ink};stroke-width:1}`,
  `.mx-seg{fill:none;stroke:${PALETTE.dim};stroke-width:1}`, `.mx-done{fill:${PALETTE.border}}`,
  `.mx-next{stroke:${PALETTE.accent};stroke-width:2}`,
  `.mx-codeline{fill:${PALETTE.ink};font-family:ui-monospace,Menlo,monospace;white-space:pre}`,
  `.mx-off{fill:${PALETTE.dim}}`, `.mx-hl{fill:${PALETTE.ink}}`, `.mx-hlbar{fill:${PALETTE.accent}}`,
].join('');

// The module squares of docs/deploy-authority.md (figures-authority.js).
const SQUARES = [
  `.mx-sq{fill:${PALETTE.dim};stroke:none}`, `.mx-quiet{fill:none;stroke:${PALETTE.dim};stroke-width:1}`,
  `.mx-inside{fill:${PALETTE.dim}}`, `.mx-outside{fill:${PALETTE.ink}}`,
  `.mx-own{stroke:${PALETTE.accent};stroke-width:2}`, `.mx-hot{fill:${PALETTE.accent};stroke:${PALETTE.accent};stroke-width:2}`,
].join('');

const r = (n) => Math.round(n * 10) / 10;
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

// Put a builder's <svg> on a padded dark panel with its own stylesheet.
function panel(svg, pad, moreStyle) {
  const w = Number(svg.match(/ width="([\d.]+)"/)[1]), h = Number(svg.match(/ height="([\d.]+)"/)[1]);
  const inner = svg.replace(/^<svg[^>]*>/, '').replace(/<\/svg>$/, '');
  const label = (svg.match(/aria-label="([^"]*)"/) || [, ''])[1];
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${r(w + 2 * pad)}" height="${r(h + 2 * pad)}" ` +
    `viewBox="0 0 ${r(w + 2 * pad)} ${r(h + 2 * pad)}" role="img" aria-label="${label}">` +
    `<style>${STYLE}${moreStyle || ''}</style><rect width="100%" height="100%" fill="${PALETTE.paper}"/>` +
    `<g transform="translate(${pad} ${pad})">${inner}</g></svg>\n`;
}

// A stand-in for CanvasRenderingContext2D that records what draw.js draws as SVG. It
// implements only what the renderers use.
function svgContext(width, height) {
  const out = [];
  let pathD = '', arc = null, clipId = null, clips = 0, dash = '';
  const stack = [];
  const ctx = {
    fillStyle: '#000', strokeStyle: '#000', lineWidth: 1, globalAlpha: 1, font: '12px sans-serif', textAlign: 'left',
    clearRect() {}, setTransform() {},
    measureText: (t) => ({ width: String(t).length * 6.6 }),
    save() { stack.push({ clipId, alpha: ctx.globalAlpha }); },
    restore() { const s = stack.pop(); if (s) { clipId = s.clipId; ctx.globalAlpha = s.alpha; } },
    setLineDash(a) { dash = a.length ? a.join(' ') : ''; },
    beginPath() { pathD = ''; arc = null; },
    closePath() {},
    moveTo(x, y) { pathD += `M${r(x)} ${r(y)}`; },
    lineTo(x, y) { pathD += `L${r(x)} ${r(y)}`; },
    rect(x, y, w, h) { ctx._rect = [x, y, w, h]; },
    clip() {
      const [x, y, w, h] = ctx._rect; clipId = 'c' + (++clips);
      out.push(`<clipPath id="${clipId}"><rect x="${r(x)}" y="${r(y)}" width="${r(w)}" height="${r(h)}"/></clipPath>`);
    },
    arc(x, y, rad) { arc = [x, y, rad]; },
    fill() { if (arc) out.push(`<circle cx="${r(arc[0])}" cy="${r(arc[1])}" r="${r(arc[2])}" fill="${ctx.fillStyle}"${extra()}/>`); },
    stroke() {
      if (pathD) out.push(`<path d="${pathD}" fill="none" stroke="${ctx.strokeStyle}" stroke-width="${ctx.lineWidth}"` +
        `${dash ? ` stroke-dasharray="${dash}"` : ''}${extra()}/>`);
    },
    fillRect(x, y, w, h) { out.push(`<rect x="${r(x)}" y="${r(y)}" width="${r(w)}" height="${r(h)}" fill="${ctx.fillStyle}"${extra()}/>`); },
    strokeRect(x, y, w, h) {
      out.push(`<rect x="${r(x)}" y="${r(y)}" width="${r(w)}" height="${r(h)}" fill="none" stroke="${ctx.strokeStyle}" ` +
        `stroke-width="${ctx.lineWidth}"${dash ? ` stroke-dasharray="${dash}"` : ''}${extra()}/>`);
    },
    fillText(text, x, y) {
      const m = ctx.font.match(/(\d+)?\s*(\d+)px/) || [, '', '12'];
      const anchor = ctx.textAlign === 'center' ? 'middle' : ctx.textAlign === 'right' ? 'end' : 'start';
      out.push(`<text x="${r(x)}" y="${r(y)}" fill="${ctx.fillStyle}" font-family="system-ui,-apple-system,sans-serif" ` +
        `font-size="${m[2]}" font-weight="${m[1] || 400}" text-anchor="${anchor}"${extra()}>${esc(text)}</text>`);
    },
    toSvg() {
      return `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">` + out.join('') + '</svg>';
    },
  };
  function extra() {
    return (ctx.globalAlpha !== 1 ? ` opacity="${ctx.globalAlpha}"` : '') + (clipId ? ` clip-path="url(#${clipId})"` : '');
  }
  return ctx;
}

// The card each poster shows: one that carries the figure's point on its own.
const POSTER = { declaration: 'all', 'state-map': 'all', 'fan-out': 'functions', mailbox: 'sessions', cluster: 'ledger-stop' };

function posterState(figure, data) { return ME.buildState(figure, POSTER[figure], data); }

function canvasPoster(figure, data, height, label) {
  const pad = 14, ctx = svgContext(WIDTH, height);
  const state = posterState(figure, data);
  const colors = { ink: PALETTE.ink, dim: PALETTE.dim, accent: PALETTE.accent };
  ME.draw[figure](ctx, state, { width: WIDTH, height }, colors);
  const inner = ctx.toSvg().replace(/^<svg[^>]*>/, '').replace(/<\/svg>$/, '');
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${WIDTH + 2 * pad}" height="${height + 2 * pad}" ` +
    `viewBox="0 0 ${WIDTH + 2 * pad} ${height + 2 * pad}" role="img" aria-label="${label}">` +
    `<rect width="100%" height="100%" fill="${PALETTE.paper}"/><g transform="translate(${pad} ${pad})">${inner}</g></svg>\n`;
}

function renderAll(data) {
  const F = ME.figures, sm = data.state_map;
  return {
    declaration: panel(F.declaration(data.order, { width: WIDTH, from: 0, to: 0 }), 14),
    'state-map': panel(F.stateMap(sm, { width: WIDTH, lit: sm.path.length }), 14),
    'fan-out': panel(F.fanOut(data.order, { width: WIDTH, stage: POSTER['fan-out'] }), 14),
    mailbox: canvasPoster('mailbox', data, 300, 'One actor: its mailbox, its state and the sessions parked in it'),
    cluster: canvasPoster('cluster', data, 440, 'The cluster after the host holding the Ledger has stopped'),
  };
}

// The second page's posters (docs/deploy-authority.md): the squares with the app's own
// modules picked out, the topology with its firewall, and the patch stopped at forge's gate.
const AUTHORITY_POSTER = { reach: 'own', topology: 'firewall', rollout: 'refused' };

function topologyPoster(figure, data, label) {
  const pad = 14, design = ME.draw.topologyDesign({ width: WIDTH }), ctx = svgContext(design.width, design.height);
  const state = ME.buildState(figure, AUTHORITY_POSTER[figure], data);
  ME.draw.topology(ctx, state, design, { ink: PALETTE.ink, dim: PALETTE.dim, accent: PALETTE.accent });
  const inner = ctx.toSvg().replace(/^<svg[^>]*>/, '').replace(/<\/svg>$/, '');
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${design.width + 2 * pad}" height="${design.height + 2 * pad}" ` +
    `viewBox="0 0 ${design.width + 2 * pad} ${design.height + 2 * pad}" role="img" aria-label="${label}">` +
    `<rect width="100%" height="100%" fill="${PALETTE.paper}"/><g transform="translate(${pad} ${pad})">${inner}</g></svg>\n`;
}

function renderAuthority(data) {
  return {
    reach: panel(ME.figures.reach(data.modules, { width: WIDTH, stage: AUTHORITY_POSTER.reach, dep: data.dep }), 14, SQUARES),
    topology: topologyPoster('topology', data, 'Four machines in two pools, the roles each holds and the firewall links between them'),
    rollout: topologyPoster('rollout', data, 'A patch that adds a capability, stopped at a gate on the developer\'s machine'),
  };
}

module.exports = { renderAll, renderAuthority, svgContext, posterState, PALETTE };

if (require.main === module) {
  const read = (name) => JSON.parse(fs.readFileSync(path.join(ROOT, 'docs/_data', name), 'utf8'));
  const dir = path.join(ASSETS, 'fallback');
  let stale = 0;
  const images = Object.assign({}, renderAll(read('explainer.json')), renderAuthority(read('authority.json')));
  for (const [name, svg] of Object.entries(images)) {
    const file = path.join(dir, name + '.svg');
    if (process.argv.includes('--check')) {
      if (!fs.existsSync(file) || fs.readFileSync(file, 'utf8') !== svg) { console.log('stale: ' + path.relative(ROOT, file)); stale += 1; }
    } else {
      fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(file, svg);
      console.log('wrote ' + path.relative(ROOT, file));
    }
  }
  if (stale) { console.log('run node scripts/render-explainer-fallbacks.js'); process.exit(1); }
}
