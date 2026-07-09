/**
 * March JS runtime shim — ES module.
 * Provides builtins that don't inline directly to JS primitives.
 */

/** process.stdout.write without newline (mirrors march's `print` builtin) */
export function march_print(s) {
  process.stdout.write(String(s));
}

/** Float → string mirroring the interpreter's OCaml `string_of_float`
 *  (`%.12g` + a trailing '.' on bare integers): 1.0 -> "1.", 1.5 -> "1.5",
 *  0.1 -> "0.1". Whole numbers now agree with the native/interpreter backends
 *  (specs/lang/golden/g09_float_show.march); extreme-exponent magnitudes where
 *  JS toPrecision and C %g pick fixed-vs-exponential notation differently
 *  remain a deferred edge (untested, out of scope for the whole-number fix). */
export function march_float_to_string(f) {
  if (Number.isNaN(f)) return "nan";
  if (f === Infinity) return "inf";
  if (f === -Infinity) return "-inf";
  let s = f.toPrecision(12);          // 12 significant digits, like %.12g
  if (s.includes('e')) {
    s = s.replace(/\.?0+e/, 'e');     // strip trailing mantissa zeros before exp
  } else if (s.includes('.')) {
    s = s.replace(/0+$/, '');         // 1.500..0 -> "1.5" ; 1.000..0 -> "1."
  }
  return /^-?\d+$/.test(s) ? s + '.' : s;   // bare integer 1 -> "1."
}

/** Truncating integer division, matching runtime/march_runtime.c's
 *  march_checked_idiv (panics on a zero divisor instead of producing
 *  Infinity/NaN). Used for the `int_div` builtin (e.g. stdlib/array.march's
 *  PVec leaf-count math), distinct from the bare `/` operator's looser
 *  unchecked lowering. */
export function march_int_div(a, b) {
  if (b === 0) throw new Error("int_div: division by zero");
  return Math.trunc(a / b);
}

/** Truncating integer remainder (sign follows the dividend, matching JS's
 *  native `%` and C's `%`), matching march_runtime.c's march_checked_imod. */
export function march_int_mod(a, b) {
  if (b === 0) throw new Error("int_mod: division by zero");
  return a % b;
}

/** Euclidean remainder (always non-negative), matching march_runtime.c's
 *  march_checked_umod for the magnitudes representable as JS numbers. */
export function march_int_mod_euclid(a, b) {
  if (b === 0) throw new Error("int_mod_euclid: division by zero");
  return ((a % b) + Math.abs(b)) % Math.abs(b);
}

/** Integer exponentiation by squaring, matching march_runtime.c's
 *  march_int_pow (negative exponents return 0, mirroring the native
 *  backend rather than JS's fractional Math.pow). */
export function march_int_pow(base, exp) {
  if (exp < 0) return 0;
  let result = 1;
  while (exp > 0) {
    if (exp & 1) result *= base;
    base *= base;
    exp >>= 1;
  }
  return result;
}

/** Seconds since epoch as a fractional float, matching march_runtime.c's
 *  march_unix_time (CLOCK_REALTIME tv_sec + tv_nsec/1e9). Used by
 *  stdlib/random.march's default seed and a few timestamp helpers. */
export function march_unix_time() {
  return Date.now() / 1000;
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
