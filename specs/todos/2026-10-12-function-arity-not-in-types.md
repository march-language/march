# `[P3]` Function arity is not part of the function type

**Filed** 2026-10-12, the residual of
`specs/progress/2026-10-12-two-arg-fn-accepted-as-curried.md`.

`fn add(a, b)` and `fn a -> fn b -> a + b` share the type `a -> b -> c`, and
no closure records its arity, so applying a function value with a different
argument count than it takes fails at runtime (an arity panic interpreted, a
SIGSEGV compiled). The `callback_arity_mismatch` check catches the common
case syntactically: a named fn or lambda passed straight to a known fn whose
body applies that parameter with another count. It does NOT see function
values that flow through records, lists, `Option`, or a higher-order builtin,
or a parameter that is only returned or stored.

A sound fix needs one of:

- arity in the type: a separate n-ary arrow (and surface syntax for one of
  the two meanings `a -> b -> c` has today: fold's `f(acc, x)` vs Map's
  `cmp(a)(b)`), threaded through typecheck, the builtin signatures, TIR
  `convert_ty`, refinements and the LSP; or
- an arity-adapting call path (closure arity word plus `caml_applyN`-style
  over/under-application), a closure ABI change that reaches HCR.

**Findings 2026-10-13.** After the alias / let-bound-lambda extension
(`specs/progress/2026-10-12-two-arg-fn-accepted-as-curried.md`), these still
`--check` clean and crash at runtime (arity panic interpreted, SIGSEGV
compiled): a fn returned by another fn (`pfn pick() do add end`, then
`ap2(pick(), 1, 2)`), and a fn taken out of a list (`[add]`, `Cons(f, _)`,
`f(1)`). Both need arity to flow through types or values; no syntactic
extension reaches them soundly.
