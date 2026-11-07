/**
 * March JS runtime shim — ES module.
 * Provides builtins that don't inline directly to JS primitives.
 */

/* print / println: the string's bytes (see "Byte strings"). Under Node a
 * string holding raw bytes (U+F780..U+F7FF) is written as those bytes, as
 * the native target writes them; anything else is ordinary text. */
function march_has_raw(s) {
  for (let i = 0; i < s.length; i++) { const c = s.charCodeAt(i); if (c >= 0xF780 && c <= 0xF7FF) return true; }
  return false;
}
function march_write(s, nl) {
  s = String(s);
  if (typeof process !== "undefined" && process.stdout && process.stdout.write) {
    if (march_has_raw(s)) {
      const b = march_encode_bytes(s);
      process.stdout.write(nl ? Buffer.concat([Buffer.from(b), Buffer.from("\n")]) : Buffer.from(b));
    } else process.stdout.write(nl ? s + "\n" : s);
  } else console.log(s);
}

/** process.stdout.write without newline (mirrors march's `print` builtin) */
export function march_print(s) { march_write(s, false); }

/** println: the string and a newline */
export function march_println(s) { march_write(s, true); }

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

/* int_div / int_mod / int_mod_euclid are defined below in the checked
   "Int builtins (63-bit semantics)" section (exact within ±(2^53−1), throw
   beyond). int_pow stays here — it is JS-target-only. */

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

/* march_unix_time is defined below in the System section. */

/* ── Byte strings ────────────────────────────────────────────────────
 * A March String is a byte sequence; on this target it is carried in a JS
 * string so that text stays ordinary JS text:
 *   - a code unit below 0x80 is that ASCII byte;
 *   - U+F780..U+F7FF is the single byte 0x80..0xFF (a byte that isn't part of
 *     valid UTF-8, e.g. from a binary file);
 *   - any other character stands for its UTF-8 bytes.
 * march_bytes_to_string builds this canonical form from raw bytes (valid
 * UTF-8 runs decode to text, other bytes use the U+F7xx range), so a slice of
 * binary data that holds a name compares equal to the literal name.
 * Byte-indexed operations (byte_length, byte_at, slice, index_of) see the
 * bytes: directly when every code unit is one byte, else through a byte view
 * cached per string, so byte access is O(1) after one O(n) pass. */
const MARCH_RAW_BASE = 0xF700;

function march_unit_is_byte(c) { return c < 0x80 || (c >= 0xF780 && c <= 0xF7FF); }

function march_encode_bytes(s) {
  const out = new Uint8Array(s.length * 3);
  let n = 0;
  for (let i = 0; i < s.length; i++) {
    let c = s.charCodeAt(i);
    if (c < 0x80) out[n++] = c;
    else if (c >= 0xF780 && c <= 0xF7FF) out[n++] = c - MARCH_RAW_BASE;
    else {
      if (c >= 0xD800 && c <= 0xDBFF && i + 1 < s.length) {
        const d = s.charCodeAt(i + 1);
        if (d >= 0xDC00 && d <= 0xDFFF) { c = 0x10000 + ((c - 0xD800) << 10) + (d - 0xDC00); i++; }
      }
      if (c < 0x800) { out[n++] = 0xC0 | (c >> 6); out[n++] = 0x80 | (c & 63); }
      else if (c < 0x10000) { out[n++] = 0xE0 | (c >> 12); out[n++] = 0x80 | ((c >> 6) & 63); out[n++] = 0x80 | (c & 63); }
      else { out[n++] = 0xF0 | (c >> 18); out[n++] = 0x80 | ((c >> 12) & 63); out[n++] = 0x80 | ((c >> 6) & 63); out[n++] = 0x80 | (c & 63); }
    }
  }
  return out.subarray(0, n);
}

// The last few strings' byte views (null: every code unit is one byte), keyed by
// the string itself: a Map hashes a string once and keeps the hash, where `===`
// compares contents (JavaScriptCore does so even for a string and itself, which
// made every byte_at on a 3.5 MB string cost ~150 us in Safari). At most one
// string of each length: V8 before Node 26 hashes a string over 16K units by its
// length alone, so two cached strings of one length would share a bucket and
// every hit could compare their contents.
const march_view_cache = new Map();
const march_view_by_len = new Map();
function march_byte_view(s) {
  if (s.length < 32) {
    for (let i = 0; i < s.length; i++) if (!march_unit_is_byte(s.charCodeAt(i))) return march_encode_bytes(s);
    return null;
  }
  const hit = march_view_cache.get(s);
  if (hit !== undefined) return hit;
  let v = null;
  for (let i = 0; i < s.length; i++) if (!march_unit_is_byte(s.charCodeAt(i))) { v = march_encode_bytes(s); break; }
  const same = march_view_by_len.get(s.length);
  if (same !== undefined) march_view_cache.delete(same);
  march_view_cache.set(s, v);
  march_view_by_len.set(s.length, s);
  if (march_view_cache.size > 4) {
    const old = march_view_cache.keys().next().value;
    march_view_cache.delete(old);
    march_view_by_len.delete(old.length);
  }
  return v;
}

function march_utf8_seq(b, i, n) {
  const c = b[i];
  let len, cp;
  if (c >= 0xC2 && c <= 0xDF) { len = 2; cp = c & 31; }
  else if (c >= 0xE0 && c <= 0xEF) { len = 3; cp = c & 15; }
  else if (c >= 0xF0 && c <= 0xF4) { len = 4; cp = c & 7; }
  else return null;
  if (i + len > n) return null;
  for (let k = 1; k < len; k++) { const d = b[i + k]; if ((d & 0xC0) !== 0x80) return null; cp = (cp << 6) | (d & 63); }
  if ((len === 3 && (cp < 0x800 || (cp >= 0xD800 && cp <= 0xDFFF))) || (len === 4 && (cp < 0x10000 || cp > 0x10FFFF))) return null;
  return { len, cp };
}

/** A March String's bytes, as a Uint8Array (the inverse of march_bytes_to_string). */
export function march_string_bytes(s) { return march_encode_bytes(s); }

/** Raw bytes (a Uint8Array) to a March String in canonical form. */
export function march_bytes_to_string(b) {
  const n = b.length;
  const parts = [];
  let run = [];
  const flush = () => { if (run.length) { parts.push(String.fromCharCode.apply(null, run)); run = []; } };
  for (let i = 0; i < n; ) {
    const c = b[i];
    if (c < 0x80) { run.push(c); i++; }
    else {
      const q = march_utf8_seq(b, i, n);
      if (q) { if (q.cp >= 0x10000) { const v = q.cp - 0x10000; run.push(0xD800 + (v >> 10), 0xDC00 + (v & 1023)); } else run.push(q.cp); i += q.len; }
      else { run.push(MARCH_RAW_BASE + c); i++; }
    }
    if (run.length >= 8192) flush();
  }
  flush();
  return parts.join("");
}

/* Byte offset <-> code-unit index, for strings that need a view. */
function march_unit_index_to_byte(s, u) {
  return u === 0 ? 0 : march_encode_bytes(s.slice(0, u)).length;
}

/** String byte length (bytes, matching the native backend) */
export function march_string_byte_length(s) {
  const v = march_byte_view(s);
  return v ? v.length : s.length;
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
  let raw = false;
  while (list.$ === "Cons") {
    const c = list._0;
    if (!raw && c.length === 1) { const u = c.charCodeAt(0); raw = u >= 0xF780 && u <= 0xF7FF; }
    s += c; list = list._1;
  }
  // Raw bytes (byte_to_char) may spell valid UTF-8: give the canonical form,
  // so Bytes.to_string(from_list([195, 169])) is "é".
  return raw ? march_bytes_to_string(march_encode_bytes(s)) : s;
}

