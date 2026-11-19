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

## Fixed 2026-11-17

Both the fixture todo (`2026-10-12-payload-atom-match-compiled-ice.md`, moved to
progress with this one) and this one are closed by the representation below.

**The decision.** `Atom` stays one type and an `i64` value. A nullary atom's
hash now has bit 0 forced to 1 (`Llvm_ctx.atom_hash`, the runtime's
`march_atom_of_name`, and `march_http.c`'s method atoms), so it is always odd.
A payload atom is a heap cell, so it is always an even pointer. Every consumer
tells them apart by bit 0, which is the uniform-slot law's own test.

- **Cell layout** (`Tir_names.atom_cell_ctor`, runtime `MARCH_ATOM_TAG` = -11):
  - slot 0 holds the name's hash;
  - slot 1 is a metadata word: the payload count, then 4 bits per field giving
    its static kind (Int, Bool, Atom or other), which `show` and `==` need
    because the payload is stored uniform;
  - slots 2 onward hold the payload.
- **Lowering**: `lower_expr` builds
  `EAlloc ($Atom, [:name; n; payload…])`, so the TIR argument count is the
  cell's slot count. A payload-atom pattern's branch tag is `$Atom.name`, which
  can't collide with a constructor named the same.
- **Match** (`Llvm_case`): the switch key is the atom itself when it is odd,
  else the cell's hash xor 1. A payload arm's label is therefore even and a
  nullary arm's odd, so `:ok` never matches `:ok(n)`. The arm binds payload
  slot i like any erased-slot field, with its own reference.
- **`==`**: `march_atom_eq` compares structurally. Only native code calls it;
  the WASM runtime keeps the hash compare.
- **`show`**: the generated `@march_atom_to_string` hands an even value to
  `march_atom_value_to_string` (`march_extras.c`), which prints `ok(7)`,
  `error("bad")`, `wrap(inner(2))`, as the interpreter does.
- **JS backend**: keeps `{ $: "name", _0: … }`. Its literal case chain now
  tests a payload arm against that object instead of `===` on it. It had been
  matching nothing.
- **Kept out of reach**: FBIP reuse and TRMC skip atom-cell allocations.

**Follow-ups**:
- A payload-atom cell was never freed at first. That was fixed the same day by
  reference counting `Atom`: `specs/progress/2026-11-17-payload-atom-cells-leak.md`.
- Still open: JS `show` of any atom and JS `==` on payload atoms:
  `specs/todos/2026-11-17-js-payload-atom-show-and-eq.md`.

**Tests**: `test/test_codegen.ml` `payload_atom_codegen` runs a program at
`--opt 0` and `--opt 2` with `MARCH_VERIFY_TIR=1` and requires the
interpreter's output. The program covers matches through parameters, nested
payload atoms, a heap-string payload matched twice, `show` and `==`. The three
spec fixtures now give the same output interpreted, compiled and under
`--target js`: `t12_atom_payload_and_name_erasure`,
`p14_list_and_atom_payload_patterns` and `g22_atom_payload_match`.
