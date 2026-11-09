Set measures over a node type and its `List` of children (stage A of
`specs/todos/2026-11-06-prove-map-set-contracts.md`).

`Set` and `Map` are HAMTs: a branch holds a `List` of child nodes, a collision
bucket a `List` of elements. Their contents measure is a pair, one over the node
and one over the child list, that call each other, and the bucket arm needs a
list's `elts`. Three things stood in the way.

## What changed

- **Termination certificate, cross-type mutual recursion**
  (`Refine_term.certify`). Phase 1 certified a mutual SCC only when every
  member's position held one TYPE FAMILY (types defined in terms of each other).
  `List` is not defined in terms of the node, so a tree recursing through its
  children was `unproved:not-same-family`, and a measure over it
  `invalid_measure`. Any parameter position is now a candidate. Every edge still
  has to pass a bare strict-component variable of its source's position.
  Soundness: a strict pattern component is a proper subterm, so it has fewer
  constructors whatever its type. Values are finite (F11), so around any cycle
  the sizes strictly fall. The `not-same-family` outcome is gone, and with it
  `param_head`. This closes the first group of
  `2026-10-27-termination-structural-certificate-gaps.md`.
- **`empty` in a set measure on the command line** (`Refine_term.build_graph`).
  The typechecker binds the set vocabulary OVER the module scope inside a set
  measure, but the termination graph looked globals up first. The prelude
  declares several functions named `empty`, so `Leaf -> empty` named one of them
  as a value (R7), and EVERY user set measure checked from the CLI was
  `invalid_measure: names empty as a value`. The in-process test harness has no
  prelude, which is why `avl-induction` never saw it. The vocabulary now
  resolves first, and the bare constant `empty` records no site.
- **`elts(field)` in a set measure's body.** The typechecker binds
  `elts : List(a) -> Set(a)` there. Reflection accepts it (`set_ops`). The axiom
  translator encodes it as the built-in list measure `$elts` renamed to the
  field's list instance. The module preamble declares that instance beside the
  measures and files its quantified axioms by symbol. A query that also names it
  skips the duplicate declaration (`global_instance_names`).

## Tests

Group `nested-measure` (`test/test_refine_nested_measure.ml`, real compiler):

- `empty` with a global `empty` in scope;
- the HAMT measure pair;
- a List insert proved through both measures, with a REJECT for a contract that
  drops the new node;
- a collision bucket's `ne(_) == elts(xs)` proved, with a REJECT for `== empty`.

Perturbing the `$elts` instance name turns the bucket case RED.

Group `termination-structural`: `mutual_two_adts` (`Tree` / `List(Tree)`) is now
`structural`. New REJECT controls are `mutual_cross_param`, a cross-type edge
passing the parameter itself, and `mutual_cross_built`, an edge passing a value
built from it. Both stay `unproved:no-structural-arg`.

## Found, not fixed

An `if` that tests an Int before a `match` on the list
(`if idx <= 0 do … else match lst do … end end`) is solver-undecided even over a
plain `List(a)`. The same function with the `match` outermost proves. Filed as
`specs/todos/2026-11-08-refine-if-before-match-induction.md`.
