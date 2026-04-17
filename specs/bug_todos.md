# Compiler Bug Todos

Generated from adversarial review on 2026-04-14. Each entry has a priority (P0–P4), file, line(s), and a description.

---

## P0 — Critical

- [x] **#33** `lib/tir/llvm_emit.ml emit_case` — **ECase var_slot state leak** (user-reported codegen bug).  `alloca_name` mutates `ctx.var_slot[name]` to the uniquified slot when a branch introduces a shadow binding.  `emit_case` never restored `var_slot` between branches, so a shadow written by an earlier branch (e.g. `Between(e, lo, hi)` shadowing the function's outer `e` parameter → `var_slot["e"] = "e_1"`) remained in effect for all subsequent branches.  Short arms that referenced the OUTER `e` — typically the scrutinee-free DecRC synthesised by Perceus — then loaded from `%e_1.addr` (an uninitialised Between-branch slot) and `march_decrc_local` segfaulted.
  - **Reproduced** with [examples/codegen_case_var_slot_leak.march](examples/codegen_case_var_slot_leak.march): pre-fix `exit=139`, post-fix `1`.  Also reproduced with the user-reported depot case (`compile_delete` with `Where(ExprParam(1))`).
  - **Fixed:** `emit_case` now snapshots and restores `ctx.var_slot` around each branch body (and the default arm).  Only `var_slot` is restored; `local_names` and `var_llvm_ty` stay monotonic because they back LLVM SSA-name uniqueness (restoring them would cause duplicate `%x.addr = alloca` definitions when two sibling branches bind the same name).



- [x] **#16** `runtime/march_gc.c:138-149` (audit C4, C5) — `walk_block` only checked `total >= sizeof(meta)+16` and `total <= blk->capacity`, with a silent `break` on failure.  A corrupt object truncated the whole block from pass 1's live set, turning a localised heap-corruption bug into a process-wide use-after-free at teardown.  No bounds check on `n_fields` either.
  - **Fixed:** `walk_block` now bounds-checks `total <= remaining`, validates `n_fields*8 <= payload`, and aborts with a diagnostic via `gc_corrupt` rather than silently breaking.  Three abort paths regression-tested via fork in `test_gc_abort_paths` (`test/test_heap.c`).

