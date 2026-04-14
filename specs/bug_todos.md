# Compiler Bug Todos

Generated from adversarial review on 2026-04-14. Each entry has a priority (P0–P4), file, line(s), and a description.

---

## P0 — Critical

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
- #5 — confirmed false alarm after reading `llvm_ret_ty`; no fix needed.
- #6 — confirmed false alarm after re-reading `find_missing_mc`; algorithm is correct.
- #7 — confirmed false alarm after reading `surface_ty`; `a` is never linked by that function.
