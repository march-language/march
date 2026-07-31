- **OPEN — a destructuring parameter silently discards EVERY parameter
  refinement on that function (`lib/desugar/desugar.ml`, found 2026-07-25).**
  First recorded as "desugar renames params to `__argN` so the predicate
  classifies `Unusable`". Probing shows that understates it. A clause whose
  params include a real destructuring `FPPat` (e.g. `fn f({ w: w, h: h }, n)`)
  misses both fast paths in `desugar_fn_def` and takes the general path, which
  rebuilds the clause with `List.map mk_named_param arg_names` — and
  `mk_named_param` sets `param_ty = None`. So it is not a renaming problem:
  **all parameter type annotations, refinements included, are dropped**, and
  separately the surviving return refinement references parameter names that no
  longer exist. Direction is silence in both cases (an absent refinement is
  never checked; an unresolvable predicate classifies `Unusable`), so this is
  incompleteness, not unsoundness — but it is silent, and a user who writes
  `fn f({ w: w }, n : {Int | _ >= 0})` gets no checking and no warning.

  Live repro, confirmed against the built compiler: with
  `fn destr({ w: w, h: h }, n : Int) : {Int | _ < n} do n - 1 end`,
  the call `takepos(destr({ w: 1, h: 2 }, 0))` exits 0; the identical function
  without the destructuring parameter exits 1.

  NOT a small fix, which is why it is filed rather than done: the general path
  would have to preserve parameter types positionally, changing what the
  typechecker sees for every such function, in the same code path that carries
  the documented tuple-adapter use-after-free hazard (see the `inject_defaults`
  item above). Wants its own task with its own review.
