// Tests for scripts/render-explainer-fallbacks.js: the static image each figure shows
// when its script has not run (no JavaScript, or a figure that failed to mount).
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const fb = require('../../scripts/render-explainer-fallbacks.js');
const ROOT = path.join(__dirname, '../..');
const data = JSON.parse(fs.readFileSync(path.join(ROOT, 'docs/_data/explainer.json'), 'utf8'));
const all = fb.renderAll(data);

test('there is one image per figure on the page', () => {
  const page = fs.readFileSync(path.join(ROOT, 'docs/protocol-to-cluster.md'), 'utf8');
  const figures = [...page.matchAll(/data-figure="([a-z-]+)"/g)].map((m) => m[1]).sort();
  assert.deepEqual(Object.keys(all).sort(), figures);
});

test('each image stands alone: no page variables, a background, and a style for every class it uses', () => {
  for (const [name, svg] of Object.entries(all)) {
    assert.ok(svg.startsWith('<svg'), name);
    assert.equal(svg.includes('var('), false, name + ' uses a page variable an <img> cannot resolve');
    assert.ok(svg.includes(fb.PALETTE.paper), name + ' has no background');
    const style = (svg.match(/<style>([\s\S]*?)<\/style>/) || [, ''])[1];
    for (const m of svg.matchAll(/class="([^"]+)"/g)) {
      for (const cls of m[1].split(' ')) assert.ok(style.includes('.' + cls), `${name}: no style for .${cls}`);
    }
  }
});

test('the canvas renderers replay into SVG: a square per held slot, the host names as text', () => {
  const svg = all.cluster;
  const state = fb.posterState('cluster', data);
  const held = state.hosts.reduce((n, h) => n + h.stock.filter((x) => x !== null).length, 0) +
    state.ledger.slots.filter((x) => x !== null).length;
  const filled = (svg.match(new RegExp('<rect[^>]* fill="' + fb.PALETTE.ink + '"', 'g')) || []).length;
  assert.ok(filled >= held, `${filled} filled squares for ${held} held slots`);
  for (const h of state.hosts) assert.ok(svg.includes('>' + h.id + '<'), h.id);
});

test('the svg context turns canvas calls into elements', () => {
  const ctx = fb.svgContext(100, 50);
  ctx.fillStyle = '#123456'; ctx.fillRect(1, 2, 3, 4);
  ctx.strokeStyle = '#654321'; ctx.setLineDash([4, 3]); ctx.strokeRect(5.5, 6.5, 7, 8); ctx.setLineDash([]);
  ctx.beginPath(); ctx.arc(10, 11, 2, 0, Math.PI * 2); ctx.fill();
  ctx.beginPath(); ctx.moveTo(0, 0); ctx.lineTo(9, 9); ctx.stroke();
  ctx.font = '600 13px system-ui, sans-serif'; ctx.textAlign = 'center'; ctx.fillText('a <b>', 20, 30);
  const svg = ctx.toSvg();
  assert.ok(svg.includes('<rect x="1" y="2" width="3" height="4" fill="#123456"'));
  assert.ok(/<rect x="5.5" y="6.5" width="7" height="8" fill="none" stroke="#654321"[^>]*stroke-dasharray="4 3"/.test(svg));
  assert.ok(svg.includes('<circle cx="10" cy="11" r="2" fill="#123456"'));
  assert.ok(svg.includes('<path d="M0 0L9 9" fill="none" stroke="#654321"'));
  assert.ok(/<text x="20" y="30"[^>]*font-size="13"[^>]*font-weight="600"[^>]*text-anchor="middle"[^>]*>a &lt;b&gt;<\/text>/.test(svg));
});

test('the committed images are what the renderers produce today', () => {
  for (const [name, svg] of Object.entries(all)) {
    const file = path.join(ROOT, 'docs/assets/explainer/fallback', name + '.svg');
    assert.ok(fs.existsSync(file), name + '.svg is missing; run node scripts/render-explainer-fallbacks.js');
    assert.equal(fs.readFileSync(file, 'utf8'), svg, name + '.svg is stale; run node scripts/render-explainer-fallbacks.js');
  }
});

test('every figure on the page has its image in its stage, with alt text', () => {
  const page = fs.readFileSync(path.join(ROOT, 'docs/protocol-to-cluster.md'), 'utf8');
  for (const name of Object.keys(all)) {
    const re = new RegExp('data-figure="' + name + '">\\s*<div class="mx-figure"><div class="mx-stage"><img class="mx-fallback" src="[^"]*/fallback/' + name + '\\.svg" alt="[^"]{20,}"');
    assert.ok(re.test(page), name);
  }
});
