# A NaN prints `nan` whatever its sign bit; interpreter `show` of nan/inf matches native

`float_to_string` of a NaN differed by platform. Both the interpreter (OCaml's
`string_of_float`) and the native runtime (`march_format_float_ocaml`) are `%.12g` through
the platform libc. glibc prints a NaN whose sign bit is set as `-nan`; macOS prints `nan`
for either sign. x86's default NaN (`inf -. inf`, `0.0 /. 0.0`) has the sign bit set and
arm64's does not, so the same program printed `-nan` on x86 Linux and `nan` on an arm64 Mac.
It surfaced as the `codegen` job failing on #1233, whose test built its NaN with `inf -. inf`.

## What changed

- `lib/eval/eval_runtime.ml`: a module-level `string_of_float` shadows `Stdlib.string_of_float`
  and returns `"nan"` for any NaN. It is exported from `eval_runtime.mli`: `eval_builtins.ml`
  (the `float_to_string` builtin, `print_float`, the logger's `LFloat`) and `eval_net.ml` open
  `Eval_runtime`, and without the export they kept `Stdlib.string_of_float` (the first version
  of this change forgot it; Linux CI caught `float_to_string(-n)` still printing `-nan`).
- `runtime/march_runtime.c`: `march_format_float_ocaml` (behind `float_to_string`,
  `march_print_float`, polymorphic `show`) and the logger's `logger_float_str` return `nan`
  for any NaN.
- `--target js` already returned `nan` (`march_float_to_string` in `march_runtime.mjs`).
- The interpreter's `show` of a Float appended `.0` to a string with no `.` or `e`. Since
  `string_of_float` already gives a bare integer a trailing dot (`1.`), only `nan`, `inf` and
  `-inf` ever reached that branch, so `show` printed `nan.0` / `inf.0` / `-inf.0` where native and
  JS print `nan` / `inf` / `-inf`. Six sites (`value_to_string`, `show_dispatch`, the native
  array element formatters) now use `string_of_float` as is.

## Test

`test_nan_prints_without_sign_compiled` in `test/test_codegen.ml` runs one program through
the interpreter and a compiled binary and requires `nan nan nan nan inf -inf`. The negative
NaNs do not depend on the CPU: `-x` flips the sign bit and `string_to_float("-nan")` applies it.

The sign half can only go red on glibc; macOS libc prints `nan` for the unfixed code too, so
it was not seen failing locally. The `show` half (`nan.0`) did fail before the fix on macOS.

## Not covered

`runtime/march_runtime_wasm.c` has its own hand-rolled formatter with a 6-decimal cap and was
not touched or checked for NaN. `march_jw_f64` (JSON) already emits `null` for a non-finite
value.
