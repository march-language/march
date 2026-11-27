`[P2]` Remove the deprecated `fn main(c : Cap(K))` form (next release) (2026-11-26)

Ocap phase 7b (`specs/progress/2026-11-26-ocap-p7b-retire-cap-values.md`) kept
`fn main(c : Cap(IO.X))` for one release with the warning `deprecated_main_cap`. In the
release after that:

- make it an error (`main_signature`), keeping the fix;
- move `test/native/main_cap_io.march` and `test/errors/deprecated_main_cap_1.march` to
  the error;
- delete what only retired code reaches: the `cap_narrow` typing (`check_cap_narrow_sites`,
  the `cap_producer_ivars` unify hook, `tag_cap_producer_result`), the `Cap(IO)` branches
  of `cap_mismatch` (`refine_cap_mismatches`, `Typecheck_unify.report_cap_mismatch`), the
  `cap_root_broad` hint's collector, the D34 `declared_io_caps` comparison in
  `solve_role_roots_full`, `main_request_caps`' parameter half, and the `cap_narrow` /
  `root_cap` builtins in the typechecker, interpreter, LLVM and JS backends;
- drop `add_param_fix` / `cap_param_name` if nothing else uses them.

Keep `Cap(X)` for proof capabilities, `mint_cap()` and `cap_impl`.