export function march_string_concat3(a, b, c) {
  return a + b + c;
}

export function march_string_concat_n(...parts) {
  return parts.join("");
}

export function march_string_join(list, sep) {
  const parts = [];
  while (list.$ === "Cons") { parts.push(list._0); list = list._1; }
  return parts.join(sep);
}

export function march_string_contains(s, sub) { return s.includes(sub); }
export function march_string_starts_with(s, pre) { return s.startsWith(pre); }
export function march_string_ends_with(s, suf) { return s.endsWith(suf); }

/* Mirrors march_string_slice in runtime/march_runtime.c: a slice of [len]
 * BYTES from byte [start], clamped (C clamps a negative index to 0, where JS
 * would count from the end). */
export function march_string_slice(s, start, len) {
  const v = march_byte_view(s);
  const slen = v ? v.length : s.length;
  if (start < 0) start = 0;
  if (start > slen) start = slen;
  if (len < 0) len = 0;
  if (start + len > slen) len = slen - start;
  return v ? march_bytes_to_string(v.subarray(start, start + len)) : s.slice(start, start + len);
}

/* Mirrors march_string_byte_at: byte value 0..255, or -1 out of range. */
export function march_string_byte_at(s, i) {
  const v = march_byte_view(s);
  if (v) return i < 0 || i >= v.length ? -1 : v[i];
  if (i < 0 || i >= s.length) return -1;
  const c = s.charCodeAt(i);
  return c < 0x80 ? c : c - MARCH_RAW_BASE;
}

/** List(Int) of Unicode code points (mirrors `string_to_codepoints`).
 * `[...s]` iterates by code point, not UTF-16 code unit, so an astral
 * character yields ONE element rather than a surrogate pair. */
export function march_string_to_codepoints(s) {
  let list = { $: "Nil" };
  for (const c of [...s].reverse()) list = { $: "Cons", _0: c.codePointAt(0), _1: list };
  return list;
}

/** Option(String) for one code point (mirrors `string_from_codepoint`).
 * None for out of range or a lone UTF-16 surrogate half — String.fromCodePoint
 * accepts surrogates, so that case has to be rejected explicitly to match the
 * native and interpreted backends. */
