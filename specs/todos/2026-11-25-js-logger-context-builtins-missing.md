`[P3]` The JS target cannot build `Logger.with_scope` / `with_fields` / `field_count` (2026-11-25)

`march --target js` refuses a program that calls `Logger.with_scope` (or `with_span`,
`with_fields`, `field_count`): the builtins `logger_add_field`, `logger_field_count` and
`logger_pop_to_depth` have no JavaScript implementation, and js_emit's allowlist stops the
build with "builtin `logger_add_field` has no JavaScript-target implementation".

Split out of 2026-11-11-logger-with-scope-thunk-arity.md (now in progress/), whose owner
decision asked to "map `logger_pop_to_depth` on the JS target". That one builtin is not
enough: the field stack it pops is filled by `logger_add_field` and read by
`logger_field_count` / `logger_get_fields`, none of which exist on JS.

Fix: a field stack in runtime/march_runtime.mjs with the three builtins mapped in
lib/tir/js_emit.ml (call arm, `runtime_uses`, the wrapper shim), and whatever
`logger_get_fields` / the dispatch path needs for the fields to appear in output. Test: the
with_scope repro from the progress file under `--target js` and node: `1` then `0`.
