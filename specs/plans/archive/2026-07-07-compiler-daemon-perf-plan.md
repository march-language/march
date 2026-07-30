# Cached stdlib typecheck env — amortize stdlib typecheck across invocations

**Status: SHIPPED, reduced scope (2026-07-07).** Landed for `march
check`/`forge check` only (`run_check_cmd` in `bin/main.ml`) — NOT for
`--compile`. Two things changed from the "REVISED" design below during
implementation:

1. **Phase 2's gaps turned out irrelevant.** The shipped implementation
   never uses `check_module_with_env` at all — it uses `check_module_core`'s
   new `?seed_env` parameter directly (Phase 3a, the recommended path),
   which shares pass 1/1b/2 with the full `--check`/`--compile` path
   unconditionally. Verified byte-identical diagnostic output against the
   unmodified compiler across a corpus of real projects (`march_doc`,
   `marathon`, `scroll`, `bastion`) and synthetic error/warning fixtures.
2. **A real regression was found and fixed before shipping: `--compile`
   cannot use this optimization the same way `--check` does.** `compile`'s
   `desugared` value (in `bin/main.ml`) is used for BOTH typechecking AND
   later TIR lowering — lowering needs stdlib's own function BODIES emitted,
   not just their types. An earlier version of this change skipped
   prepending `stdlib_decls` onto `desugared` whenever no shadowing was
   needed, which silently dropped stdlib from what gets lowered. The full
   test suite caught this immediately: 24 codegen + 6 stdlib failures, all
   "type-incorrect TIR reached codegen" internal-compiler-errors from
   stdlib functions the user's code called into never being lowered.
   `compile` was reverted to always prepend `stdlib_decls` as before —
   caching stdlib's LOWERED TIR (not just its typecheck env) for
   `--compile` is real follow-up work, out of scope here (Phase 4 already
   flagged this as a separate, riskier follow-up before implementation
   started).

Measured win (warm cache, `forge check`, `rm -rf .forge/check-cache` for a
clean run): `march_doc` 0.86s → 0.20s (~4.3x), `marathon` 0.51s → 0.16s
(~3.2x). Projects that shadow a stdlib module name by filename (`scroll`,
`bastion`, both via a transitive `depot` dependency) fall back to the
original from-scratch combined check unchanged — a deliberate, documented
tradeoff rather than parameterizing the cache key on the shadow set.

An incidental finding surfaced and then became moot: while `compile`'s
seed_env change was still in place, it exposed a pre-existing inconsistency
where `--compile` (unlike `--check`) silently failed to warn about a missing
`needs IO.Console` for a bare `println` call, because prelude's own
unwrapped decls happened to sit in the same top-level decl list as the
user's code. Reverting `compile` entirely also reverted this side effect —
`--compile`'s capability-warning behavior is unchanged from before this
plan. Worth filing separately if the underlying `--check`/`--compile`
inconsistency is worth chasing on its own merits later.

---

**Below is the design-and-investigation record kept as-is; "Phase 3a" is
what shipped, scoped to `run_check_cmd` only — see the status note above
for exactly how `compile` differs from what's written below.**

**Status: REVISED (2026-07-07, superseded above).** The original version of this plan proposed
a persistent daemon process (fork-per-request, Unix socket, warm in-memory
state) to amortize stdlib typecheck/lower cost across `march`/`forge`
invocations. Implementation investigation found that **the REPL/JIT already
solved the hard part of this** — an on-disk Marshal cache of the fully
TYPECHECKED stdlib environment, keyed by content hash, that lets the REPL
typecheck a new snippet against a pre-built baseline instead of re-checking
stdlib from scratch (`lib/repl/repl.ml`'s `load_cached_tc_env` /
`save_cached_tc_env` / `Typecheck.check_module_with_env`). No daemon, no
process management, no fork/socket complexity needed — just wiring
`bin/main.ml`'s `compile`/`run_check_cmd` to use the SAME on-disk cache
instead of combining stdlib+user decls into one list and re-typechecking
both from scratch every time. This is a much smaller, lower-risk change than
the original daemon design, reusing already-shipped, REPL-battle-tested code.