export function march_string_from_codepoint(cp) {
  if (!Number.isInteger(cp) || cp < 0 || cp > 0x10ffff) return { $: "None" };
  if (cp >= 0xd800 && cp <= 0xdfff) return { $: "None" };
  return { $: "Some", _0: String.fromCodePoint(cp) };
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

/* index_of results are BYTE offsets, as natively. */
export function march_string_index_of(s, sub) {
  const i = s.indexOf(sub);
  return i < 0 ? { $: "None" } : { $: "Some", _0: march_byte_view(s) ? march_unit_index_to_byte(s, i) : i };
}

export function march_string_index_of_from(s, sub, start) {
  const v = march_byte_view(s);
  const slen = v ? v.length : s.length;
  if (start < 0) start = 0;
  if (start > slen) return { $: "None" };
  if (sub.length === 0) return { $: "Some", _0: start };
  if (!v) {
    const i = s.indexOf(sub, start);
    return i < 0 ? { $: "None" } : { $: "Some", _0: i };
  }
  const head = march_bytes_to_string(v.subarray(0, start));
  const i = s.indexOf(sub, head.length);
  return i < 0 ? { $: "None" } : { $: "Some", _0: march_unit_index_to_byte(s, i) };
}

export function march_string_last_index_of(s, sub) {
  const i = s.lastIndexOf(sub);
  return i < 0 ? { $: "None" } : { $: "Some", _0: march_byte_view(s) ? march_unit_index_to_byte(s, i) : i };
}

/* ── Char operations ───────────────────────────────────────────────── */

export function march_char_from_int(n) {
  return String.fromCodePoint(n);
}

/* A Char holding one raw byte (Bytes.from_list, from_hex): bytes 0x80-0xFF
 * use the byte-string range (see "Byte strings"), so the string they make
 * has exactly those bytes rather than each one's UTF-8 encoding. */
export function march_byte_to_char(n) {
  return n < 0x80 ? String.fromCharCode(n) : String.fromCharCode(MARCH_RAW_BASE + n);
}

export function march_char_to_int(c) {
  return c.codePointAt(0);
}

export function march_char_is_digit(c) { return /^\d$/.test(c); }
export function march_char_is_alphanumeric(c) { return /^\w$/.test(c); }
export function march_char_is_whitespace(c) { return /^\s$/.test(c); }

/* ── Int builtins (63-bit semantics, checked) ──────────────────────── */
/*
 * March Int is a 63-bit integer natively, but the JS target stores it in an
 * IEEE-754 double, which is exact only within ±(2^53 - 1). These helpers
 * implement the specified 63-bit semantics (specs/lang/type-system.md, "Int
 * width and overflow": int_shr is an ARITHMETIC shift and int_popcount counts
 * the 63-bit two's-complement pattern, as the interpreter and native code do)
 * exactly within that range,
 * and THROW a RangeError rather than silently rounding when an argument or
 * result falls outside it. Fast paths cover int32 and non-negative
 * double-exact operands so hot code (e.g. stdlib Random's 32-bit sfc32 core)
 * never touches BigInt.
 */

const __INT_LIMIT_MSG =
  " on --target js: March Int is stored in a JS double, exact only within" +
  " ±(2^53 - 1); full 63-bit values are not representable on this target.";

function __int_check(x, op) {
  if (!Number.isSafeInteger(x))
    throw new RangeError(op + ": argument " + x +
      " is outside the exact integer range" + __INT_LIMIT_MSG);
}

function __int_result(b, op) {
  const n = Number(b);
  if (!Number.isSafeInteger(n))
    throw new RangeError(op + ": result " + b +
      " overflows the exact integer range" + __INT_LIMIT_MSG);
  return n;
}

const __in32 = (x) => x >= -0x80000000 && x <= 0x7fffffff;
const __MAX_SAFE = Number.MAX_SAFE_INTEGER;
const __POW32 = 0x100000000;

/* Split non-negative safe ints into (hi, lo) 2^32-radix words so bitwise ops
 * stay exact without BigInt. hi ≤ 2^21, lo < 2^32; `>>> 0` re-reads the JS
 * 32-bit op's int32 result as unsigned. */
export function march_int_and(a, b) {
  if (__in32(a) && __in32(b)) return a & b;
  if (a >= 0 && b >= 0 && a <= __MAX_SAFE && b <= __MAX_SAFE) {
    const hi = Math.floor(a / __POW32) & Math.floor(b / __POW32);
    return hi * __POW32 + (((a % __POW32) & (b % __POW32)) >>> 0);
  }
  __int_check(a, "int_and"); __int_check(b, "int_and");
  return __int_result(BigInt.asIntN(63, BigInt(a) & BigInt(b)), "int_and");
}

export function march_int_or(a, b) {
  if (__in32(a) && __in32(b)) return a | b;
  if (a >= 0 && b >= 0 && a <= __MAX_SAFE && b <= __MAX_SAFE) {
    const hi = Math.floor(a / __POW32) | Math.floor(b / __POW32);
    return hi * __POW32 + (((a % __POW32) | (b % __POW32)) >>> 0);
  }
  __int_check(a, "int_or"); __int_check(b, "int_or");
  return __int_result(BigInt.asIntN(63, BigInt(a) | BigInt(b)), "int_or");
}

export function march_int_xor(a, b) {
  if (__in32(a) && __in32(b)) return a ^ b;
  if (a >= 0 && b >= 0 && a <= __MAX_SAFE && b <= __MAX_SAFE) {
    const hi = Math.floor(a / __POW32) ^ Math.floor(b / __POW32);
    return hi * __POW32 + (((a % __POW32) ^ (b % __POW32)) >>> 0);
  }
  __int_check(a, "int_xor"); __int_check(b, "int_xor");
  return __int_result(BigInt.asIntN(63, BigInt(a) ^ BigInt(b)), "int_xor");
}

/** lnot: ~x = -x - 1, exact for every safe-integer argument. */
export function march_int_not(a) {
  __int_check(a, "int_not");
  return __int_result(-a - 1, "int_not");
}

/** lsl with 63-bit wraparound; shift range checked like the interpreter. */
export function march_int_shl(a, n) {
  if (n < 0 || n >= 63) throw new Error("int_shl: shift out of range");
  __int_check(a, "int_shl");
  if (Math.abs(a) <= Math.floor(__MAX_SAFE / 2 ** n)) return a * 2 ** n;
  return __int_result(BigInt.asIntN(63, BigInt(a) << BigInt(n)), "int_shl");
}

/** asr: ARITHMETIC (sign-propagating) shift, like the interpreter and native
 * code: int_shr(-8, 1) = -4. That is floor division by 2^n, exact for every
 * safe-integer argument (dividing by a power of two is exact in a double). */
export function march_int_shr(a, n) {
  if (n < 0 || n >= 63) throw new Error("int_shr: shift out of range");
  __int_check(a, "int_shr");
  return Math.floor(a / 2 ** n);
}

/** Population count of the 63-bit two's-complement pattern, like the
 * interpreter and native code: int_popcount(-1) = 63. */
export function march_int_popcount(a) {
  __int_check(a, "int_popcount");
  let b = BigInt.asUintN(63, BigInt(a));
  let c = 0;
  while (b) { b &= b - 1n; c++; }
  return c;
}

/* a % b on doubles is fmod, which is EXACT for exact-integer operands and
 * truncates toward zero — same as OCaml's Rem / C's %. int_div derives the
 * quotient from it: (a - a % b) is an exact multiple of b, so the division
 * is exact too (Math.trunc(a / b) alone can be off by one near 2^53). */
export function march_int_mod(a, b) {
  if (b === 0) throw new Error("int_mod: division by zero");
  __int_check(a, "int_mod"); __int_check(b, "int_mod");
  return a % b;
}

export function march_int_div(a, b) {
  if (b === 0) throw new Error("int_div: division by zero");
  __int_check(a, "int_div"); __int_check(b, "int_div");
  return (a - a % b) / b;
}

export function march_int_mod_euclid(a, b) {
  if (b === 0) throw new Error("int_mod_euclid: division by zero");
  __int_check(a, "int_mod_euclid"); __int_check(b, "int_mod_euclid");
  const r = a % b;
  return r < 0 ? r + Math.abs(b) : r;
}

export function march_int_div_euclid(a, b) {
  if (b === 0) throw new Error("int_div_euclid: division by zero");
  __int_check(a, "int_div_euclid"); __int_check(b, "int_div_euclid");
  const q = (a - a % b) / b;
  const r = a % b;
  if (r < 0) return b > 0 ? q - 1 : q + 1;
  return q;
}

export function march_int_div_floor(a, b) {
  if (b === 0) throw new Error("int_div_floor: division by zero");
  __int_check(a, "int_div_floor"); __int_check(b, "int_div_floor");
  const q = (a - a % b) / b;
  const r = a - q * b;
  return (r !== 0 && ((r < 0) !== (b < 0))) ? q - 1 : q;
}

export function march_int_mod_floor(a, b) {
  if (b === 0) throw new Error("int_mod_floor: division by zero");
  __int_check(a, "int_mod_floor"); __int_check(b, "int_mod_floor");
  const r = a % b;
  return (r !== 0 && ((r < 0) !== (b < 0))) ? r + b : r;
}

/* Int `+ - *` and negation panic when the result leaves the 63-bit range
 * [-2^62, 2^62) (specs/lang/type-system.md, "Int width and overflow"), with
 * the interpreter's and native code's message. js_emit wraps each Int op as
 * march_int_ovf(a OP b, code). Within the target's exact range, ±(2^53 - 1),
 * nothing can overflow; the check is against the ROUNDED double, so past it
 * (outside the documented subset) a result within a rounding step of ±2^62
 * can be misjudged either way. */
const __OVF_MSGS = [
  "attempt to add with overflow", "attempt to subtract with overflow",
  "attempt to multiply with overflow", "attempt to negate with overflow",
];
const __INT63_LIMIT = 4611686018427387904;   // 2^62
export function march_int_ovf(r, op) {
  if (r >= __INT63_LIMIT || r < -__INT63_LIMIT) throw new Error(__OVF_MSGS[op]);
  return r;
}

/** int_wrapping_add/sub/mul: modulo-2^63 arithmetic, for hashes and
 * checksums. Exact within ±(2^53 - 1); a wrapped result outside it throws a
 * RangeError like the other checked Int builtins. */
export function march_int_wrapping_add(a, b) {
  __int_check(a, "int_wrapping_add"); __int_check(b, "int_wrapping_add");
  const r = a + b;
  if (Number.isSafeInteger(r)) return r;
  return __int_result(BigInt.asIntN(63, BigInt(a) + BigInt(b)), "int_wrapping_add");
}

export function march_int_wrapping_sub(a, b) {
  __int_check(a, "int_wrapping_sub"); __int_check(b, "int_wrapping_sub");
  const r = a - b;
  if (Number.isSafeInteger(r)) return r;
  return __int_result(BigInt.asIntN(63, BigInt(a) - BigInt(b)), "int_wrapping_sub");
}

export function march_int_wrapping_mul(a, b) {
  __int_check(a, "int_wrapping_mul"); __int_check(b, "int_wrapping_mul");
  const r = a * b;
  if (Number.isSafeInteger(r)) return r;
  return __int_result(BigInt.asIntN(63, BigInt(a) * BigInt(b)), "int_wrapping_mul");
}

/** Float → Int rounding, half AWAY FROM ZERO (mirrors OCaml Float.round;
 * JS Math.round rounds half toward +inf, so Math.round(-2.5) would differ). */
export function march_float_round(f) {
  return Math.sign(f) * Math.round(Math.abs(f));
}

/* ── System ────────────────────────────────────────────────────────── */

/** Seconds since the Unix epoch as a Float (mirrors `unix_time`). */
export function march_unix_time() {
  return Date.now() / 1000;
}

/** Milliseconds since the Unix epoch as an Int (mirrors `unix_time_ms`). */
export function march_unix_time_ms() {
  return Date.now();
}

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

/* Stable sorts behind Array.sort_by / sort_by_key and RRB.sort_by /
 * sort_by_key (the native builtins are list_stable_sort_by /
 * list_sort_by_int_key in march_runtime.c). Array.prototype.sort is stable
 * (ES2019). `le(a, b)` true means a may come before b; a pair that is `le`
 * both ways compares equal, so ties keep input order, as in the native
 * sort for a `<=`-style comparator. The key closure is called once per
 * element. */
export function march_list_stable_sort_by(list, le) {
  const arr = [];
  while (list.$ === "Cons") { arr.push(list._0); list = list._1; }
  arr.sort((a, b) => le._0(le, a, b) ? (le._0(le, b, a) ? 0 : -1) : 1);
  let result = { $: "Nil" };
  for (let i = arr.length - 1; i >= 0; i--) result = { $: "Cons", _0: arr[i], _1: result };
  return result;
}

export function march_list_sort_by_int_key(list, key) {
  const arr = [];
  while (list.$ === "Cons") { arr.push(list._0); list = list._1; }
  const keys = arr.map((x) => key._0(key, x));
  const idx = arr.map((_, i) => i);
  idx.sort((i, j) => (keys[i] < keys[j] ? -1 : keys[i] > keys[j] ? 1 : 0));
  let result = { $: "Nil" };
  for (let k = idx.length - 1; k >= 0; k--) result = { $: "Cons", _0: arr[idx[k]], _1: result };
  return result;
}

/* ── Structural equality ────────────────────────────────────────────
 * Deep, tag-aware `==`/`!=` for NON-primitive operands. js_emit routes
 * bare `==`/`!=` here whenever either operand's static type is not a
 * primitive (an ADT/tuple/record, or an erased type variable that may hold
 * one at runtime); primitive-vs-primitive stays on JS `===`. Values are the
 * usual shapes: variants `{ $: tag, _0, _1, … }`, records `{ field: … }`,
 * tuples `{ _0, _1, … }`, scalars as JS number/string/boolean. Mirrors
 * native's per-type __eq / march_poly_eq. */
export function march_deep_eq(a, b) {
  if (a === b) return true;
  if (a === null || b === null ||
      typeof a !== "object" || typeof b !== "object") {
    return a === b;
  }
  /* Constructor tag ($) must match; undefined on both for records/tuples. */
  if (a.$ !== b.$) return false;
  const ka = Object.keys(a);
  const kb = Object.keys(b);
  if (ka.length !== kb.length) return false;
  for (const k of ka) {
    if (!Object.prototype.hasOwnProperty.call(b, k)) return false;
    if (!march_deep_eq(a[k], b[k])) return false;
  }
  return true;
}

/* ── Native arrays ─────────────────────────────────────────────────
 * NativeI32Arr is an Int32Array, NativeU8Arr a Uint8Array and NativeIntArr a
 * Float64Array (Int's representation). Stores wrap exactly as the native
 * runtime's (typed-array conversion is ToInt32 / ToUint8: mod 2^32 / 2^8),
 * reads of i32 are sign-extended, and an out-of-bounds index fails with the
 * native message.
 *
 * set mutates in place and returns the same array. The native runtime copies
 * when the array is shared (rc > 1), but RC is erased on this target, so a
 * program that keeps using an array after `set` on it sees the new value here.
 * Thread arrays linearly (the usual NativeArray style) and both agree. */
function march_native_arr_oob(fn, a, i) {
  throw new RangeError(`march: runtime error: ${fn}: index ${i} out of bounds (len=${a.length})`);
}
function march_native_arr_fill(a, fill) { if (fill !== 0) a.fill(fill); return a; }

// The bounds test stays inline and tiny (an integer in [0, length): `i >>> 0`
// is i only for a whole number in [0, 2^32)); the
// error path is out of line so V8 inlines the accessors.
export function march_native_i32_arr_make(n, fill) { return march_native_arr_fill(new Int32Array(n), fill); }
export function march_native_i32_arr_length(a) { return a.length; }
export function march_native_i32_arr_get(a, i) { if (!((i >>> 0) === i && i < a.length)) march_native_arr_oob("native_i32_arr_get", a, i); return a[i]; }
export function march_native_i32_arr_set(a, i, v) { if (!((i >>> 0) === i && i < a.length)) march_native_arr_oob("native_i32_arr_set", a, i); a[i] = v; return a; }

export function march_native_u8_arr_make(n, fill) { return march_native_arr_fill(new Uint8Array(n), fill); }
export function march_native_u8_arr_length(a) { return a.length; }
export function march_native_u8_arr_get(a, i) { if (!((i >>> 0) === i && i < a.length)) march_native_arr_oob("native_u8_arr_get", a, i); return a[i]; }
export function march_native_u8_arr_set(a, i, v) { if (!((i >>> 0) === i && i < a.length)) march_native_arr_oob("native_u8_arr_set", a, i); a[i] = v; return a; }

export function march_native_int_arr_make(n, fill) { return march_native_arr_fill(new Float64Array(n), fill); }
export function march_native_int_arr_length(a) { return a.length; }
export function march_native_int_arr_get(a, i) { if (!((i >>> 0) === i && i < a.length)) march_native_arr_oob("native_int_arr_get", a, i); return a[i]; }
export function march_native_int_arr_set(a, i, v) { if (!((i >>> 0) === i && i < a.length)) march_native_arr_oob("native_int_arr_set", a, i); a[i] = v; return a; }

/* NativeU8Arr -> Bytes: a byte string (one code unit per byte, see "Byte
 * strings" in the JS backend design doc) in the Bytes constructor. */
export function march_u8_arr_to_bytes(a) {
  return { $: "Bytes", _0: march_bytes_to_string(a) };
}

/* --js-int-check: [r] is the double result of [a op b]; throw when it is
 * outside the doubles' exact integer range, where it has silently rounded. */
export function march_ck_int(r, a, op, b, loc) {
  if (Number.isSafeInteger(r)) return r;
  throw new RangeError(`Int overflow on the JS target in ${loc}: ${a} ${op} ${b}`);
}

/* --js-int-check: an Int literal outside the doubles' exact range. */
export function march_ck_lit(text, loc) {
  throw new RangeError(`Int literal ${text} is not exact on the JS target in ${loc}`);
}

/* process_argv: under Node, the arguments after the script; [] in a browser. */
export function march_process_argv() {
  const args = (typeof process !== "undefined" && process.argv) ? process.argv.slice(2) : [];
  let list = { $: "Nil" };
  for (let i = args.length - 1; i >= 0; i--) list = { $: "Cons", _0: args[i], _1: list };
  return list;
}

/* ── Panics ──────────────────────────────────────────────────────────────
 * A March panic is a thrown Error tagged .marchPanic, its message the panic
 * report as a byte string.  The test runner catches a tagged throw the way
 * the native runner catches a longjmp'd march_panic; an untagged Error is a
 * genuine JS fault and, as there, kills the process. */
export function march_panic(msg) {
  const e = new Error(msg === undefined || msg === null ? "panic" : String(msg));
  e.marchPanic = true;
  throw e;
}

/* ── Capability dictionaries under `march --test` ────────────────────────
 * --test injects the ambient-capability dispatch wrappers (lib/ir/io_ops_gen.ml),
 * and each wrapper opens with `match cap_dict(c)`.  Native's builtins treat a
 * capability as NULL-or-a-dictionary (runtime/march_runtime.c "Capabilities"),
 * and a JS capability is a value with no representation of its own: the
 * argument-free entry call leaves it undefined, exactly native's NULL.  None
 * must be a fresh tagged object here — JS Option has no NULL niche — so the
 * wrapper's `Some(d)`/`None` arms match. */
export function march_cap_dict(c) {
  return (c === null || c === undefined)
    ? { $: "None" }
    : { $: "Some", _0: c };
}
export function march_cap_impl(_c, d) { return d; }
export function march_mint_cap(_c) { return undefined; }
export function march_cap_narrow(c) { return c; }

/* ── Test harness: the `march --target js --test` runner ─────────────────
 * A line-for-line port of the C runner in runtime/march_runtime.c
 * (march_test_init / march_test_header / march_test_run / march_test_report
 * and march_assert_fail's report engine), which is itself a port of
 * lib/errors/test_report.ml that the interpreter runs: a failed test must
 * report byte for byte the same on every backend.  Change one, change all.
 *
 * A JS panic is a thrown Error tagged .marchPanic (march_panic above); the
 * runner catches it the way the native runner longjmp's back.  Test
 * functions may be async, so the runner awaits them one at a time: the
 * dot/✓/F stream stays in order, and `march_test_report` still runs after
 * every test has settled. */

function march_test_write(s) { march_write(s, false); }

/* ── Byte strings as byte arrays: the report engine's working form ──
 * The differ's work strings are byte strings (see "Byte strings" above);
 * it operates on byte arrays, since it counts columns in bytes, splits at
 * byte offsets, and marks a byte's whole UTF-8 sequence.  tr_bytes /
 * tr_bstr cross the boundary at the edges of the engine. */
function tr_bytes(s) {
  if (s === null || s === undefined || s === "") return [];
  const v = march_byte_view(s);
  if (v) return Array.from(v);
  const n = s.length, a = new Array(n);
  for (let i = 0; i < n; i++) {
    const c = s.charCodeAt(i);
    a[i] = c < 0x80 ? c : c - MARCH_RAW_BASE;
  }
  return a;
}
function tr_bstr(a) { return a.length ? march_bytes_to_string(a) : ""; }

const TR_ELLIPSIS = [0xe2, 0x80, 0xa6];   /* UTF-8 "…" */
const TR_ELIDE_OVER = 60;

function tr_cont(b) { return (b & 0xc0) === 0x80; }
function tr_width(a) {
  let w = 0;
  for (let i = 0; i < a.length; i++) if (!tr_cont(a[i])) w++;
  return w;
}

function TrBuf() { this.a = []; }
TrBuf.prototype.add = function (a) { for (let i = 0; i < a.length; i++) this.a.push(a[i]); };

/* test_report.ml's [clip]: at most [max] columns, the last an ellipsis. */
function tr_clip(a, max) {
  if (tr_width(a) <= max) return a.slice();
  const out = [];
  let w = 0, i = 0;
  const n = a.length;
  while (i < n && (w < max - 1 || tr_cont(a[i]))) {
    if (!tr_cont(a[i])) w++;
    out.push(a[i]);
    i++;
  }
  const b = new TrBuf();
  b.add(out); b.add(TR_ELLIPSIS);
  return b.a;
}

/* test_report.ml's [quote]. */
function tr_quote(s) {
  const out = [34];
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (c === 34) out.push(92, 34);
    else if (c === 92) out.push(92, 92);
    else if (c === 10) out.push(92, 110);
    else if (c === 9) out.push(92, 116);
    else if (c === 13) out.push(92, 114);
    else if (c < 0x20 || c === 0x7f) {
      const hx = c.toString(16).padStart(2, "0");   /* %02x, lowercase */
      out.push(92, 120);
      for (const ch of hx) out.push(ch.charCodeAt(0));
    } else out.push(c);
  }
  out.push(34);
  return out;
}

