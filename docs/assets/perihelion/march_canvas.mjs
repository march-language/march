// march_canvas.mjs — 2D Canvas wrapper functions for March programs compiled with --target js.
// Imported automatically when the compiled module uses the Canvas stdlib module.

// ── Helpers ──────────────────────────────────────────────────────────────────

function some(v) { return { $: "Some", _0: v }; }
const none = { $: "None" };
function opt(v) { return (v != null) ? some(v) : none; }

// ── Setup ────────────────────────────────────────────────────────────────────

export function march_canvas_get_context(node) {
  return opt(node.getContext("2d"));
}

// ── State stack ────────────────────────────────────────────────────────────

export function march_canvas_save(ctx) { ctx.save(); }
export function march_canvas_restore(ctx) { ctx.restore(); }
export function march_canvas_translate(ctx, x, y) { ctx.translate(x, y); }
export function march_canvas_rotate(ctx, angle) { ctx.rotate(angle); }
export function march_canvas_scale(ctx, sx, sy) { ctx.scale(sx, sy); }

// ── Style ──────────────────────────────────────────────────────────────────

export function march_canvas_set_fill_style(ctx, color) { ctx.fillStyle = color; }
export function march_canvas_set_stroke_style(ctx, color) { ctx.strokeStyle = color; }
export function march_canvas_set_line_width(ctx, w) { ctx.lineWidth = w; }
export function march_canvas_set_global_alpha(ctx, a) { ctx.globalAlpha = a; }
export function march_canvas_set_font(ctx, font) { ctx.font = font; }

// ── Rects ──────────────────────────────────────────────────────────────────

export function march_canvas_clear_rect(ctx, x, y, w, h) { ctx.clearRect(x, y, w, h); }
export function march_canvas_fill_rect(ctx, x, y, w, h) { ctx.fillRect(x, y, w, h); }
export function march_canvas_stroke_rect(ctx, x, y, w, h) { ctx.strokeRect(x, y, w, h); }

// ── Paths ──────────────────────────────────────────────────────────────────

export function march_canvas_begin_path(ctx) { ctx.beginPath(); }
export function march_canvas_close_path(ctx) { ctx.closePath(); }
export function march_canvas_move_to(ctx, x, y) { ctx.moveTo(x, y); }
export function march_canvas_line_to(ctx, x, y) { ctx.lineTo(x, y); }
export function march_canvas_arc(ctx, x, y, radius, start_angle, end_angle) {
  ctx.arc(x, y, radius, start_angle, end_angle);
}
export function march_canvas_quadratic_curve_to(ctx, cpx, cpy, x, y) {
  ctx.quadraticCurveTo(cpx, cpy, x, y);
}
export function march_canvas_bezier_curve_to(ctx, cp1x, cp1y, cp2x, cp2y, x, y) {
  ctx.bezierCurveTo(cp1x, cp1y, cp2x, cp2y, x, y);
}
export function march_canvas_fill(ctx) { ctx.fill(); }
export function march_canvas_stroke(ctx) { ctx.stroke(); }

// ── Noise fill ───────────────────────────────────────────────────────────────
// A tileable greyscale value-noise texture (module-level cache, reused for
// every call and context -- a CanvasPattern is just an image source) for the
// visible internal GRAIN. Two octaves (grids of 6 and 11 cells, each wrapped
// independently mod its own size) give richer, less repetitive detail than
// a single octave.
let __noiseTile = null;
function noiseTile() {
  if (__noiseTile) return __noiseTile;
  const SIZE = 256;
  const tile = document.createElement("canvas");
  tile.width = SIZE; tile.height = SIZE;
  const tctx = tile.getContext("2d");
  const img = tctx.createImageData(SIZE, SIZE);
  function smooth(t) { return t * t * (3 - 2 * t); }
  function grid(n, seed) {
    const g = [];
    let s = seed >>> 0;
    for (let i = 0; i < n; i++) {
      g.push([]);
      for (let j = 0; j < n; j++) {
        s = (Math.imul(s, 1103515245) + 12345) >>> 0;
        g[i].push(s / 0xffffffff);
      }
    }
    return g;
  }
  function sample(g, n, u, v) {
    const gx = u * n, gy = v * n;
    const x0 = Math.floor(gx) % n, y0 = Math.floor(gy) % n;
    const x1 = (x0 + 1) % n, y1 = (y0 + 1) % n;
    const fx = smooth(gx - Math.floor(gx)), fy = smooth(gy - Math.floor(gy));
    const top = g[x0][y0] * (1 - fx) + g[x1][y0] * fx;
    const bot = g[x0][y1] * (1 - fx) + g[x1][y1] * fx;
    return top * (1 - fy) + bot * fy;
  }
  const g1 = grid(6, 17), g2 = grid(11, 91);
  for (let py = 0; py < SIZE; py++) {
    for (let px = 0; px < SIZE; px++) {
      const u = px / SIZE, v = py / SIZE;
      let n = sample(g1, 6, u, v) * 0.6 + sample(g2, 11, u, v) * 0.4;
      n = Math.max(0, Math.min(1, n));
      const val = Math.round(n * 255);
      const idx = (py * SIZE + px) * 4;
      img.data[idx] = val; img.data[idx + 1] = val; img.data[idx + 2] = val;
      img.data[idx + 3] = 255;
    }
  }
  tctx.putImageData(img, 0, 0);
  __noiseTile = tile;
  return tile;
}

