# Float -> Int conversions panic on NaN, infinities and out of range (#1230)

`float_to_int`, `float_truncate`, `float_floor`, `float_ceil` and `float_round` returned
whatever the host's conversion gave for NaN, ±infinity and a result outside Int's
[-2^62, 2^62). The interpreter and native code agreed and were both wrong: on arm64 a C
`(int64_t)` cast (undefined for these values) saturates to the int64 limits, which become
`-1` and `0` as a 63-bit Int, and 2^62 fits int64 but wraps to -2^62. `--target js`
returned the double itself (`1e20`, `NaN`, `Infinity`). Repro:
https://github.com/notactuallytreyanastasio/march-repros/tree/main/float-to-int-out-of-range

## Semantics

Each builtin rounds first, then panics when the rounded value is NaN
(`<op>: cannot convert NaN to Int`) or outside [-2^62, 2^62) (`<op>: value out of Int
range`), where `<op>` is the builtin's own name. Same text on every backend; written up
in `specs/lang/type-system.md`, "Converting a Float to an Int" (`docs/types.md`
regenerated). Consistent with the Int overflow trap
(`specs/progress/2026-10-30-int-overflow-trap.md`).

## Implementation

- Interpreter: `Eval_runtime.int_of_float_checked` checks NaN and the 63-bit range on
  every host (before, only the browser REPL's narrow host checked, and only
  `float_truncate`/`float_to_int` used it). `float_floor`/`ceil`/`round` now go through it.
- Native: `march_float_int_checked` in `runtime/march_runtime.c`, used by all five
  `march_float_*` entry points. The bounds are exact doubles (`±0x1p62`); NaN fails the
  in-range test.
- wasm: the same test in `runtime/march_runtime_wasm.c`, trapping like
  `march_int_overflow` does there. `march_float_to_int` was missing from that runtime and
  is added. Syntax-checked with `clang --target=wasm64 -ffreestanding`; not run (no
  wasi-sdk/wasmtime here, and CI does not build it).
- JS: `march_float_{to_int,truncate,floor,ceil,round}` in `runtime/march_runtime.mjs`
  throw with the same messages; `js_emit.ml` calls them for both inline calls and the
  first-class wrappers, instead of inlining `Math.trunc`/`floor`/`ceil`.
- Fold: unchanged. `Fold` already folds these only for a finite literal under 4.6e18, so
  an out-of-range literal panics at run time; the new test has a literal row for it.
- LLVM: no inline lowering of these builtins exists; they are always runtime calls.

## Stdlib callers changed

These used to rely on getting a wrong Int back, and would have started to panic:

- `Math.floor`/`ceil`/`round`/`truncate` return NaN, the infinities and |x| >= 2^53 unchanged
  (all already whole) instead of round-tripping through Int. Before, `Math.floor(1e20)`
  was `-1.`.
- `Json.to_string` and `DataFrame.json_value_to_value` tested "is this Number integral"
  with `int_to_float(float_to_int(f)) == f`. That worked for 1e20 and NaN only because
  the wrong Int failed the comparison. They now check |f| < 4.6e18 first.
- `DataFrame.value_hash` scaled a Float by 1e6 and truncated, which overflows for
  |f| >= ~4.6e12. Those values (and NaN) now hash their `float_to_string`.
- `Plot`'s histogram `bin_of` and SVG `fmt_float` clamp or fall back to `float_to_string`.

The bound is 4.6e18 rather than 2^62 because a long Float literal is shortened to 12
significant digits on `--target js` (#1169), and 4.6e18 survives that unchanged.

## Not done

- `cap no_panic` does not see these panics (nor `int_shl`'s); the panic surface lists
  only `panic`/`todo_`/`unreachable_` and contracted stdlib names.
- No `Option`-returning or saturating variants were added; #1230 leaves that choice to the
  maintainers.
- `Diagnose`, `Recon`, `Trace` and `Topology` call `float_to_int` on JSON numbers they
  wrote themselves (ms timestamps, counts) and are left as they are. A hostile or corrupt
  input there now panics instead of giving a wrong Int.

## Tests

`test_float_to_int_range_panics` (codegen): every builtin on NaN, ±inf, ±1e20, 2^62,
-2^62 - 1024 (panic), 2^62 - 1024 and -2^62 (in range), through first-class values and
direct calls, a literal out-of-range row and a folded in-range one, plus the `Math` and
`Json` callers. Interpreter, compiled and JS output must all equal one expected string.
On a compiler built from main every matrix row prints `ok` and `Math.floor(1e20)` prints
`-1.`. `test_int_overflow_uncaught_panic` gains a `float_floor(2^122)` row: uncaught, it
exits 1 with the message on all three backends.