/* Node kinds: LEAF / STR / LIST / TUPLE / RECORD / CTOR.
 * text: LEAF/STR the text (STR's includes the quotes and escapes);
 * CTOR/RECORD the name ([] = none).  sep: RECORD ": " or " = " (interned,
 * so === compares). */
const TR_LEAF = 0, TR_STR = 1, TR_LIST = 2, TR_TUPLE = 3, TR_RECORD = 4, TR_CTOR = 5;
function tr_node(kind) { return { kind, text: null, sep: null, n: 0, items: [], keys: null }; }

/* The parser: tr_parse.s is a byte array.  NULL (JS null) is "unreadable". */
function tr_is_delim(b) {
  return b === 44 || b === 40 || b === 41 || b === 91 || b === 93
    || b === 123 || b === 125 || b === 34;
}
function tr_alpha_byte(b) { return (b >= 65 && b <= 90) || (b >= 97 && b <= 122); }
function tr_alnum_byte(b) { return tr_alpha_byte(b) || (b >= 48 && b <= 57); }
function tr_is_ident(t) {
  if (!t.length) return false;
  if (!(tr_alpha_byte(t[0]) || t[0] === 95)) return false;
  for (let i = 0; i < t.length; i++)
    if (!(tr_alnum_byte(t[i]) || t[i] === 95 || t[i] === 46)) return false;
  return true;
}
/* OCaml's String.trim: ' ', '\012', '\n', '\r', '\t' (\012 == '\n'). */
function tr_is_trim(b) { return b === 32 || b === 10 || b === 13 || b === 9; }

