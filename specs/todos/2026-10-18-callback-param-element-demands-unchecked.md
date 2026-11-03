`[P2]` Element demands on a callback-typed parameter are never checked

Found 2026-10-18 by the independent review of the element-flow phase 0 fix
(`specs/progress/2026-10-18-relational-element-refinement-scope.md`, reviewer probe H9).
A callback parameter whose DOMAIN carries an element refinement (`g : (List({Int | _ <
5})) -> Int`) obliges nothing when the body calls it: `g(ys)` with `ys : List({Int | _ <
60})` files **zero** obligations, `--refine-report` counts nothing (not even a skip), and
`cap verified` compiles it, although `ys = [59]` breaks `g`'s contract. This is not about
relational slots: the closed `_ < 5` is unchecked too. `callback_sig_of_ty`
(`lib/refinecheck/refine_scope.ml`) builds a signature for a callback only when its
domain has a top-level refinement (`refined_param_ty`) or its codomain carries one; a
domain whose only refinement is an element slot gets no signature, so `g` enters no
`cbenv` and `visit`'s `EApp` arm finds no callee to run `check_arg_elements` against. Fix
direction: also build the signature when the domain carries an element refinement
(`elem_refinement (Some dom)`), with `param_tys = [ Some dom ]` as today, so the existing
`check_arg_elements` path obliges the actual. A slot naming a parameter of the ENCLOSING
function is then in the caller's own namespace, and `instantiate_entry` (formals
`[callback_param_name]`) records it as a skip; that is conservative and should be stated,
not silently widened.

```march
mod H9 do
  cap verified
  fn go(g : (List({Int | _ < 5})) -> Int, ys : List({Int | _ < 60})) : Int do
    g(ys)      -- 0 obligations today; should be violated
  end
end
```
