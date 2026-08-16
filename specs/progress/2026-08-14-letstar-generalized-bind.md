`[P2]` - [x] **`let*` — generalized monadic-bind sugar, generalizing `let?` beyond `Result`. Implemented 2026-08-14.**

**Shipped.** `specs/plans/2026-08-09-parsing-and-string-search.md` §4.3
identified this as the chosen syntax-sugar direction on 2026-08-12 but left
it unimplemented; this closes it. Full design, dispatch mechanism, and
diagnostics: `specs/lang/let-star-generalized-bind.md`.

**What it is:** `let* p = e1; e2` — generalizes `let?` (hardwired to
`Result`) to any type `M` with a same-named module exporting
`flat_map(x : M(a), f : a -> M(b)) : M(b)`. Verified end-to-end against
`Option`, `Result`, and `List`, interpreted and compiled:

```march
fn compute(a : Int, b : Int, c : Int) : Option(Int) do
  let* x = safe_div(a, b)
  let* y = safe_div(x, c)
  Some(y + 1)
end
```

**Implementation shape** (mirrors `let?`'s precedent throughout):
- `lib/ast/ast.ml`: new `ELetStar of pattern * expr * expr * span`.
- `lib/parser/parser.mly`: `LET STAR` productions in the same 3 statement
  contexts `let?` has (block/lambda/call-arg-lambda), plus the 2 dedicated
  error productions (type-annotation rejection, missing-`=` recovery).
  `fold_letq` (the right-fold that nests a flat statement list into
  continuations) now recognizes BOTH `ELetQ` and `ELetStar`, so a block may
  freely mix them — verified with a dedicated fixture
  (`specs/lang/grammar/parse/p35`) since this is the one place a single
  function now has to dispatch correctly on two different binder shapes.
  Confirmed zero new shift/reduce conflicts (10 before, 10 after — the
  historical baseline had already drifted from the older "9" recorded
  elsewhere in the codebase, from unrelated grammar growth since).
- `lib/desugar/desugar.ml`: passthrough (same conn-scope treatment as
  `ELetQ`) — no expansion here; that happens at TIR-lowering time, since the
  target of the expansion (which `flat_map`) isn't known until types are.
- `lib/typecheck/typecheck.ml`: the genuinely new part — a type-directed
  dispatch mechanism the compiler didn't have before. `Ast.ELetStar`'s
  `infer_expr` case infers the RHS's type, reduces it to a head type
  constructor, resolves `<Name>.flat_map` through the SAME qualified-name
  resolution (`resolve_qualified_var`) an ordinary `Option.flat_map(...)`
  call already goes through, then unifies the RHS/pattern/continuation
  against whatever shape that `flat_map` scheme actually has — never
  hand-constructing `M(...)` itself, so it's arity-agnostic (works
  identically for `Option(a)` and `Result(a, e)`).
- `lib/tir/lower.ml`: expands `let* p = e1; e2` into an ordinary
  `M.flat_map(e1, fn $tmp -> match $tmp do p -> e2 end end)` call and
  re-lowers through the normal `EApp`/`ELam`/`EMatch` path — mirroring how
  `let?`'s own lowering builds a synthetic `EMatch` and re-enters
  `lower_expr`. `M` comes from the typechecker's `type_map`
  (`ty_of_expr`/`ty_of_span`), the same table monomorphization already
  reads for interface-method dispatch. No new TIR node, no new codegen.
- `lib/eval/eval.ml`: the interpreter has no compile-time types, so it
  dispatches on the RUNTIME value's type instead (`type_name_of_value`, the
  same primitive `hash`/`to_json`'s dynamic dispatch already uses), then an
  ordinary qualified-name env lookup of `<Type>.flat_map`. The continuation
  is passed in as a native `VBuiltin` closure — `apply` already dispatches
  a `VBuiltin` exactly like a March closure.
- ~25 mechanical AST-traversal sites gained a matching `ELetStar` arm
  (usually an or-pattern alongside the existing `ELetQ` arm, since the two
  share the same `pattern * expr * expr * span` shape): LSP
  (`analysis.ml` ×5, `workspace.ml`, `depot.ml`), `lib/format/format.ml`
  (pretty-printer, including the actual `let* p = e` rendering, not just
  traversal), `lib/dump/{dump,ast_json}.ml`, `lib/lint/lint.ml`,
  `lib/caps/cap_rows.ml`, `lib/coverage/coverage.ml`,
  `lib/ctxesc/scan_templates.ml`, `lib/refactor/refactor.ml` (×4),
  `lib/refinecheck/{cap_infer,no_alloc,division_safety,refine_check}.ml`
  (refine_check.ml alone: 11 sites — this file implements the "two fact
  channels: scope AND path" shadow-discipline machinery flagged elsewhere
  in this codebase's own history as bug-prone, so each site was read in
  full context rather than blindly mirrored). One genuinely DIFFERENT
  site: `typecheck.ml`'s self-recursion tail-call-position checker treats
  `let*`'s continuation like `ELam`'s body (a fresh scope, not tracked
  further) rather than like `let?`'s (in_tail inherited) — because after
  lowering, `let*`'s continuation genuinely lives inside a callback lambda
  passed to `flat_map`, so it is never actually in tail position relative
  to the enclosing function, unlike `let?`'s direct `match`-based expansion.

**A real, documented gap, not silently worked around:** the dispatch
resolves `M`'s `flat_map` by convention — "the module named `M` owns `M`'s
operations" — which holds for `Option`/`Result`/`List`/etc. but NOT for
`stdlib/parse.march`, whose `Parser` type lives in a module named `Parse`.
`let*` over a `Parser`-typed value reports a clear "`Parser.flat_map`
doesn't exist" error rather than silently failing or picking the wrong
thing. Fixing this (module rename, or a second explicit resolution path)
is a follow-up, not bundled into this change — see
`specs/lang/let-star-generalized-bind.md` §2/§6.

**Also explicitly out of scope, filed not silently skipped:** REPL support
(`let?` has a dedicated `ReplLetQ` top-level form with its own
`Result`-hardwired path in `lib/repl/repl.ml`; `let*` has none yet — a
parse error at the REPL prompt, not a crash).

**Verification:**
- Golden: `specs/lang/golden/g47_letstar_generalized_bind.march` (Option
  chain + short-circuit, Result chain matching `let?`'s g42 shape, List
  cartesian product) — interp/compiled byte-identical, full golden corpus
  47/47.
- Conformance: `specs/lang/types/{accept/t177-t178, reject/t178-t179}`
  (Option chain, Result-subsumes-let?, no-flat_map error, trailing-let*
  error), full `types-check` corpus 295/295.
- Grammar: `specs/lang/grammar/{parse/p35, reject/r16}` (mixed
  `let?`/`let*` block fold, type-annotation rejection), full
  `grammar-check` corpus 48/48.
- Manual end-to-end against the real compiler: Option/Result/List,
  tuple-pattern destructuring, both original error diagnostics, and the
  documented `Parser`/`Parse` gap — each checked interpreted AND compiled
  (`--compile --opt 2`).
- Full local suite (`scripts/run-tests.sh`): green.
