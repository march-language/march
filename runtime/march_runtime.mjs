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

// The last few strings' byte views (null: every code unit is one byte).
const march_view_cache = [];
function march_byte_view(s) {
  if (s.length < 32) {
    for (let i = 0; i < s.length; i++) if (!march_unit_is_byte(s.charCodeAt(i))) return march_encode_bytes(s);
    return null;
  }
  for (const e of march_view_cache) if (e.s === s) return e.v;
  let v = null;
  for (let i = 0; i < s.length; i++) if (!march_unit_is_byte(s.charCodeAt(i))) { v = march_encode_bytes(s); break; }
  march_view_cache.unshift({ s, v });
  if (march_view_cache.length > 4) march_view_cache.pop();
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

// The bounds test stays inline and tiny (an integer in [0, length)); the
// error path is out of line so V8 inlines the accessors.
export function march_native_i32_arr_make(n, fill) { return march_native_arr_fill(new Int32Array(n), fill); }
export function march_native_i32_arr_length(a) { return a.length; }
export function march_native_i32_arr_get(a, i) { if (!(i >= 0 && i < a.length && i === Math.floor(i))) march_native_arr_oob("native_i32_arr_get", a, i); return a[i]; }
export function march_native_i32_arr_set(a, i, v) { if (!(i >= 0 && i < a.length && i === Math.floor(i))) march_native_arr_oob("native_i32_arr_set", a, i); a[i] = v; return a; }

export function march_native_u8_arr_make(n, fill) { return march_native_arr_fill(new Uint8Array(n), fill); }
export function march_native_u8_arr_length(a) { return a.length; }
export function march_native_u8_arr_get(a, i) { if (!(i >= 0 && i < a.length && i === Math.floor(i))) march_native_arr_oob("native_u8_arr_get", a, i); return a[i]; }
export function march_native_u8_arr_set(a, i, v) { if (!(i >= 0 && i < a.length && i === Math.floor(i))) march_native_arr_oob("native_u8_arr_set", a, i); a[i] = v; return a; }

export function march_native_int_arr_make(n, fill) { return march_native_arr_fill(new Float64Array(n), fill); }
export function march_native_int_arr_length(a) { return a.length; }
export function march_native_int_arr_get(a, i) { if (!(i >= 0 && i < a.length && i === Math.floor(i))) march_native_arr_oob("native_int_arr_get", a, i); return a[i]; }
export function march_native_int_arr_set(a, i, v) { if (!(i >= 0 && i < a.length && i === Math.floor(i))) march_native_arr_oob("native_int_arr_set", a, i); a[i] = v; return a; }

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
