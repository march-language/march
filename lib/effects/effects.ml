(** March capability system — Phase 1 enforcement.

    Transitive capability checking: every module that imports another module
    which declares [needs X] must itself declare [needs X] (or a parent capability).
    Extern blocks must also declare their capability via [needs].

    Phase 1 enforcement is embedded in the type-checker's [check_module_needs]
    function (lib/typecheck/typecheck.ml).  This module is the explicit call-site
    hook that runs on both the eval and compile paths (see bin/main.ml). *)

(** Run capability enforcement on [m], adding any violations to [errors].
    Delegates to [Typecheck.check_module] which performs:
      - Check 1: every Cap(X) in a function signature must be declared in [needs]
      - Check 2: every [needs] declaration must be used
      - Check 3: hint when Cap(IO) (root) is used — suggest narrowing
      - Check 4: transitive — importing a module that [needs X] requires declaring [needs X]
      - Check 5: extern blocks must declare their capability in [needs]
    All paths (eval and compile) pass through this function via [bin/main.ml]. *)
let check_capabilities ?(errors = March_errors.Errors.create ())
    (m : March_ast.Ast.module_) : March_errors.Errors.ctx =
  let (err_ctx, _type_map) = March_typecheck.Typecheck.check_module ~errors m in
  err_ctx
