# `[P2]` Linearity: a closure can capture a linear value unless it is an infer-mode lambda

Filed 2026-09-13 from the probe sweep in
`specs/plans/2026-09-13-linearity-holes-plan.md` (step 4).

## The hole

The "cannot be captured by a closure" rule exists. It only runs when a lambda
is **inferred**. A lambda **checked** against a known arrow type (every
lambda passed straight to an annotated function, which is most of them) and
a local `fn … end` can both capture a linear value. Called twice, the closure
duplicates it:

```march
mod C do
  needs IO.Console
  always_linear type S1 = S1(Int)
  fn sink(s : S1) : Int do match s do S1(e) -> e end end
  fn run2(k : () -> Int) : Int do k() + k() end
  fn main(c : Cap(IO.Console)) do
    let s = S1(1)
    println(int_to_string(run2(fn () -> sink(s))))   -- accepted; s consumed twice
  end
end
```

`--check` exit 0, and the interpreter runs it and prints `2`.

## Measured (main `8eb0d7ee`)

| shape | result |
|---|---|
| `let f = fn () -> sink(s)`, infer mode | rejected: "The linear value `s` cannot be captured by a closure." |
| `run2(fn () -> sink(s))`, check mode, callee calls `k() + k()` | **accepted** |
| `run2(fn x -> x + sink(s))` against `Int -> Int` | **accepted** |
| `fn g() : Int do sink(s) end` in a block, `g() + g()` | **accepted** |

## Cause

The capture check is written inline in `infer_expr`'s `Ast.ELam` arm
(`typecheck.ml` l.1776). It snapshots the outer `env.lin` used-flags, infers
the body, and reports any outer linear entry that went unused → used. The two
other closure-forming sites never take the snapshot:

- `check_expr`'s `Ast.ELam` peel (l.2386);
- `infer_block`'s `Ast.ELetFn` (l.2955).

## Design

Factor the snapshot/diff out of the infer arm into one helper and call it at
all three sites:

```ocaml
(** Run [body_check], then report every OUTER linear/affine entry of [env]
    that was unused before and used after: a closure captured it. *)
and with_capture_check env ~span (body_check : unit -> 'a) : 'a
```

Two corrections while moving it:

- **Key the snapshot on entry identity, not name.** Today it is
  `List.assoc_opt le.le_name snapshot`. It works because the diff iterates
  the *outer* env's entries, and `record_use` hits the innermost same-named
  entry first. That is load-bearing and undocumented. Snapshot
  `(le.le_used, !(le.le_used))` pairs and compare with `==`, the same idiom
  as `lin_entries_added` in
  [[2026-09-10-linear-lambda-parameter-not-must-use]]. If that item lands
  first, reuse its helper.
- **Wrap the whole peel, not one step.** In check mode, wrap the outer call
  `peel params expected env` so the snapshot is taken before the first
  parameter is bound and the diff runs after the innermost body. Wrapping
  per step would count the lambda's own earlier parameters as outer
  entries. The `| _, _ -> infer_expr …` fallback already has its own check
  via the infer arm, so don't nest a second one around it: guard it or
  restructure.

For `ELetFn`, wrap the body check. Recursive self-calls inside the body are
fine: the self binder is not linear.

Affine captures stay rejected, as the infer arm does today
(`le_lin <> Unrestricted`). Keep that behaviour identical at the new sites;
don't relax it in this change.

### The ergonomic cost, stated up front

This rejects some programs that are safe in practice, because the callee
calls the closure once: `with_lock(fn () -> consume(h))`,
`task_spawn(fn _ -> use(h))`. The infer-mode rule already rejects those same
programs when written through a `let`, so this makes the language
consistent rather than stricter in kind. The real answer is a once-only
closure type (Rust's `FnOnce`, or a `linear` arrow), and that is a separate
design. Record every rejection the blast-radius run turns up, as evidence
for that design. Don't carve exceptions here.

## Tests

Reject witnesses (RED first), expected `cannot be captured by a closure`:

- check-mode zero-arg lambda capturing a linear `let` (the program above);
- check-mode one-arg lambda capturing it;
- local `fn g() … end` capturing it.

Accept witnesses:

- a check-mode lambda whose **own parameter** shadows an outer linear name
  and consumes it, with the outer value consumed after the call. Accepted
  today, and the name-keyed snapshot is the thing that could break it;
- a check-mode lambda that references an outer **unrestricted** value;
- the existing infer-mode capture reject must keep its exact message.

Run `scripts/types-oracle.sh` and the session goldens. The endpoint line
should be unaffected. That was checked, not assumed:

- `desugar_endpoints.ml`'s `suspend_with` handler lambda receives
  `(_from, msg, ep1)` and mints the next state from `ep1`. It captures
  only the unrestricted callback `k`, never a state.
- The user callbacks in `test/session/stream_endpoints.march` take the state
  as a parameter (`fn (_b, st2) -> …`) and capture `s : Cap(Session.Live)`
  and plain `Int`s. Capabilities are not tracked linear for capture: an
  infer-mode `let f = fn () -> say(c, "a")` called twice is accepted today.

So a hit in the session goldens means the change over-reaches, not a
generator bug.
