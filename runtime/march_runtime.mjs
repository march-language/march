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

/* string_to_float accepts exactly what C strtod accepts in the "C" locale with
 * the whole string consumed — the native runtime's grammar (#1178; see
 * march_float_syntax_ok in march_runtime.c for the grammar, and
 * test/native/string_to_float_grammar.march, which pins all three backends).
 * `Number(s)` is not that: it reads "" and "  " as 0, trims trailing space,
 * takes 0b/0o, spells infinity only "Infinity", rejects hex floats, and its
 * NaN result can't tell "nan" from a failed parse. */
const MARCH_FLOAT_DEC = /^(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$/;
const MARCH_FLOAT_HEX = /^0[xX](?:([0-9a-fA-F]+)(?:\.([0-9a-fA-F]*))?|\.([0-9a-fA-F]+))(?:[pP]([+-]?[0-9]+))?$/;
const MARCH_FLOAT_INF = /^[iI][nN][fF](?:[iI][nN][iI][tT][yY])?$/;
const MARCH_FLOAT_NAN = /^[nN][aA][nN](?:\([0-9A-Za-z_]*\))?$/;

/* Hex digits `int`.`frac` times 2^exp, correctly rounded (nearest, ties to
 * even, gradual underflow), as strtod rounds it. */
function march_hex_float(int, frac, exp) {
  const digits = (int + frac).replace(/^0+/, "");
  if (digits === "") return 0;
  const m = BigInt("0x" + digits);
  const e = Number(exp) - 4 * frac.length;
  const bl = m.toString(2).length;
  const top = bl + e;                  // m * 2^e lies in [2^(top-1), 2^top)
  if (top > 1025) return Infinity;
  if (top < -1075) return 0;
  // Bits a double keeps at this magnitude: 53, fewer once subnormal.
  const keep = Math.min(53, top + 1074);
  let shift = bl - keep;
  let q = m;
  if (shift > 0) {
    const sb = BigInt(shift);
    q = m >> sb;
    const rem = m & ((1n << sb) - 1n);
    const half = 1n << (sb - 1n);
    if (rem > half || (rem === half && (q & 1n) === 1n)) q += 1n;
  } else {
    shift = 0;
  }
  // q has at most 54 bits, so Number(q) is exact; the result is representable,
  // and scaling in two halves keeps each power of two a normal double.
  const k = e + shift;
  const k1 = Math.trunc(k / 2);
  return Number(q) * Math.pow(2, k1) * Math.pow(2, k - k1);
}

export function march_string_to_float(s) {
  let i = 0;
  while (i < s.length) {
    const c = s.charCodeAt(i);
    if (c === 32 || (c >= 9 && c <= 13)) i++; else break;
  }
  let neg = false;
  if (s[i] === "+" || s[i] === "-") { neg = s[i] === "-"; i++; }
  const body = s.slice(i);
  let v;
  if (MARCH_FLOAT_DEC.test(body)) v = Number(body);
  else if (MARCH_FLOAT_INF.test(body)) v = Infinity;
  else if (MARCH_FLOAT_NAN.test(body)) v = NaN;
  else {
    const h = MARCH_FLOAT_HEX.exec(body);
    if (h === null) return { $: "None" };
    v = h[3] !== undefined ? march_hex_float("", h[3], h[4] ?? "0")
                           : march_hex_float(h[1], h[2] ?? "", h[4] ?? "0");
  }
  return { $: "Some", _0: neg ? -v : v };
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

/* `to_string` on a value with no Show impl (js_emit's show_expr renders the
 * statically typed parts).  march_show_str is a String BENEATH the top,
 * quoted and escaped like native's cb_put_escaped (march_extras.c: OCaml's
 * String.escaped for the ASCII controls, three-digit decimal escapes).
 * march_show_dyn classifies a value whose static type is a type variable, as
 * native's generic slot does; a JS number cannot say whether it was a Float,
 * so a whole-number Float there prints as an Int. */
export function march_show_str(s) {
  let b = "\"";
  for (let i = 0; i < s.length; i++) {
    const ch = s[i], c = s.charCodeAt(i);
    if (ch === "\"") b += "\\\"";
    else if (ch === "\\") b += "\\\\";
    else if (ch === "\n") b += "\\n";
    else if (ch === "\t") b += "\\t";
    else if (ch === "\r") b += "\\r";
    else if (ch === "\b") b += "\\b";
    else if (c < 32 || c === 127) b += "\\" + String(c).padStart(3, "0");
    else b += ch;
  }
  return b + "\"";
}

export function march_show_dyn(v) {
  if (v === undefined || v === null) return "()";
  switch (typeof v) {
    case "number": return Number.isInteger(v) ? String(v) : march_float_to_string(v);
    case "boolean": return v ? "true" : "false";
    case "string": return march_show_str(v);
    case "function": return "<fn>";
    case "object": break;
    default: return String(v);
  }
  if (typeof v.$ === "string") {
    if (v.$.startsWith("$Clo")) return "<fn>";
    if (v.$ === "Nil" || v.$ === "Cons") {
      const xs = [];
      let p = v;
      while (p && p.$ === "Cons") { xs.push(march_show_dyn(p._0)); p = p._1; }
      if (p && p.$ === "Nil") return "[" + xs.join(", ") + "]";
    }
    const args = [];
    for (let i = 0; ("_" + i) in v; i++) args.push(march_show_dyn(v["_" + i]));
    return args.length === 0 ? v.$ : v.$ + "(" + args.join(", ") + ")";
  }
  const keys = Object.keys(v);
  if (keys.length > 0 && keys.every((k, i) => k === "_" + i))
    return "(" + keys.map((k) => march_show_dyn(v[k])).join(", ") + ")";
  keys.sort();
  return "{ " + keys.map((k) => k + ": " + march_show_dyn(v[k])).join(", ") + " }";
}

/* A top-level String is the identity, as march_value_to_string's. */
export function march_to_string_dyn(v) {
  return typeof v === "string" ? v : march_show_dyn(v);
}

/* A `panic` / `todo` / `unreachable`: the Error's message is the bare text,
 * and [prefix] ("panic: ", "todo: ") is what __try_call puts in front of it
 * on the Err, as the interpreter's message and native's march_panic_user /
 * march_todo_ext do. */
export function march_panic_error(prefix, msg) {
  const e = march_panic_err(String(msg));
  if (typeof Error.captureStackTrace === "function")
    Error.captureStackTrace(e, march_panic_error);
  Object.defineProperty(e, "marchPanicPrefix", { value: prefix });
  return e;
}

/* __try_call / __try_call_val: run a `fn _ -> body` thunk, Ok(result), or
 * Err(message) if it panics (march_try_call in march_runtime.c).  A thunk
 * that is async (it awaits a JS-module extern) is not supported: its panic
 * would reject a Promise this cannot wait for. */
export function march_try_call(thunk) {
  try {
    return { $: "Ok", _0: thunk._0(thunk, true) };
  } catch (e) {
    let msg;
    if (e instanceof RangeError && /call stack/i.test(e.message)) msg = "stack overflow";
    else if (e instanceof Error) msg = (e.marchPanicPrefix || "") + e.message;
    else msg = String(e);
    return { $: "Err", _0: msg };
  }
}

/* process_env / process_cwd / process_pid: node's process; in a browser
 * there is no environment (None), the cwd is "/" and the pid 0. */
export function march_process_env(name) {
  const v = (typeof process !== "undefined" && process.env) ? process.env[name] : undefined;
  return v === undefined ? { $: "None" } : { $: "Some", _0: v };
}
export function march_process_cwd() {
  return (typeof process !== "undefined" && process.cwd) ? process.cwd() : "/";
}
export function march_process_pid() {
  return (typeof process !== "undefined" && typeof process.pid === "number") ? process.pid : 0;
}

/* Int `/` and `%` by zero panic with the operator messages the interpreter
 * and native code use (march_checked_div_op / march_checked_mod_op in
 * march_runtime.c). js_emit inlines the quotient/remainder and calls these
 * only on a zero divisor. */
export function march_div_zero() { throw new Error("division by zero"); }
export function march_mod_zero() { throw new Error("modulo by zero"); }

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

/** `compare` on Float: a total preorder like march_compare_float in
 * march_runtime.c (and the interpreter's Float.compare). NaN equals NaN and
 * is less than every other value; otherwise IEEE order (-0.0 == +0.0). */
export function march_compare_float(x, y) {
  const xn = x !== x, yn = y !== y;
  if (xn || yn) return (yn ? 1 : 0) - (xn ? 1 : 0);
  return x < y ? -1 : x > y ? 1 : 0;
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

/* Float → Int (float_to_int, float_truncate, float_floor, float_ceil,
 * float_round).  `r` is the argument already rounded.  NaN, ±Infinity and a
 * value outside the 63-bit range [-2^62, 2^62) throw with the native
 * runtime's messages (march_float_int_checked in march_runtime.c) instead of
 * returning a JS number that is not an Int.  The bound is the one
 * march_int_ovf uses; between 2^53 and 2^62 the result is an inexact Int, as
 * for any Int on this target. */
function __float_int(r, op) {
  if (r >= -__INT63_LIMIT && r < __INT63_LIMIT) return r;
  throw new Error(op + (r !== r ? ": cannot convert NaN to Int" : ": value out of Int range"));
}
export function march_float_to_int(f) { return __float_int(Math.trunc(f), "float_to_int"); }
export function march_float_truncate(f) { return __float_int(Math.trunc(f), "float_truncate"); }
export function march_float_floor(f) { return __float_int(Math.floor(f), "float_floor"); }
export function march_float_ceil(f) { return __float_int(Math.ceil(f), "float_ceil"); }

/** Float → Int rounding, half AWAY FROM ZERO (mirrors OCaml Float.round;
 * JS Math.round rounds half toward +inf, so Math.round(-2.5) would differ). */
export function march_float_round(f) {
  return __float_int(Math.sign(f) * Math.round(Math.abs(f)), "float_round");
}

/* ── System ────────────────────────────────────────────────────────── */

/** Seconds since the Unix epoch as a Float (mirrors `unix_time`). */
export function march_unix_time() {
  return Date.now() / 1000;
}

/* ocap phase 1 capability check point; runtime/march_extras.c has the native
 * twin and test/run_cap_conformance.ml pins that they agree. Nothing refuses
 * except the TEST-ONLY hook MARCH_TEST_REFUSE (comma-separated kinds, matched
 * exactly), read once; a page with no `process` allows everything. */
let marchCapHook = null;
function marchCapHookInit() {
  if (marchCapHook !== null) return marchCapHook;
  const raw = (typeof process !== "undefined" && process.env && process.env.MARCH_TEST_REFUSE) || "";
  const text = raw.trim();
  const kinds = text.split(",").map((k) => k.trim()).filter((k) => k !== "");
  marchCapHook = { text, kinds };
  return marchCapHook;
}

/** 0 when the launch admits an operation of `kind` on `target`, else 1. */
export function march_cap_check_raw(kind, _target) {
  return marchCapHookInit().kinds.includes(kind) ? 1 : 0;
}

/** The test hook's trimmed value, the refusing limit's scope text. */
export function march_cap_launch_text() {
  return marchCapHookInit().text;
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

/* ── Diagnostics: crash observers (stdlib/diagnostics.march) ──────────────
 * The JS twin of march_runtime.c's "Diagnostics: crash observers" and the
 * interpreter's Eval_prim.diag_*.  What differs, and why:
 *
 * - One crash context for the program.  JS runs one thread; async code that
 *   interleaves at an `await` shares it (native keeps one per green thread).
 * - The report is made when an error escapes `main` (js_emit wraps the call
 *   when the program registers an observer), not at the panic: a JS `throw`
 *   cannot know whether a `catch` further out handles it.  A panic records
 *   the context and the panic call's site on the Error it throws
 *   (march_panic_err), so a report still carries the context of the
 *   `with_context` scopes it unwound through, as on the other backends.
 *   `--test` runs never report (the runner handles every test's panic, as
 *   native's test trap does).
 * - Any error escaping `main` is reported (an Int overflow too, like the
 *   interpreter), always as kind Panic, with pid -1 and supervised false.
 * - The backtrace is empty: the JS stack names emitted JS functions and
 *   lines of the .mjs, not March functions and source lines. */

const march_diag_observers = [];        // [id, closure], registration order
let march_diag_next_id = 1;
let march_diag_ctx = null;              // null: no context (Nil)
let march_diag_site_file = null;        // the next panic's call site
let march_diag_site_line = 0;
let march_diag_dispatching = false;

/* diag_observe(cb): the handle is a positive id, never reused. */
export function march_diag_observe(cb) {
  const id = march_diag_next_id++;
  march_diag_observers.push([id, cb]);
  return id;
}

/* Idempotent: an unknown or already-removed id is a no-op. */
export function march_diag_unobserve(id) {
  const i = march_diag_observers.findIndex((e) => e[0] === id);
  if (i >= 0) march_diag_observers.splice(i, 1);
  return undefined;
}

export function march_diag_context_get() {
  return march_diag_ctx === null ? { $: "Nil" } : march_diag_ctx;
}

export function march_diag_context_set(ctx) {
  march_diag_ctx = ctx;
  return undefined;
}

/* __panic_site(file, line, col, end_col): emitted right before a direct
 * panic / todo / unreachable call; the next march_panic_err takes it. */
export function march_panic_site(file, line, _col, _end_col) {
  march_diag_site_file = file;
  march_diag_site_line = line;
  return undefined;
}

/* The Error a panic throws: carries the context in force and the recorded
 * call site (taken and cleared), for a crash report made later. */
export function march_panic_err(msg) {
  const e = new Error(msg);
  /* Drop this frame, so Node's uncaught-error excerpt and stack start at the
   * March program's throw, not at this helper (as `throw new Error` did). */
  if (typeof Error.captureStackTrace === "function")
    Error.captureStackTrace(e, march_panic_err);
  /* Non-enumerable: Node prints an uncaught Error's enumerable fields. */
  if (march_diag_site_file !== null) {
    Object.defineProperty(e, "march_site",
      { value: [march_diag_site_file, march_diag_site_line] });
    march_diag_site_file = null;
    march_diag_site_line = 0;
  }
  Object.defineProperty(e, "march_ctx", { value: march_diag_context_get() });
  return e;
}

/* try_finally(action, cleanup): action's value; cleanup runs after it
 * returns or throws, and the error goes on (march_try_finally in
 * march_runtime.c).  Both closures take one ignored argument.  An action
 * that returns a promise (an async closure) is cleaned up when it settles. */
export function march_try_finally(action, cleanup) {
  let r;
  try {
    r = action._0(action, undefined);
  } catch (e) {
    cleanup._0(cleanup, undefined);
    throw e;
  }
  if (r !== null && typeof r === "object" && typeof r.then === "function")
    return r.finally(() => cleanup._0(cleanup, undefined));
  cleanup._0(cleanup, undefined);
  return r;
}

/* An error escaped `main`: call every observer registered now, in
 * registration order, with a Diagnostics.DiagCrash.  An observer's own
 * error (or rejected promise) is swallowed and never reported. */
export async function march_diag_unhandled(e) {
  if (march_diag_observers.length === 0 || march_diag_dispatching) return;
  const isErr = e instanceof Error;
  const msg = isErr ? e.message : String(e);
  const site = (isErr && e.march_site) ? e.march_site : ["", 0];
  const ctx = (isErr && e.march_ctx) ? e.march_ctx : march_diag_context_get();
  const snapshot = march_diag_observers.slice();
  march_diag_dispatching = true;
  try {
    for (const [, cb] of snapshot) {
      const report = { $: "DiagCrash", _0: 0, _1: msg, _2: { $: "Nil" }, _3: -1, _4: 0,
                       _5: ctx, _6: site[0], _7: site[1] };
      try { await cb._0(cb, report); } catch (_) { /* swallowed */ }
    }
  } finally {
    march_diag_dispatching = false;
  }
}

/* ── Test runner (`march --target js --test`) ─────────────────────────────
 * The JS twin of the native harness (march_test_init / march_test_run /
 * march_test_report and march_assert_fail in runtime/march_runtime.c), and a
 * port of lib/errors/test_report.ml's value differ, which those two already
 * share line for line.  All three must print byte for byte the same report:
 * test/run_test_reports.ml runs every golden case interpreted, compiled and
 * on this target.  Change one, change the others.
 *
 * Strings are handled as arrays of code points, so a "column" is a code
 * point, as test_report.ml's [width] counts UTF-8 lead bytes. */

let march_test_verbose = false;
let march_test_filter = "";
let march_test_total = 0;
let march_test_failed = 0;
const march_test_failures = [];
let march_test_cur_header = null;

function march_test_out(s) {
  if (typeof process !== "undefined" && process.stdout && process.stdout.write) process.stdout.write(s);
  else console.log(s.endsWith("\n") ? s.slice(0, -1) : s);
}

/* --verbose / -v and --filter=SUBSTRING, as a native test binary takes them. */
export function march_test_init() {
  const args = (typeof process !== "undefined" && process.argv) ? process.argv.slice(2) : [];
  for (const a of args) {
    if (a === "--verbose" || a === "-v") march_test_verbose = true;
    else if (a.startsWith("--filter=")) march_test_filter = a.slice(9);
  }
}

/* The running test's panic header: `This test panicked: \x01` under its
 * `test "..."` line, the \x01 replaced by the panic message. */
export function march_test_header(h) { march_test_cur_header = h; return undefined; }

function march_test_failure_message(e) {
  let fail = (e instanceof Error) ? e.message : String(e);
  if (fail === "") fail = "assertion failed";
  if (fail.startsWith("-- TEST FAILURE ") || march_test_cur_header === null) return fail;
  const hole = march_test_cur_header.indexOf("\x01");
  if (hole < 0) return fail;
  return march_test_cur_header.slice(0, hole) + fail + march_test_cur_header.slice(hole + 1);
}

function march_test_indented(indent, msg) {
  let out = "";
  for (const line of msg.split("\n")) out += (line.length > 0 ? indent + line : "") + "\n";
  return out;
}

export async function march_test_setup_all(fn) { if (fn) await fn(); }

export async function march_test_run(fn, name, setup) {
  if (march_test_filter !== "" && !name.includes(march_test_filter)) return;
  march_test_total++;
  if (setup) await setup();
  march_test_cur_header = null;
  let err = null, failed = false;
  try { await fn(); } catch (e) { err = e; failed = true; }
  if (!failed) {
    march_test_out(march_test_verbose ? `  ✓ ${name}\n` : ".");
  } else {
    const msg = march_test_failure_message(err);
    if (march_test_verbose) march_test_out(`  ✗ ${name}\n` + march_test_indented("    ", msg));
    else march_test_out("F");
    march_test_failures.push([name, msg]);
    march_test_failed++;
  }
}

/* The summary; the exit status (1 on any failure) goes to process.exitCode. */
export function march_test_report() {
  let out = march_test_verbose ? "" : "\n";
  if (march_test_failed > 0 && !march_test_verbose) {
    out += `\n${march_test_failures.length} failure(s):\n\n`;
    for (const [name, msg] of march_test_failures)
      out += `FAIL: "${name}"\n` + march_test_indented("  ", msg) + "\n";
  }
  out += `Finished: ${march_test_total} test${march_test_total === 1 ? "" : "s"}, ` +
         `${march_test_failed} failure${march_test_failed === 1 ? "" : "s"}\n`;
  march_test_out(out);
  const code = march_test_failed > 0 ? 1 : 0;
  if (typeof process !== "undefined") process.exitCode = code;
  return code;
}

/* ── The value differ (test_report.ml) ── */

const TR_ELLIPSIS = "…";
const TR_ELIDE_OVER = 60;
const tr_cps = (s) => Array.from(s);
const tr_width = (s) => tr_cps(s).length;

function tr_clip(s, max) {
  const cs = tr_cps(s);
  if (cs.length <= max) return s;
  return cs.slice(0, Math.max(0, max - 1)).join("") + TR_ELLIPSIS;
}

function tr_quote(s) {
  let b = "\"";
  for (let i = 0; i < s.length; i++) {
    const ch = s[i], c = s.charCodeAt(i);
    if (ch === "\"") b += "\\\"";
    else if (ch === "\\") b += "\\\\";
    else if (ch === "\n") b += "\\n";
    else if (ch === "\t") b += "\\t";
    else if (ch === "\r") b += "\\r";
    else if (c < 0x20 || c === 0x7f) b += "\\x" + c.toString(16).padStart(2, "0");
    else b += ch;
  }
  return b + "\"";
}

const tr_is_delim = (c) => ",()[]{}\"".includes(c);
const tr_is_ident = (s) => /^[A-Za-z_][A-Za-z0-9_.]*$/.test(s);
/* OCaml's String.trim: ' ', '\012', '\n', '\r', '\t'. */
function tr_trim(s) {
  const ws = (c) => c === " " || c === "\x0c" || c === "\n" || c === "\r" || c === "\t";
  let a = 0, b = s.length;
  while (a < b && ws(s[a])) a++;
  while (b > a && ws(s[b - 1])) b--;
  return s.slice(a, b);
}

/* Nodes: {k:"leaf"|"str", t} | {k:"list"|"tuple", xs} | {k:"ctor", t, xs}
 *        | {k:"record", t: name, sep, keys, xs} */
function tr_parse(s) {
  const n = s.length;
  let pos = 0;
  const UNREADABLE = {};
  const skip = () => { while (pos < n && s[pos] === " ") pos++; };
  const peek = () => (pos < n ? s[pos] : null);
  function value() {
    skip();
    const c = peek();
    if (c === null) throw UNREADABLE;
    if (c === "\"") {
      const start = pos;
      pos++;
      while (pos < n && s[pos] !== "\"") { if (s[pos] === "\\") pos++; pos++; }
      if (pos >= n) throw UNREADABLE;
      pos++;
      return { k: "str", t: s.slice(start, pos) };
    }
    if (c === "[") { pos++; return { k: "list", xs: seq("]") }; }
    if (c === "(") {
      pos++;
      const xs = seq(")");
      return xs.length === 0 ? { k: "leaf", t: "()" } : { k: "tuple", xs };
    }
    if (c === "{") { pos++; return fields(""); }
    if (tr_is_delim(c)) throw UNREADABLE;
    const start = pos;
    while (pos < n && !tr_is_delim(s[pos])) pos++;
    const text = tr_trim(s.slice(start, pos));
    if (text === "") throw UNREADABLE;
    if (pos < n && s[pos] === "(" && tr_is_ident(text)) { pos++; return { k: "ctor", t: text, xs: seq(")") }; }
    if (pos < n && s[pos] === "{" && tr_is_ident(text)) { pos++; return fields(text); }
    return { k: "leaf", t: text };
  }
  function seq(close) {
    skip();
    if (peek() === close) { pos++; return []; }
    const acc = [];
    for (;;) {
      acc.push(value());
      skip();
      const c = peek();
      if (c === ",") { pos++; continue; }
      if (c === close) { pos++; return acc; }
      throw UNREADABLE;
    }
  }
  function fields(name) {
    let sep = "";
    const keys = [], xs = [];
    skip();
    if (peek() === "}") { pos++; return { k: "record", t: name, sep: ": ", keys, xs }; }
    for (;;) {
      skip();
      const start = pos;
      while (pos < n && s[pos] !== ":" && s[pos] !== "=" && !tr_is_delim(s[pos])) pos++;
      const c = peek();
      const here = c === ":" ? ": " : c === "=" ? " = " : null;
      if (here === null) throw UNREADABLE;
      if (sep === "") sep = here; else if (sep !== here) throw UNREADABLE;
      const key = tr_trim(s.slice(start, pos));
      if (!tr_is_ident(key)) throw UNREADABLE;
      pos++;
      const v = value();
      keys.push(key); xs.push(v);
      skip();
      const d = peek();
      if (d === ",") { pos++; continue; }
      if (d === "}") { pos++; return { k: "record", t: name, sep, keys, xs }; }
      throw UNREADABLE;
    }
  }
  try {
    const v = value();
    skip();
    return pos !== n ? { k: "leaf", t: s } : v;
  } catch (e) {
    if (e === UNREADABLE) return { k: "leaf", t: s };
    throw e;
  }
}

function tr_eq(a, b) {
  if (a.k !== b.k) return false;
  if ((a.t ?? null) !== (b.t ?? null)) return false;
  if (a.k === "record" && a.sep !== b.sep) return false;
  const ax = a.xs || [], bx = b.xs || [];
  if (ax.length !== bx.length) return false;
  for (let i = 0; i < ax.length; i++) {
    if (a.keys && a.keys[i] !== b.keys[i]) return false;
    if (!tr_eq(ax[i], bx[i])) return false;
  }
  return true;
}

function tr_print(v) {
  switch (v.k) {
    case "leaf": case "str": return v.t;
    case "list": return "[" + v.xs.map(tr_print).join(", ") + "]";
    case "tuple": return "(" + v.xs.map(tr_print).join(", ") + ")";
    case "ctor": return v.t + "(" + v.xs.map(tr_print).join(", ") + ")";
    case "record":
      return (v.t === "" ? "" : v.t + " ") + "{ " +
        v.xs.map((x, i) => v.keys[i] + v.sep + tr_print(x)).join(", ") + " }";
  }
  return "";
}

/* Steps: {idx} | {field} | {arg}.  Kinds: {whole} | {chars: i} | {len: [nl, nr]}.
 * [chars] is a code-point offset into the quoted string. */
function tr_first_diff(a, b, path) {
  if (tr_eq(a, b)) return null;
  const items = (xs, ys, mk) => {
    for (let i = 0; i < Math.min(xs.length, ys.length); i++)
      if (!tr_eq(xs[i], ys[i])) return tr_first_diff(xs[i], ys[i], path.concat([mk(i)]));
    return null;
  };
  if (a.k === "list" && b.k === "list") {
    const d = items(a.xs, b.xs, (i) => ({ idx: i }));
    return d || { path, kind: { len: [a.xs.length, b.xs.length] } };
  }
  if ((a.k === "tuple" && b.k === "tuple" && a.xs.length === b.xs.length)
      || (a.k === "ctor" && b.k === "ctor" && a.t === b.t && a.xs.length === b.xs.length))
    return items(a.xs, b.xs, (i) => ({ arg: i }));
  if (a.k === "record" && b.k === "record" && a.t === b.t
      && a.keys.length === b.keys.length && a.keys.every((k, i) => k === b.keys[i])) {
    for (let i = 0; i < a.xs.length; i++)
      if (!tr_eq(a.xs[i], b.xs[i]))
        return tr_first_diff(a.xs[i], b.xs[i], path.concat([{ field: a.keys[i] }]));
    return { path, kind: { whole: true } };
  }
  if (a.k === "str" && b.k === "str") {
    const s = tr_cps(a.t), t = tr_cps(b.t);
    let i = 0;
    while (i < Math.min(s.length, t.length) && s[i] === t[i]) i++;
    return { path, kind: { chars: i } };
  }
  return { path, kind: { whole: true } };
}

function tr_path_text(path) {
  let b = "";
  for (const st of path) {
    if (st.idx !== undefined) b += `[${st.idx}]`;
    else if (st.field !== undefined) b += "." + st.field;
    else break;
  }
  return b;
}

function tr_render(elide, root, path, kind, longer) {
  let b = "", col = 0, mark = [0, 1];
  const add = (s) => { b += s; col += tr_width(s); };
  const marked = (s) => { const c = col; add(s); mark = [c, Math.max(1, tr_width(s))]; };
  const full = (v) => (elide ? tr_clip(tr_print(v), TR_ELIDE_OVER) : tr_print(v));
  function go(v, p) {
    if (p.length === 0) return target(v);
    const [st, ...rest] = p;
    if (v.k === "list" || v.k === "tuple" || v.k === "ctor") {
      const i = v.k === "list" ? (st.idx ?? -1) : (st.arg ?? -1);
      const open = v.k === "list" ? "[" : v.k === "tuple" ? "(" : v.t + "(";
      const close = v.k === "list" ? "]" : ")";
      if (i < 0 || i >= v.xs.length) return target(v);
      add(open);
      if (elide) {
        if (i > 0) add(TR_ELLIPSIS + ", ");
        go(v.xs[i], rest);
        if (i < v.xs.length - 1) add(", " + TR_ELLIPSIS);
      } else {
        v.xs.forEach((x, j) => { if (j > 0) add(", "); if (j === i) go(x, rest); else add(tr_print(x)); });
      }
      add(close);
      return;
    }
    if (st.field !== undefined && v.k === "record") {
      const idx = v.keys.lastIndexOf(st.field);
      if (idx < 0) return target(v);
      const n = v.keys.length;
      if (v.t !== "") add(v.t + " ");
      add("{ ");
      if (elide) {
        if (idx > 0) add(TR_ELLIPSIS + ", ");
        add(st.field + v.sep);
        go(v.xs[idx], rest);
        if (idx < n - 1) add(", " + TR_ELLIPSIS);
      } else {
        v.xs.forEach((x, j) => {
          if (j > 0) add(", ");
          add(v.keys[j] + v.sep);
          if (j === idx) go(x, rest); else add(tr_print(x));
        });
      }
      add(" }");
      return;
    }
    return target(v);
  }
  function target(v) {
    if (kind.chars !== undefined && v.k === "str") return str_marked(tr_cps(v.t), kind.chars);
    if (kind.len !== undefined && v.k === "list") {
      const [nl, nr] = kind.len;
      const common = Math.min(nl, nr);
      add("[");
      if (!longer) {
        if (elide && v.xs.length > 0) add(TR_ELLIPSIS);
        else v.xs.forEach((x, j) => { if (j > 0) add(", "); add(tr_print(x)); });
        marked("]");
        return;
      }
      if (common > 0) {
        if (elide) add(TR_ELLIPSIS + ", ");
        else v.xs.forEach((x, j) => { if (j < common) { add(tr_print(x)); add(", "); } });
      }
      const extra = v.xs.slice(common);
      let et;
      if (elide) {
        et = extra.length === 0 ? ""
          : tr_clip(tr_print(extra[0]), TR_ELIDE_OVER) + (extra.length > 1 ? ", " + TR_ELLIPSIS : "");
      } else et = extra.map(tr_print).join(", ");
      marked(et);
      add("]");
      return;
    }
    marked(full(v));
  }
  function str_marked(s, i) {
    const n = s.length;
    const sub = (a, z) => s.slice(a, z).join("");
    if (!elide || n <= TR_ELIDE_OVER) {
      add(sub(0, i)); marked(sub(i, i + 1)); add(sub(i + 1, n));
      return;
    }
    let back = i, cols = 0;
    while (back > 1 && cols < 20) { back--; cols++; }
    let fwd = i, fcols = 0;
    while (fwd < n - 1 && fcols < 30) { fwd++; fcols++; }
    if (fwd >= n - 1) fwd = n;
    add(back > 1 ? "\"" + TR_ELLIPSIS : "\"");
    add(sub(back, i));
    const j = Math.min(i + 1, n);
    marked(sub(i, j));
    const stop = Math.max(j, fwd);
    add(sub(j, stop));
    if (stop < n) add(TR_ELLIPSIS + "\"");
  }
  go(root, path);
  return [b, mark[0], mark[1]];
}

function tr_label(side, src, printed) {
  const squash = (s) => s.split(" ").join("");
  return (src === "" || squash(src) === squash(printed)) ? side : `${side} \`${src}\``;
}

function tr_compare_body(op, lsrc, rsrc, l, r) {
  const IND = "    ", VIND = "        ";
  let b = "";
  const line = (s) => { b += s + "\n"; };
  const shown = (v) => tr_clip(v, 200);
  const plain = () => {
    line(IND + tr_label("left", lsrc, l)); line(VIND + shown(l));
    line(IND + tr_label("right", rsrc, r)); line(VIND + shown(r));
  };
  if (op === "!=") {
    line(IND + "Both sides are:");
    line(VIND + shown(l));
  } else if (op === "==" && l !== r) {
    const lt = tr_parse(l), rt = tr_parse(r);
    const d = tr_first_diff(lt, rt, []);
    if (d === null) plain();
    else {
      const elide = tr_width(l) > TR_ELIDE_OVER || tr_width(r) > TR_ELIDE_OVER;
      const [nl, nr] = d.kind.len || [0, 0];
      const side = (name, src, printed, tree, longer) => {
        const [text, c, w] = tr_render(elide, tree, d.path, d.kind, longer);
        line(IND + tr_label(name, src, printed));
        line(VIND + text);
        line(VIND + " ".repeat(c) + "^".repeat(w));
      };
      side("left", lsrc, l, lt, nl > nr);
      side("right", rsrc, r, rt, nr > nl);
      const where = tr_path_text(d.path);
      if (d.kind.len) {
        const [a, c] = d.kind.len;
        const what = where === "" ? "The left list" : `\`${where}\` on the left`;
        line("");
        line(`${IND}${what} has ${a} element${a === 1 ? "" : "s"}; on the right it has ${c}.`);
      } else if (where !== "") {
        line("");
        line(`${IND}They first differ at \`${where}\`.`);
      }
    }
  } else {
    plain();
    if (op === "==") {
      line("");
      line(IND + "They print the same, so they differ in something printing");
      line(IND + "does not show: a custom `Eq` impl, or a Float NaN.");
    }
  }
  return b.endsWith("\n") ? b.slice(0, -1) : b;
}

/* A failed `assert`: [meta] is header \x1f op \x1f left source \x1f right
 * source \x1f flags (Lower_expr's EAssert arm); [l]/[r] the operands'
 * `to_string`.  Throws the whole report, as march_assert_fail panics with it. */
export function march_assert_fail(meta, l, r) {
  const parts = String(meta).split("\x1f");
  while (parts.length < 5) parts.push("");
  const [header, op, lsrc, rsrc, flags] = parts;
  let msg = header;
  if (op !== "") {
    const ls = flags[0] === "q" ? tr_quote(String(l)) : String(l);
    const rs = flags[1] === "q" ? tr_quote(String(r)) : String(r);
    msg += "\n\n" + tr_compare_body(op, lsrc, rsrc, ls, rs);
  }
  throw new Error(msg);
}
