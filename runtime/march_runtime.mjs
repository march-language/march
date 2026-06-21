/**
 * March JS runtime shim — ES module.
 * Provides builtins that don't inline directly to JS primitives.
 */

/** process.stdout.write without newline (mirrors march's `print` builtin) */
export function march_print(s) {
  process.stdout.write(String(s));
}

/** Float → string matching C's %g (6 significant digits, no trailing zeros) */
export function march_float_to_string(f) {
  if (!isFinite(f)) return String(f);
  const s = f.toPrecision(6);
  // Remove trailing zeros and unnecessary decimal point (like C's %g)
  if (s.includes('e')) {
    return s.replace(/\.?0+(e)/, '$1');
  }
  return s.replace(/\.?0+$/, '');
}

/** String byte length (UTF-8 bytes, matching the native backend) */
export function march_string_byte_length(s) {
  return new TextEncoder().encode(s).length;
}

/** String grapheme count (user-visible characters) */
export function march_string_grapheme_count(s) {
  return [...new Intl.Segmenter().segment(s)].length;
}

/* ── String operations ─────────────────────────────────────────────── */

export function march_string_to_int(s) {
  const n = Number(s);
  if (!Number.isInteger(n) || String(n) !== s.trim()) return { $: "None" };
  return { $: "Some", _0: n };
}

export function march_string_to_float(s) {
  const n = Number(s);
  if (isNaN(n)) return { $: "None" };
  return { $: "Some", _0: n };
}

export function march_string_to_lowercase(s) { return s.toLowerCase(); }
export function march_string_to_uppercase(s) { return s.toUpperCase(); }
export function march_string_trim(s) { return s.trim(); }
export function march_string_trim_start(s) { return s.trimStart(); }
export function march_string_trim_end(s) { return s.trimEnd(); }
export function march_string_reverse(s) { return [...s].reverse().join(""); }

export function march_string_chars(s) {
  let list = { $: "Nil" };
  for (const c of [...s].reverse()) list = { $: "Cons", _0: c, _1: list };
  return list;
}

export function march_string_from_chars(list) {
  let s = "";
  while (list.$ === "Cons") { s += list._0; list = list._1; }
  return s;
}

export function march_string_join(list, sep) {
  const parts = [];
  while (list.$ === "Cons") { parts.push(list._0); list = list._1; }
  return parts.join(sep);
}

export function march_string_contains(s, sub) { return s.includes(sub); }
export function march_string_starts_with(s, pre) { return s.startsWith(pre); }
export function march_string_ends_with(s, suf) { return s.endsWith(suf); }

export function march_string_slice(s, start, end_) {
  return s.slice(start, end_);
}

export function march_string_split(s, sep) {
  const parts = s.split(sep);
  let list = { $: "Nil" };
  for (const p of parts.reverse()) list = { $: "Cons", _0: p, _1: list };
  return list;
}

export function march_string_split_first(s, sep) {
  const i = s.indexOf(sep);
  if (i < 0) return { $: "None" };
  return { $: "Some", _0: { _0: s.slice(0, i), _1: s.slice(i + sep.length) } };
}

export function march_string_replace(s, from, to) {
  return s.replace(from, to);
}

export function march_string_replace_all(s, from, to) {
  return s.replaceAll(from, to);
}

export function march_string_repeat(s, n) { return s.repeat(n); }

export function march_string_pad_left(s, n, c) {
  return s.padStart(n, c);
}

export function march_string_pad_right(s, n, c) {
  return s.padEnd(n, c);
}

export function march_string_index_of(s, sub) {
  const i = s.indexOf(sub);
  return i < 0 ? { $: "None" } : { $: "Some", _0: i };
}

export function march_string_last_index_of(s, sub) {
  const i = s.lastIndexOf(sub);
  return i < 0 ? { $: "None" } : { $: "Some", _0: i };
}

/* ── Char operations ───────────────────────────────────────────────── */

export function march_char_from_int(n) {
  return String.fromCodePoint(n);
}

export function march_byte_to_char(n) {
  return String.fromCharCode(n);
}

export function march_char_to_int(c) {
  return c.codePointAt(0);
}

export function march_char_is_digit(c) { return /^\d$/.test(c); }
export function march_char_is_alphanumeric(c) { return /^\w$/.test(c); }
export function march_char_is_whitespace(c) { return /^\s$/.test(c); }

/* ── List operations ───────────────────────────────────────────────── */

export function march_list_append(list, elem) {
  const arr = [];
  while (list.$ === "Cons") { arr.push(list._0); list = list._1; }
  arr.push(elem);
  let result = { $: "Nil" };
  for (const x of arr.reverse()) result = { $: "Cons", _0: x, _1: result };
  return result;
}

export function march_list_concat(a, b) {
  const arr = [];
  while (a.$ === "Cons") { arr.push(a._0); a = a._1; }
  let result = b;
  for (const x of arr.reverse()) result = { $: "Cons", _0: x, _1: result };
  return result;
}
