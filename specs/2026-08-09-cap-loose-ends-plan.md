# Capability loose ends — consolidated plan

Covers seven filed todos, re-audited against the state after #225/#230/#233/
#234/#236 (ceiling-on-by-default, nested-module attribution, the R1 grant
check). Several premises were stale; one re-audit turned up a bug more
serious than anything on the original list. Ordered by what the re-audit
found, not by filing date.

Source todos: `2026-08-03-cap-sandbox-remaining.md`,
`2026-08-03-capability-diagnostic-duplication.md`,
`2026-08-03-forge-deps-upgrade-cap-diff.md`,
`2026-08-03-registry-capability-notarization.md`,
`2026-08-03-runtime-symbol-naming-and-uncompiled-cap-builtins.md`,
`2026-08-04-cap-ceiling-follow-ups.md`,
`2026-08-04-dependency-cap-audit-followups.md`.

## Tier 0 — a shadowed builtin name is a false capability requirement, now a hard default-on error

**Found during this re-audit, not in any filed todo.** The
`runtime-symbol-naming` todo diagnosed `dns_resolve`'s false-marker risk as a
narrow C-symbol-naming quirk ("the C function is unprefixed"). It is not
narrow. Reproduced against current main:

```march
mod T do
  needs IO.Console
  fn file_read(x : Int) : Int do
    x + 100
  end
  fn main() : () do
    println(int_to_string(file_read(1)))
  end
end
```

`file_read`'s C symbol is `march_file_read` — no naming collision at the
runtime level at all — and this still fails:

```
function body calls a builtin that requires `Cap(IO.FileRead)` but `T` does
not declare `needs IO.FileRead`.
```

Confirmed the user's function is what actually runs (interpreted AND
compiled: printing `101`, not a file-read result — module-scope declarations
correctly shadow builtins in real name resolution). The diagnostic is not
imprecise, it is **wrong**: this program uses zero `IO.FileRead`.

**Root cause.** Every capability-inference pass that scans call sites does so
syntactically — `March_ast.Calls.names_and_name_spans` walks raw AST call
expressions and string-matches the callee name against a capability table,
with no awareness that a module-level declaration of the same name shadows
the builtin. Six sites in `check_module_needs` alone
(`lib/typecheck/typecheck.ml:8590,8782,8912,8956,8997,9012`), all matching
against `builtin_cap_table`. The same shape recurs in `check_pure_module` and
`check_deterministic_module` (banned-builtin-name sets, same file) and
independently in `lib/refinecheck/cap_infer.ml`'s `cap_of_call`/
`iter_cap_calls` (a third, independently duplicated capability table —
this codebase's established "two-tables-drift" failure mode, now a third
copy).

