# A closure's environment and captures are released when the closure dies

**Landed 2026-09-13.** Items 1 and 2 (in part) of
`specs/todos/2026-09-06-closure-capture-release-widening.md` and §1 of
`specs/2026-09-11-codegen-leaks-design.md` ("A + B together"). The todo stays
open for its items 3–5.

## The defect

```march
fn lengths(a : List(Int), b : List(Int)) : (Int) -> Int do
  fn x -> List.length(a) + List.length(b) + x
end
-- called once per iteration: 6 objects leaked per call (environment + 5 list cells)
```

Two things kept everything alive.

1. **Perceus dup'd `$clo` at the first capture read.** The apply fn's TIR was
   `let a = inc_rc $clo; $clo.$fv1 in let b = $clo.$fv2 in dec_rc $clo; …`.
   The spliced `dec_rc $clo` only undid that dup, so the reference the caller
   transferred into the apply fn was never released. `find_inc_vars`' `EField`
   exclusion already covered `TTuple` / `TRecord` projection sources for this
   reason, but not `TPtr`, which is the type of `$clo`.
2. **`Drop.owning_apply_fns` declined every closure factory.** A closure
   allocation that was not directly `ELet`-bound latched its type to "not
   owning". A factory's body is exactly that: a bare tail `alloc $Clo_…`. So
   even a freed environment released none of its captures.

## What landed

- **`lib/tir/perceus_core.ml`**: `TPtr` joins `TTuple` / `TRecord` as a
  projection source that is never dup'd.
- **`lib/tir/drop.ml` `owning_apply_fns`** scans with a destination context:
  - a tail allocation that a function **returns** escapes, so it owns its
    captures. A closure allocation that is not ELet-bound is one
    `Borrow.owned_in`'s non-escaping exception never applies to, so its
    captures were transferred in;
  - the tail of an `ELet` right-hand side is judged by
    `Borrow.closure_escapes` of the bound var;
  - anything else still fails closed.
- **`lib/tir/drop.ml` `rewrite_apply_clo_drop`: a use-after-free that the
  narrow gate had hidden.** The rewrite put
  `case $freed of True -> drop captures` in front of **every** tail. For
  `fn s -> a ++ s ++ b` the tail is `string_concat3(a, s, b)`, so the second
  call to a dying closure released `a` and `b` and then concatenated them. The
  probe's leg printed **43,893 instead of 62,786** with only the first two
  pieces landed. Tails are now handled by kind:
  - a tail using no capture keeps the release in front;
  - a tail call to March code (a module function or any `ECallPtr`) that uses
    a capture releases only the captures it does not use. The used ones leak
    on that path, and the call stays a tail call. Wrapping it would put work
    after the call on every invocation, not just the freeing one, and cost
    llvm_tco's loop;
  - any other using tail, including a call to a builtin or extern, is bound
    and released after: `let r = tail in (release; r)`.

## Verification

`test/native/closure_capture_release_probe.march` (+ `.expected`,
`test/dune`) has seven legs of 5,000 calls:
- a factory capturing two lists;
- string captures used by the tail;
- a list of closures folded over;
- a closure inside a constructor;
- a capture reused across calls;
- a closure returning its capture;
- a closure wrapping its capture in a constructor.

Output, `flat` flags included, is identical to the interpreter's.

| build | result |
|---|---|
| this change | all legs flat, values match the interpreter (3 of 3 runs) |
| tail rule reverted (release in front of every tail) | `string captures` prints **43893** |
| Perceus `TPtr` exclusion reverted | factory and string legs `flat: false` |

The design doc's hazard check: `test/native/node_discovery.march` and
`test/native/record_pattern.march`, compiled with and without this change and
run interleaved, 40 of each, 30-second cap per run. **160 of 160 runs exited
0**, with no SIGTRAP, SIGBUS or underflow on either side.

TIR snapshots `nested_cons_ctor_heap`, `trmc_modulo_cons` and
`tuple_atom_string_arms` (perceus stage) lose only the `inc_rc $clo` before
capture reads.

## Still leaking (measured, not regressions)

- **A closure whose tail is an indirect call using a capture**
  (`fn x -> f(f(x))`). The release is withheld on purpose; see the tail rules
  above.
- **A capturing lambda passed to a HOF** (`List.map(base, fn x -> x +
  string_length(label))`). It leaked before this change too. It is the
  closure-argument ownership mismatch in
  `specs/todos/2026-08-21-ecallptr-owned-arg-borrow-callee-leak.md`.
