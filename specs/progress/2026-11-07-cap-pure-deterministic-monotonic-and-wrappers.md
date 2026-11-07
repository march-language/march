# `cap pure` / `cap deterministic`: monotonic clock reads and stdlib wrappers (2026-11-07)

Issue #1180. Three gaps between `docs/capabilities.md` and the compiler.

## What shipped

1. **Monotonic clock reads are banned under both module caps.** `sys_uptime_ms` (the
   builtin behind `System.monotonic_time`) stays ambient for `needs`; the comment at its
   signature in `lib/typecheck/typecheck_builtins.ml` explains why. Because it has no
   `builtin_cap_table` row, neither banned set derived from that table contained it.
   `lib/typecheck/typecheck_modcaps.ml` now has `monotonic_clock_builtins`, unioned into
   both `pure_banned` and `deterministic_banned`. `lib/tir/purity.ml` already listed
   `sys_uptime_ms` as impure, so the two agree.

2. **Stdlib wrappers of ambient banned builtins.** The call scan sees only direct calls,
   so `System.monotonic_time()` still passed. `stdlib_reach` follows a call to a stdlib
   function through `env.fn_refs` (the reference edges the capability closure already
   records), resolved the way `Cap_rows.resolve_ref` resolves them (owner's module prefix
   first, then the raw name) and restricted to `env.stdlib_fns`. A call is rejected when
   it reaches a banned builtin that has no capability row (`ceiling_blind`): for
   `cap deterministic` that is `sys_uptime_ms`, and for `cap pure` it is `sys_uptime_ms`,
   `spawn`, `send`, `exit` and `read_byte`. The banned builtins that have a row are left to
   rule 3 plus the capability ceiling, which rejects a wrapper call made without its
   `needs`. This works from the stdlib's own bodies, not a hand-kept list of wrapper names,
   so a new wrapper is covered when it lands. A stdlib sibling that shares a builtin's name
   resolves as a function and is walked, not banned.

3. **The `needs` half.** `check_module_cap_needs` rejects any `needs` in a `cap pure`
   module, and in a `cap deterministic` module any `needs` that subsumes `IO.Clock` or
   `IO.Random` (that is, `IO.Clock`, `IO.Random`, `IO`). Both use the existing slugs
   (`[pure_violation]`, `[deterministic_violation]`), point at the `needs` line, and skip a
   stdlib-spanned `needs`. This closes `File.read` / `DateTime.now()` under the caps: the
   ceiling admits a stdlib wrapper only when the calling module declares its `needs`.

4. **Docs (`specs/lang/capabilities.md`, regenerated into `docs/capabilities.md`).** The
   hierarchy says monotonic time is ambient and not `IO.Clock`, with a paragraph on why
   and that both caps ban it. The "Which tool" table and the `cap pure` /
   `cap deterministic` sections describe the `needs` rule and the stdlib follow-through.
   The `IO.Foreign` exclusion from the upper limit, and the "Pure functions need no
   declaration" paragraph, say that the exclusion covers first-party stdlib modules built
   on `extern` (`Js.Dom`, `Js.Canvas`, `Js.Audio` on `--target js`), and that function
   `needs ()` bounds and `main`'s grant still report that reach. That was item 3 of the
   issue, and it changes the docs only.

## Corpus impact

No stdlib, example or conformance module declares `cap pure` or `cap deterministic`
together with a rejected `needs`, except the reject fixtures that already fail
(`specs/lang/types/reject/t45`-`t47` and their `test/errors` twins `pure_violation_1`,
`pure_violation_2`, `deterministic_violation_1`). Those carried a `needs` so that only the
call ban fired. They now also report the `needs` line, and their goldens are regenerated.

## Tests

- `test/test_compiler.ml`, group `cap_pure_no_extern_det`: direct `sys_uptime_ms` under
  both caps, the ambient control, `cap pure` + `needs`, `cap deterministic` + each of
  `IO.Clock` / `IO.Random` / `IO`, and `cap deterministic` + `IO.FileRead` / `IO.Console`
  allowed.
- Group `cap_propagation`, with `process.march` and `system.march` loaded: the
  `System.monotonic_time` wrapper rejected under both caps, accepted in a plain module.
- `test/errors/pure_violation_3`, `pure_violation_4`, `deterministic_violation_2` and
  `deterministic_violation_3`: the issue's programs.

## Left out

- A stdlib function passed as a value (`let f = System.monotonic_time`) is not followed.
  The direct-builtin scan has the same limit for a builtin passed as a value.
- Other ambient process introspection (`sys_cpu_load_milli`, `sys_mem_available_bytes`,
  allocation gauges) varies from run to run, but the docs do not name it among the
  nondeterminism sources, so neither cap bans it.
