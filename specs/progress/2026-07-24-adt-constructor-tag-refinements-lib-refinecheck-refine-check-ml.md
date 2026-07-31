- ADT constructor-tag refinements (`lib/refinecheck/refine_check.ml`,
  `lib/refine/smt.ml`, 2026-07-24). Every constructor of every registered ADT
  implicitly gains an `is_<Ctor>` tester the refinement checker understands
  (`ctor_of_tester`, folded into `known_predicate_fn`), reflected to the Z3
  datatype tester `((_ is Ctor) x)` via a new `Smt.IsCtor`. Two fact sources:
  a constructor literal at the call site (`unwrap(None)`), and `match`-arm
  narrowing, which pushes a synthetic `is_Ctor(s)` path condition so it flows
  through the existing `smt_of` translation. `rparam` gained a `sort` field and
  `refined_param_ty` admits any registered-ADT base type; `check_call` reflects
  the subject with the existing `reflect_dt` and attaches the datatype
  declarations (`adt_vc_preamble`, deduplicated against `measure_preamble`).
  `Option`/`Result` are seeded in `register_builtin_adts` alongside `List` —
  the plan assumed they came from stdlib `DType`s, but they have NO `type`
  declaration anywhere; the typechecker pre-registers them (`builtin_ctors`)
  and the refinement checker must do the same or `is_Some` names nothing.
  Deliberately NOT extended: `refined_scope_ty` / `return_refine_ext` /
  `check_post`, so a tag refinement is discharged at the call site and not
  carried through a binding — extending `scope_facts` would have flipped
  `check_post` into its "SAT = definite error" mode for ADT scope entries whose
  sorts the record preamble does not declare, a false-positive risk with no
  test coverage. Narrowing is skipped for a non-variable scrutinee, an arm that
  rebinds the scrutinee's name, and an ambiguous constructor name (shared by
  two ADTs). `test_refinecheck.exe`: 104 tests, exit 0 (was 94);
  `run_compiler`/`run_eval`/`run_stdlib -q` all exit 0; zero new diagnostics on
  stdlib-using programs.