- [x] **#17** `runtime/march_gc.c:190-213` (audit C3) — Pass-2 left intra-arena pointers dangling when `fwd_lookup` returned NULL; the from-space buffer was then freed at line 254, producing silent UAF.
  - **Fixed:** snapshot from-space block address ranges before pass 2; in `pass2_visit`, distinguish missing-fwd-entry pointers that fall *inside* a from-space block (intra-arena dangling reference → abort) from those that fall *outside* (legitimate malloc'd object such as `march_string` → leave alone).

- [x] **#18** `runtime/march_gc.c:180` (audit L1) — `pass1_visit` ignored `fwd_insert`'s return value.  An allocation failure inside the forwarding table produced a missing entry → C3 dangling pointer → UAF.
  - **Fixed:** check the return; abort with a diagnostic on failure.

- [x] **#19** `runtime/march_gc.c:38` (audit C6) — The `MARCH_STRING_TAG` check was unreachable: no allocation path tags strings with -1 (`march_string_lit` bypasses the arena entirely; `copy_string` overwrites the header without re-tagging).
  - **Fixed:** kept the check (it's correct *if* a future allocator routes strings through this arena and tags them) and documented why it currently does nothing.

- [x] **#12** `runtime/march_runtime.c:160` (audit C1) — `march_decrc_freed` was missing the RC-underflow guard that `march_decrc` has, so any `prev <= 0` path silently returned 1 (and called `free`). On a stale or double-pattern-match call the runtime would double-free instead of aborting.
  - **Fixed:** split the `prev <= 1` branch — `prev == 1` frees normally, `prev < 1` prints a diagnostic and `abort()`s, mirroring `march_decrc`.

- [x] **#13** `runtime/march_gc.c:191` (audit C2) — Pass-2 of the semi-space GC classified pointer fields with only `< 4096`, missing the low-bit-tagged-immediate and sign-bit guards that `IS_HEAP_PTR` enforces. Tagged integers from polymorphic containers were being passed to `fwd_lookup` (wasted work, latent collision risk if heap layouts ever shift).
  - **Fixed:** added `GC_IS_HEAP_PTR` mirroring the runtime predicate; `pass2_visit` now skips tagged immediates and negative scalars. Regression test in `test/test_heap.c` (`test_gc_pass2_scalar_preservation`).

- [x] **#14** `lib/tir/perceus.ml:361` (audit P1) — When the same heap variable was passed at multiple borrowed positions of a single call (e.g. `string_eq(s, s)`) and was dead after the call, Perceus emitted one post-call `EDecRC` per position, underflowing the caller's single reference and aborting via `march_decrc_local`'s own underflow guard.
  - **Fixed:** dedup `post_dec_vars` by `v_name` using a `seen` `StringSet`. Confirmed pre-fix behaviour reproduces in `examples/rc_borrowed_dup_arg.march` (compiled binary aborts with "RC underflow") and disappears post-fix.

- [x] **#15** `lib/tir/llvm_emit.ml:2206` (audit M1) — The non-`TCon` `EReuse` lowering wrote arg fields into the reused cell but never reset the constructor tag. The fresh-allocation branch (`emit_heap_alloc … 0 …`) does write tag 0, so the two branches produced differently-tagged cells from the same source expression.
  - **Fixed:** added `emit_store_tag ctx rv 0` in the reuse branch so both branches emit cells with tag 0.

- [x] **#1** `lower.ml:852,858` — Non-exhaustive match silently returns `LitInt 0` in compiled path instead of emitting a panic/unreachable. Interpreter panics correctly; compiled code produces silent wrong results.
  - **Fixed:** replaced `EAtom(ALit(LitInt 0))` with a `panic "non-exhaustive pattern match"` EApp call, consistent with how `ECond` handles it at line 394.

- [x] **#2** `purity.ml:16–17` — Purity oracle has false positives. Docstring says "false positives are not safe", but the implementation whitelisted only 6 impure builtins and treated everything else (`read_line`, `random_bytes`, `unix_time`, `spawn`, `tcp_connect`, …) as pure. Affects fusion and inlining correctness.
  - **Fixed:** expanded `impure_builtins` to cover all IO, networking, randomness, time, actor/task, process-control, and mutable-state builtins.

- [x] **#3** `llvm_emit.ml:1027,1033` — Duplicate `root_cap` guard arm at line 1033 is dead code (line 1027 matches first). Copy-paste error that may have left a sentinel case unhandled.
  - **Fixed:** removed the duplicate arm. Merged both comments into the surviving arm.

- [x] **#4** `lexer.mll:191,205,234` — Invalid escape sequences (e.g. `\x`, `\z`) silently passed through as literal backslash + char instead of raising a lexer error. Also, legitimate escapes `\r`, `\b`, `\f`, `\0` were missing, causing failures in `json.march` and `base64.march` which used `\r`.
  - **Fixed:** added `\r`, `\b`, `\f`, `\0` as valid escapes in `read_string` and `read_string_interp`; added a catch-before-the-wildcard arm `'\\' (_ as c)` that raises `Lexer_error` for any other backslash sequence.

- [ ] **#5** `llvm_emit.ml:1086–1089` — **FALSE ALARM.** The else branch exclusively handles `"ptr"` (the only remaining case from `llvm_ret_ty`), and `ret ptr %r` is valid LLVM IR when `%r` is a ptr. No fix needed.

---

## P1 — Important

- [x] **#20** `lib/tir/perceus.ml:519-533` (audit P3) — FBIP `shape_matches` could false-positive across types when the scrutinee's type was `TVar "_"` (typical for closure-internal helpers): the code unconditionally rewrote the dec'd var's type to `TCon (ctor_tag, [])` (unqualified), and a same-name ctor of an unrelated type would match by name+arity, producing wrong-layout writes into the reused cell.
  - **Fixed:** only rewrite the var's type when the scrutinee is `TCon` (so we can form a properly qualified `Type.Ctor` tag); otherwise leave it alone.  `shape_matches` then returns false for the (TVar, TCon) case, suppressing FBIP for these scrutinees — the safe fallback.

- [x] **#21** `lib/tir/llvm_emit.ml:2173,2213` (audit M2) — `EReuse` loaded the RC field with a plain `load i64`.  For values that may be actor-shared (atomic-RC contract) this is technically a data race; even though FBIP only fires for values borrow inference proved local, the load is also a TOCTOU on the `rc == 1` test.
  - **Fixed:** changed to `load atomic i64 … monotonic`.  Negligible cost relative to the `march_decrc` call on the fresh-branch path; closes the door on a future widening of FBIP eligibility.

- [x] **#22** `lib/tir/perceus.ml:31` (audit L2) — `_rc_fresh_ctr` was a process-global ref, so identical compilations of the same module produced different IR depending on what came before.  Bad for diff-based test baselines and CAS caching.
  - **Fixed:** reset to 0 at the start of each `perceus` invocation.

- [x] **#24** `lib/tir/llvm_emit.ml:2632-2657, 2667-2685, 2802-2814` (audit P2) — `tail_calls_in`, `has_non_tail_group_call`, and `has_self_tail_call` couldn't see through the `ELet (tmp, EApp f, ESeq(decs..., EAtom tmp))` wrapper Perceus emits when a borrowed-arg-last-use post-call DecRC needs to run.  For mutual recursion this silently dropped TCO at the March IR level (LLVM's own TCO can mask the symptom for direct self-recursion at -O2 but not for the explicit mutual-TCO loop emitter).
  - **Fixed:** added `is_trivial_dec_chain_returning` and an `ELet`-pattern arm in each of the three analyses to recognise the wrap as an effective tail call.  Smoke test: `examples/rc_mutual_tco_borrowed.march` exercises a mutual-recursion shape that hits the wrap path.

- [x] **#25** `runtime/march_gc.c:166-176` (audit M3) — `pass1_visit` had no defensive assert that `n_fields*8` fits the payload size.  walk_block now enforces this (after #16) but a caller bypassing walk_block could re-introduce the same out-of-bounds read.
  - **Fixed:** added a belt-and-suspenders abort with diagnostic in `pass1_visit`.

- [x] **#26** `lib/tir/perceus.ml:155-167` (audit M5) — `vars_of_atom`'s `ADefRef` arm needed clearer documentation about why it returns the empty set: `ADefRef` resolves to a code-segment address that needs no RC, and `march_incrc`/`march_decrc` would corrupt or crash if called on it.  The behaviour is correct; the comment was insufficient.
  - **Fixed:** expanded the docstring + linked to the corresponding `top_fns` guard in `llvm_emit.ml`.

- [x] **#28** `runtime/march_runtime.c:177-214` (audit M4) — `march_decrc_local` does not call `march_heap_record_death` because `march_alloc` is currently plain `calloc`.  When the per-process arena (`march_heap.c`) becomes the default allocator, the GC trigger (`march_heap_should_gc`) will never fire because `live_bytes` won't decrement.
  - **Fixed:** added a load-bearing `TODO(audit-M4)` at the exact site where the call needs to land, plus a top-of-function comment summarising the dependency.

- [x] **#29** `lib/tir/perceus.ml:782-810` (audit L5) — `elide_expr` only matched cancel pairs that were directly adjacent.  After `fix_tail_value`'s ELet restructuring, many cancel pairs end up separated by a single `let tmp = rhs in ...` where `rhs` does not reference the cancelled variable.
  - **Fixed:** added two extra match arms that elide `ESeq (Inc/Dec v, ELet (x, rhs, ESeq (Dec/Inc v, rest)))` to `ELet (x, rhs, rest)` when `v` is not free in `rhs`.  Pure optimisation (no behavioural change), benchmarks unchanged.

- [x] **#31** `lib/tir/perceus.ml:783-835` (audit P4) — `elide_expr` was previously permissive about atomicity: a mixed `EIncRC + EAtomicDecRC` (or inverse) pair would be elided as if they cancelled.  In correct Perceus output this never arises (atomicity is selected uniformly per function via `_actor_sent`), but a future pass that crosses actor-send boundaries (e.g. inliner) could produce mismatched pairs — eliding them would silently drop the required atomic op and introduce a data race.
  - **Fixed:** split the 2 permissive arms into 4 strict arms (and 4 more for the L5 across-ELet variant).  Mixed-atomicity pairs are now left in place so any introducing bug surfaces as extra RC ops rather than a memory-ordering heisenbug.  Dedicated unit test `test_perceus_elide_preserves_mixed_atomicity` (test/test_march.ml) covers all 4 matched-elide shapes + all 4 mismatched-preserve shapes + across-ELet variants.

- [x] **#32** `lib/tir/perceus.ml:436-445` (audit P5) — `ECallPtr` has no callee name and so cannot query the module borrow map; every arg is conservatively treated as owning.  Result: extra IncRC/DecRC pairs around higher-order calls whose apply function actually borrows.  Correct but a real perf tax.
  - **Fixed (doc only):** added a load-bearing comment at the handler explaining the trade-off and sketching the architectural change required for a real fix (per-call-site borrow modes attached to closures at EAlloc time, plumbed through dispatch).  No code change — full fix deferred; it requires closure-layout evolution beyond the audit's scope.

- [x] **#30** `lib/tir/llvm_emit.ml:2154-2249` (audit L6) — EReuse FBIP merge previously used an `alloca ptr` slot with `store` in each branch and `load` at the merge.  mem2reg eliminates this in optimisation, but it leaves a worse first-pass IR and depends on the optimiser running.
  - **Fixed:** switched to LLVM `phi` directly.  `reuse_lbl`/`fresh_lbl` are the immediate predecessors of `merge_lbl` because the body of each branch only emits non-label-producing helpers (`emit_store_tag`, `emit_store_field`, `emit_heap_alloc`).

- [x] **#27** `lib/tir/borrow.ml:288-309` (audit M6) — `escapes_through` only follows direct aliasing (`let v = src in ...`).  Indirect aliases via trivial wrapper calls (`let v = identity(src) in ...`) would not be tracked.  Not a correctness bug today (no such pass exists), but a perf foot-gun if one is added.
  - **Fixed:** documented the limitation in a load-bearing comment so the constraint is visible at the matcher.  Adding an `EApp`-recognising case for known-identity callees is the natural follow-up if a future opt pass produces such patterns.

- [x] **#23** `lib/tir/borrow.ml:194-210, 369-443` (audit L3, L4) — Two debug instrumentations gated on `MARCH_BORROW_DEBUG` / `MARCH_BORROW_DEBUG2` env vars and string-equals against three specific function names.  Fossil from a past investigation that future readers would mistakenly assume was load-bearing.
  - **Fixed:** removed.

- [ ] **#6** `typecheck.ml` (~exhaustiveness check) — **FALSE ALARM** after deep re-read. The `is_complete = false` branch correctly returns `None` (exhaustive) when wildcard rows in the default matrix cover the missing constructors — that is the correct semantics. No fix needed.

- [ ] **#7** `typecheck.ml:1777–1786` — **FALSE ALARM** after reading `surface_ty`. That function only constructs types; it never calls `unify`, so `a` cannot be linked during the call. The `a_id = 0` fallback is dead code. No fix needed.

---

## P2 — Error Message / UX

- [x] **#8** `eval.ml:2184` — Modulo error message contained literal `%%` (inside a `Printf.ksprintf` call, so `%%` was decoded correctly to `%` at runtime, but the div-by-zero case fell through to the wrong message and the message was also misleading).
  - **Fixed:** added an explicit `[VInt _; VInt 0] -> eval_error "modulo by zero"` arm; changed the catch-all message to `"builtin %%: expected two integers"`.

---

## P3 — Performance

- [x] **#9** `mono.ml` — No depth limit on recursive monomorphic specialization. A recursive polymorphic call pattern can cause unbounded specialization depth, compilation non-termination, and code-size explosion.
  - **Fixed:** added `spec_counts` tracking per original function. If any function accumulates ≥ 512 distinct specializations, `monomorphize` raises a `Failure` with a diagnostic message naming the function and explaining the likely cause (polymorphic recursion). Limit is conservative — legitimate generic code rarely needs more than a handful of specializations per function.

- [x] **#10** `perceus.ml:68–84` — `collect_closure_fvs` did not recurse into `ELetRec`. If a defunctionalized apply function has a local recursive binding that loads closure fields, those names would not be in `_closure_fvs` and the RC inserter would emit spurious dec/incRC on closure-owned variables (potential double-free).
  - **Fixed:** added `ELetRec` arm to the `scan` traversal, recursing into each function body and then the continuation.

---

## P4 — Dead Code / Cleanup

- [x] **#11** `typecheck.ml:676` — `| Link t' -> inst t'` arm in `inst` is unreachable: `repr` fully dereferences all links before returning, so a TVar after `repr` cannot be a Link.
  - **Fixed:** replaced the arm with `| Link _ -> assert false` to make the invariant explicit and catch any future breakage.

---

## Done (moved from above)

- #1, #2, #3, #4, #8, #9, #10, #11 — fixed and all tests passing (dune runtest: green).
- #12, #13, #14, #15 — audit follow-ups (C1, C2, P1, M1) fixed; new regression tests (`test_gc_pass2_scalar_preservation` in `test/test_heap.c`, `examples/rc_borrowed_dup_arg.march`). dune runtest still green (1358 OCaml tests, 4176 C-runtime checks).
- #5 — confirmed false alarm after reading `llvm_ret_ty`; no fix needed.
- #6 — confirmed false alarm after re-reading `find_missing_mc`; algorithm is correct.
- #7 — confirmed false alarm after reading `surface_ty`; `a` is never linked by that function.
