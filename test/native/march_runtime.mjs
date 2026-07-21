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

/* ── Int builtins (63-bit semantics, checked) ──────────────────────── */
/*
 * March Int is a 63-bit integer natively, but the JS target stores it in an
 * IEEE-754 double, which is exact only within ±(2^53 - 1). These helpers
 * implement the INTERPRETER's semantics (the reference backend — e.g. int_shr
 * is a LOGICAL shift of the 63-bit pattern, and int_popcount flips the sign
 * bit before counting, mirroring lib/eval/eval.ml) exactly within that range,
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

/** lsr: LOGICAL shift of the 63-bit pattern (zero fill), like the interpreter.
 * For a >= 0 the pattern's high bits are zero, so it's floor division. */
export function march_int_shr(a, n) {
  if (n < 0 || n >= 63) throw new Error("int_shr: shift out of range");
  __int_check(a, "int_shr");
  if (a >= 0) return Math.floor(a / 2 ** n);
  return __int_result(BigInt.asUintN(63, BigInt(a)) >> BigInt(n), "int_shr");
}

/** Mirrors eval.ml: negative inputs get the sign bit (bit 62) flipped off
 * before counting, so e.g. int_popcount(-1) = 62. */
export function march_int_popcount(a) {
  __int_check(a, "int_popcount");
  let b = BigInt.asUintN(63, BigInt(a));
  if (a < 0) b ^= 1n << 62n;
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