**Why this is Tier 0 and not filed alongside the rest.** The severity flip
(#219, 2026-08-06) turned Check 1b's diagnostic from a warning into a hard,
default-on compile ERROR. Before that date this bug was a wrong warning; now
it silently breaks the build for anyone who names a function `file_read`,
`file_write`, `random_bytes`, `dns_resolve`, or any of ~20 other ordinary
English words that happen to be capability-bearing builtin names — with no
workaround short of renaming their own function. `march caps` (the
inferred-capability extractor feeding `forge audit --inferred` and the
`--cap-sandbox` profile) has the identical bug via the same shared
`builtin_caps_of_expr` helper, so a shadowed name can also **under-sandbox**
a binary in the opposite direction from what the diagnostic claims — silently
this time, since nothing errors.

**Fix.** Per module (each `check_module_needs`/`check_pure_module`/
`check_deterministic_module` invocation, and `cap_infer.ml`'s per-module
`check_decls` recursion, already scoped correctly since `DMod` recurses with
its own `decls`), build a `locally_declared_names` set from that module's own
`DFn` names and top-level `DLet` `PatVar` names — the set that provably wins
name resolution over a global builtin at this scope, verified empirically
above. Gate every capability-table lookup on "and not shadowed."

**Deliberately out of scope for this fix, and why:**
- Nested-module shadowing (`Lib.file_read`) is already immune — TIR/AST
  qualifies the name, so it never string-matches the bare table key.
- A parameter or `let` shadowing a builtin *within* a function body is a real
  residual gap (rarer — a param literally named `file_read` used as a
  variable, not called) and needs actual scope-aware resolution to close
  correctly, which these AST-level passes don't have. Filed as a follow-up
  rather than blocking this fix; the module-level case is the one that
  actually reproduces and the one severity-flip made dangerous.

**This closes the runtime-symbol-naming todo's false-marker half.** Its
other half — `dns_resolve`'s C function being unprefixed, and the three
cap-table builtins with no compiled lowering — become Tier 1 cosmetic/UX
items once the false-positive danger is gone.

**Landed 2026-08-09** — `specs/progress/2026-08-09-cap-shadowing-false-positive.md`.
Worth reading before touching this area again: the fix's own FIRST version
shipped a regression (prelude's own `println` — unwrapped into the entry
module's flat decl list in the real pipeline, invisible to a bare
`parse_and_desugar` unit test — got treated as "locally declared,"
silencing the single most basic capability check in the system). Nine
unit tests all passed while it was broken; the corpus sweep caught it via
an unrelated fixture reading the same closure table. The regression test
written to pin it *also* failed to reproduce on its first attempt for the
identical reason (a test helper that wraps prelude in a `DMod` rather than
flattening it). The lesson: a fix to a stdlib-touching syntactic pass is
not verified by unit tests alone — it needs at least one exercise against
the real, stdlib-prepended shape, and the corpus sweep is what actually
provides that here.

## Tier 1 — real, narrow, in-repo bugs

**`dns_resolve`'s C function is unprefixed** (`march_runtime.c` —
`dns_resolve`, not `march_dns_resolve`). No longer a false-marker risk after
Tier 0, but still a naming inconsistency with every other runtime entry.
Rename to `march_dns_resolve`, add an explicit `llvm_builtins.ml` entry with
`c_name`, update `Cap_symbols.table`'s key and the drift test
(`test_cap_symbols.ml`).

**Three cap-table builtins have no compiled lowering** (`task_spawn_link`,
`unix_time_ms`, `uuid_v7`) — confirmed still true, and worse than the todo
described: compiling a program that calls one produces a raw, unhelpful
linker error:

```
Undefined symbols for architecture arm64:
  "_unix_time_ms", referenced from: ...
ld: symbol(s) not found for architecture arm64
march: clang failed (exit 1)
```

Fix: reject at typecheck under `--compile` with a clear
"`unix_time_ms` is not available in compiled builds" message, rather than
letting it reach the linker. (`get_work_pool` is not in this set — it's a
legitimate global-access lowering, already correctly excluded.)

## Tier 2 — the ceiling's now-default blast radius, previously opt-in gaps

