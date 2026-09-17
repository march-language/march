# `Alloc_contract.trmc_note` IS reachable; its test now asserts both directions

Settled 2026-09-17. Closes
`specs/todos/2026-09-09-trmc-note-in-alloc-contract-may-be-unreachable.md`,
which asked whether the note could fire at all and said to delete it if not.

**It fires.** The todo's suspicion — that the note's premise might be
structurally unreachable, because the shape TRMC would help is the same shape
FBIP already optimises — was a good hypothesis and is wrong. The two probes
just happened to fail for two DIFFERENT reasons, one per conjunct of
`(not trmc) && trmc_eligible name`:

| probe | why no note |
|---|---|
| `inc_all(xs) = Cons(h+1, inc_all(t))` | no `no_alloc` diagnostic at all — FBIP reuses the scrutinee cell, so nothing allocates and there is nothing to attach a note to |
| `upto(n) = Cons(n, upto(n-1))` | diagnostic fires, but the function is **`non-trmc`** — `MARCH_TRMC_REPORT=1` reports `tail=0 modcons=0 other=1`, because generating a list from an `Int` is not a modulo-cons shape. The SECOND conjunct is what fails here, which the todo had listed as unexplained |

Both conjuncts hold at once for a function that is modulo-cons over a list
(hence TRMC-eligible) and ALSO allocates something FBIP cannot elide:

```march
@[no_alloc]
fn pairs(xs : List(Int)) : List((Int, Int)) do
  match xs do
    Nil -> Nil
    Cons(h, t) -> Cons((h, h), pairs(t))
  end
end
```

`MARCH_TRMC_REPORT=1` reports `eligible pairs tail=0 modcons=1 other=0
List.Cons@1`, and under `--no-trmc` the diagnostic carries the note.

## What makes it a clean witness

The allocation the diagnostic names is the base case's **`Nil`**, which TRMC
does not remove either — so this fixture reports `no_alloc` in BOTH modes and
differs only in whether the note is attached. Nothing varies across the two
runs except `trmc`, which is exactly the guard.

(That also corrected a wrong assumption in the first draft of the test, whose
control asserted the default build compiles clean. It does not, and the failure
was the more useful shape.)

## Change

`test/test_alloc_contract.ml`'s `TRMC hint absent when --trmc is on` had been
documented as knowingly vacuous since the default flipped on 2026-09-09: with
TRMC on, the guard is false on every ordinary build, so the assertion held for
a reason unrelated to the flag it passed — it would have passed if `--trmc` did
nothing. It is kept, and a second case now asserts the other direction, so
deleting the guard fails a test instead of silently passing.

The note itself is unchanged. Nothing about the `no_alloc` contract was in
question and nothing about it moved.

## The test must not inherit the ambient TRMC default

The first version asserted the note's ABSENCE with `compile ~flags:""`, i.e.
whatever the build default happens to be. That passes locally and fails in
`ci.yml`'s `trmc-suite` job, which runs the entire suite under
`MARCH_NO_TRMC=1` — there `flags:""` means TRMC is OFF, the note is present,
and the assertion inverts.

Both halves now pass the flag explicitly (`--trmc` / `--no-trmc`). The env
forms are seeded before `Arg.parse` precisely so an explicit flag wins, which
is what makes the case configuration-independent — and it is a better test for
it: the claim is about the guard, not about what the default is this month.

Verified in both configurations: the case passes plain and under
`MARCH_NO_TRMC=1`, and the full compiler suite passes under `MARCH_NO_TRMC=1`
(1112 tests).

**Worth knowing generally:** a test that compiles a fixture and asserts on
TRMC-dependent output has TWO configurations in CI, not one. `scripts/run-tests.sh`
locally is the first; `MARCH_NO_TRMC=1 scripts/run-tests.sh` is the second, and
only the `trmc-suite` job runs it.
