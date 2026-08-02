# `forge search --callers`: final review fix wave

Landed 2026-08-01, on top of `5397f979` (the 7-task feature landing).

**What this fixed.** The final whole-branch review of `forge search
--callers` (see `specs/progress/2026-08-01-forge-search-callers-reverse-reference-search.md`
for the feature itself) found 7 issues after all 7 individual tasks had
already passed per-task review. All 7 were fixed in this single wave since
the fixes interact:

1. **Critical — cache version bump was inert.** `Search.build_index` bumped
   `version` to 2 when the `references` table was added, but nothing ever
   compared a loaded cache's version against it — an existing user's stale
   v1 cache silently returned "no references found" forever.
   `forge/lib/cmd_search.ml`'s `load_or_build_index` now checks
   `idx.version = Search.current_index_version` (new named constant,
   `lib/search/search.ml`) and rebuilds on mismatch.
2. **Critical — `current_decl` leaked across unrelated functions for
   Call/Ctor.** `env.current_decl` was set by `check_fn` but never restored,
   so a reference recorded at a "callerless" position (top-level `let`,
   `test`/`setup` blocks, actor bodies, default interface-method bodies,
   extern signatures) got attributed to whatever function was checked last
   in module order — wrong, and shown to cross file boundaries in
   multi-file compilation. `check_fn` now saves/restores `current_decl` via
   `Fun.protect`; every other callerless `check_decl` arm (systematically
   found via grep for `infer_expr`/`check_expr`/`surface_ty` call sites
   outside `check_fn`) is wrapped in the existing `with_no_caller` helper;
   the `EVar`/`ECon` hooks now skip recording when `caller = ""`, matching
   `TyCon`'s existing behavior.
3. **Important — prelude/synthetic-module qualification inconsistency.**
   The `EVar`/`ECon`/`check_fn` hooks built `modname ^ "." ^ name` ad hoc,
   producing a leading `.` for prelude ctors (`ci_module = ""`) and leaking
   `Search.typecheck_decls`'s `"__stdlib__"` synthetic wrapper module name
   into references from `prelude.march`'s deliberately-unwrapped top-level
   decls. Unified behind one `qualify_ref_name` helper in `typecheck.ml`;
   `search.ml` strips the `__stdlib__.` prefix before building `ref_entry`s.
4. **Important — `local_fns` shadowing gap.** A function parameter or local
   `let` shadowing a top-level fn name (e.g. `fn wrapper(helper) do
   helper() end` where `helper` is also a top-level fn) had its local
   variable's use misrecorded as a Call to the shadowed top-level fn — a
   textual match, not a resolution-based one. `bind_var` now clears
   `local_fns` on rebind (mirroring the existing `fn_arities`/
   `plain_let_names` clears), with matching conditional restores at the two
   sites that re-bind a genuine top-level fn's own name after checking it.
5. **Important — LSP/JIT reused envs never reset `refs`/`current_decl`.**
   `lsp/lib/typecheck_cache.ml`'s `derive` and `lib/jit/repl_jit.ml`'s three
   per-call env constructions reset `errors`/`type_map`/etc. but not the two
   new mutable fields — an unbounded per-keystroke/per-REPL-fragment memory
   leak in a process-lifetime server. Both now reset `refs`/`current_decl`.
6. **Important — `--limit` silently ignored for `--callers`.**
   `forge/lib/cmd_search.ml`'s `--callers` branch never called `take limit`
   on its results. Fixed.
7. **Important — undeduped type+ctor candidates double-counted
   references.** `search_callers`'s bare-name candidate resolution didn't
   dedupe qualified names before calling `callers_of` on each, so the common
   `type Foo = Foo(...)` newtype pattern (~80 occurrences in the real
   stdlib) double-reported every reference. Fixed with `List.sort_uniq`.

**Regression caught mid-fix.** Fixing #2's `check_fn` save/restore, combined
with #4's `bind_var` change, initially broke two PRE-EXISTING passing tests
(`test_call_ref_same_module`, `test_call_ref_cross_module`): `check_decl`'s
`DFn` arm rebinds a function's own name via `bind_var` right after
`check_fn` returns, which (once `bind_var` started clearing `local_fns`)
wiped the function's own `local_fns` membership — so every same-module call
to a function checked *earlier* in the module silently stopped being
recorded. Caught by re-running the full `test_search.exe` suite immediately
after the change (not assumed clean); fixed by restoring `local_fns`
alongside the existing `fn_arities` restore at that site.

**Test coverage added.** 9 new cases in `test/test_search.ml`'s
`"references"`/`"integration"` groups (findings 2–4, 7) and 3 new cases in
`forge/test/test_forge.ml`'s new `"search_index_cache"` group (findings 1,
6). Finding 5 (env resets) verified by code inspection only — impractical to
assert an unbounded-leak absence in a unit test within scope.

**Full-suite result.** `test_search.exe` 46/46, `test_forge.exe` 133/133,
the other 6 forge test binaries all green, `run_compiler.exe` 628/628,
`run_eval.exe` 256/256, `run_codegen.exe` 541/541, `run_stdlib.exe` 828/829
(1 pre-existing `MARCH_SANITIZE` ASAN-timeout flake, `adversarial-regressions`
#39, already judged unrelated by the final reviewer).

See `.superpowers/sdd/2026-08-01-forge-search-callers/final-fix-report.md`
for the full per-finding detail (file:line, exact test names, results).
