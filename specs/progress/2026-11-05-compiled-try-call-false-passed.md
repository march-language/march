Compiled `Check.all` passed every property that returned `false` (fixed 2026-11-05).

`__try_call(thunk)` (`march_try_call`, runtime/march_runtime.c) runs a property and returns
`Ok(bool)` or `Err(panic message)`. It tagged the thunk's result, `(b << 1) | 1`, for the Ok
field. That was right when it was written (commit 61cfb279e, 2026-06-11, when a closure's apply
function returned a raw `i64`). Closures now return `ptr` in the uniform representation, so the
Bool comes back already tagged (`false` = 1, `true` = 3). Tagging it again turned `false` into
3, which reads back as `true`.

Effect: compiled, `__try_call(fn _ -> false)` was `Ok(true)`, so `Check.try_prop` never saw a
property return `false`. A compiled property that failed by returning `false` passed
(`forge test` compiles tests). One that failed by panicking or by a failing `assert` inside it
was still caught. The interpreter was right throughout.

Fix: store the result verbatim, as `march_try_call_val` already did. Found while surveying test
failure output: `Check.all_with(Gen.list(Gen.int(-100, 100)), fn xs -> List.reverse(xs) == xs,
seed 42)` failed interpreted and passed compiled.

Pinned by `test/test_reports/properties.march` ("a property returning false"), which runs
compiled and must fail with the same report as the interpreter.

Behaviour change: a compiled test suite with a wrong `false`-returning property that used to
pass now fails, as it does under `march test`.
