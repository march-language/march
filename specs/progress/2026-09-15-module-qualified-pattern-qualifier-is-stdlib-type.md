# Module-qualified ctor pattern whose qualifier is also a stdlib type name

**Symptom (compiled only).** A program with a nested module

```march
mod Tree do
  type T = Leaf(Int) | Node(T, T)
end
```

matching `Tree.Leaf(n)` / `Tree.Node(l, r)` from the enclosing module warned
`Non-exhaustive pattern match — missing case: LWWRegister(_, _)`, and the
compiled binary panicked `non-exhaustive pattern match`. The interpreter printed
the right answer. Independent of `cap no_alloc`; renaming `T` removed the warning
but not the panic, so these were two bugs.

## Bug 1: lowering took the TYPE reading of a MODULE qualifier

`Lower_match.pat_tag_and_subs` translates a module-qualified pattern
(`Json.Array`) into the type-qualified key codegen's `ctor_info` uses
(`JsonValue.Array`), but skipped the translation whenever the qualifier's last
segment *also* names some declared type carrying that constructor
(`type_declares_ctor`, meant for `List.Cons`). Stdlib's `OrderedMap.Tree` and
`SortedSet.Tree` both declare `Leaf`/`Node`, so the tag stayed `Tree.Leaf` and
`Llvm_case.qualified_br_key` resolved it against a stdlib `Tree` key, a
collision-range tag (`0x0200003F`) that a `Tree.T` value never carries. Every
arm fell to the panic default.

**Fix.** When a qualifier reads both ways, break the tie with the scrutinee's
inferred `TCon` when it has one (module reading iff the module's type has the
scrutinee's short name), else with the enclosing module: code inside the module
that declares the type named by the qualifier keeps the type reading (e.g.
`Tree.Leaf` written inside `OrderedMap`), everywhere else the module reading
wins. Nested sub-patterns (scrutinee `TVar "_"` at lowering) take the second
rule.

## Bug 2: exhaustiveness merged same-bare-named types from nested modules

`Typecheck_exhaustive.ctors_for_type` collects constructors by the parent's
*bare* type name, so `Tree.T` merged with stdlib `CRDT.LWWRegister.T`. Its
local-shadow filter only fires for a type declared by the *current* module, not
a nested one. **Fix:** when the universe still spans several declaring modules,
keep only modules that declare a constructor the match's first column names.

## Tests

- `test/test_codegen.ml` `cross_module_ctor_resolution` / "module-qualified
  pattern whose qualifier is a stdlib type name": compiled/interp parity,
  including nested sub-patterns. Pre-fix (lowering reverted alone): compiled
  `panic: non-exhaustive pattern match`, EXIT 1.
- `test/test_compiler.ml` `match_diagnostics` / "nested-module type sharing a
  bare name: no foreign missing case": asserts no `Reg(` case is demanded and a
  genuinely missing `Node` still warns. Pre-fix: fails on the first assertion.

## Not fixed here

A separate, pre-existing exhaustiveness false positive reproduces on a plain
non-colliding type: `Nd(Lf(a), Lf(b)) | Nd(Nd(_, _), Lf(b)) | Nd(_, Nd(_, _)) |
Lf(n)` warns `missing case: Nd(_, Lf(0))`.
