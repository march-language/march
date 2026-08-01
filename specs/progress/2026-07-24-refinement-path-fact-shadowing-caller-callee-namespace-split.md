- Refinement path-fact shadowing + caller/callee namespace split
  (`lib/refinecheck/refine_check.ml`, 2026-07-24). Three review-found false
  positives, all "a fact about a *name* read where that name changed meaning".
  (1) `path_shadow` (+ `expr_mentions`) is the path-context companion to
  `scope_shadow`: it drops any path condition mentioning a name a binding
  construct rebinds, applied at all five sites in `visit` (`EBlock` `let`
  threading, `ELam`, `ELetFn`, `EMatch` arm binders, `ELetQ`) and the two in
  `tails`. Fixes both the ADT case (`None -> let x = Some(1); unwrap(x)`) and
  the pre-existing `Int`/`if`-guard case. Over-approximate by design —
  discarding a fact can only produce silence. (2) `check_call` gained
  caller-namespace `path_resolve_var`/`path_resolve_measure`/
  `path_resolve_tester` for the path context, so a path condition is no longer
  re-pointed at the callee's actuals through `rp.binder`/`actual_of_name`; a
  caller variable reflects to `Const name`, the same term an `EVar` actual
  reflects to, so narrowing still links. Predicate translation unchanged.
  (3) `register_builtin_adts`/`register_adt_names`/`register_field_sorts`
  hoisted out of the `measure_axioms` guard — with the flag off, `adt_ctors`
  was empty and the vocabulary warning falsely called `is_Some` unknown.
  Plus: removed `is_adt_base`'s stale `[@@warning "-32"]`; documented the
  `as`-pattern narrowing limit; replaced the vacuous "narrowing does not leak
  past a rebinding pattern binder" test (both arms were `-> 0`, so nothing was
  checked). `test_refinecheck.exe`: 112 tests, exit 0 (was 104); nine new
  cases, each confirmed RED first. Open follow-up: `check_post`'s `resolve_var`
  has the same caller/callee conflation for a *named* return binder.
