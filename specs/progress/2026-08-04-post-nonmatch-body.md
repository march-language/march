# 2026-08-04 — a constructor-literal body gets its postcondition attempted

Closes item 3 of the "THREE independent things" list in
`specs/todos/2026-07-29-refinement-contract-composition-follow-ups-open-from-the-2026-07.md`.

## The silent no-op

`check_post_induction` (Tier 2, `lib/refinecheck/refine_check.ml`) recognised
exactly **one** clause-body shape: a top-level `EMatch` on a structural
parameter. Everything else hit the implicit fall-through and returned `false`.
Because Tier 2 is verdict-only — it emits no diagnostic either way — the failure
was completely invisible:

```march
fn push(t : Tree, x : Int) : {Tree | size(_) == size(t) + 2} do Node(t, x, Leaf) end
```

`size(Node(t,x,Leaf))` is `size(t) + 1`, never `size(t) + 2`, yet
`--check --refine-report` printed

```
  by kind: 42 precondition, 0 postcondition
```

Zero postcondition obligations of *any* kind — not `1 skipped` (attempted and
undecided), simply never attempted. This is the simplest possible Tier 2 case:
no induction is needed at all, because there is no recursive call to
hypothesise over — just one unfolding of the measure's recursion equation.

## Implementation: shape (a), hoist and re-parameterise

The brief offered two shapes. Shape (b) — route the body through the existing
`EMatch` arm by synthesising a degenerate branch — was **rejected**: it is not
merely riskier, it is *not general*. The existing arm is entered only when there
is an ADT-typed parameter to match on, so a constructor-literal body with no ADT
parameter at all (`fn leafy(x : Int) : {Tree | size(_) == 1} do Node(Leaf, x, Leaf) end`)
could never be routed through it. A synthesised branch would also assert a
pattern equation constraining a parameter the body never inspects.

So: **shape (a)**. The per-VC builder (`decls` / `declare` / `assume` / `fresh`
/ `reflect_at` / `reflect_dt` / `reflect_int` / `pred_term` and the discharge)
was lifted out of the `EMatch` arm and out of `check_branch`, and
re-parameterised on two optional inputs:

- `~mctx : (mparam * madt * mparam_idx * structural_subvars) option` — the
  **induction context**. It is the *only* thing that licenses an induction
  hypothesis, so a body with no top-level match passes `None` and can therefore
  never assume one. That keeps the soundness property of Tier 2 (the IH may be
  assumed only at a structurally smaller recursive argument) trivially intact
  for the new shape: there is no IH at all.
- `~pat : (ctor * binder_sorts) option` — the arm's pattern equation. Omitted
  for the new shape; the parameters simply stay universally quantified, which is
  strictly *weaker* than any equation, so omitting it cannot make a goal
  provable that would otherwise fail.

There is deliberately still **one** VC generator. A second, parallel builder for
the non-match shape is the drift hazard recorded at `postcond_infer.ml:25`.

`check_branch` is now a plain (non-recursive) local function — it never called
itself; only `check_tail` — and `check_tail` returns
`Obligation.verdict option` instead of `bool`, with `proved_tail` preserving the
old boolean contract for the `EMatch` path.

### Ledger accounting, and why only on the new shape

Tier 2 recorded nothing at all, so "attempted and proved" and "never looked at"
were indistinguishable from outside — the exact ambiguity `Obligation`'s header
comment says the ledger exists to remove. The constructor-literal shape now
records a `Postcondition` obligation. Verdict classification follows the
**definite-failure-only** rule already used by `check_post`:

| solver | verdict |
|---|---|
| goal `Verified` | `Proved` |
| `¬goal` `Verified` | `Violated` — the predicate can never hold |
| neither | `Skipped Solver_undecided` |
| no VC built | `Skipped Unreflectable_predicate` |

`Violated` is ledger accounting only; Tier 2 still emits no diagnostic, so this
cannot reject correct code. The extra refutation query runs **only** on this
shape (`~refute:true`); the `EMatch` path passes `~refute:false` and is
unchanged, both in verdict and in solver-query count.

Extending the same accounting to the `EMatch` shape is deliberately **not**
bundled here — it would move counts under every existing Tier 2 fixture and is
its own change.

## Evidence

**RED (before).** `test post-nonmatch-body` → 2 failures, cases 0 and 1, in
0.016s (the solver was never reached). CLI confirmation of the *reason*, on a
cleared CAS (`rm -rf .march/cas/artifacts-v2 .march/cas/vc`):

```
  by kind: 42 precondition, 0 postcondition
```

**GREEN (after).** `test post-nonmatch-body` → 3/3, 6.07s (the solver is now
consulted).

**Load-bearing, mutation 1** — new arm builds no VC
(`match (ignore body; None) with`): cases 0 and 1 fail again, in 0.005s. The
tests pin the new arm, not something else.

**Load-bearing, mutation 2** — `~refute:true` → `~refute:false`: case **1
only** fails (the REJECT control). This is the sharper result: it proves the
reject control specifically pins the *refutation* path, so it cannot be
satisfied by a checker that merely stopped looking.

**Stdlib false-positive sweep.** 112 `stdlib/*.march` files, `--check`, one
fixed fixture path (`stdlib/...`, relative, same cwd) in both runs so no
worktree path is embedded in output; CAS cleared once before each run. Pre-change
binary vs post-change binary: **byte-identical** (4296 lines).

**Positive control for that sweep** (required — a clean diff otherwise only
proves the instrument is dead): see report. The stdlib has no variant-ADT return
refinements at all, which is also *why* the identity is expected rather than
suspicious.

**Corpus.** `specs/lang/types/accept/*.march` and `reject/*.march` unchanged.

## Docs

`specs/lang/refinement-types.md` ("What is proven") and `docs/refinement-types.md`
(Limitations) both updated — the two copies are independently maintained.

## Positive control result

`stdlib/list.march` had two private functions appended
(`pfn zz_pc_sink(x : {Int | _ > 0})` and `pfn zz_positive_control() do
zz_pc_sink(0) end`), the same 112-file sweep was re-run with the post-change
binary, and the diff against the pre-change baseline was **111 lines**
(non-empty), carrying the expected `refinement violation: argument `x` of
`zz_pc_sink` does not satisfy precondition `_ > 0``. The instrument detects a
change; the byte-identical real comparison is therefore meaningful. `list.march`
was restored from a saved copy afterwards (`git diff --stat stdlib/` empty).
