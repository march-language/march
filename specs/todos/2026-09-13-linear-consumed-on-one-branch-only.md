# `[P2]` Linearity: a linear value consumed on only one branch is accepted

Filed 2026-09-13 from the probe sweep in
`specs/plans/2026-09-13-linearity-holes-plan.md` (step 7). **Decided
2026-09-13: Option A** (require consumption on every path that can fall
through; divergent paths exempt).

## The hole

A `Linear` value consumed in one arm of an `if`/`match`/`cond` and not in the
other is accepted. On the other path it is simply dropped. This holds for
every binder kind, including the strictest ones:

```march
mod B do
  needs IO.Console
  always_linear type S1 = S1(Int)
  fn sink(s : S1) : Int do match s do S1(e) -> e end end
  fn g(b : Bool, st : S1) : Int do
    if b do sink(st) else 0 end            -- accepted; st leaks when b is false
  end
  fn main(c : Cap(IO.Console)) do println(int_to_string(g(false, S1(1)))) end
end
```

The language reference says the opposite. `specs/lang/linear-types.md`,
"Practical Rules" 4: "each branch must use it in a compatible way."

## Measured (main `8eb0d7ee`)

| shape | result |
|---|---|
| top-level fn param, consumed in `if` then-branch only | **accepted** |
| same via `match b do true -> sink(st) false -> 0 end` | **accepted** |
| same with an explicit `linear t : T` param | **accepted** |
| `let`-bound, consumed in one `if` branch | **accepted** |
| lambda param, same (check mode) | **accepted** |
| consumed in then-branch, else-branch is `panic("no")` | accepted (**correct**: that path doesn't return) |
| linear param in scope across `let? v = mk(i)`, consumed after it | **accepted** (leaks on the early `Err` return) |
| consumed twice within one branch | rejected (correct) |
| consumed once in each branch | accepted (correct) |

## Cause

This is deliberate, and documented at the helper. `iter_paths_linear`
(`typecheck.ml` l.2659), used by `EMatch` arms (via `iter_arms_linear`, both
infer and check mode) and both `EIf` branches (l.2051), resets the
used-flags before each path and then sets each entry to **consumed iff
consumed before the branch or on some path** (a union). `ECond` (l.2066)
can't use the helper wholesale, because its conditions share state with
each other, so it has its own inline copy of the same union over its bodies. The union is what stops a value consumed once per arm from being
reported as a double use. It also makes a value consumed on **some** path
count as consumed on **all** of them. That second effect is the hole: for
must-use purposes, linear values behave affinely across branches.

`let?` is a hidden branch: an early return on `Err`, and nothing asks what
that return drops.

## The decision

**Option A: strict, with divergence exempt (chosen).** For a `Linear`
entry, after all paths have run:

- consumed on every path that **can fall through** → consumed;
- consumed on none → unchanged (the scope close decides, as today);
- consumed on some fall-through paths but not others → error at the branch
  construct, with a label on a path that consumed it and one on a path that
  didn't.

A path that **cannot fall through** doesn't count, since nothing after it
runs. Affine entries keep the union: dropping on a path is what affine
permits, and session endpoints rely on it.

**Option B: keep the union, fix the documentation.** Declare that linearity
is enforced per path for duplication but only "on some path" for
consumption, and rewrite Practical Rule 4 to say so. Zero blast radius, and
it accepts that `always_linear` guarantees no-duplicate, not no-leak, across
branches. Every typestate API (`Handle`, `@[endpoints]` states) then
documents a hole instead of closing it.

Option A is what the language already claims. Option B is what it does.
Picking B is legitimate, but it has to be chosen and written down, not
inherited from a helper's comment.

## Design, for Option A

1. **Divergence.** March has no `Never` type (`panic : String -> a`), so
   divergence is syntactic. A path diverges if its **tail expression** is a
   call to one of the builtins `typecheck_builtins.ml` lists under
   "Diverging primitives" (today `panic`, `panic_`, `todo_`, `unreachable_`);
   a `match`/`if`/`cond` all of whose paths diverge; or a block whose last
   expression diverges. Put this
   in one predicate, `path_diverges : Ast.expr -> bool`, next to
   `iter_paths_linear`, and keep the name list in one place. A user function
   that always panics is **not** recognised. That is a false positive the
   error message can mitigate ("if this branch never returns, end it with
   `panic(…)`").
2. **`iter_paths_linear`** takes each path's body along with its thunk, so
   it can call `path_diverges`. The current signature is `(unit -> unit)
   list`; widen it to `(Ast.expr option * (unit -> unit)) list`, where `None`
   means "can't tell, treat as falling through". Call sites:
   `iter_arms_linear` (arm body) and `EIf` (each branch). `ECond`'s inline
   copy (`body_acc` / `run_body`) must get the same join rule. Factor the
   join out of `iter_paths_linear` so both use one implementation, rather
   than editing two copies.
3. **Join rule.** For each snapshot entry with `le_lin = Linear`, track the
   set of fall-through paths that consumed it. Union as today for `Affine`
   and for sentinels whose base binder is affine. For `Linear`: all → used;
   none → keep the pre-branch flag; mixed → error, then mark used (so the
   scope close doesn't add a second "never used").
4. **Pending entries** (from
   [[2026-09-13-linear-unannotated-parameter-never-promoted]]) aren't
   judged until their scope closes, when the paths are gone. Record, per
   pending entry, whether a mixed join happened (a `le_mixed : Ast.span
   option ref`), and report it at the close if the type resolves `Linear`.
5. **`let?`.** `let?` reaches the typechecker as its own node, `Ast.ELetQ`
   (`typecheck.ml` ~l.2239), not a desugared `match`, so it needs its own
   rule. At the `Err` exit, every `Linear` entry in scope that is still unused
   is dropped. Report it at the `let?` span: "`st` is still unconsumed when
   `let?` returns early on `Err`." Entries bound **inside** the continuation
   aren't in scope at the exit; use the identity snapshot taken before the
   continuation is checked.

Match guards and `if` conditions run on every path, and must stay outside
the per-path reset, as the helper's comment already requires.

## Tests (Option A)

Reject witnesses (RED first). Expected `consumed on some branches`, except
the `let?` one, which expects `returns early on`:

- the program above;
- the same via `match`;
- a `let`-bound value consumed in one arm of a three-arm `match`;
- a linear param across a `let?` that can return `Err`.

Accept witnesses:

- consumed once in each branch;
- consumed in one branch, the other `panic(…)`;
- a three-arm `match`, one arm diverging, the other two consuming;
- an **affine** value consumed on one branch (the union stays);
- a session-channel endpoint driven on one branch only (affine);
- a value consumed **before** the `if`, touched in neither branch.

Blast radius is the largest of any item in the plan. Every conditional in
code that touches `Handle` or an endpoint state is in reach. Run
`scripts/types-oracle.sh`, the session goldens, `test/cap_mock/`, and
`~/code/bastion_todos`, and classify every new diagnostic as either a real
leak or a divergence the predicate missed. The second kind means widen the
predicate, not relax the rule.

## When decided

Whichever option is chosen, rewrite Practical Rule 4 in
`specs/lang/linear-types.md` and `docs/linear-types.md` to say exactly what is
enforced.