function tr_skip(p) { while (p.pos < p.n && p.s[p.pos] === 32) p.pos++; }
function tr_peek(p) { return p.pos < p.n ? p.s[p.pos] : -1; }

/* Items up to [close]; null on an unreadable sequence. */
function tr_seq(p, kind, close) {
  const v = tr_node(kind);
  tr_skip(p);
  if (tr_peek(p) === close) { p.pos++; return v; }
  for (;;) {
    const x = tr_value(p);
    if (!x) return null;
    v.items.push(x); v.n++;
    tr_skip(p);
    const c = tr_peek(p);
    if (c === 44) { p.pos++; continue; }
    if (c === close) { p.pos++; return v; }
    return null;
  }
}

function tr_fields(p, name) {
  const v = tr_node(TR_RECORD);
  v.text = name; v.sep = null; v.keys = [];
  tr_skip(p);
  if (tr_peek(p) === 125) { p.pos++; v.sep = ": "; return v; }
  for (;;) {
    tr_skip(p);
    const start = p.pos;
    while (p.pos < p.n && p.s[p.pos] !== 58 && p.s[p.pos] !== 61 && !tr_is_delim(p.s[p.pos])) p.pos++;
    const c = tr_peek(p);
    const this_sep = c === 58 ? ": " : c === 61 ? " = " : null;
    if (!this_sep || (v.sep !== null && v.sep !== this_sep)) return null;
    v.sep = this_sep;
    const key = tr_trim(p.s.slice(start, p.pos));
    if (!tr_is_ident(key)) return null;
    p.pos++;
    const x = tr_value(p);
    if (!x) return null;
    v.items.push(x); v.n++; v.keys.push(key);
    tr_skip(p);
    const c2 = tr_peek(p);
    if (c2 === 44) { p.pos++; continue; }
    if (c2 === 125) { p.pos++; return v; }
    return null;
  }
}

function tr_trim(a) {
  let x = 0, y = a.length;
  while (x < y && tr_is_trim(a[x])) x++;
  while (y > x && tr_is_trim(a[y - 1])) y--;
  return a.slice(x, y);
}