**However:** direct comparison of the two typecheck entry points found the
REPL's incremental path (`check_module_with_env`) is a **confirmed reduced
duplicate** of the full path (`check_module_core`, what `--check`/`--compile`
use today) — it's fine for the REPL's own purposes but has real gaps that
must be closed (or proven immaterial) before it's safe to put on the primary
compiler path. This plan is now scoped around closing those gaps first,
THEN wiring the cache in. Do not skip straight to wiring — the whole point of
today's investigation was to avoid silently changing what errors get
reported.

## Phase 0 — Baseline measurement (done)

Measured via `--timings` (extended earlier this session) and `forge check`
wall-clock across three real projects (`rm -rf .forge/check-cache` first for
a clean cache-miss run):

| Project | Files | Total (`forge check`) | Est. stdlib-typecheck share |
|---|---|---|---|
| `~/code/march_doc` | 10 | 0.63s | **~68%** (0.43s fixed cost) |
| `~/code/scroll` (+ transitive deps) | 16 | 2.27s | ~19% |
| `~/code/bastion` (+ transitive deps) | 80 | 8.99s | ~5% |

The ~0.43s fixed cost is `march --check` on a 1-line trivial program (all of
which is stdlib typecheck, per its own `--timings` breakdown: `stdlib-load`
0.013s, `typecheck` delta 0.430s — ~97% of that invocation's total time).

**Verdict: proceed.** Small-to-medium projects (which most real March
projects seen this session are — `march_doc`, `marathon`, `scroll`, `depot`
all fall in the 8–20 file range) spend a large, avoidable, constant fraction
of every `forge check`/`forge build` on re-typechecking the same ~108-module
stdlib. Only the outlier large project (`bastion`, 80 files) sees a small
relative share, and it still pays the same ~0.43s in absolute terms.

## Phase 1 — The existing mechanism (found, not built)

`lib/repl/repl.ml`:
- `stdlib_content_hash decls` — MD5 of the marshaled stdlib decl list (a
  sibling of `bin/main.ml`'s own `stdlib_source_hash`, which hashes file
  bytes directly — the two should probably be unified, see Phase 4).
- `load_cached_tc_env ~content_hash ~type_map` — unmarshals a
  `Typecheck.env` (confirmed plain data, no closures — `Marshal` round-trips
  it directly) from `~/.cache/march/stdlib_tcenv_<hash>.bin`, restores a
  saved `type_map` association list into the live `type_map` hashtable, and
  returns a fresh env with a clean `errors` context.
- `save_cached_tc_env ~content_hash tc_env` — writes it back (temp file +
  rename, safe under concurrent sessions sharing the cache dir).
- `Typecheck.check_module_with_env (env : env) (m : Ast.module_)` — pass 1
  (forward-reference placeholders) + pass 2 (`check_decl` fold) over `m`'s
  decls ONLY, starting from the given `env` instead of `make_env`. This is
  the actual mechanism that lets the REPL avoid re-typechecking stdlib per
  snippet.

The target shape for `bin/main.ml`: build (or load-from-cache)
`stdlib_tc_env` ONCE per invocation from `stdlib_decls` alone, then
typecheck ONLY the user's `all_decls` against it via `check_module_with_env`,
instead of today's `Typecheck.check_module (stdlib_decls @ all_decls
combined)`. A cache hit skips stdlib typecheck entirely; a cache miss
(stdlib changed, or first run) still has to typecheck stdlib once, but that
result gets saved for every subsequent invocation on the same machine.

## Phase 2 — Confirmed gaps blocking safe reuse (found this session, NOT fixed)

Direct line-by-line comparison of `check_module_with_env`'s pass 1 (used by
the REPL) against `check_module_core`'s pass 1 (used by `--check`/`--compile`
today, via `Typecheck.check_module`) found two real discrepancies:

1. **Nested-module forward-ref placeholders are weaker.** `check_module_core`'s
   `prebind_mod_members` (its helper for pre-binding a `DMod`'s public
   members before pass 2 reaches them) gives a forward-referenced function
   inside a nested module a proper polymorphic scheme via `prebind_fn_scheme
   def` (reads the function's own type annotation and generalizes it — real
   inference precision for a function referenced from a SIBLING module
   before its own body is checked). `check_module_with_env`'s equivalent
   helper, `prebind_mod_members_inc`, instead ALWAYS uses `Mono (fresh_var
   0)` — a bare monomorphic placeholder. A stdlib module referencing another
   stdlib module's not-yet-checked polymorphic function forward would get
   less-precise inference under the REPL path than under the CLI path.
   (`lib/typecheck/typecheck.ml`, compare `prebind_mod_members`'s `Ast.DFn`
   arm around the `check_module_core` definition against
   `prebind_mod_members_inc`'s `Ast.DFn` arm inside `check_module_with_env`.)

2. **Missing `local_fns`/`fn_arities` bookkeeping at the top level.**
   `check_module_core`'s top-level pass-1 `Ast.DFn` arm additionally records
   the function into `env.local_fns` (used so a local definition correctly
   shadows a bulk `use X.*` import of the same name) and `env.fn_arities`
   (used for arity-mismatch diagnostics against a FORWARD-REFERENCED call —
   i.e. calling a function before its own `DFn` has been checked). `check_module_with_env`'s
   top-level pass-1 `Ast.DFn` arm does neither — it's a bare
   `bind_var def.fn_name.txt (Mono (fresh_var 0)) env`. This is the more
   consequential gap: if the user's own top-level decls are typechecked via
   `check_module_with_env` instead of `check_module_core`, a forward call
   with the wrong number of arguments to one of the user's OWN not-yet-checked
   sibling functions could silently produce a worse (or missing) diagnostic
   compared to today's behavior — an actual regression in error reporting,
   not just a performance change.

**These gaps exist today, independent of this plan** — they only matter
because this plan proposes routing MORE typechecking traffic through
`check_module_with_env`. Whether gap 1 is reachable for stdlib specifically
(does any stdlib module actually forward-reference an unchecked sibling's
polymorphic function today?) and whether gap 2 matters when
`check_module_with_env` is used ONLY for the pre-warmed STDLIB portion (with
the user's own `all_decls` still routed through the normal, un-gapped path)
needs to be pinned down before deciding how to close them.

## Phase 3 — Design once the gaps are closed (or proven inapplicable)

Two wiring shapes, in increasing order of risk/reward — **pick based on
what Phase 2's follow-up finds:**

**3a (lower risk): cache the stdlib env, keep user-code typecheck on the
existing full path.** Build `stdlib_tc_env` via `check_module_core` on
`stdlib_decls` ALONE (reusing the exact same pass-1/pass-2 machinery
`--check`/`--compile` already trust for stdlib — no gap, since
`check_module_core` typechecks stdlib the same way either way), cache that
`final_env` to disk. Then typecheck the user's `all_decls` by feeding them
through `check_module_core` too, but seeded from the cached env instead of
`make_env` — this needs `check_module_core` itself to optionally accept a
starting env (a small, additive signature change), NOT `check_module_with_env`.
This sidesteps BOTH Phase 2 gaps entirely, since the user's own code still
gets the full, un-gapped pass 1. Preferred if Phase 2's stdlib-forward-reference
question comes back "yes, this happens" for gap 1.

**3b (more reuse, more risk): route both stdlib and user-code through
`check_module_with_env`,** after fixing gap 1 (swap `Mono (fresh_var 0)` for
`prebind_fn_scheme def` in `prebind_mod_members_inc`, mirroring
`check_module_core` exactly) and gap 2 (add the missing `local_fns`/
`fn_arities` updates to `check_module_with_env`'s top-level `Ast.DFn` pass-1
arm). This makes `check_module_with_env` a true drop-in for
`check_module_core` rather than a REPL-specific reduced duplicate, which is
arguably the more correct fix on its own merits (closes a latent gap
regardless of this plan) but touches more of typecheck.ml's shared, load-bearing
pass-1 logic.

**Recommendation: do 3a first.** It's strictly additive to `check_module_core`,
touches nothing the REPL depends on, and delivers the full measured win
(stdlib typecheck is the expensive part; the user's own files are typically
small). 3b can follow later as a general typecheck-internals correctness
fix, decoupled from this performance work.

## Phase 4 — Wiring (once 3a lands)

**Files:** `bin/main.ml`'s `compile` (~line 1147) and `run_check_cmd`
(~line 2639).

- Both currently build `combined = stdlib_decls @ all_decls` (or a synthetic
  wrapping module) and call `Typecheck.check_module combined` fresh. Replace
  with: load-or-build `stdlib_tc_env` (new cache, `~/.cache/march/stdlib_tcenv_<hash>.bin`
  — reuse the REPL's cache file naming/location so a warm REPL session and a
  `forge check` invocation share the SAME cache entry, doubling the value of
  each cache-populating run) via the Phase 3a mechanism, then typecheck
  `all_decls` against it.
- Unify `bin/main.ml`'s `stdlib_source_hash` (file-byte hash) and
  `repl.ml`'s `stdlib_content_hash` (marshaled-decls hash) — right now they're
  two different hash functions over conceptually the same input, computed in
  two different files; if they diverge, the two cache namespaces
  (`stdlib_ast_*` for parsed decls, `stdlib_tcenv_*` for typechecked env)
  could silently go stale independently of each other. Not urgent, but worth
  a `Digest`-level shared helper before this plan's cache adds a THIRD
  hash-of-stdlib computation.
- `--compile`'s stdlib TIR LOWERING cost (measured Phase 0 delta: ~0.07s,
  much smaller than typecheck's ~0.41s) is explicitly OUT OF SCOPE for this
  plan — `lower.ml`'s heavy use of global mutable `Hashtbl` refs
  (`_lowered_modules`, `_use_aliases`, `_iface_methods`, etc., the same
  machinery whose interaction with auto-discovery caused the transitive
  bugs found earlier this session) makes caching lowered TIR across
  invocations a substantially riskier follow-up, not justified by the small
  measured payoff.

## Phase 5 — Verification (required before this ships, not optional)

- **Diagnostic-parity harness:** for a representative corpus of real
  projects (`march_doc`, `scroll`, `bastion`, plus the compiler's own
  `test/`), run `forge check`/`march check` through BOTH the old
  (`check_module` combined) and new (cached-env + `check_module_core` with
  seed) paths and assert byte-identical diagnostic output (same errors, same
  warnings, same spans, same order). Any divergence is a correctness bug in
  the new path, full stop — this plan must not ship if it changes what gets
  reported, only how fast.
- Cache invalidation test: touch a stdlib file, confirm the next invocation
  detects the hash change and rebuilds (not silently serves a stale env).
- Regression test in `test/test_compiler.ml` or a new `test_typecheck_cache.ml`
  for the underlying `check_module_core`-with-seed-env mechanism itself
  (independent of the disk cache), asserting it produces identical
  diagnostics/types to a from-scratch combined check on a small fixture with
  cross-module forward references (the exact shape Phase 2's gaps are about).

## Non-goals (unchanged from the original daemon plan)

- CI / one-shot cold builds get no benefit from a warm on-disk cache on a
  machine that just checked out the repo — this is a repeat-invocation,
  same-machine optimization only.
- No persistent process, no IPC, no fork — superseded by reusing the
  existing on-disk Marshal cache mechanism.
