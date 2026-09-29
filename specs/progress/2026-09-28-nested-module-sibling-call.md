# `[P2]` DONE A nested module's qualified call to a SIBLING submodule fails to LINK

Found and fixed 2026-09-28, compiling `@[endpoints]` protocols declared inside a
stdlib module (an early layout of `stdlib/control.march`, dd step 12a). Sibling of
[2026-09-25-nested-module-parent-call.md](2026-09-25-nested-module-parent-call.md),
which fixed the BARE call to an enclosing module's fn.

## The bug

```march
mod Sib do
  mod Outer do
    mod A do
      fn f(x : Int) : Int do x + 1 end
    end
    mod B do
      fn g(x : Int) : Int do A.f(x) * 2 end
    end
    fn h(x : Int) : Int do B.g(x) + A.f(0) end
  end
  fn main(c : Cap(IO)) do print_line(int_to_string(Outer.h(3))) end
end
```

Interpreted: `9`. Compiled: a link failure. The lowering renamed a nested module's
bare references to its own and its enclosing modules' fns (`rename_scoped_vars`), but
left a QUALIFIED reference relative to an enclosing module (`A.f`, `B.g`) as written.
No module is called `A`; the fn is `Outer.A.f`. An entry file's own top level is
unprefixed, so its direct children's `A.f` happened to match; one more level of
nesting, or any MARCH_LIB_PATH or stdlib module, hit it. Every `@[endpoints]` protocol
inside such a module hits it, since its generated role modules call their siblings
`P_Msg` and `P_Run` (`@CtlFetch_Msg.try_decode` undefined).

## The fix

`Lower_decls.nested_qualified_fn_names decls` lists every fn (and module-level `let`)
of every submodule nested in `decls`, spelled relative to that module (`A.f`,
`B.C.k`). Both lowering paths (`lower.ml`'s `lower_mod_decls` for modules in the
combined program and `lower_decls.ml`'s `lower_stdlib_mod_decls` for lazily lowered
ones) now put these next to the module's bare fn names in its `rename_scoped_vars`
scope, so a relative qualified call is prefixed exactly as a bare parent call is.
Innermost-first application keeps lexical shadowing. `scoped_names` (the bare-name
set for `with_enclosing_module_fns`) filters the dotted names back out.

## Tests

`test/test_codegen.ml`, group `nested_module_sibling_call`: a MARCH_LIB_PATH module
and an entry-file module nested two levels, each covering a sibling call, a call two
levels down, a deeper module reaching an uncle, and a sibling's module-level `let`.
A protocol declared inside a nested module additionally needs a typechecker fix
([../todos/2026-09-28-endpoints-protocol-in-nested-module.md](../todos/2026-09-28-endpoints-protocol-in-nested-module.md));
this fix is the lowering half of it.
