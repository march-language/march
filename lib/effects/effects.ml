(** March capability system — Phase 1 enforcement.

    Transitive capability checking: every module that imports another module
    which declares [needs X] must itself declare [needs X] (or a parent capability).
    Extern blocks must also declare their capability via [needs].

    Phase 1 enforcement is embedded in the type-checker's [check_module_needs]
    function (lib/typecheck/typecheck.ml), which [check_module_core] calls
    unconditionally — so every path that typechecks a module enforces
    capabilities, and this module is not one of the paths that does it.

    THIS MODULE IS NOT A PIPELINE STAGE. It is a thin convenience wrapper whose
    only callers are two assertions in test/test_codegen.ml; [bin/main.ml] never
    calls it, reaching enforcement directly through [check_module_full] →
    [check_module_core] → [check_module_needs]. The docstring here used to claim
    the opposite ("runs on both the eval and compile paths"), which made the file
    look load-bearing when it is bypassed — the same trap lib/codegen/codegen.ml
    set. Someone editing this file to change capability enforcement would observe
    no behavior change at all. See
    specs/progress/2026-08-27-effects-ml-docstring-claims-a-call-path-that-does-not-exist.md. *)

(** Run capability enforcement on [m], adding any violations to [errors].
    Delegates to [Typecheck.check_module] which performs:
      - Check 1: every Cap(X) in a function signature must be declared in [needs]
      - Check 2: every [needs] declaration must be used
      - Check 3: hint when Cap(IO) (root) is used — suggest narrowing
      - Check 4: transitive — importing a module that [needs X] requires declaring [needs X]
      - Check 5: extern blocks must declare their capability in [needs]
    Used by tests only — see the module header for why [bin/main.ml] does not
    call this, and what it does instead. *)
let check_capabilities ?(errors = March_errors.Errors.create ())
    (m : March_ast.Ast.module_) : March_errors.Errors.ctx =
  let (err_ctx, _type_map) = March_typecheck.Typecheck.check_module ~errors m in
  err_ctx
