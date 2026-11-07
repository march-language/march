# string_to_float: one grammar on every backend (2026-11-07)

Issue #1178. `string_to_float` (and `float_from_string`, the same builtin, and
`String.to_float`, which wraps it) used each host's parser, so the three backends
accepted different strings.

## Before

- **JS** (`runtime/march_runtime.mjs`): `Number(s)`, NaN mapped to `None`. `"inf"`,
  `"-inf"`, `"infinity"`, `"nan"` gave `None` (a genuine `"nan"` could not be told apart
  from a failed parse); `""`, `" "`, `"\t"` gave `Some(0.)`; `"1.5 "`, `"1.5\n"`, `"0b11"`,
  `"0o17"` were accepted; hex floats (`"0x1p3"`, `"-0x10"`) were rejected. `Toml` builds
  `inf`/`nan` with `string_to_float` and falls back to `0.0`, so `x = inf` read as `0.`.
- **Interpreter** (`lib/eval/eval_builtins.ml`): OCaml `float_of_string`, which also takes
  `_` separators (`"1_000"` gave `Some(1000.)`), hands `nan(...)` to the host libc, and
  misrounds some subnormal hex floats.
- **Native** (`runtime/march_runtime.c`): `strtod` with `*end == '\0'`. That stops at an
  embedded NUL (`"1.5\0x"` gave `Some(1.5)`), and the accepted set was the libc's: macOS
  takes `"nan(1 )"`, glibc and musl (the Linux release builds) do not.
- `float_infinity`, `float_neg_infinity`, `float_nan`, `float_epsilon`, `float_is_nan`,
  `float_is_infinite` and `float_from_string` had no `--target js` mapping, so a program
  using them failed to compile for JS.

## The grammar

C99 `strtod` in the "C" locale, the whole string consumed (native is the Tier-1
reference):

```
ws* [+-]? ( dec | hex | "inf" | "infinity" | "nan" ( "(" [0-9A-Za-z_]* ")" )? )
dec = ( digit+ ("." digit*)? | "." digit+ ) ( [eE] [+-]? digit+ )?
hex = "0" [xX] ( xdigit+ ("." xdigit*)? | "." xdigit+ ) ( [pP] [+-]? digit+ )?
ws  = one of " \t\n\v\f\r"   (leading only)
```

The words are ASCII case-insensitive. Values round to nearest, ties to even, with gradual
underflow; overflow gives `inf`, underflow `0.`.

## What changed

- **Native:** `march_float_syntax_ok` checks the shape over `str->len` bytes before
  `strtod` computes the value, and the result requires `end == data + len`. The check uses
  ASCII comparisons, not `strncasecmp`/`ctype`, so a locale can't change it.
- **JS:** `march_string_to_float` matches the grammar with four anchored regexes (no `/i`
  flag, so no Unicode case folding), uses `Number` for a validated decimal body and a
  BigInt hand parser (`march_hex_float`) for hex, correctly rounded including subnormals.
- **Interpreter:** `march_float_of_string` checks the same shape, then calls
  `float_of_string` on a sign-less decimal body (strtod underneath) and its own
  `hex_float` for hex. OCaml's hex reader is NOT usable: it rounds twice in the subnormal
  range (`0x4e9e.85bc87c31aaep-1037` came out one ulp above what strtod, Python's
  `float.fromhex` and the new JS parser give; 9 of 30000 random hex strings differed).
  `hex_float` keeps the first 57+ significant bits exactly plus a sticky bit and rounds
  once.
- **`lib/tir/js_emit.ml`:** maps the float constants and predicates to JS (`Infinity`,
  `NaN`, `Number.EPSILON`, `Number.isNaN`, `Math.abs(x) === Infinity`) and
  `float_from_string` to `march_string_to_float`.
- **Docs:** the grammar is in `specs/lang/type-system.md` ("Parsing a Float",
  regenerated into `docs/types.md`), in `String.to_float`'s doc comment, and in the
  `march-lang` skill's builtin table.

## Tests

`test/native/string_to_float_grammar.march` runs every row from the issue plus ~90 more
(signs, `nan(...)`, partial words, exponent and hex shapes, leading and trailing
whitespace, embedded NUL, hex rounding at ties and in the subnormal range, the float
constants, a TOML `inf`) compiled, interpreted and as `--target js`; `test/dune` diffs all
three against one `.expected`. Before the fix all three were red: native on the NUL and
`nan(1 )` rows, the interpreter on `1_000` and `nan(1 )`, and JS failed to compile. The two
subnormal hex rows were added after that run, once a random cross-check found OCaml's hex
reader one ulp off on them (the expected integers come from Python's `float.fromhex`, and
native `strtod` agrees).

## Not done

- `strtod` still reads the process locale for the decimal point. March never calls
  `setlocale`; an embedding application that sets a `,` locale would make native reject
  `"1.5"` (the shape check passes, the `end` check fails), not misparse it.
- `runtime/march_runtime_wasm.c`'s `march_string_to_float` still returns `None` always.
