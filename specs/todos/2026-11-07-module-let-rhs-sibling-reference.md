`[P3]` A module-level `let` whose right-hand side names a sibling in the same module fails

Found while fixing the function-typed module-level `let`
(`specs/progress/2026-11-07-function-typed-module-let-outside-entry.md`). Both cases are in a
non-entry module and both are front-end/interpreter problems, not lowering ones; native builds of
the first case are right.

1. A sibling `fn`: the checker accepts it, native prints `11`, the interpreter fails with
   `unbound variable: Cst.make`.

   ```march
   mod M2 do
     needs IO.Console
     mod Cst do
       fn make(n : Int) : Int do n + 1 end
       let k = make(10)
     end
     fn main(_c : Cap(IO.Console)) : () do
       println(int_to_string(Cst.k))
     end
   end
   ```

2. A sibling `let`: `march --check` rejects it with a misleading
   ``Unknown module `Cst`. Did you mean `Csv`?`` [unknown_qualified_name] pointing at each bare
   sibling name.

   ```march
   mod Cst do
     let inc = fn x -> x + 1
     let compose = fn (f, g) -> fn x -> f(g(x))
     let inc2 = compose(inc, inc)
   end
   ```

Workaround: put the helper in another module (`let add10 = Mk.make_adder(10)`), as
`test/native/module_let_fn.march` does.