// Cheap deterministic hash, same GLSL-style trick used throughout the March
// side -- used here to derive each cloud's SILHOUETTE wobble purely from its
// own (cx, cy), so no new data needs to cross the March/JS boundary and the
// shape is still fully determined by the (seed-driven) cloud position.
function hashJs(x, y) {
  const v = Math.sin(x * 12.9898 + y * 78.233) * 43758.5453;
  return v - Math.floor(v);
}

// Shortest signed angular difference a - b, wrapped into [-PI, PI].
function angDiff(a, b) {
  let d = a - b;
  while (d > Math.PI) d -= Math.PI * 2;
  while (d < -Math.PI) d += Math.PI * 2;
  return d;
}

let __noisePattern = null;
let __scratch = null;
function scratchCanvas(size) {
  if (!__scratch || __scratch.width < size) {
    __scratch = document.createElement("canvas");
    __scratch.width = __scratch.height = size;
  } else {
    __scratch.getContext("2d").clearRect(0, 0, __scratch.width, __scratch.height);
  }
  return __scratch;
}

export function march_canvas_fill_noise_circle(ctx, cx, cy, r, alpha) {
  if (!__noisePattern) __noisePattern = ctx.createPattern(noiseTile(), "repeat");

  // An irregular, lobed outline instead of a perfect circle: sum three sine
  // harmonics (different frequency/phase per cloud, hashed from its own
  // position) around the boundary. This is what actually reads as a
  // nebula's ragged edge -- a noise-textured but still perfectly circular
  // clip (tried first) barely dents the silhouette, since noise variance
  // shows up as internal grain, not edge shape.
  const a1 = 0.16 + 0.10 * hashJs(cx, cy),          p1 = hashJs(cx + 1, cy) * Math.PI * 2;
  const a2 = 0.10 + 0.08 * hashJs(cx + 2, cy),      p2 = hashJs(cx + 3, cy) * Math.PI * 2;
  const a3 = 0.06 + 0.06 * hashJs(cx + 4, cy),      p3 = hashJs(cx + 5, cy) * Math.PI * 2;

  // Some clouds stretch one lobe into a long, narrow arm reaching well past
  // the base silhouette -- a Gaussian angular bump layered on top of the
  // harmonic wobble at a hashed angle, not a separate shape system.
  const hasArm = hashJs(cx + 6, cy) < 0.35;
  const armAngle = hashJs(cx + 7, cy) * Math.PI * 2;
  const armReach = r * (1.6 + 0.6 * hashJs(cx + 8, cy)); // 1.6x-2.2x r
  const armWidth = 0.10 + 0.09 * hashJs(cx + 9, cy);     // narrow angular width (radians)

  function edgeR(theta) {
    const wob = 1 + a1 * Math.sin(3 * theta + p1) + a2 * Math.sin(5 * theta + p2) + a3 * Math.sin(8 * theta + p3);
    let rr = r * wob;
    if (hasArm) {
      const d = angDiff(theta, armAngle) / armWidth;
      rr += (armReach - r) * Math.exp(-0.5 * d * d);
    }
    return rr;
  }

  // A hard ctx.clip() to this lobed path always terminates as a crisp vector
  // edge, no matter what's drawn inside it -- gradients composited within a
  // clip still snap to nothing right at the clip boundary. To get an actual
  // soft edge, build the shape on an offscreen buffer and blur the WHOLE
  // composited result (silhouette + noise grain + holes together) while
  // blitting it back -- a real Gaussian-style blur, not a faked falloff.
  const rMax = Math.max(r * 1.4, armReach * 1.15); // covers wobble + any arm's reach
  const blurPx = Math.max(14, Math.min(40, r * 0.14));
  const pad = blurPx * 3; // headroom so the blur fades to nothing before the buffer edge
  const size = Math.ceil((rMax + pad) * 2);
  const sc = scratchCanvas(size);
  const sctx = sc.getContext("2d");
  const lcx = size / 2, lcy = size / 2;

  sctx.save();
  sctx.beginPath();
  const N = 96; // fine enough resolution that a narrow arm doesn't facet
  for (let i = 0; i <= N; i++) {
    const theta = (i / N) * Math.PI * 2;
    const rr = edgeR(theta);
    const px = lcx + Math.cos(theta) * rr, py = lcy + Math.sin(theta) * rr;
    if (i === 0) sctx.moveTo(px, py); else sctx.lineTo(px, py);
  }
  sctx.closePath();
  sctx.clip();

  // Keep the noise pattern world-aligned so it still reads as one continuous
  // texture across clouds, not one that resets per scratch buffer. Scoped to
  // its own save/restore so the translate doesn't leak into the hole step
  // below (holes are positioned in local scratch-buffer coordinates).
  sctx.save();
  sctx.translate(cx - lcx, cy - lcy);
  sctx.fillStyle = __noisePattern;
  sctx.fillRect(cx - rMax, cy - rMax, rMax * 2, rMax * 2);
  sctx.restore();

  // A few clouds get dark internal voids -- 0-3, hashed, kept within the
  // inner ~60% of the radius so they read as gaps in the body rather than
  // notches in the edge. Cut with destination-out (still bounded by the
  // clip above), then the final blur softens their edges along with
  // everything else.
  const holeCount = Math.min(3, Math.floor(hashJs(cx + 10, cy) * 3.2));
  if (holeCount > 0) {
    sctx.globalCompositeOperation = "destination-out";
    for (let i = 0; i < holeCount; i++) {
      const hs = cx + 20 + i * 11;
      const hAngle = hashJs(hs, cy) * Math.PI * 2;
      const hDist = r * (0.15 + 0.45 * hashJs(hs + 1, cy));
      const hRadius = r * (0.12 + 0.20 * hashJs(hs + 2, cy));
      const hx = lcx + Math.cos(hAngle) * hDist, hy = lcy + Math.sin(hAngle) * hDist;
      sctx.beginPath();
      sctx.arc(hx, hy, hRadius, 0, Math.PI * 2);
      sctx.fill();
    }
    sctx.globalCompositeOperation = "source-over";
  }
  sctx.restore();

  ctx.save();
  ctx.globalAlpha = alpha;
  ctx.filter = `blur(${blurPx}px)`;
  ctx.drawImage(sc, 0, 0, size, size, cx - lcx, cy - lcy, size, size);
  ctx.restore();
}

// ── Text ───────────────────────────────────────────────────────────────────

export function march_canvas_fill_text(ctx, text, x, y) { ctx.fillText(text, x, y); }
export function march_canvas_stroke_text(ctx, text, x, y) { ctx.strokeText(text, x, y); }
export function march_canvas_set_text_align(ctx, align) { ctx.textAlign = align; }

// ── Images ─────────────────────────────────────────────────────────────────
// `load_image` is `blocking raises`: returns/throws the bare payload — the
// compiler emits the await + try/catch → Ok/Err marshalling automatically.

export async function march_canvas_load_image(url) {
  return await new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = () => reject(new Error("failed to load image: " + url));
    img.src = url;
  });
}

export function march_canvas_draw_image(ctx, img, x, y) { ctx.drawImage(img, x, y); }
export function march_canvas_draw_image_scaled(ctx, img, x, y, w, h) {
  ctx.drawImage(img, x, y, w, h);
}
