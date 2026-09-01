# Function-head binders aren't seen as structurally smaller (same code errors in one form, warns in the other)

The tail-call checker treats a non-tail recursive call as a hard **error**
unless one argument is provably structurally smaller
(`lib/typecheck/typecheck_tailcall.ml`, `chk`'s `EApp` arm). Binders
introduced by an explicit `match` on a parameter count. **Binders introduced
by multi-head function heads do not**, so the identical program is accepted
in one spelling and rejected in the other.

## A/B (same type, same logic, same recursion)

Accepted — warning only, runs correctly:

```march
fn has_val(t : BTree, target : Int) : Bool do
  match t do
    Tip -> false
    Branch(l, v, r) -> v == target || has_val(l, target) || has_val(r, target)
  end
end
```

Rejected — hard error, will not compile:

```march
fn has_val(Tip, _target : Int) : Bool do
  false
end
fn has_val(Branch(l, v, r), target : Int) : Bool do
  v == target || has_val(l, target) || has_val(r, target)
end
```

> Function `has_val`: recursive call to `has_val` is not in tail position
> (wrapped in binary operation `||`).
> Hint: Consider using an accumulator parameter.

`l` and `r` are bound by a constructor pattern on the parameter in both cases;
only the spelling differs. Desugar merges multi-head clauses into a single
`EMatch`, so by the time the checker runs the shapes should be equivalent —
something about the merged form is not populating `fn_params` / the `smaller`
set the way a hand-written `match` does.

## Why it matters

Multi-head matching is idiomatic March and is what the surface-syntax docs
lead with. Today, writing a perfectly ordinary structurally-recursive tree
walk that way is a compile error, and the hint ("use an accumulator
parameter") is wrong advice for a branching search — an accumulator does not
help here. The only workaround is `@[no_warn_recursion]`, which suppresses a
diagnostic that is *false* in this case rather than one the author is choosing
to accept, so it also disables the check where it would be genuinely useful.

## Fix sketch

Make the multi-head merge feed the same parameter/`smaller` information the
`match` path does, so head binders are recognised. Then the A/B above must
agree: both warn, neither errors.

Guard against regression with the A/B itself — the two spellings must produce
the same verdict.

## Related

- `specs/todos/2026-09-01-trmc-warning-promises-a-loop-that-does-not-happen.md`
  — the same warning's TRMC claim.
- Also hit while writing this up, worth separate consideration: a
  self-referential **record** type cannot be used with function-head matching
  at all. The heads leave the type unresolved ("expected `BTree` but got
  `a`"), the diagnostic says to add a type annotation, and a destructuring
  parameter cannot carry one — `fn f({ ... } : BTree)` is a parse error. So
  the suggested fix is unexpressible and record trees must use an explicit
  `match`. Variants are unaffected (constructor patterns are nominal).
