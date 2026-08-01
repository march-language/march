**FIXED 2026-07-31.**

`[P2]` **The tail-call analysis merges an entry module's names with the prelude's, fabricating an SCC.**

```march
mod Zed do
  fn go(ys : List(Int)) : Int do if length(ys) == 0 do 1 else 2 end end
  fn main() : Int do go([1]) end
end
```

→ ``Function `go`: recursive call to `length` is not in tail position``

There is no recursion here. `enforce_tail_calls_in_decls`
(`lib/typecheck/typecheck.ml`) builds `fn_names` and the call graph over one
flat decl list, and an entry module's members are unwrapped to top level next to
the prepended prelude's — so a nested helper's name colliding with an
entry-module function fabricates a strongly-connected component. Specifically
`stdlib/prelude.march`'s `fn length` contains an inner `fn go`, so any entry
module that defines `go` and calls `length` hits it.

Any entry-module function whose name collides with a prelude helper can trigger
this; `go` is simply the one that surfaced.

Surfaced 2026-07-30 while making `collect_direct_names` exhaustive (an
entry-module extern's self-qualified call now strips to the bare name and lands
here), but **entirely independent of that change** — reproduced with the
parent's `desugar.ml` swapped in, and the fault is in `typecheck.ml`, which that
commit does not touch.

## Resolution

The diagnosis above is right, and the fix is in `lib/typecheck/typecheck.ml`
§16. Two independent changes, each of which fixes the reported repro on its own
(measured by disabling one and rebuilding); together they also cover the
extern-free shape, which the extern change alone does not.

1. **`collect_direct_fn_calls` is now scope-aware.** It treated `fn_names` as a
   flat name list, so a call to a *locally bound* helper whose name collided
   with a top-level function forged a call-graph edge. Binders now retire their
   names: an `ELetFn`/`ELet` inside an `EBlock` shadows for the rest of that
   block (these nodes carry no continuation of their own, so the block is the
   only place the shadowing can be applied), a `match` arm's pattern shadows
   inside the arm, and `let?`'s pattern shadows in its continuation.
   `collect_pattern_vars` moved above the collector to make this possible.

2. **Extern-declared names are removed from `fn_names`** in
   `enforce_tail_calls_in_decls`. An `extern` has no body and cannot recurse, so
   a bare call to one must never resolve against a same-named ordinary function
   — which is exactly what the injected prelude puts next to it.

A third change fixes the *same* shadow-blindness one layer down, found while
probing the residual: `check_tail_position`'s `chk` matched call names against a
fixed `recursive_names`, so inside a genuinely recursive SCC a call to a local
binding that shadowed an SCC member was still misattributed. `recursive_names`
is now threaded as a scope (`names`) and retired by inner `fn`/`let`/`let?`
binders and match-arm patterns. Witness:

```march
fn f(n : Int) : Int do
  match Some(fn x -> x + 1) do
    Some(g) -> g(n) + 1   -- the arm-bound closure, NOT the top-level `g`
    None -> g(n)
  end
end
fn g(n : Int) : Int do if n == 0 do 0 else f(n - 1) end end
```

The direction is strictly narrowing (fewer edges ⇒ fewer SCCs ⇒ fewer
diagnostics), so genuine recursion is still caught; two control tests pin
that (real non-tail self-recursion, real mutual recursion).

Regression coverage:

- `test/test_compiler.ml`, group `tail_call_enforcement` — 4 shadowing/extern
  cases plus 2 controls. These run through the plain `typecheck` helper
  (no prelude), so they pin the root cause directly.
- `test/imports/extern_shadow/es_extern_length.march` and
  `es_prelude_helper.march`, run under `--check` by two `test/dune` rules with
  `(source_tree ../stdlib)` — the end-to-end witnesses, since the bug needs the
  prelude spliced into the entry module. Both exit 1 on a compiler built from
  the parent commit and 0 after the fix.
