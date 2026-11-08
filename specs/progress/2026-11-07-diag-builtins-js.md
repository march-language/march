`[P3]` Diagnostics builtins on the JS target

**Done:** 2026-11-07. Item 7 (JS half) of
`todos/2026-10-14-diagnostics-backtrace-followups.md`; the wasm half stays open there.

`--target js` rejected every program using `Diagnostics` (`diag_observe`,
`diag_unobserve`, `diag_context_get`, `diag_context_set` unmapped), and `try_finally`
(which `with_context` is built on) had no JS binding at all: it is reached as a
first-class closure value, which the unmapped-builtin check does not see, so it
compiled into a `ReferenceError` at run time.

What landed:

- `runtime/march_runtime.mjs`: `march_diag_observe` / `unobserve` /
  `context_get` / `context_set`, `march_panic_site`, `march_panic_err`,
  `march_diag_unhandled` and `march_try_finally`. The comment above them lists
  where JS differs from native.
- `lib/tir/js_emit.ml`: call arms for the four builtins, `__panic_site` (was a
  no-op) and `try_finally`, a `try_finally` closure-protocol wrapper const; every
  panic throws `march_panic_err(msg)` (an `Error` carrying the context and the
  recorded call site); `main()` is wrapped, only when the program calls
  `diag_observe`, in `try { ... } catch ($e) { await march_diag_unhandled($e); throw $e; }`.
- `stdlib/diagnostics.march`: the module doc gains a JavaScript paragraph.

Semantics (closest to native that JS allows):

- Reported when an error escapes `main` (a JS `throw` cannot know whether an outer
  `catch` handles it). A panic records its context and site on its `Error` at the
  throw, so the report has the context of the `with_context` scopes it unwound
  through, as natively and in the interpreter. `--test` runs never report.
- Any escaping error is reported (like the interpreter), always kind `Panic`,
  pid -1, `supervised` false. One crash context per program (single thread).
- `backtrace` is empty: JS frames name emitted JS, not March functions/lines.
- Observer order, an observer's panic swallowed, `unobserve` idempotent: as native.
  After the observers the error is rethrown, so Node's output and exit 1 are unchanged.
  `march_panic_err` drops its own frame (`Error.captureStackTrace`), so Node's uncaught-error
  excerpt and stack still start at the program's throw, not at the runtime helper.

Test: `test/test_codegen.ml` `test_js_diagnostics_observers` compiles a program with
`--target js`, runs it under node, and requires its stdout to equal the
interpreter's (context inside/after scopes, removed observer silent, report kind /
message / context / pid / location, observer panic swallowed, next observer runs),
exit 1, and the panic on stderr.

Integration with the JS test-runner fixes preserves `march_panic_error` prefixes
while delegating context and source-location capture to `march_panic_err`. Both
helper frames are omitted from the thrown stack and metadata stays non-enumerable.
Six focused codegen regressions (cases 10–15 in `iface_impl_mono_codegen`) pass,
including Diagnostics observer parity and caught-error/test-runner behavior.
