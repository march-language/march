# Refinement reflection, phase 3: the stdlib `List` set (2026-11-03)

Design: `specs/2026-10-29-refinement-reflection-design.md` §10 "Phase 3" (D18). Builds on
phases 2 (lemmas, #1061) and 4 (fuel, #1065).

## What landed

- **The lift.** `reverse` and `take` keep their loops in private top-level functions,
  `reverse_onto(lst, acc)` and `take_onto(lst, k, acc)`, instead of a local `go`. A lemma can
  only name a top-level function.
- **13 lemmas in `stdlib/list.march`, all proved:**
  - the spec's ten: `append_nil`, `append_assoc`, `len_append`, `reverse_onto_append`,
    `reverse_append`, `reverse_reverse`, `len_reverse`, `len_take`, `len_drop`, `take_drop`;
  - three accumulator generalisations the proofs need: `len_reverse_onto`, `len_take_onto` and
    `take_onto_drop`.

  `len_take` and `len_drop` hold only for `0 <= n <= len(xs)`, so those bounds are parameter
  refinements, that is, hypotheses each call must prove. `reverse_reverse` keeps three `assert`
  steps that the default fuel of 2 does not reach on its own.
- **`List.filter`'s length contract.** Its return gains `len(_) <= len(xs)`, which is proved,
  next to the existing `subset(elts(_), elts(xs))`.
- **The stdlib lemma manifest, `stdlib/lemmas.verified`.**
  - It records each shipped lemma that proved, with a digest over the lemma's qualified name and
    the full text of every file its theorem and proof reach.
  - "Reach" means the termination graph's reachable SCCs from the lemma, from every unit its body
    calls (asserts included), and from every unit its theorem names.
  - A stdlib lemma whose line matches is admitted as `trusted` without its body being walked.
  - Any edit to a reached file changes the digest, so the lemma is proved again.
  - `march --emit-lemma-manifest` proves every lemma (the manifest is ignored) and prints the file.
    `scripts/gen-lemma-manifest.sh` writes it, and `--check` diffs it.
  - The `reflect-stdlib-list` test "stdlib/lemmas.verified is fresh" runs that check in CI's
    refinecheck shard, so a stale manifest fails CI without a workflow change.
  - `MARCH_LEMMA_MANIFEST=<path>` overrides the file, for tests.
- **Encoder additions for `len` over reflected terms.** All are stage-2-only, so stage 1 is
  unchanged:
  - `len(f(..))`, where `f` is a reflected call, and `len(Cons(..))` both become `$len(term)`;
  - a list constant's `len$x` is tied to `$len(x)`;
  - a caller variable that only appears inside a reflected call still loads its own measure facts.

## Rulings

1. **The manifest file is `stdlib/lemmas.verified`, not `.lemmas.verified`.** Dune ignores
   dot-files, so a hidden file would never be staged next to the build's stdlib. It is also added
   to `stdlib/dune`'s install stanza.
2. **The digest is over whole files, not per definition.** Hashing whole files is coarse, since
   an unrelated edit to `list.march` also invalidates the lemmas. But it is simple and cannot miss
   a dependency. The cost of a stale entry is only a re-proof, plus a CI failure until the file is
   regenerated.
3. **The lift is not IR-neutral.**
   - The spec expected the IR to differ only in the renamed symbols. In fact 137 of 515 programs
     changed IR.
   - In a sample of 7, normalising line-number fields and the renamed symbols leaves 5 identical.
   - The other 2 lose the static closure `$Clo_go$0_List_reverse_List_Int` (the old local `go`
     compiled as a closure) in favour of a direct call, and renumbered temporaries make that
     diff large.
   - `bench/list_ops.march` at `--opt 2` gives identical output and binary size, and timing
     within noise (base 0.059-0.089 s, new 0.062-0.071 s, under load).
4. **Checking `stdlib/list.march` directly as a user file** leaves 6 of its new lemma
   obligations as `unreflectable-predicate`. There the theorems' unqualified `reverse` and `take`
   are ambiguous with the prelude's own definitions. In every real program (stdlib prepended) all
   13 prove. These are new obligations, not regressions.
5. **Filter.** Reflecting `filter` itself waits for phase 5 (function values), as the spec rules.
   The length contract is its substitute.

## Tests (group `reflect-stdlib-list`, `test/test_refine_stdlib_list.ml`; 9 cases)

- From user code: `std_len_append` (proved with the call, a skip without it),
  `std_reverse_reverse`, `std_take_drop`, `std_len_take` and the out-of-range
  `lemma_unproved_call`, and `std_filter_len`.
- Every shipped lemma is `trusted` from the manifest, and none is re-proved.
- A stale entry (`MARCH_LEMMA_MANIFEST` with a wrong digest) makes `len_append` prove again while
  the other entries still admit their lemmas.
- The manifest is fresh, regenerated and diffed (`Slow`).

## Verification

| Check | Result |
|---|---|
| `reflect-stdlib-list` | 9/9 |
| refine-oracle vs main `9517c9ed5` | see "Oracle" below |
| ir-oracle vs main | CHANGED, see ruling 3 |
| doc-lint | passes |
| after merging main | `reflect-stdlib-list` 9/9, `reflect-lemma` 42/42, `reflect-fuel` 13/13, `run_errors` 325/325; the full refinecheck and compiler suites are left to CI |

### Oracle

566 of 568 programs differ only by `+13 trusted` in their user+stdlib total: the manifest-admitted
lemmas. No user-code total moved, and no proved count fell in any program. The two exceptions:
- `native_entry_module_named_list`: +10 trusted. A user module named `List` changes which lemmas
  resolve.
- `native_owned_call_drop_fusion`: +15 proved and +7 trusted.

`stdlib_list` (ruling 4) gains 16 proved and 6 skipped new obligations.
