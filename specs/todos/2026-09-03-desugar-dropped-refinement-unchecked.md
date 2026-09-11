# Desugar drops or relocates a declared refinement before the checker ever sees it

`[P2]` Filed 2026-09-03, found by the refinement coverage audit's whole-plan
review (`.superpowers/sdd/refinement-coverage-audit/whole-plan-review.md`,
findings 1 and 2), covering two shapes:

## What is broken

### 1. A default parameter's own refinement (a false Enforced)

```march
mod T6e do
  cap verified
  fn f(a : Int, b : {Int | b > 0} \\ 1) : Int do a + b end
  fn main() : Int do f(1, 0) end
end
```

```
$ rm -rf .march/cas/artifacts-v2
$ ./_build/default/bin/main.exe --check --refine-audit --refine-report t6e.march
refinement obligations (user code): 1 proved, 0 violated, 0 trusted, 0 skipped
coverage audit (user code): 1 enforced, 0 inert (warned), 0 unenforced
```

`f(1, 0)` violates `b > 0`, under `cap verified`, and this used to exit 0
(fixed for the AUDIT below; the underlying checker hole remains). No decl
named `f` survives desugar: `expand_defaults_decl`
(`lib/desugar/desugar.ml:1605`) replaces it with `f$1` (a short wrapper)
and `f$2` (full arity, keeping the refined parameter). A user call written
`f(1, 0)` names `f`, which `collect_all_defs` cannot resolve to any refined
signature, so it files nothing. The one obligation that WAS filed came from
the wrapper's own internal call, not from `main`'s call site.

### 2. A multi-head function's refinement (no site at all)

```march
mod T8c do
  cap verified
  fn f(n : {Int | n > 0}) do n end
  fn f(0) do 0 end
  fn main() : Int do f(0 - 1) end
end
```

```
$ ./_build/default/bin/main.exe --check --refine-audit --refine-report t8c.march
refinement obligations (user code): 0 proved, 0 violated, 0 trusted, 0 skipped
coverage audit (user code): 0 enforced, 0 inert (warned), 0 unenforced
```

`f(0 - 1)` violates `n > 0` and this exits 0. `Desugar.desugar_fn_def`'s
general merge path (`lib/desugar/desugar.ml:1125`, `mk_named_param`)
rebuilds every parameter with `param_ty = None` when merging two or more
clauses into one `EMatch`, discarding the declared refinement before
`check_module` ever sees it.

## Why it matters

Both are silent: `cap verified` promises every obligation is discharged,
and the promise is kept vacuously because no obligation was ever filed for
the parameter a plain call actually goes through. Neither shape is rare;
a default argument and a multi-head function are both ordinary March.

## The audit no longer hides these

`--refine-audit` reports the audit's finding for the FIRST fixture as:

```
coverage audit: t6e.march:3:27: param `f` #1: b > 0: this refinement was declared here, but no occurrence with the same enclosing name and predicate text survives desugaring: either the declared type was discarded entirely (a multi-head function's clause merge drops every parameter type before the checker ever sees it) or it now lives only under a mangled name a plain call cannot resolve to (a default-argument function's arity variant, e.g. `f$2`). See specs/todos/2026-09-03-desugar-dropped-refinement-unchecked.md.
coverage audit (user code): 1 enforced, 0 inert (warned), 1 unenforced
```

and the second:

```
coverage audit: t8c.march:3:18: param `f` #0: n > 0: this refinement was declared here, but no occurrence with the same enclosing name and predicate text survives desugaring: ...
coverage audit (user code): 0 enforced, 0 inert (warned), 1 unenforced
```

via `Refine_audit.desugar_dropped`, which compares the pre-desugar site
list against the post-desugar one and reports any pre-desugar site with no
surviving occurrence (same declaration name and predicate text, except a
`Return` site which matches by predicate text alone, see
`lib/refinecheck/refine_audit.ml`'s comment for why the two positions need
different matching rules). This closes the AUDIT'S blind spot. It does not
fix the underlying checker: both fixtures above still exit 0 under
`cap verified` until this todo is done.

Fixtures pinned at `test/refine_audit/holes/default_param.march` and
`test/refine_audit/holes/multi_head.march`.

## Where a fix would land

- For the default-parameter case: the checker's name resolution
  (`collect_all_defs`, `lib/refinecheck/refine_check.ml` /
  `refine_scope.ml`) would need to recognize a bare call `f(...)` against
  the mangled arity variants desugar produces for `f`, the way the
  compiled/interpreted pipeline's own `_default_dispatch` /
  `VMultiarity` mechanisms already do for evaluation. Until then, a
  refined default parameter is enforced only via an internal call
  literally spelled `f$2(...)`, which no user source ever writes.
- For the multi-head case: `Desugar.desugar_fn_def`'s general merge path
  would need to preserve each clause's original parameter types on the
  synthesized match arms (or record them in a side table the checker's
  scope-registration can consult), rather than discarding them via
  `mk_named_param`.

Both are checker/desugar changes, not audit changes; scope is intentionally
left open here rather than assumed, since either fix interacts with how
call sites are resolved for the mangled/merged shape, which the audit
itself does not need to solve.
