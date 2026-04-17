# Compiler Bug Todos

Generated from adversarial review on 2026-04-14. Each entry has a priority (P0–P4), file, line(s), and a description.

---

## P0 — Critical

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
