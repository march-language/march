`[P2]` - [ ] **Compiled: matching a payload atom that arrives through a parameter is an internal compiler error.**

Filed 2026-10-12 by the interpreter-vs-compiled differential sweep (group V).
Two spec fixtures hit it: `specs/lang/types/accept/t12_atom_payload_and_name_erasure.march`
and `specs/lang/grammar/parse/p14_list_and_atom_payload_patterns.march`.

```march
mod Main do
  needs IO.Console
  fn describe(tagged) do
    match tagged do
      :ok(n) -> n * 10
      _ -> 0
    end
  end
  fn main(_c : Cap(IO.Console)) do
    println(describe(:ok(7)))     -- interpreted: 70
  end
end
```

Compiled:

```
internal compiler error: LLVM Llvm_ctx.emit: constructor pattern ok($f…)
destructures a non-pointer scrutinee `tagged` — type-incorrect TIR reached codegen
```

(`specs/lang/golden/g22_atom_payload_match.march` passes only because its
scrutinee is a local the optimiser folds.)

**Why it is not a quick fix.** Every atom has the one type `Atom`, which
`Llvm_ctx` lowers as an `i64` immediate (`TCon ("Atom", []) -> "i64"`,
an FNV hash of the name), and `llvm_case` treats an `Atom` scrutinee as a
non-pointer. A payload atom, though, is lowered as a heap allocation
(`lower_expr.ml`, `Ast.EAtom (a, args, _)` → `EAlloc (TCon (a, []), …)`), so
one `Atom`-typed value can be either. A fix needs a representation decision:
e.g. payload atoms as boxed cells and nullary atoms as tagged immediates
under a ptr-typed `Atom`, with the case switch splitting on `IS_HEAP_PTR`
(immediate → compare hashes; heap → compare the cell's atom tag) and RC
treating `Atom` as possibly-heap. Today a payload atom's cell is never
released either (Atom is not RC'd).
