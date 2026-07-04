> ## STATUS ADDENDUM (2026-07-03) — program closed out, Waves 1–4
>
> This block is an append-style addendum prepended above the original 2026-07-01
> report. Nothing below this block has been rewritten; dispositions are recorded
> here, against the section numbers they resolve. Campaign plans: Wave 1
> `specs/plans/2026-07-01-wave1-p0-fixes.md`, Wave 2
> `specs/plans/2026-07-02-wave2-testing-infra.md`, Wave 3 chunk 1
> `specs/plans/2026-07-03-wave3-chunk1-refactors.md`, Wave 3 chunk 2
> `specs/plans/2026-07-03-wave3-chunk2-emit-lower.md`, Wave 4
> `specs/plans/2026-07-04-wave4-docs.md`. Full per-wave ledger:
> `.superpowers/sdd/progress.md`. Program-closeout paragraph:
> `specs/progress.md` "Program closeout" entry.
>
> ### §2 P0s — ALL FIXED (Waves 1–2)
>
> All 16 lettered findings (B1–B16) plus the FLOAT pattern-arm gap are fixed.
> B-id → landing commit:
>
> | Finding | Commit | Landed |
> |---|---|---|
> | B1 (owned+borrowed double-dec) | `a5dad194` | pre-Wave-1 (sibling lineage, merged; also the governing commit Wave 4 Task 2 cites) |
> | B2 (FBIP arity/type-param conflation) | `a5dad194` | pre-Wave-1 (same commit as B1) |
> | B13 (oracle skips compiled crashes) | `a5dad194` | pre-Wave-1 (same commit as B1/B2) |
> | B3 (guard-exhaustion returns 0) | `11925401` | Wave 1 Task 1 |
> | B4 (dropped PatRecord/LitFloat rows) | `e8a43b7b` | Wave 1 Task 2 |
> | FLOAT missing from `is_pattern_start` | `6e376e4d` | Wave 1 (token-filter gap, same series) |
> | B9 (`march_` prefix off-by-one) | `cd0770d9` | Wave 1 Task 3 |
> | B10 (RC-op shadow guard gap) | `b98115da` | Wave 1 Task 4 |
> | B5 (EUpdate on erased record) | `0d1a829e` | Wave 1 Task 5 |
> | B15 (lexer newline desync) | `f169070c` | Wave 1 Task 11 (cherry-picked from Stream B) |
> | B6 (pipe-into-match discards scrutinee) | `b579f848` | Wave 1 Task 12 (cherry-picked from Stream B) |
> | B14 (interleaved fn-clause groups) | `4cdc65de` | Wave 1 Task 13 (cherry-picked from Stream B) |
> | B16 (`~H` CSRF free-variable injection) | `f39a5c49` | Wave 1 Task 14 (cherry-picked from Stream B) |
> | B7 (mutual-TCO dec-chain drop) | `05d9e46b` | Wave 1 Task 6 |
> | B8 (mutual-TCO no reduction check) | `bc5b0e22` | Wave 1 Task 7 |
> | B12 (`cur_type_defs` stale global) | `53c70a0e` | Wave 1 Task 8 |
> | B11 (REPL closure wrapper ptr-ABI) | `b32d8569` | Wave 1 Task 9 |
>
> Final-review pass over Wave 1 (commit `926b14f4`) additionally closed an
> `in_tail` blind spot in mutual-TCO group formation that the B7/B8 fixes had
> left open, plus REPL desugar-diagnostic rendering (the LSP-analogous gap —
> `lsp/lib/analysis.ml` threading `~errors` into `desugar_module` — landed the
> same family via merged commit `07fdb5b7`, cross-referenced in
> `specs/progress.md`). Wave 2's double-dec_rc P0 (a distinct, newly-discovered
> bug surfaced by the Wave 2 Task 4 snapshot corpus, not one of the original 16)
> was fixed in `20d1d144` and excludes the scrutinee from cross-branch decs —
> see the Task 2 note below on the scrutinee-borrowed approximation.
>
> ### §7 refactors — COMPLETE (Wave 3 chunks 1–2)
>
> Every module split and shared-contract extraction in §7.1–§7.4 landed, each
> as a pure-move commit verified byte-identical-IR against the pre-move
> compiler (×4 benchmarks/fixtures per step) with zero snapshot churn:
> `Tir_names` (§7.1, commit `c1ad25dd`), `Rc_types` (§7.1, `0cd6b627`),
> `fn_kind` role flags replacing name-sniffing (§7.1, `c28ff465`), Perceus
> env-record threading (§7.3, `98d4a96d`), the `lib/tir/perceus/` file split
> into 5 modules (§7.3, `743b581b`); then in chunk 2, `llvm_ctx.ml` tag-helper
> extraction (§7.4, `50c30f18`), the declarative builtin table (§7.4,
> `7d10fe02`), `llvm_eq.ml`/`llvm_data.ml`/`llvm_case.ml` (§7.4, `ec294fb8`),
> `llvm_calls.ml`/`llvm_tco.ml` (§7.4, `ce2fb5aa`), `llvm_toplevel.ml`/
> `llvm_repl.ml` with `llvm_emit.ml` reduced to an 8-module orchestrator (§7.4,
> `c37e81df`), `lower.ml` env-record threading (§7.2, `fe046757`), and the
> `lower.ml` split into 5 focused modules plus orchestrator (§7.2, `190c0797`).
> `perceus.ml` went from 1937 to a 162-line orchestrator + 4 modules;
> `llvm_emit.ml` went from 6879 to a 2957-line orchestrator + 8 modules;
> `lower.ml` went from 2868 to a 1399-line orchestrator + 6 modules. The
> transitional `fn_kind` asserts seeded in chunk 1 were retired once `FnFused`
> gained bidirectional test coverage (chunk 2 Task 1/2, `4404b2fa`/`7d10fe02`).
>
> ### §8 testing — items 1–4 LANDED; W2.0 loud-skips beyond the plan; items 5–8 OPEN BY CHOICE
>
> Landed: **(1)** the differential-oracle fix is part of the same `a5dad194`
> commit as B1/B2/B13 above — it is what let both criticals be caught at all.
> **(2)** the confirmed repros landed as compiled regression tests in the same
> commit series (`both(s,s,1)` owned+borrowed shape, FBIP dead-binding-reuse
> shape) — see `test/test_stdlib_suite.ml`/`test/test_codegen.ml`'s
> `fbip_p8`/`same_arity_raw_type_refused` entries. **(3)** the LLVM IR validity
> gate landed as Wave 2 Task 3 (`d685bc61`) — `opt -passes=verify` over all
> 37 native-target fixtures, wired into `run_codegen`. **(4)** TIR snapshot
> infrastructure landed as Wave 2 Task 4 (`dfcd19d7`) — 14-program corpus, 29
> tests, a 6th runner (`run_snapshots.exe`); its own audit pass additionally
> found a genuine double-`dec_rc` P0 (fixed `20d1d144`) beyond anything §8
> asked for. **Beyond the plan:** W2.0 (commit `867d5a33`) converted ~23
> vacuous test-harness skip-sites to loud failures — not one of items 1–8, but
> the same "stop swallowing compiled-mode failures" discipline; it caught the
> still-open Monomorphization-limit P0 (below) as a direct result. **Open by
> choice, items 5–8:** the RC balance/gc-trace harness (item 5), codegen
> twin-path FileCheck-style tests (item 6), property-test generators biased at
> the known weak spots (item 7), and the menhir conflict budget (item 10 in the
> original numbering) were never scheduled into Waves 1–4 — the campaign
> judged items 1–4 sufficient leverage for the fix backlog in hand and
> deliberately left 5–8 for a future testing-infra wave. They remain valid,
> undiminished recommendations; see `specs/todos.md` P2 "Testing infrastructure"
> family for the open entries where any exist.
>
> ### §9 docs — COMPLETE (Wave 4)
>
> All seven documentation recommendations landed as four new/extended docs:
> `docs/value-representation.md` (Wave 4 Task 1, commit `94b7c36d` — item 1);
> `specs/perceus-invariants.md` (Task 2, `e5343e84` — item 2, including the
> scrutinee-borrowed approximation rewritten for post-campaign truth: sort_by
> was exonerated, per `.superpowers/sdd/sortby-diagnosis.md`, the real bug was
> `mono.ml`'s empty-substitution interface-impl resolution fixed in `ffe6fba8`,
> not `ECase` scrutinee ownership); `specs/features/tir-invariants.md` plus the
> actor-layout runtime mirror comment (Task 3, `68f8055b` — items 3 and 4); the
> if/then correction removing the undocumented `then` production from the
> grammar plus both syntax docs corrected to verified truth (Task 4, `f8b25df7`
> — part of item 5, the "wrong docs found during review" cleanup); and the
> user-facing semantics notes section in `syntax_reference.md` covering
> top-level-let re-evaluation, newline-glom continuation, derived-Ord/Hash
> payload-blindness, nested-default-arg value dropping, and the soft-keyword
> asymmetry (Task 5, amended to `f145439a` — item 6). Item 7 (the synthetic-name
> registry) is folded into Task 3's `tir-invariants.md` rather than a standalone
> spec. The stale `compiler-rc` skill `test/test_snapshots.ml` reference (item
> 5's other half) was corrected in Wave 2 Task 4.
>
> **Two new P1s Wave 4 itself discovered** — evidence the program's discipline
> outlived the program: while verifying Task 5's semantics-notes claims by
> re-executing every probe (per the wave's own claim-verification gate), the
> reviewer's fix cycle caught that the *original* probes had run against the
> wrong compiler binary (a stale shell `cwd` resolved to a different checkout
> entirely), and re-running them at the correct HEAD surfaced two previously
> undocumented compiler bugs rather than confirming the milder behavior first
> assumed: **(1)** derived `compare`/`hash`/`eq` called *by name* (not via the
> `==` operator) on a `Newtype`-repr variant (single constructor, single field)
> crashes the compiled binary — SIGSEGV for an `Int` payload, a non-exhaustive
> panic for a `String` payload — while the interpreter runs fine; the `==`
> operator path is unaffected. **(2)** top-level default-arg functions are
> unreachable by their own name from March source at any arity, in every mode
> (`--check`/`--compile`/interpreted) — `expand_defaults_decl` emits only
> mangled `f$N` decls and the typechecker (unlike the interpreter's
> `VMultiarity` reconstruction and the TIR's `_default_dispatch` rewrite) never
> learns the bare name exists. Both are filed with full repros, root-cause
> pointers, and test-gap notes in `specs/todos.md` P1 "Compiler (found during
> Wave 4 Task 5 semantics-notes verification, 2026-07-03)"; neither is fixed by
> this campaign (Wave 4's scope was documentation, not new code repair) — see
> `specs/progress.md`'s program-closeout entry for the full disposition.

# March Compiler Pipeline — Deep Review & Recommendations

**Date:** 2026-07-01
**Scope:** `lib/tir/lower.ml`, `lib/tir/llvm_emit.ml`, `lib/tir/perceus.ml` (the three highest-churn bug sources), plus `lib/tir/borrow.ml` and the front end (`lib/lexer/lexer.mll`, `lib/parser/parser.mly`, `lib/desugar/desugar.ml`) since upstream choices repeatedly cause backend RC bugs.
**Methodology:** Four parallel deep-review passes, each reading its assigned files in full with line-level verification. The RC and front-end reviews additionally **compiled and ran repro programs** to confirm findings. Churn analysis from git history.

**Finding status legend:**
- ✅ **runtime-confirmed** — a repro was compiled/run and the failure observed
- 📖 **source-verified** — the defect is visible in the code with citations; no repro run
- ❓ **needs investigation** — plausible defect, specific open question stated

---

## 1. Executive summary

### The churn evidence

| File | Commits | Fix-commits | Fix % | Since 2026-05 |
|---|---|---|---|---|
| `lib/tir/perceus.ml` | 44 | 39 | **89%** | 14 |
| `lib/tir/borrow.ml` | 18 | 16 | **89%** | 8 |
| `lib/tir/llvm_emit.ml` | 181 | 123 | **68%** | 92 |
| `lib/tir/lower.ml` | 91 | 61 | **67%** | 33 |
| `lib/parser/parser.mly` | 93 | 41 | 44% | 28 |
| `lib/desugar/desugar.ml` | 46 | 18 | 39% | 10 |
| `lib/lexer/lexer.mll` | 42 | 16 | 38% | 15 |

perceus.ml and borrow.ml are essentially *never touched except to fix a bug*. llvm_emit.ml has absorbed 92 commits in two months. These are the files where structural investment (refactoring, invariant docs, better tests) pays off most.

### Bugs found (fix these first)

Six critical, ten high. The two RC criticals were confirmed with compiled repros:

| # | Sev | Where | One-liner | Status |
|---|-----|-------|-----------|--------|
| B1 | CRIT | perceus.ml:505–561, 617–677 | Var at owned **and** borrowed position in one call → double-dec → use-after-free (abort, exit 134) | ✅ |
| B2 | CRIT | perceus.ml:282–285, 1450–1482 | FBIP dead-binding reuse sizes the cell by **type-parameter count**, not constructor field count → heap overflow (e.g. reusing an `Ok(x)` cell for a 2-field ctor) | ✅ |
| B3 | CRIT | lower.ml:1173, 1119 | Guard exhaustion returns literal `0` instead of panicking — garbage value of arbitrary type (the file's own comment at :1028 says this is wrong) | 📖 |
| B4 | CRIT | lower.ml:925–947, 1089–1091 | `PatRecord` and float-literal match arms **silently dropped** from match compilation (same shape as the fixed PatAtom bug 99e5cf82) | 📖 |
| B5 | CRIT | llvm_emit.ml:4214–4251 | `EUpdate` on a type-erased record allocates a 0-field cell then writes fields past it (EField has a `_dyn` fallback for this case; EUpdate doesn't) | 📖 |
| B6 | CRIT | desugar.ml:451–454 | `x \|> (match scrut do ...)` silently **discards the scrutinee** and matches on `x` instead | ✅ |
| B7 | HIGH | llvm_emit.ml:2969–3002 | Mutual-TCO back-edge emits the Perceus dec-chain into a dead block → RC leak every loop iteration | 📖 |
| B8 | HIGH | llvm_emit.ml:5350–5542 | Mutual-TCO combined fn has **no reduction check** → a mutual-recursion loop starves the scheduler worker forever | 📖 |
| B9 | HIGH | llvm_emit.ml:1433–1434 | `String.sub n 0 7 = "march_"` — off-by-one makes the runtime-extern-as-value arm dead; fallthrough can call the extern with 0 args | 📖 |
| B10 | HIGH | llvm_emit.ml:4091–4133 | `EIncRC`/`EDecRC`/`EFree` skipped by *name* against top_fns/builtins with no `var_slot` shadow check — a local named `link`/`send` gets zero RC ops | 📖 |
| B11 | HIGH | llvm_emit.ml:6803–6826 | REPL closure wrapper missed the uniform ptr-ABI fix (e709bee9) — REPL closure returning Int gets halved on odd results | 📖/❓ |
| B12 | HIGH | llvm_emit.ml:205 | `cur_type_defs` set only by `emit_module`; all REPL/fragment emitters use stale type defs → niche-vs-boxed ABI mismatch across JIT fragments (same family as the cross-module Option repr bug) | 📖 |
| B13 | HIGH | test_properties.ml:730 | Differential oracle **skips** compiled crashes (`rc_run <> 0 → None`) — the one harness positioned to catch B1/B2 is blind to them by construction | 📖 |
| B14 | HIGH | parser.mly:33–77 | Interleaved same-name fn clause groups silently shadow the earlier group; the "later validation pass" promised in the comment doesn't exist | ✅ |
| B15 | HIGH | lexer.mll:204–226 | Raw newline inside `"…"` accepted without `Lexing.new_line` → every subsequent diagnostic line number off by one per embedded newline | ✅ |
| B16 | HIGH | desugar.ml:269–347 | `~H` CSRF injection fires on any `<form method=post>` and splices a free variable literally named `conn` + `CSRF.tag_string` — breaks all non-Bastion `~H` users (worse now that bastion is being removed) | ✅ |

Full per-file findings, including ~25 medium/low items, are in §3–§6.

### Why these files keep generating bugs — five structural root causes

The fix-theme analysis across all four reviews converges on the same five patterns. Nearly every historical fix and every new finding above is an instance of one of them:

1. **Global mutable state with manual save/restore.** lower.ml has 12 module-level refs/Hashtbls and is non-reentrant (JIT calls it per fragment); perceus.ml threads ownership through 6 globals restored by hand at every scope boundary (the shadow double-dec 7cbb3b3 and tuple-param ECase 3c937d37 fixes were save/restore omissions); llvm_emit's `cur_type_defs` is stale for every non-`emit_module` entry point (B12); the lexer's interpolation state can't nest and leaks across parses in the LSP/REPL. **Fix: thread explicit env records.**

2. **Magic-string contracts between passes with no single source of truth.** `$TupleN`, `$fv%d`, `__try_call*`, `$apply$`, `$Clo_`, `Iface$Ty.m`, `base$N`, bool tags spelled `"True"`/`"true"`/`string_of_bool` in three places, the actor `$d_`/`$e_`/`$f_` alphabetical-sort hack coupled to hardcoded C-runtime word indices, user-capturable `__arg0`/`__celem`/`conn`. A rename in one pass silently disables an RC exemption in another (`is_apply_fn` is copy-pasted between perceus.ml:246 and llvm_emit.ml:384). **Fix: a shared `Tir_names` module + role flags on `fn_def` instead of name sniffing.**

3. **Parallel code paths that drift.** llvm_emit fans every ABI decision across EApp / 4 ECallPtr arms / closure dispatch / REPL wrappers — the ptr-ABI fix landed in 3 of 5 places (B11); self-TCO handles the Perceus dec-chain, mutual-TCO doesn't (B7); EField has an erased-record fallback, EUpdate doesn't (B5). lower.ml has three diverged copies of the module-decl walker (lazy-stdlib copy silently drops DUse/DActor/DExtern). `needs_rc` is duplicated between borrow.ml and perceus.ml and **already diverges** on `TFn`/`TVar`. **Fix: single-source resolvers (return-type-of-fn, decl walker, needs_rc) + twin-path regression tests.**

4. **Silent fallbacks that miscompile instead of failing loudly.** Guard exhaustion → `0` (B3); unhandled pattern rows → `None -> ()` discard (B4); `ctor_entry` fabricates tag 0 for unknown ctors; `coerce` catch-all returns the uncoerced value; `derive X for TypoName` → silently skipped; MPST role-count fallback `3`; the differential oracle skipping crashes (B13). **Fix: a "fail loudly" policy — internal fallbacks become `failwith`/diagnostics; adopt it as a review rule.**

5. **The testing gap is structural, not incidental.** No TIR snapshot tests exist anywhere (`test/snapshots/` does not exist — note the `compiler-rc` skill doc references `test/test_snapshots.ml`, which is stale). Codegen assertions are substring checks + end-to-end goldens; no `llvm-as`/`opt -verify` gate; the property-test oracle skips exactly the crash class RC bugs produce. **Fix: §8, in priority order — the oracle fix alone would have caught both runtime-confirmed criticals.**

---

## 2. Prioritized action list

### P0 — surgical bug fixes (each small; most testable with a one-file repro)

1. **B13 oracle fix** (`test/test_properties.ml:730`): treat `WIFSIGNALED`/exit ≥128 from the compiled binary as **failure** when the interpreter succeeded. Do this first — it converts the whole RC bug class from silent to caught.
2. **B1 owned+borrowed double-dec** (`perceus.ml`): when a variable occupies ≥1 owned position in a call, suppress its borrowed-position post-dec (or emit one IncRC per coexisting borrowed-dead occurrence). Add the `both(s, s, 1)` repro as a compiled regression test.
3. **B2 FBIP arity** (`perceus.ml:282`): compare against the constructor's real field count (as `add_scrutinee_free_for` at :939–944 already does), never `List.length ts` of the binding's type. Audit `Borrow.has_matching_alloc` (borrow.ml:182–199) for the same heuristic.
4. **B3 guard-exhaustion panic** (`lower.ml:1173, 1119`): hoist `nonexhaustive_panic` out of `compile_matrix_impl` and use it in both fallbacks.
5. **B4 dropped pattern rows** (`lower.ml:1089–1091`): add `PatRecord` + `LitFloat` to `pat_tag_and_subs`; replace the swallowing `None -> ()` with `failwith` so the next unhandled kind fails loudly.
6. **B5 EUpdate erased-record** (`llvm_emit.ml:4214`): add a `march_record_update_dyn` runtime path mirroring EField's `_dyn` fallback, or `failwith` when `all_fields = []` with pending updates.
7. **B9 `march_` prefix off-by-one** (`llvm_emit.ml:1433`): `String.sub n 0 6`. One character. Check whether this intersects the still-open `sort_by`/Known_call crash (the dead arm exists precisely for runtime fns passed to HOFs).
8. **B10 RC-op shadow guards** (`llvm_emit.ml:4091–4133`): add the `not (Hashtbl.mem ctx.var_slot ...)` guard (which `emit_atom` already has, twice) to all five RC arms.
9. **B7 mutual-TCO dec-chain** (`llvm_emit.ml:2969`): add mutual-group twins of the self-TCO `ELet`/`ESeq` interception arms (2301–2339, 2351).
10. **B8 mutual-TCO reduction check** (`llvm_emit.ml`): `emit_reduction_check` after the `mutual_loop` label.
11. **B15 lexer newline** (`lexer.mll:204–226`): call `Lexing.new_line` (or reject raw newlines) in `read_string` and `read_string_interp`.
12. **FLOAT pattern arms** (`token_filter.ml:115–123`): add `Parser.FLOAT` to `is_pattern_start`; audit the predicate against `simple_pattern` (parser.mly:1289–1308).
13. **B6 pipe-into-match** (`desugar.ml:451`): reject `x |> (match scrut do ...)` with a positioned diagnostic (and convert the sibling ECond `failwith` at :436–444 to a proper diagnostic).
14. **B14 interleaved clauses** (`parser.mly`): after `group_fn_clauses`, error when a fn name recurs in a non-adjacent group at the same level.
15. **B16 `~H` conn injection** (`desugar.ml:269–347`): gate on module opt-in or on `CSRF` resolving; with bastion leaving the stdlib this currently breaks every mutating form in `~H`.
16. **B12 `cur_type_defs`** (`llvm_emit.ml:205`): make type defs a `ctx` field; delete the global.
17. **B11 REPL wrapper** (`llvm_emit.ml:6803`): delete the inline wrapper copy; call `clo_wrap_define`. Verify with a REPL session storing then calling a closure.

### P1 — testing leverage (see §8 for detail)

Oracle fix (above) → compiled regression repros for B1/B2 → IR-validity gate (`opt -passes=verify` over the native fixture corpus) → TIR snapshot infrastructure → RC balance harness (gc-trace, assert inc == dec + free) → front-end adversarial suite → menhir conflict budget.

### P2 — refactors (§7): split the three big files, extract `Tir_names` + `Rc_types`, thread env records through lower and perceus.

### P3 — documentation (§9): value-representation doc, Perceus ownership invariants doc, post-lowering TIR invariants, synthetic-name catalogue, and fixing the *wrong* claims in syntax_reference.md / CLAUDE.md.

---

## 3. Findings — perceus.ml + borrow.ml (RC insertion & borrow inference)

### Critical

**[B1 ✅] Owned + borrowed positions of the same variable → use-after-free** — perceus.ml:505–561 (EApp), duplicated :617–677 (ECallPtr extern). `find_inc_vars` inspects only `non_borrowed_args` (:527) → 0 dups; `post_dec_vars` independently adds a dec for the borrowed-dead occurrence (:535–561). One reference, two consumptions. Confirmed: `both(a:own, b:borrow, n)` called as `both(s, s, 1)` with `s` dead-after emits `dec_rc s` after the call while the result aliases `s` — compiled binary aborts (exit 134) deterministically; interpreter prints correctly. This is the owned+borrowed generalization of the owned-only multi-position fix 4303965f, never extended to the borrowed side.

**[B2 ✅] FBIP `same_arity` conflates type parameters with constructor fields** — perceus.ml:282–285 via `try_fbip_sink` :1450–1469 and `fbip_expr` :1477–1482. The scrutinee-free path is safe (synthesized `TCon` carries real field count, :939–944), but the **dead-binding** path feeds `dec_v.v_ty` directly. Confirmed in TIR: dead `Ok(7) : Result(Int,String)` (1 field, 2 type params) reused as `Duo.D(3, 4)` (2 fields) — 8 bytes written past the allocation; only arena slop hid the corruption. The niche guard in llvm_emit.ml:3910–3931 doesn't fire (Result is Boxed). `Borrow.has_matching_alloc` (borrow.ml:182–199) shares the "type-name prefix ⇒ reuse candidate" heuristic — audit together.

### High

**[B13 📖] Differential oracle skips compiled crashes** — test_properties.ml:730: `if rc_run <> 0 then None (* runtime crash — skip *)`. Both criticals above manifest exactly as non-zero exits. Distinguish clean error exits from signal kills; interpreter-succeeds + compiled-dies is a failure, not a skip.

**[📖] Scrutinee-borrowed test is path-insensitive by design and load-bearing for the open sort_by bug** — perceus.ml:988–1004 (`name_free_in v br.br_body`, any-path). Documented at :969–987 as a deliberate leak-not-crash approximation; the comment admits the precise fix is a "significant refactor". Fragile: any liveness-precision "improvement" silently re-breaks sort_by. Pin current behavior with a snapshot; then do the path-sensitive branch analysis properly.

### Medium

- **Six module-global refs with manual save/restore** — perceus.ml:43–122, 800–831, 1017–1027, 1336–1347 (`_borrowed_field_vars`, `_var_ctx`, `_closure_fvs`, `_actor_sent`, …). The shadow double-dec (7cbb3b3) and tuple-param ECase (3c937d37) fixes were precisely save/restore omissions. Thread an explicit env record through `insert_rc_expr` — the single highest-value structural change in this file.
- **`needs_rc` duplicated and already diverged** — borrow.ml:152–163 vs perceus.ml:203–237 (duplication acknowledged at borrow.ml:149–151). Perceus says `TFn _`/`TVar _` need RC; borrow says they don't — so those params are never borrow-classified yet get RC ops, exactly where the closure-FV fixes (a705cc95, d2cf09e, fd520110) kept landing. Extract a shared canonical predicate; if the passes must answer differently, give the two questions different names (`borrow_eligible` vs `needs_rc`).
- **Magic-string role recovery** — borrow.ml:204–206 (`"$Clo_"` prefix), :220/:232/:240 (`__try_call*`), perceus.ml:246–252 (`"$apply$"` substring — copy-pasted at llvm_emit.ml:384), :128 (`"$clo"`), :164 (`send` matched by bare name → any user `send/2` gets atomic RC on arg 2). Carry roles as flags on `fn_def` set at synthesis time.

### Low

- **Elision L5 is name-based, not value-based** — perceus.ml:1388–1407: cancels `IncRC v … DecRC v` around an `ELet` when `v` isn't syntactically free in the RHS; a different-named alias of the same cell consumed by the RHS would break it. Document the no-cross-name-aliasing assumption at the site.
- **[❓] `owned_in` index alignment** — borrow.ml:287–291 indexes flattened args against `modes.(i)`; fails safe today (bounds guard :146). Open question: **does defun/known_call guarantee post-defun EApp is always fully applied with arg-count == param-count?**

### Pass-ordering note (write down)

`preprocess_fn` (scrut-escape) → `insert_rc` → `elide_cancel_pairs` → `insert_fbip`; runs after Known_call/Beta_adt/Join_points-pre and before Escape (bin/main.ml:1575–1617). The `is_apply_fn` guard exists solely because Known_call rewrites `ECallPtr → EApp` before Perceus — document that dependency at the guard.

---

## 4. Findings — lower.ml (AST → TIR)

### Critical

**[B3 📖] Guard exhaustion returns `0`** — lower.ml:1173 and :1119. `Tir.EAtom (Tir.ALit (Ast.LitInt 0)) (* match failure *)` — for pointer-typed results this is memory-unsafe garbage. The correct policy is already stated 140 lines earlier at :1028–1029 (`nonexhaustive_panic`: "Returning LitInt 0 here would silently produce wrong values").

**[B4 📖] `PatRecord` / `LitFloat` rows silently dropped** — `pat_tag_and_subs` (:925–947) returns `None` for both; `is_trivial_pat` (:899–902) is false for both; the grouping loop's `| None -> () (* trivial — should not appear here *)` (:1090) discards the arm. Same shape as the fixed PatAtom bug (99e5cf82, regression at test/test_eval.ml:731–743). `collect_pat_names` handles PatRecord (:1135), confirming records are expected here. *(Cross-reference: the front-end review found `PatRecord` currently unreachable from the grammar — no `{...}` pattern production — which is why this hasn't fired. It becomes live the day record patterns are parseable; fix both ends now.)*

### High

- **Interface-method prefix-stripping can hijack qualified calls** — :232–262, 606–612. `resolve_iface_method` strips module segments until a bare method matches; a user interface method named `contains` with a String impl would hijack `String.contains(s, "x")`. The shadow guard (:606–608) covers only same-module bare names (2f4589f3 patched one instance of the family). Only strip known module qualifiers — or better, consume the typechecker's already-computed resolution.
- **Non-reentrant global state; Pass 1 runs against stale tables** — 12 module-level refs (:20–224). `lower_module` resets four at entry (:1765–1768) but not `_current_module_fns`, `_default_dispatch`, `_fn_param_types`; impl bodies are lowered (:1998) *before* dispatch tables are rebuilt (:2040, :2069) — i.e. against the previous invocation's tables. The REPL JIT calls `lower_module` per fragment (lib/jit/repl_jit.ml:252). Cleanup (:2459–2463) is not exception-protected. `reset_counter()` (:1764) restarts `$lamN` numbering per fragment — [❓] does repl_jit dedupe lifted `$lam1` collisions across fragments? (c6c42780 shows the class has bitten before.)
- **`lower_ty` vs `convert_ty` disagree** — :49 vs :78–84 (annotation path curries `TyArrow(a,b) → TFn([a], b)`; type_map path uncurries `TArrow` chains) and :55 vs :94 (`TyNat n` → `TCon("Nat", [TCon(string_of_int n, [])])` vs `TCon("Nat_<n>", [])` — can never unify in mono). One canonical converter.
- **Lazy stdlib lowering swallows failures and diverged from the main walker** — :1342–1401. `_ensure_module_lowered` re-parses at lowering time with `with _ -> ()` (:1400): parse failures → undefined symbols with no diagnostic; lowering happens without a matching type_map (prior bug 383b2614 documented at :1770–1775); `lower_stdlib_mod_decls` handles only DFn/DType/DMod/DLet while the main walker (:2114–2228) also handles DUse/DActor/DExtern — lazily-loaded modules silently lose imports, actors, externs. Unify into one parameterized walker.
- **Actor glue collisions** — :808–826, 2195–2206. Fixed binder `$raw_actor` (:820) instead of `fresh_name` — two `spawn()` calls in one function produce identically-named `ELet`s, and downstream RC passes key on `v_name` [❓ whether borrow/perceus shadow-handle this]. Spawn glue symbol is the actor's *short* name (`Pool_spawn`) — two `Pool` actors in different modules collide.

### Medium

- **Top-level `let` RHS re-evaluated once per referencing function** (:2396–2450) — a side-effectful top-level `let conn = connect()` runs N times compiled, once interpreted. Also `fn_body_uses` respects `ELet` shadowing (:2409) but not `ECase` branch vars (:2413–2416) or `ELetRec` params → spurious injection. Document the contract or lower to memoized thunks (module-level DLets already are, :2135–2149).
- **Guarded matches duplicate the rest-tree per arm** (:1172–1202) — `rest_expr` embedded inline (:1195) *and* as fallback (:1200); only the fallback copy is join-pointed → O(n²) TIR for n guarded arms. Same for the trivial-row default materialized once per tag branch (:1078→:1110, :1121). Hoist into a single join point.
- **`own` special-case hijacks user fns** (:630) — fires on any 2-arg call named `own` without consulting `_current_module_fns`. Same family as 4fdeda08/2f4589f3.
- **Silently-dropped forms** — :389 (non-PatVar sub-patterns in tuple let-destructure leave vars unbound, no diagnostic), :2099/:1376/:2150 (module/top DLet with non-PatVar pattern produces nothing), :1053 (empty pattern row "trivial"). Emit diagnostics; [❓] verify typecheck rejects refutable let patterns.
- **Type-info loss** — :1105 (ctor sub-pattern vars get `unknown_ty`), :994/:999 (join points typed `TFn([], TVar "_")`), :862–875 (`let?` uses `dummy_span` → ctor alloc key degrades via :685–692), :1324 (`lower_type_def` drops type parameters). And TIR carries **no spans at all** (tir.ml:40–74) — every downstream diagnostic is location-free.

### Low

- Bare `failwith` without span at :784, :786, :829, :894, :1274, :1303 (user-triggerable crash text).
- MPST guessing fallbacks (:539 `n_roles = 3`; :553/:567 role `"unknown"`).
- Dead scaffolding: `call2`/`call1` neutralized with `ignore` (:1798–1831); stale `let _ = inner_fb` (:1077).
- DExtern lowering duplicated verbatim (:2207–2226 vs :2231–2250; the two ed_raises fixes 64202fc0/f999b270 show it already bit once). Nested externs keep unqualified `ed_march_name` (:2217) [❓ cross-module collision].
- `tag_groups` quadratic append (:1095–1097).

---

## 5. Findings — llvm_emit.ml (LLVM IR text emitter)

### Critical

**[B5 📖] `EUpdate` on statically-unknown record writes past the allocation** — :4214–4251. When `get_record_fields` returns `[]`, `emit_heap_alloc ctx 0 0` allocates header-only; the updates loop still runs; `field_index_for` falls back to `(0, TVar "_")` (:1686–1693) and `emit_store_field ctx ptr 0` writes at offset 16 — past the end, all updated fields colliding on index 0. `EField` (:4192–4205) has a `march_record_field_dyn` fallback for exactly this flow, proving erased records reach codegen; EUpdate has none.

### High

- **[B7 📖] Mutual-TCO drops the Perceus dec-chain** — :2969–3002 vs :2301–2339. Self-TCO intercepts `ELet(tmp, EApp(self, args), dec_chain)` and emits the dec-chain before the back-edge; the mutual arm has no ELet counterpart — the generic ELet handler emits the back-edge, opens a dead block (:2997), and the dec-chain lands in it. The shape is explicitly expected (`tail_calls_in` :5002–5005, `has_non_tail_group_call` :5025–5032 both special-case it). Leak per iteration. Add mutual twins of the :2301 and :2351 arms.
- **[B8 📖] Mutual-TCO has no reduction check** — `emit_fn` emits one per loop iteration (:5266–5269) + entry (:5301); `emit_mutual_tco_group` (:5350–5542) has none anywhere. `is_even`/`is_odd`-style loops starve the scheduler worker. Insert `emit_reduction_check` after `mutual_loop`.
- **[B11 📖/❓] REPL closure wrapper missed the ptr-ABI fix** — :6803–6826 vs `clo_wrap_define` :401–422. ECallPtr closure dispatch always reads results as `ptr` (:3596–3604); `clo_wrap_define` tags scalars accordingly (e709bee9); the REPL inline copy still returns raw `target_ret` — its comment claims it's "identical" and cites stale line numbers. Odd Int results get halved. Reuse `clo_wrap_define`; verify in a REPL session.
- **[B12 📖] `cur_type_defs` never set by REPL/fragment emitters** — set exactly once in `emit_module` (:6011); `emit_repl_expr`/`emit_repl_decl`/`emit_repl_fn`/`emit_repl_fn_with_closure_slot`/`emit_fns_fragment` all leave it stale while every niche/newtype decision consults it (:3651, :3831, :4287–4327, :1786) → cross-fragment ABI mismatch (same family as the cross-module Option repr bug). Make it a `ctx` field.
- **[B9 📖] Dead `march_` guard, off-by-one** — :1433–1434: 7-char substring vs 6-char literal (three sibling checks use `0 6`: :575, :3243, :3481). The runtime-extern-as-first-class-value arm never fires; erased fallthrough *calls the extern with 0 args* (:1508–1518). [❓ intersects the open sort_by/Known_call crash?]
- **[B10 📖] RC-op name-based skips ignore shadowing** — :4091–4133 (five arms). `emit_atom` learned the shadow lesson twice (:1363–1371 recursive-closure `go`; :1440–1452 local `link`, with a "heap corruption / use-after-free" comment); the RC arms didn't. A local heap value named `link`/`send`/`monitor` or shadowing a top-level fn gets zero RC ops.

### Medium

- **EApp doesn't coerce args to callee param types** — :3189–3196 (also direct-call ECallPtr arms :3388–3391, :3452–3454); closure dispatch does (:3627–3631). i64↔ptr accidentally works (same register class); `double` vs ptr/i64 crosses FP/GP — silent garbage.
- **`EUpdate` RC contract hole** — :4222–4235 + perceus.ml:1144–1153: children copied with no dup, consumed base never released, runtime free is shallow (march_runtime.c:166–187). Today: base leaked per update; children aliased under a single count [❓ whether records are ever ctor-destructured such that the alias double-decs]. Decide and document: release base + dup children, or make Perceus treat the base as borrowed.
- **Apply-fn ptr-ABI override missing from `fn_declare_str` and both direct ECallPtr arms** — :5315–5320, :3382–3409, :3450–3507 (vs :5197–5200, :3233–3234). Centralize "LLVM return type of fn X" in one resolver used by all four sites.
- **Mutual-TCO wrappers pass `undef` to `nonnull dereferenceable(16)` params** — :5383, :5519–5530 — licenses speculative wild loads after optimization. Drop attributes on combined-fn params or pass `null`.
- **REPL emitters drop `ctx.extra_fns`** — :6692–6698, :6738–6743, :6839–6844 (`emit_repl_fn` :6774 keeps them). `$clo_wrap` trampolines and `ensure_adt_eq_fn` outputs vanish → undefined JIT symbols. [❓ repro: `==` on an ADT inside a bare REPL expression.]
- **`ctor_entry` fabricates tag 0 for unknown ctors** (:1623–1626) — should `failwith` like the arity checks at :3744–3747; this is the ctor-collision family again.
- **`coerce` catch-all returns the value unchanged** (:1291) — e.g. `("double","i64")` yields ill-typed IR with an unlocatable clang error. `failwith` with the pair.

### Low

- `ESeq` value-propagation cleanup list omits `EFree` (:2422–2429) while Perceus's `fix_tail_value` includes it (perceus.ml:880–882) — the 6398c305 bug class.
- `fresh`/`fresh_block` share LLVM's value/label namespace with independent counters (:261–267; d7e920b0 fixed one collision, warning comments duplicated :3704–3713, :3879–3884). One counter or reserved prefixes.
- String-case chain: scrutinee passed to `march_string_eq(ptr)` uncoerced; `is_string_case` is `List.exists` and would mis-slice mixed-tag matches (:4616–4638).
- Niche Some/None classified by `br_vars = []` (:4415–4416) [❓ does the pattern matrix always bind a payload var for wildcard payloads?].
- `is_builtin_fn` is `List.mem` over ~230 strings on hot paths (:431–562); adding a builtin touches **four** unsynchronized places (`is_builtin_fn`, `builtin_ret_ty` :623–898, `mangle_extern` :900–1190, preamble declares :5595–5993) — source of ≥5 "missing builtin" fixes.
- Dead `emit_main_wrapper` (:5995–6003); `is_trivial_dec_chain_returning` defined twice with a "must stay identical" comment (:2206 vs :4990); `llvm_name` sanitization can collide distinct TIR names (:282–288); `EStackAlloc` (:3789–3817) lacks EAlloc's niche/newtype handling [❓ does fusion guarantee only boxed shapes stack-allocate?].

---

## 6. Findings — front end (lexer.mll, parser.mly, token_filter.ml, desugar.ml)

All items below marked ✅ were verified by compiling/running test programs.

### Critical

- **[B6 ✅] Pipe into parenthesized `match` discards the scrutinee** — desugar.ml:451–454. `1 |> (match 2 do ... end)` matches on `1`; scrutinee `2` silently dropped. Sibling ECond case (:436–444) uses bare `failwith` instead of a positioned diagnostic.
- **[B14 ✅] Interleaved same-name fn clauses silently shadow** — parser.mly:33–35, 59–77. `group_fn_clauses` merges only adjacent clauses; the promised validation pass doesn't exist (grepped). First group becomes dead code + a misleading non-exhaustive warning pointing at it.

### High

- **[✅] Multi-head fn + default args: all clauses but the first dropped, then the name doesn't resolve** — desugar.ml:1631–1651 (`first :: _`). Result: "I cannot find `f`. Did you mean `%`?". Error explicitly when a grouped DFn has >1 clause and any `FPDefault`.
- **[B15 ✅] Raw newline in `"…"` desyncs all subsequent line numbers** — lexer.mll:204–226: catch-all `_ as c` consumes `\n` without `Lexing.new_line` (triple-string at :238 does it right). Also applies to `read_string_interp`.
- **[✅] `Lexer_error` uncaught in the CLI** — lexer.mll:5,190; no handler in bin/main.ml (handlers exist only in lint/repl/LSP). Stray `#` → raw OCaml fatal exception, no position. Give it a position (the int-literal path :110–119 already raises positioned `ParseError`) and catch it.
- **[✅] Nested string interpolation mislexes; interp state leaks across parses** — lexer.mll:11–13, 125–139, 206–210, 232–235. Global `interp_depth`/`interp_triple` can't nest (`"a${"b${x}c"}d"` fails opaquely) and are never reset at parse entry — a mid-interpolation abort poisons the next parse in the LSP/REPL. Make it a stack; reset in `Token_filter.make`.
- **[B16 ✅] `~H` CSRF injection references a free variable `conn`** — desugar.ml:269–347 (:331). Fires on any `<form method=post/put/patch/delete>` in any `~H` literal → "I cannot find `conn`" + "Unknown module `CSRF`" for non-Bastion users; with a coincidental `conn` in scope it type-errors or silently captures.
- **[✅] `FLOAT` missing from `is_pattern_start`** — token_filter.ml:115–123. Float-literal match arms fail to parse ("expecting `end`") unless written with a leading `|`.
- **[✅] syntax_reference.md:453 and CLAUDE.md are both wrong about `if`** — (a) `if c do ... end` without `else` is a hard parse error (parser.mly:1025–1029), docs say optional; (b) `if c then e1 else e2` **parses and runs** (parser.mly:1018–1019), docs say no `then` keyword. Decide whether the `then` form is intended (it contradicts da7ce42b's `then`-specific error work); fix both docs either way.

### Medium

- **[✅] STRING/INTERP token spans cover only the *closing* quote** — lexer.mll:204–226 (each sub-rule match resets `lex_start_p`), parser.mly:1166. Note: specs/todos.md:434 and specs/progress.md:863 say *opening* quote — the direction is wrong (matters for anyone slicing from span start). Fix: save `lex_start_p` before entering `read_string`, restore before returning (token_filter.ml:44–63 demonstrates the pattern).
- **[✅] `derive X for UnknownType` silently ignored** — desugar.ml:1396–1397 (`None -> []`). Unknown *interface* errors properly (:1379–1385); unknown *type* (a typo) doesn't.
- **[✅] Derived `Ord` ignores constructor payloads (Hash ditto)** — desugar.ml:1044–1070 (ctor-index subtraction), :1002–1012. `compare(Wrap(1), Wrap(2))` = 0 → sorting scrambles payload order silently. Also inconsistent result ranges between variant-Ord (index difference) and record-Ord (delegates to `compare`).
- **[✅] Block comment across a match-arm boundary swallows the separating NL** — lexer.mll:197–202 (`line_comment` :192–195 emits NL; `block_comment` doesn't). Degraded error, legal-looking code.
- **[✅] Newline-glom generalizes beyond `V(...)`** — token_filter.ml:332–333 + juxtaposition `block_body` (parser.mly:957–998): any `(`-led or operator-led line continues the previous expression — `let b = a` then a line `- 1` silently binds `b = a - 1`. Document the rule; consider a statement-boundary lookahead like the match-arm one.
- **[✅] Soft-keyword asymmetry** — parser.mly:1320–1334 vs :1182–1232, :1312–1314: `init`, `loop`, `on`, `protocol`, `app`, `as`, `with`, `when`, `use`, `in`, `for` are bindable but not referenceable (only STATE/TAG have expr productions); `.init` field access impossible while `.send/.choose/.offer` got special cases (:1152–1160). Errors are generic "I got stuck here" — at minimum name the reserved word.
- **`group_fn_clauses` drops later clauses' ret annotation / doc / attrs silently** — parser.mly:59–77.
- **Menhir: 59 shift/reduce conflicts "arbitrarily resolved" (7 states)** despite the header comment (parser.mly:171–185) claiming explicit resolution. Run `menhir --explain`; add a conflict budget to dune.

### Low

- **[✅] Synthetic names user-capturable** — `__arg0…N` (desugar.ml:57–64, 626–665) and `__celem` (parser.mly:87) are lexable and were verified capturable from user code; `__app_init__` (desugar.ml:751) is user-definable. `f$N` names ARE collision-proof (`$` unlexable). Reserve the `__` prefix or use `$`-names for all synthetics.
- **`FPPat` in default expansion emits unbound `__arg`** — desugar.ml:1658 — `fn f(Some(x), y \\ 1)` → wrapper calls `f$2(__arg, 1)` → unbound-var error at a synthetic site instead of a targeted "patterns + defaults unsupported".
- **Fabricated spans are systemic; type_map is span-keyed, making collisions load-bearing** — desugar.ml:57–64 (`__synth__` + counter), :399–408 (`uniq_span` hack; its comment :388–397 documents that span collisions mis-tag ctors in TIR), all derive bodies use `dummy_span`. [❓ derive-generated nodes share `dummy_span` across different types — exactly the documented collision mechanism; why doesn't derived-Json mis-lower the way pre-fix ~H did? Accidental lookup order, or a latent compiled-mode bug?] Replace all three schemes with one `fresh_synth_span ~near:sp`.
- **Nested-module default-arg fns silently drop default *values*** — desugar.ml:594–624 (the c9ce0d1 fast path; ":616 Default values are dropped here") — arity error where an identical top-level fn works. Code-comment-only; not in syntax_reference.md.
- **`qualify_level` skips DTest/DDescribe/DSetup/DSetupAll/DImpl bodies** — desugar.ml:1789–1808 [❓ does forge's per-file order-independent typecheck trip on unqualified refs inside nested-module tests/impls?].
- **`PatRecord` unreachable from the grammar** — ast.ml:47 defines it; parser.mly:1278–1308 has no `{...}` pattern production. Dead constructor with live (and, per B4, *broken*) downstream handling.
- Misc verified error-quality gaps: leading `|` on variants → generic error; `test` + newline + `"name"` demotes obscurely (token_filter.ml:43–72); lambda `fn x do...end` *does* get a good targeted error (parser.mly:1009–1015).

### Synthetic-construct catalogue (naming contracts backend passes depend on)

| Construct | Synthesized at | Collision-proof? | Contract documented? |
|---|---|---|---|
| `__arg0…N` params/scrutinee (multi-head fns) | desugar.ml:57–64, 626–665 | **No** (✅ capturable) | Comment only (:53–56) |
| `__celem` (comprehensions) | parser.mly:87 | **No** (✅ capturable) | No |
| `__app_init__` | desugar.ml:751 | **No** | Yes (eval.ml:8304, typecheck.ml:6992) |
| `f$N` default-arg mangles | desugar.ml:1641,1665 | **Yes** (`$` unlexable) | Comments (desugar.ml:1611–1627, lower.ml:223, :2013) |
| `__arg` unbound placeholder (FPPat) | desugar.ml:1658 | No — latent bug | No |
| Derive binder families (`_da%d`, `_jv%d`, …) | desugar.ml:885–1341 | Safe in practice | No |
| Pseudo-interfaces `JsonTo`/`JsonFrom` | desugar.ml:1361–1377 | User-declarable | Comment only |
| Sugar-injected name-resolved calls (`to_string`, `++`, `List.map`, `Cons`/`Nil`, `CSRF.tag_string`, free var **`conn`**) | desugar.ml:188–408, parser.mly:40–105 | **No** — resolve in user scope | Only the ~H span invariant (:388–397) |
| `$TupleN` / `$fv%d` / `$lamN` / `Iface$Ty.m` / `$apply$` / `$Clo_` / `__try_call*` / actor `$d_/$e_/$f_` | lower/defun/join_points | `$`-safe from users, but **pass-to-pass by convention** | Scattered comments; no single doc |

---

## 7. Refactoring plan

Ordering: extract the shared modules first (they shrink all three files and kill the drift class), then split files. Each step should be a pure-move commit verified by the full test suite + benchmarks (`bench/tree_transform.march`, `bench/list_ops.march`, `bench/binary_trees.march`).

### 7.1 New shared modules (highest leverage)

- **`lib/tir/tir_names.ml`** — every cross-pass name contract: `tuple_tag n`, `tuple_field i`, `fv_field i`, lambda/join-point prefixes, `iface_mangle`, default-arg mangle/parse (`base$N`, `f$N`), actor suffixes + the `$d_/$e_/$f_` sort trick, `try_call` names, `apply_fn` naming + predicate, bool tag spelling, test fn names (`__march_test_%d__`). Consumers: lower, defun, join_points, borrow, perceus, llvm_emit, js_emit.
- **`lib/tir/rc_types.ml`** — the single canonical `needs_rc` (+ a separately-named `borrow_eligible` if the divergence is intentional), `incrc_for`/`decrc_for`, constructor-arity lookup (fixing B2's `same_arity`), shared by borrow + perceus.
- **Role flags instead of name sniffing** — add `fn_kind : Normal | Lambda | JoinPoint | Apply | TryThunk` to `fn_def`, set at synthesis; retire the `"$apply$"`/`"$Clo_"`/`"__try_call"` string tests in borrow/perceus/llvm_emit.

### 7.2 lower.ml (2464 → ~9 modules)

| Module | Content | Current lines |
|---|---|---|
| `lower_env.ml` | Explicit env record replacing all 12 globals; scoped param-type map (the save/restore dance is hand-rolled 6×: 344–354, 417–435, 718–737, 844–848, 1144–1153, 1179–1199) | 18–263 |
| `lower_types.ml` | Unified `lower_ty`/`convert_ty` (one arrow/Nat encoding) | 31–98 |
| `lower_builtins.ml` | chan/MPST/own/send/spawn/assert special forms as a data table | 489–581, 624–667, 795–829, 877–891 |
| `lower_expr.ml` | `lower_to_atom_k`/`lower_atoms_k`/`lower_expr` | 264–894 |
| `lower_match.ml` | matrix compiler, guards, join points, `pat_tag_and_subs` | 896–1203 |
| `lower_decls.ml` | fn/type defs, **one** parameterized module-decl walker (replacing the 3 diverged copies), aliases, extern (deduped) | 1205–1401, 1909–2308 |
| `lower_actor.ml` | `lower_actor` | 1403–1748 |
| `lower_tests.ml` | test-mode collection | 2309–2395 |
| `lower.ml` | thin orchestrator + `builtin_type_defs` + top-let injection | remainder |

### 7.3 perceus.ml (1779 → `lib/tir/perceus/`)

1. `rc_types.ml` (shared, above) · 2. `liveness.ml` (`live_before`, `name_free_in`, `vars_of_atom(s)` — already self-contained, :292–413) · 3. `insert.ml` (`insert_rc_expr` with an **explicit env record** replacing the six globals — do this first) · 4. `elide.ml` (:1370–1433) · 5. `fbip.ml` (`try_fbip_sink`/`fbip_expr`, with the B2 arity fix) · 6. `scrut_escape.ml` (Phase-0.5, :1515–1653).

### 7.4 llvm_emit.ml (6879 → ~9 modules)

| Module | Content | Current lines |
|---|---|---|
| `llvm_ctx.ml` | ctx, fresh/emit, `llvm_name`, type mapping, `coerce`, **new `emit_tag_scalar`/`emit_untag_scalar`** replacing ~9 inline tag sites (1260–1268, 417–421, 3663–3668, 3690–3696, 3838–3843, 3864–3871, 2181–2184, 2724–2729, 4358–4361), layout constants cross-ref'd to `march_hdr` (runtime/march_runtime.h:11) | 22–425, 1219–1341, 1543–1626 |
| `llvm_builtins.ml` | one declarative table replacing the 4 unsynchronized builtin tables, **generating** the preamble declares | 427–1218, 5592–6003 |
| `llvm_eq.ml` | `mangle_ty_for_eq`, `ensure_adt_eq_fn` | 1746–2130 |
| `llvm_calls.ml` | EApp/ECallPtr, wrappers, dispatch, `clo_wrap_define`, one "return-type-of-fn" resolver honoring `is_apply_fn` (used by emit_fn, EApp, ECallPtr, `fn_declare_str`) | 366–422, 2132–2201, 2434–3643 |
| `llvm_data.ml` | EAlloc/EStackAlloc/EReuse/ETuple/ERecord/EField/EUpdate, ctor lookup, deduped `emit_niche_payload` (3677–3701 vs 3852–3876) | 1628–1744, 3644–4259 |
| `llvm_case.ml` | `emit_case` incl. niche/newtype | 4261–4975 |
| `llvm_tco.ml` | TCO predicates, SCC, mutual groups, Perceus-wrapped TCO arms; single `is_trivial_dec_chain_returning` | 2203–2235, 2289–2391, 2964–3044, 4977–5181, 5322–5542 |
| `llvm_toplevel.ml` | `emit_fn`, `build_ctor_info`, `emit_module`, entries, HCR | 5183–5320, 5544–5591, 6005–6541 |
| `llvm_repl.ml` | REPL fragment emitters (fixed to share `clo_wrap_define`, `extra_fns`, ctx-carried type defs) | 6542–6879 |

---

## 8. Testing recommendations (priority order)

1. **Fix the differential oracle** (test_properties.ml:730): interpreter-succeeds + compiled binary signal-killed (`WIFSIGNALED` / exit ≥128) = **failure**, not skip. Single highest-leverage change; would have caught both runtime-confirmed criticals.
2. **Land the confirmed repros as compiled regression tests**: (a) `both(s, s, 1)` owned+borrowed dead-after; (b) dead multi-param-ADT binding followed by a wider allocation (FBIP reuse). Assert output parity **and** exit code 0.
3. **IR validity gate**: run `llvm-as` / `opt -passes=verify` over emitted IR for the whole `test/native/` corpus (~35 fixtures). Catches the coerce-catch-all / string-case ill-typed-IR class cheaply.
4. **TIR snapshot infrastructure** — none exists (`test/snapshots/` absent; note the `compiler-rc` skill references `test/test_snapshots.ml`, which is stale and should be corrected). Golden post-lowering and post-Perceus `show_expr` dumps for a small corpus: match-compilation shapes (B3/B4 cases, join-point sharing — assert no duplicated fallback subtrees), RC-op structure for the known-bug patterns (mixed owned/borrowed args, cross-branch dec, borrowed-field escape, scrutinee-borrowed conservatism — pin it so a "cleanup" can't silently re-break sort_by).
5. **RC balance harness**: run fixtures under gc-trace (`gc_emit` exists in the runtime) and assert inc == dec + free per allocation. Catches the mutual-TCO leak (B7) and the EUpdate accounting hole. Add an ASAN job (`MARCH_SANITIZE=1`) for the compiled adversarial suite — catches the B2/B5 overflow class deterministically.
6. **Codegen twin-path tests**: per-construct FileCheck-style assertions for the ~10 tagging sites and for each parallel call path (EApp / each ECallPtr arm / closure dispatch / REPL wrapper) so an ABI change must pass N path-specific tests, not one.
7. **Property generators biased at the known weak spots**: calls passing one var at two positions with different borrow modes; dead multi-param ADT bindings before allocations; erased flows (records through TVar, closures through HOFs, odd/negative ints through tuples) for interpreter-vs-compiled diffing.
8. **lower.ml unit tests** via `Test_helpers.lower_module`: name-resolution matrix (user `own`, interface-method hijack, alias/builtin/local precedence), double-`lower_module` reentrancy (JIT-style: stale aliases, `$lamN` collisions), type-conversion parity (annotated vs inferred arrows; Nat encodings), two spawns in one fn, top-level-let side-effect count parity vs interpreter.
9. **Front-end adversarial suite**: token-filter edges (float arms, block comment across arm boundary, operator-led continuation lines), span-fidelity goldens (string caret position, line numbers after multi-line strings), desugar adversarial (pipe-into-match, interleaved clause groups, multihead+defaults, derive typo, derive-Ord payload ordering, `~H` form outside Bastion), lexer state (nested interpolation; two parses in one process after a mid-interpolation failure), CLI `Lexer_error` rendering.
10. **Menhir conflict budget**: `--explain` artifact in CI; fail on conflict-count growth (currently 59 arbitrarily resolved, contradicting the grammar's own header comment).

---

## 9. Documentation recommendations

1. **`docs/value-representation.md`** (or `specs/features/value-repr.md`) — currently the contract lives only in scattered code comments (llvm_emit.ml:1–20, 1240–1268, 366–399, 301–316, 4144–4157, runtime/march_runtime.c:139–156) and agent memory; docs/runtime.md has none of it. Must cover: `march_hdr` layout; the tagged-immediate scheme and the conditional-untag law ("ptr→i64 untags iff odd; i64→ptr tags; known-heap restore is bare inttoptr; never tag a pointer"); which slots are UNIFORM (tuples, erased cells, generic ADT fields) vs NATURAL (records, concrete ADT fields); closure struct layout + the uniform-ptr apply-wrapper ABI; trampoline double-tagging (4n+3); atom hashing (bit63==bit62); niche/newtype rules; the shallow-free RC contract (who dups children). Guard its pointers with the doc-lint script.
2. **`specs/perceus-invariants.md`** — per-TIR-construct entering/leaving ownership contracts: what owned vs borrowed promises at call boundaries (and the B1 invariant: a var at both an owned and a borrowed position must be dup'd); FBIP preconditions (reused cell field-count ≥ new ctor arity; arity = *constructor fields*, never type params; uniqueness is a runtime rc==1 check, so size is the only static obligation); the scrutinee-borrowed path-insensitive approximation and why (sort_by); the needs_rc divergence; the closure-FV rule (captures are borrowing dups; locally-invoked closures don't transfer FV ownership; `$clo` at apply arg 0 is always consumed).
3. **Post-lowering TIR invariants** (in tir.ml or specs/): ANF discipline; `TVar "_"` semantics; the `ELetRec([fn], EAtom(AVar fn))` lambda pattern defun matches on; EApp callees may be non-TFn runtime builtins; the `br_tag` namespace encoding table (ctors, `$TupleN`, ints, quoted strings, `:atoms`, bools in either case — encoder lower.ml:925–947, decoder llvm_emit.ml:4484+); **TIR carries no spans** (and whether that's accepted).
4. **Actor layout contract**: the `$d_/$e_/$f_` alphabetical-sort trick and its coupling to C-runtime word indices `a[2]..a[4]` (lower.ml:1449–1462) — document in the runtime header too (dde29502 was a fix for exactly this coupling).
5. **Fix the wrong docs found during review**: syntax_reference.md:453 + CLAUDE.md `if`/`else`/`then` claims (both false); specs/todos.md:434 + specs/progress.md:863 string-span direction ("opening" → actually *closing* quote); the `compiler-rc` skill's stale `test/test_snapshots.ml` reference. Note the doc-lint script checks pointers/counts, not semantic claims — these rotted invisibly.
6. **User-facing semantics currently documented nowhere**: top-level `let` per-referencing-function re-evaluation; the newline-glom continuation rule (`(`-led or operator-led lines continue the previous expression); nested-module default-arg value dropping; derived Ord/Hash ignoring payloads; the reserved soft-keyword list (`init` et al.).
7. **Synthetic-name registry**: the §6 catalogue table should live in a spec (adjacent to `Tir_names` once extracted) so backend authors know which names are load-bearing — the c9ce0d1 UAF is the case study for why desugar naming/shape choices are RC-relevant.

---

## 10. Fix-theme history (why we're confident in the root causes)

- **perceus/borrow (44+18 commits)**: themes tally — borrow-classification 15, closures 7, underflow 5, FBIP 4, leaks 3, escapes 3, UAF 2, shadowing 2. Dominant pattern: *who owns a value across a call/capture boundary*, inferred by one pass and re-consumed by another through duplicated predicates and mutable globals. B1/B2 sit squarely in the two densest themes.
- **llvm_emit (181 commits, ~51% literal "fix")**: tagging/erased-repr bugs ~12 (the strongest argument for the two audited tag helpers); parallel-call-path divergence ~6 (B11 is the live instance); RC balance on control-flow edges ~8 (B7 is the live instance); name/label collisions ~7 (B10 same family); builtin-table drift ~6 (mechanical, fixed by the declarative table); TCO edge cases ~4 (the mutual path trails the self path by one bug-generation — both new HIGHs are there).
- **lower (91 commits)**: name-resolution/shadowing whack-a-mole ≥10 fixes (4fdeda08, 2f4589f3, …) — each adds one more guard to global string-keyed tables; the `own` hijack and iface prefix-stripping findings are the predictable next entries. Until lowering consumes the typechecker's resolution (or a real scoped env), this series continues.
- **front end (desugar 46)**: the clearest theme is *desugar-synthesized constructs breaking the compiled backend* (92dadd92 nested-default-arg UAF, 607ab7f6, 61b5a4a6, a9f869e0) — every new sugar has needed ≥1 follow-up backend-compat fix, which is why the synthetic-name registry and adversarial desugar tests rank high.
