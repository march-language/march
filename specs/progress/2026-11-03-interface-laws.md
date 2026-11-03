# Interface laws (2026-11-03)

Idea 6 of `specs/todos/2026-11-02-lemma-uses-beyond-refinement.md`. Syntax ruled by the
user: reuse `@[lemma]`, with no new keyword.

## What landed

- **Syntax.** `interface I(a) do … @[lemma] fn law(params) : {Unit | P} end`: a body-less
  `@[lemma]` signature (`iface_law` in `lib/parser/parser.mly`, `Ast.interface_def.iface_laws`).
  An attributed body-less `fn` without `lemma` is a parse error that shows the form. Impl
  bodies now accept attributes (`impl_item`), so an impl can carry `@[lemma] fn law(..) do
  … end`, its proof. Menhir's conflict count is unchanged (7, all pre-existing).
  tree-sitter: `law_sig` and attributes in `impl_def`, with a corpus case.
- **Checking** (`lib/desugar/interface_laws.ml`, the last step of `desugar_module`). The
  refinement checker never reflects an impl method (R1: dispatch picks it by type). So for
  each impl of a lawful interface in the same file, the step generates next to the impl:
  - `__law_<m>__<Iface>_<T>`: a private copy of each impl method, with parameter types from
    the interface signature at `a := T` and sibling-method calls renamed to the copies, so
    it is an ordinary reflected function (`@[no_warn_recursion]`, no warning about code
    the user did not write);
  - `<law>__<Iface>_<T>`: a lemma whose theorem is the law's at `a := T`, with method calls
    renamed to the copies. Its body is the impl's proof (its parameters' names win, and
    recursive calls of the law are renamed), else `()`.
  - Spans: everything is respanned (`Desugar_derive.respan_derived_decl`), so impls never
    share type-map keys. The lemma's name keeps a real span: the proof's name, or the impl's
    interface name widened by the law's index. Diagnostics point at the impl.
- `Refine_scope.pred_str` prints a copy as its method's name (`law_method_display`), so a
  message reads `combine(combine(x, y), z) == …`. A `()` argument prints as `()`.
- **Erasure.** `Lemma_erase.drop_unreferenced` drops the copies (the reserved prefix) with
  the lemmas. The IR has none of it (`iface_law_erased`).
- **Formatter.** `march --fmt` prints the laws (`lib/format/format.ml`). Impl proofs already
  kept their attributes.

## Limits (in the todo)

- Only impls in the interface's own file are checked.
- A method the impl takes from a default is not copied; a law that calls it stays unproved.
- A law calling a method with a `Unit` argument stays unproved: the logic has no `Unit`
  value.
- `--lemma-test` runs generated lemmas in the interpreter only. Its compiled harness reads
  a lemma's source text, and a generated lemma has none.
- Unrelated limitation found on the way: a lemma whose theorem is an `Int`-valued
  recursive function over a user datatype (`tsize(t) >= 0`) stays unproved, hand-written
  or generated ("`tsize` is not a measure or known predicate").

## Tests

`reflect-lemma`: `iface_law_proved`, `iface_law_refuted` (a counterexample and the theorem
as written; the other impl is still admitted), `iface_law_proof` (the impl's proof admits;
without it, unproved), `iface_law_verified`, `iface_law_lemma_test`, `iface_law_erased`
(interpreted and compiled print the same; nothing in the IR), `iface_law_syntax`.
`test_fmt`: "interface law". tree-sitter corpus: "Interface law and an impl proof".