function tr_value(p) {
  tr_skip(p);
  const c = tr_peek(p);
  if (c < 0) return null;
  if (c === 34) {                       /* '"' */
    const start = p.pos;
    p.pos++;
    while (p.pos < p.n && p.s[p.pos] !== 34) {
      if (p.s[p.pos] === 92) p.pos++;   /* a backslash skips its escape */
      p.pos++;
    }
    if (p.pos >= p.n) return null;      /* no closing quote: unreadable */
    p.pos++;
    const v = tr_node(TR_STR);
    v.text = p.s.slice(start, p.pos);
    return v;
  }
  if (c === 91) { p.pos++; return tr_seq(p, TR_LIST, 93); }        /* '[' ... ']' */
  if (c === 40) {                                                   /* '(' ... ')' */
    p.pos++;
    const v = tr_seq(p, TR_TUPLE, 41);
    if (v && v.n === 0) { v.kind = TR_LEAF; v.text = [40, 41]; }    /* "()" */
    return v;
  }
  if (c === 123) { p.pos++; return tr_fields(p, []); }              /* '{' fields */
  if (tr_is_delim(c)) return null;
  const start = p.pos;
  while (p.pos < p.n && !tr_is_delim(p.s[p.pos])) p.pos++;
  const text = tr_trim(p.s.slice(start, p.pos));
  if (!text.length) return null;
  if (p.pos < p.n && p.s[p.pos] === 40 && tr_is_ident(text)) {      /* Name(args) */
    p.pos++;
    const v = tr_seq(p, TR_CTOR, 41);
    if (!v) return null;
    v.text = text;
    return v;
  }
  if (p.pos < p.n && p.s[p.pos] === 123 && tr_is_ident(text)) {     /* Name{fields} */
    p.pos++;
    return tr_fields(p, text);
  }
  const v = tr_node(TR_LEAF);
  v.text = text;
  return v;
}

function tr_parse(bytes) {
  const p = { s: bytes, n: bytes.length, pos: 0 };
  const v = tr_value(p);
  if (v) {
    tr_skip(p);
    if (p.pos === p.n) return v;
  }
  const leaf = tr_node(TR_LEAF);
  leaf.text = bytes.slice();
  return leaf;
}

/* text/keys: byte arrays; null text compares equal only to null. */
function tr_text_eq(x, y) {
  if (x === null || x === undefined || y === null || y === undefined)
    return (x === null || x === undefined) && (y === null || y === undefined);
  if (x.length !== y.length) return false;
  for (let i = 0; i < x.length; i++) if (x[i] !== y[i]) return false;
  return true;
}

function tr_eq(a, b) {
  if (a.kind !== b.kind || a.n !== b.n) return false;
  if (!tr_text_eq(a.text, b.text)) return false;
  if (a.kind === TR_RECORD && a.sep !== b.sep) return false;
  for (let i = 0; i < a.n; i++) {
    if (a.keys && !tr_text_eq(a.keys[i], b.keys[i])) return false;
    if (!tr_eq(a.items[i], b.items[i])) return false;
  }
  return true;
}

function tr_print_to(b, v) {
  switch (v.kind) {
    case TR_LEAF: case TR_STR: b.add(v.text); return;
    case TR_LIST: case TR_TUPLE: case TR_CTOR:
      if (v.kind === TR_CTOR) { b.add(v.text); b.add([40]); }
      else b.add([v.kind === TR_LIST ? 91 : 40]);
      for (let i = 0; i < v.n; i++) {
        if (i > 0) b.add([44, 32]);
        tr_print_to(b, v.items[i]);
      }
      b.add([v.kind === TR_LIST ? 93 : 41]);
      return;
    case TR_RECORD:
      if (v.text.length) { b.add(v.text); b.add([32]); }
      b.add([123, 32]);                                              /* "{ " */
      for (let i = 0; i < v.n; i++) {
        if (i > 0) b.add([44, 32]);
        b.add(v.keys[i]); b.add(tr_bytes(v.sep));
        tr_print_to(b, v.items[i]);
      }
      b.add([32, 125]);                                              /* " }" */
      return;
  }
}
function tr_print(v) { const b = new TrBuf(); tr_print_to(b, v); return b.a; }

/* A path step: an index into a list / tuple / constructor, or a field.
 * diff kinds: 0 WHOLE, 1 CHARS, 2 LENGTH. */
function tr_diff_new() { return { steps: [], nsteps: 0, kind: 0, chars: 0, nl: 0, nr: 0 }; }

/* test_report.ml's [first_diff]; [a] and [b] differ.  A path deeper than 64
 * steps stops there and marks the whole part. */
function tr_first_diff(a, b, d) {
  if (d.steps.length >= 64) { d.kind = 0; return; }
  const same_shape =
    (a.kind === TR_LIST && b.kind === TR_LIST)
    || (a.kind === TR_TUPLE && b.kind === TR_TUPLE && a.n === b.n)
    || (a.kind === TR_CTOR && b.kind === TR_CTOR && a.n === b.n
        && tr_text_eq(a.text, b.text));
  if (same_shape) {
    const m = a.n < b.n ? a.n : b.n;
    for (let i = 0; i < m; i++) {
      if (!tr_eq(a.items[i], b.items[i])) {
        d.steps.push({ is_field: 0, idx: i, field: null });
        tr_first_diff(a.items[i], b.items[i], d);
        return;
      }
    }
    /* Only a list can get here (equal-length tuples / constructors that
       differ have a differing item). */
    d.kind = 2; d.nl = a.n; d.nr = b.n;
    return;
  }
  if (a.kind === TR_RECORD && b.kind === TR_RECORD && a.n === b.n
      && tr_text_eq(a.text, b.text)) {
    let keys_same = true;
    for (let i = 0; i < a.n; i++)
      if (!tr_text_eq(a.keys[i], b.keys[i])) { keys_same = false; break; }
    if (keys_same) {
      for (let i = 0; i < a.n; i++) {
        if (!tr_eq(a.items[i], b.items[i])) {
          d.steps.push({ is_field: 1, idx: i, field: a.keys[i] });
          tr_first_diff(a.items[i], b.items[i], d);
          return;
        }
      }
      d.kind = 0;  /* only the separators differ */
      return;
    }
  }
  if (a.kind === TR_STR && b.kind === TR_STR) {
    const la = a.text.length, lb = b.text.length;
    const n = la < lb ? la : lb;
    let i = 0;
    while (i < n && a.text[i] === b.text[i]) i++;
    while (i > 0 && tr_cont(a.text[i])) i--;
    d.kind = 1; d.chars = i;
    return;
  }
  d.kind = 0;
}

function tr_path_text(d, root) {
  const b = new TrBuf();
  let v = root;
  for (let i = 0; i < d.steps.length; i++) {
    if (d.steps[i].is_field) { b.add([46]); b.add(d.steps[i].field); }
    else if (v.kind === TR_LIST) b.add(tr_bytes("[" + d.steps[i].idx + "]"));
    else break;  /* a constructor or tuple argument: the carets show the rest */
    v = v.items[d.steps[i].idx];
  }
  return b.a;
}

function tr_render_new(d, elide, longer) {
  return { b: new TrBuf(), col: 0, mcol: 0, mwidth: 1, elide, d, longer };
}
function tr_r_add(r, a) { r.b.add(a); r.col += tr_width(a); }
function tr_r_marked(r, a) {
  const c = r.col;
  tr_r_add(r, a);
  const w = tr_width(a);
  r.mcol = c; r.mwidth = w > 1 ? w : 1;
}
function tr_r_print(r, v) { tr_r_add(r, tr_print(v)); }

