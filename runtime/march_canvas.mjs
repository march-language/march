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
