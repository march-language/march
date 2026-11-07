# `march --target js --test` runs the test harness; `cap_dict` and friends exist on JS (2026-11-07)

Closes `https://github.com/march-language/march/issues/1176`. Two symptoms, one
missing feature: the JavaScript target never emitted the `--test` runner, and the
capability-mocking builtins `--test` injects had no JS backend.

## What shipped

- **`js_emit.ml` emits a runner when `tm_tests` is non-empty.** `main` is exported but
  not called; the module ends with `march_test_init(); await march_test_setup_all(...)`
  then one `await march_test_run(<fn>, "<display>", <setup>)` per test in declaration
  order, then `march_test_report()`. It mirrors the native `--compile --test` harness:
  `--filter=` substring selection, `--verbose`/`-v`, per-test `setup` and whole-run
  `setup_all`, the shared failure report (`march_assert_fail`, value differ included),
  the `Finished: N tests, M failures` footer and nonzero exit when anything failed.
- **The harness lives in `runtime/march_runtime.mjs`** (`march_test_init` /
  `march_test_header` / `march_test_setup_all` / `march_test_run` / `march_test_report`
  / `march_panic` / `march_assert_fail`): a port of the C report engine (`runtime/march_runtime.c`'s
  `tr_*` family) over the same byte-array model the JS string bridge uses, so a failing
  `assert` renders byte-for-byte the same from the interpreter, a native binary and a `.mjs`.
- **`cap_dict` / `cap_impl` / `mint_cap` / `cap_narrow` have JS implementations** in the
  runtime module: `march_cap_dict(c)` wraps a value as `{$:"Some",_0:c}` and with no value
  gives `{$:"None"}`; `march_cap_impl(_c,d)` returns `d`; `march_mint_cap(_c)` returns
  `undefined`; `march_cap_narrow(c)` is identity. `js_emit.ml` maps the four builtins to
  them and emits `undefined` for a root-level `Cap` argument (`root_cap`), mirroring the
  native `NULL`. Before this, `--test` + `--target js` died on
  `builtin 'cap_dict' has no JavaScript-target implementation` for *any* program, test
  blocks or not.
- **The JS-branch DCE roots the test functions.** `bin/main.ml`'s JS branch pruned with
  `main` alone as the root, so every `__march_test_N__` (and its helpers) was stripped
  before emission and the runner referenced dead names; the roots are now `main` plus the
  `tm_tests` functions plus `__march_setup__` / `__march_setup_all__` when present.

## Rulings

1. **The harness is runtime JS, not emitted inline.** The C harness is runtime C and the
   native `--test` harness is runtime-registered; putting the JS one in `march_runtime.mjs`
   keeps `js_emit.ml` a translator and gives every compiled `.mjs` the runner from the
   module it already imports.
2. **A JS capability is `undefined`, not an object.** Native's root grant is the `NULL`
   sentinel; JS has no need of a representation. `cap_dict` alone carries the
   mock-vs-passthrough decision (`None` vs `Some`), so that is the part worth building.
   Skipping cap-mocking injection on JS was rejected: it would make `--test` silently
   lose the feature it exists to provide.
3. **The report engine was ported, not reinterpreted.** The JS string bridge already
   models bytes (codeunit `< 0x80` as the ASCII byte, `U+F780..F7FF` as raw bytes
   `0x80..FF`, other characters as UTF-8), so the `tr_*` port works on byte arrays
   through `march_byte_view` and reaches the same bytes.
4. **Exit uses `process.exitCode` plus a stdout flush callback**, so the footer's final
   line is on the wire before the process exits — a bare `process.exit` truncates it.

## Tests

`test/test_codegen.ml` group `iface_impl_mono_codegen` gained two cases: JS `--target js
--test` output equals the native `--compile --test` binary's byte-for-byte (a two-test
module where one fails; plain and `--filter=` runs; only the `-- TEST FAILURE -- <path>`
stamp line is normalized, because the compile cache embeds the source path of whichever
compile answered), and `--target js --test` on a test-free program compiles and runs.
Certification: perturbing `Finished: ` in the runtime module turned the parity case RED
(after `dune build` refreshed `_build/default/runtime/march_runtime.mjs`, which is the
copy the compiler actually copies beside the output), then restored it to green.