function tr_r_str(r, s, i) {
  const n = s.length;
  if (!r.elide || tr_width(s) <= TR_ELIDE_OVER) {
    tr_r_add(r, s.slice(0, i));
    let j = i + 1;
    while (j < n && tr_cont(s[j])) j++;
    tr_r_marked(r, s.slice(i, j));
    tr_r_add(r, s.slice(j, n));
    return;
  }
  let back = i, cols = 0;
  while (back > 1 && cols < 20) { back--; if (!tr_cont(s[back])) cols++; }
  let fwd = i, fcols = 0;
  while (fwd < n - 1 && fcols < 30) { fwd++; if (fwd < n && !tr_cont(s[fwd])) fcols++; }
  while (fwd < n && tr_cont(s[fwd])) fwd++;
  /* Only the closing quote left: show it rather than an ellipsis. */
  if (fwd >= n - 1) fwd = n;
  { const b = new TrBuf(); b.add([34]); if (back > 1) b.add(TR_ELLIPSIS); tr_r_add(r, b.a); }
  tr_r_add(r, s.slice(back, i));
  let j = i + 1;
  while (j < n && tr_cont(s[j])) j++;
  if (j > n) j = n;
  tr_r_marked(r, s.slice(i, j));
  const stop = j > fwd ? j : fwd;
  tr_r_add(r, s.slice(j, stop));
  if (stop < n) { const b = new TrBuf(); b.add(TR_ELLIPSIS); b.add([34]); tr_r_add(r, b.a); }
}

function tr_r_target(r, v) {
  const d = r.d;
  if (d.kind === 1 && v.kind === TR_STR) { tr_r_str(r, v.text, d.chars); return; }
  if (d.kind === 2 && v.kind === TR_LIST) {
    const common = d.nl < d.nr ? d.nl : d.nr;
    tr_r_add(r, [91]);
    if (!r.longer) {
      if (r.elide && v.n > 0) tr_r_add(r, TR_ELLIPSIS);
      else for (let j = 0; j < v.n; j++) { if (j > 0) tr_r_add(r, [44, 32]); tr_r_print(r, v.items[j]); }
      tr_r_marked(r, [93]);
      return;
    }
    if (common > 0) {
      if (r.elide) tr_r_add(r, tr_bytes(TR_ELLIPSIS_STR + ", "));
      else for (let j = 0; j < common && j < v.n; j++) { tr_r_print(r, v.items[j]); tr_r_add(r, [44, 32]); }
    }
    const e = new TrBuf();
    if (r.elide) {
      if (v.n > common) {
        e.add(tr_clip(tr_print(v.items[common]), TR_ELIDE_OVER));
        if (v.n > common + 1) { const b = new TrBuf(); b.add([44, 32]); b.add(TR_ELLIPSIS); e.add(b.a); }
      }
    } else {
      for (let j = common; j < v.n; j++) {
        if (j > common) e.add([44, 32]);
        tr_print_to(e, v.items[j]);
      }
    }
    tr_r_marked(r, e.a);
    tr_r_add(r, [93]);
    return;
  }
  const p = tr_print(v);
  if (r.elide) { tr_r_marked(r, tr_clip(p, TR_ELIDE_OVER)); return; }
  tr_r_marked(r, p);
}

/* The ellipsis as a byte string, for mixing with ", " text. */
const TR_ELLIPSIS_STR = "\u2026";

function tr_r_go(r, v, step) {
  const d = r.d;
  if (step >= d.steps.length) { tr_r_target(r, v); return; }
  const s = d.steps[step];
  const i = s.idx;
  if (i < 0 || i >= v.n) { tr_r_target(r, v); return; }
  if (v.kind === TR_RECORD && s.is_field) {
    if (v.text.length) { tr_r_add(r, v.text); tr_r_add(r, [32]); }
    tr_r_add(r, [123, 32]);
    if (r.elide) {
      if (i > 0) { const b = new TrBuf(); b.add(TR_ELLIPSIS); b.add([44, 32]); tr_r_add(r, b.a); }
      tr_r_add(r, v.keys[i]); tr_r_add(r, tr_bytes(v.sep));
      tr_r_go(r, v.items[i], step + 1);
      if (i < v.n - 1) { const b = new TrBuf(); b.add([44, 32]); b.add(TR_ELLIPSIS); tr_r_add(r, b.a); }
    } else {
      for (let j = 0; j < v.n; j++) {
        if (j > 0) tr_r_add(r, [44, 32]);
        tr_r_add(r, v.keys[j]); tr_r_add(r, tr_bytes(v.sep));
        if (j === i) tr_r_go(r, v.items[j], step + 1);
        else tr_r_print(r, v.items[j]);
      }
    }
    tr_r_add(r, [32, 125]);
    return;
  }
  if (!s.is_field && (v.kind === TR_LIST || v.kind === TR_TUPLE || v.kind === TR_CTOR)) {
    if (v.kind === TR_CTOR) { tr_r_add(r, v.text); tr_r_add(r, [40]); }
    else tr_r_add(r, [v.kind === TR_LIST ? 91 : 40]);
    if (r.elide) {
      if (i > 0) { const b = new TrBuf(); b.add(TR_ELLIPSIS); b.add([44, 32]); tr_r_add(r, b.a); }
      tr_r_go(r, v.items[i], step + 1);
      if (i < v.n - 1) { const b = new TrBuf(); b.add([44, 32]); b.add(TR_ELLIPSIS); tr_r_add(r, b.a); }
    } else {
      for (let j = 0; j < v.n; j++) {
        if (j > 0) tr_r_add(r, [44, 32]);
        if (j === i) tr_r_go(r, v.items[j], step + 1);
        else tr_r_print(r, v.items[j]);
      }
    }
    tr_r_add(r, [v.kind === TR_LIST ? 93 : 41]);
    return;
  }
  tr_r_target(r, v);
}

function tr_line(b, s) { b.add(tr_bytes(s)); b.add([10]); }

function tr_label(b, side, src, printed) {
  /* squash: drop spaces, compare */
  const sq = (a) => a.filter((c) => c !== 32);
  const xs = sq(src), ys = sq(printed);
  b.add([32, 32, 32, 32]);
  b.add(tr_bytes(side));
  if (src.length && !tr_text_eq(xs, ys)) {
    b.add([32, 96]); b.add(src); b.add([96]);   /* " `src`" */
  }
  b.add([10]);
}

function tr_value_line(b, v, max) {
  b.add(tr_bytes("        "));
  b.add(tr_clip(v, max));
  b.add([10]);
}

/* test_report.ml's [compare_body]. */
function tr_compare_body(op, lsrc, rsrc, l, r) {
  const b = new TrBuf();
  if (tr_text_eq(op, [33, 61, 45 /* "!=" */])) {
    tr_line(b, "    Both sides are:");
    tr_value_line(b, l, 200);
  } else if (tr_text_eq(op, [61, 61 /* "==" */]) && !tr_text_eq(l, r)) {
    const lt = tr_parse(l), rt = tr_parse(r);
    if (tr_eq(lt, rt)) {
      tr_label(b, "left", lsrc, l);  tr_value_line(b, l, 200);
      tr_label(b, "right", rsrc, r); tr_value_line(b, r, 200);
    } else {
      const d = tr_diff_new();
      tr_first_diff(lt, rt, d);
      const elide = tr_width(l) > TR_ELIDE_OVER || tr_width(r) > TR_ELIDE_OVER;
      const nl = d.kind === 2 ? d.nl : 0, nr = d.kind === 2 ? d.nr : 0;
      for (let side = 0; side < 2; side++) {
        const rr = tr_render_new(d, elide, side === 0 ? nl > nr : nr > nl);
        tr_r_go(rr, side === 0 ? lt : rt, 0);
        tr_label(b, side === 0 ? "left" : "right", side === 0 ? lsrc : rsrc,
                 side === 0 ? l : r);
        b.add(tr_bytes("        ")); b.add(rr.b.a); b.add([10]);
        b.add(tr_bytes("        "));
        for (let k = 0; k < rr.mcol; k++) b.add([32]);
        for (let k = 0; k < rr.mwidth; k++) b.add([94]);   /* caret ^ */
        b.add([10]);
      }
      const where = tr_path_text(d, lt);
      if (d.kind === 2) {
        const what = new TrBuf();
        if (!where.length) what.add(tr_bytes("The left list"));
        else { what.add([96]); what.add(where); what.add(tr_bytes("` on the left")); }
        tr_line(b, "");
        b.add([32, 32, 32, 32]); b.add(what.a);
        b.add(tr_bytes(" has " + d.nl + " element" + (d.nl === 1 ? "" : "s")
                  + "; on the right it has " + d.nr + "."));
        b.add([10]);
      } else if (where.length) {
        tr_line(b, "");
        b.add(tr_bytes("    They first differ at `")); b.add(where);
        b.add(tr_bytes("`.") ); b.add([10]);
      }
    }
  } else {
    tr_label(b, "left", lsrc, l);  tr_value_line(b, l, 200);
    tr_label(b, "right", rsrc, r); tr_value_line(b, r, 200);
    if (tr_text_eq(op, [61, 61])) {
      tr_line(b, "");
      tr_line(b, "    They print the same, so they differ in something printing");
      tr_line(b, "    does not show: a custom `Eq` impl, or a Float NaN.");
    }
  }
  if (b.a.length && b.a[b.a.length - 1] === 10) b.a.pop();
  return b.a;
}