Both items below were true when filed (2026-08-04) and are unchanged in
mechanism, but their *consequence* changed: `--cap-strict` went from opt-in
to default (#225/#236) in the time since, so what used to affect only users
who explicitly asked for strict checking now affects every default build.

**`--cap-strict` / the ceiling is compile-only, invisible to `--check`.**
Confirmed: `--check-json` on a program with an undeclared stdlib-mediated
capability produces empty output — no diagnostic at all, so editors, the
LSP, and `forge check` cannot preview the #1 way a default build now fails.
Full fix ("lower far enough under `--check` alone") is a real pipeline
change; scope before starting.

**No migration autofix for the stdlib-mediated route.** Confirmed still
true, and now the majority case: the ceiling's plain-stderr violation
message carries no JSON/fix payload, so `forge fix` (which is purely
JSON-diagnostic-driven) cannot apply it — unlike the direct-builtin route,
which **is** already wired (verified: `--check-json` on a missing direct
`needs` emits a `"fix":{"kind":"insert",...}` payload today; that half of
the original todo is done, just not documented as such). Minimal step
that doesn't require the full `--check` pipeline change: teach the ceiling
violation path to also emit a JSON diagnostic with a `fix` payload when
`--check-json` is passed alongside `--compile`, so `forge fix` can apply the
missing `needs` line for the dominant, default-on failure mode.

**Per-dependency capability budgets in `forge.toml`** and **package-level
laundering through internal module boundaries** — both still open, both
still correctly scoped as design work in the original todo (needs the
module→package mapping `forge/lib/cap_package.ml` already computes). No new
findings; unblocked but not urgent.

## Tier 3 — cosmetic, needs a design decision

**Diagnostic duplication** (Check 1b's ERROR + `cap_infer`'s HINT at the same
span). Confirmed still happening, confirmed still "substantially reduced,
not closed" exactly as the todo's own update says — the two now carry
different information (insertion point vs. call chain) rather than
identical text. A prior attempt to suppress inside `cap_infer` broke that
pass's own standalone unit tests; the todo's own conclusion (suppress at
*presentation* time, not inside the pass) still stands. Low urgency, real
design tradeoff — do after Tier 0/1/2.

## Tier 4 — forge audit follow-ups, unblocked but not started

Re-audit finding: `forge/lib/cap_package.ml` already exports `diff`/
`widens`/`format_change` — the exact mechanism `forge-deps-upgrade-cap-diff`
asks for — but **nothing calls them**. `forge audit`'s own `--record`/
`--check` reimplements an equivalent diff independently against
`forge.caps.lock`, never reusing the library functions. So "surface
capability widenings at dependency-upgrade time" is UI + resolver plumbing
over code that already exists, cheaper than the todo's status line implies,
and — contrary to that status line — does **not** actually need registry
notarization: an upgrade-time diff can compare the newly-fetched dependency's
locally-inferred caps against the previously-installed version's, entirely
from source already on disk, the same way `forge audit` does today. The
"blocked on registry" framing was for showing a diff *before* fetching;
showing it *after* fetching (still before accepting/locking) needs nothing
external.

Also stale: the todo's own status line points to
`specs/todos/2026-08-04-cap-deps-followups.md`, which does not exist — the
actual continuation is `2026-08-04-dependency-cap-audit-followups.md`.
Fix the pointer while touching this.

Remaining sub-items, all still open, all still correctly scoped:
- toolchain probe (fail loud instead of every dep silently reporting
  `NOT ANALYZABLE` when the installed `march` predates `caps`)
- speed / caching across repeated `march caps` invocations
- `--allow-unanalyzable` for incremental adoption
- wiring into `forge add`/`forge outdated` (the actual ask — do after the
  above three, per the todo's own ordering, since without the speed item
  every `forge add` pays minutes)

Also found: `cmd_audit.ml`'s `scope_note` for declared-mode capability
extraction says an undeclared direct builtin call is "a warning, not an
error" — stale since the 2026-08-06 severity flip. One-line fix.

## Tier 5 — genuinely blocked, out of scope this pass

**Registry capability notarization.** The compiler half (`march caps`) is
done. Everything else needs a `forgepm` server change — a different repo.
Cannot be built from this repo alone; the todo's own ordering already says
so. No action here beyond confirming the block is still real.

**Linux `IO.NetListen` seccomp / `IO.FileRead` Landlock.** Real OS-level
sandboxing work (syscall filtering, kernel feature detection/fallback,
platform-specific test infrastructure) — a different skill area from
everything else in this plan, substantial on its own, and explicitly called
"low priority" / "advisory ... on BOTH platforms" in the source todo. Needs
its own design pass, not a slot in this cleanup. Left filed, not touched.

## Execution order for this session

1. **Tier 0** — the shadowing fix. Highest value: it's a correctness bug in
   shipped, default-on behavior, and it's the one that makes Tier 1's
   `dns_resolve` item safe to treat as cosmetic rather than urgent.
2. Tier 1 items, if time remains after Tier 0's verification.
3. Tiers 2-5 stay as scoped, prioritized follow-up todos — each is either a
   real design decision (2, 3), a multi-step feature (4), or externally/
   substantially blocked (5), not a same-session mechanical fix.