/* Split [a] at the \x1f separators into at most 5 byte arrays. */
function tr_split(a, max) {
  const out = [];
  let start = 0;
  for (let i = 0; i <= a.length && out.length < max; i++) {
    if (i === a.length || a[i] === 0x1f) {
      out.push(a.slice(start, i));
      start = i + 1;
    }
  }
  return out;
}

/* __assert_fail(meta, left, right): the native engine, ported — see
 * runtime/march_runtime.c's march_assert_fail. */
export function march_assert_fail(meta, left, right) {
  const parts = tr_split(tr_bytes(meta === undefined || meta === null ? "" : String(meta)), 5);
  while (parts.length < 5) parts.push([]);
  const header = parts[0], op = parts[1], lsrc = parts[2], rsrc = parts[3], flags = parts[4];
  const b = new TrBuf();
  b.add(header);
  if (op.length) {
    const lq = String.fromCharCode(flags.length ? flags[0] : 0) === "q";
    const rq = flags.length > 1 && String.fromCharCode(flags[1]) === "q";
    const lb = tr_bytes(left === undefined || left === null ? "" : String(left));
    const rb = tr_bytes(right === undefined || right === null ? "" : String(right));
    const l = lq ? tr_quote(lb) : lb;
    const r = rq ? tr_quote(rb) : rb;
    b.add([10, 10]);
    b.add(tr_compare_body(op, lsrc, rsrc, l, r));
  }
  march_panic(tr_bstr(b.a));
}

/* ── The runner ─────────────────────────────────────────────────────────── */

/* At most 2048 failures recorded to avoid unbounded memory (native parity). */
const MARCH_TEST_MAX_FAILURES = 2048;

let march_test_verbose = false;
let march_test_filter = null;         /* null: unset; else the --filter= text */
let march_test_total = 0;
let march_test_failed = 0;
const march_test_fnames = [];
const march_test_fmsgs = [];
let march_test_cur_header = null;     /* byte string, \x01-hole, or null */

/* Parse --verbose / -v and --filter=... from Node's argv (browser: none). */
export function march_test_init() {
  const args = (typeof process !== "undefined" && process.argv) ? process.argv.slice(2) : [];
  for (const a of args) {
    if (a === "--verbose" || a === "-v") march_test_verbose = true;
    else if (a.startsWith("--filter=")) march_test_filter = a.slice(9);
  }
}

/* The running test's panic header (Lower_tests sets it first thing): a
 * rendered `-- TEST FAILURE --` report with \x01 where the panic message
 * goes.  Returns nothing, as native's NULL does. */
export function march_test_header(header) {
  march_test_cur_header = (header === null || header === undefined) ? null : String(header);
  return undefined;
}

/* The message a failed test reports: a rendered report as it is, any
 * other panic message put into the test's panic header. */
function march_test_failure_message(fail) {
  const f = fail !== "" ? fail : "assertion failed";
  if (f.startsWith("-- TEST FAILURE ") || march_test_cur_header === null) return f;
  const hole = march_test_cur_header.indexOf("\x01");
  if (hole < 0) return f;
  return march_test_cur_header.slice(0, hole) + f + march_test_cur_header.slice(hole + 1);
}

/* Print [msg] with every non-empty line indented by [indent]. */
function march_test_indented_str(indent, msg) {
  let out = "", p = 0;
  const n = msg.length;
  while (p < n) {
    const nl = msg.indexOf("\n", p);
    const seg = nl < 0 ? msg.slice(p) : msg.slice(p, nl);
    if (seg.length > 0) out += indent + seg;
    out += "\n";
    if (nl < 0) break;
    p = nl + 1;
  }
  return out;
}

/* Run the setup_all function once before any tests. */
export async function march_test_setup_all(fn) { if (fn) await fn(); }

/* Run one test (which may be async); the name is its display name (a byte
 * string); setup, if given, runs before each test. */
export async function march_test_run(fn, name, setup) {
  /* Apply the filter (a case-sensitive substring match). */
  if (march_test_filter !== null && !String(name).includes(march_test_filter)) return;

  march_test_total++;
  if (setup) await setup();

  let fail = "";
  try {
    await fn();
  } catch (e) {
    if (!e || !e.marchPanic) throw e;     /* a real fault, not a March panic */
    fail = e.message === undefined || e.message === null ? "" : String(e.message);
  }

  if (fail === "") {
    if (march_test_verbose) march_test_write("  \u2713 " + name + "\n");
    else march_test_write(".");
  } else {
    const msg = march_test_failure_message(fail);
    if (march_test_verbose) march_test_write("  \u2717 " + name + "\n" + march_test_indented_str("    ", msg));
    else march_test_write("F");
    if (march_test_fnames.length < MARCH_TEST_MAX_FAILURES) {
      march_test_fnames.push(String(name));
      march_test_fmsgs.push(msg);
    }
    march_test_failed++;
  }
}

/* Print the final summary and exit with the test result (0 = all pass). */
export function march_test_report() {
  let out = "";
  if (!march_test_verbose) out += "\n";
  if (march_test_failed > 0 && !march_test_verbose) {
    out += "\n" + march_test_fnames.length + " failure(s):\n\n";
    for (let i = 0; i < march_test_fnames.length; i++) {
      out += "FAIL: \"" + march_test_fnames[i] + "\"\n"
        + march_test_indented_str("  ", march_test_fmsgs[i]) + "\n";
    }
  }
  out += "Finished: " + march_test_total + (march_test_total === 1 ? " test" : " tests")
    + ", " + march_test_failed + (march_test_failed === 1 ? " failure" : " failures") + "\n";
  march_test_write(out);
  const code = march_test_failed > 0 ? 1 : 0;
  /* Native ends with _exit().  process.exit() would truncate stdout when it
   * is a pipe (Node writes pipes asynchronously), so flush the queued writes
   * and exit from the flush callback; process.exitCode covers the case of no
   * stdout at all (a browser: the caller gets the code back). */
  if (typeof process !== "undefined" && process.exit) {
    process.exitCode = code;
    if (process.stdout && process.stdout.write)
      process.stdout.write("", () => process.exit(code));
  }
  return code;
}
