# Abstract refinements, the leftovers, phase E: `Within` field roles, `Deque.filter`

Phase E of `specs/2026-10-18-abstract-refinements-leftovers-design.md` (§6.5, §9.5;
the user decided "go", last in the order). It refines the soundness floor of
`specs/progress/2026-10-18-hidden-field-element-refinements.md` (multi-arg design
phase 0) and `2026-10-18-elem-permuted-self-field-unchecked.md`: a constructor field
of type `List(a)`, and more generally `C(args)` for another registered container, is
now modelled instead of being a recorded skip. All five phases of the leftovers
design have landed.

## Before / after

Measured with `march --check --refine-report --refine-report-sites` under a private
`HOME`, on ee1c6512d and on this branch.

| Row | Program | Before | After |
|---|---|---|---|
| Q4 | `type Dq(a) = Dq(Int, List(a), List(a))`; `fn mk_bad() : Dq({Int \| _ > 0}) do Dq(1, [0 - 1], []) end` (and the same with the `-1` in the back list) | 2 skips each, `unreflectable-subject` | **violated** (one obligation, at the `-1`) |
| mk_ok | `Dq(2, [1], [2])` | 2 skips | **proved, proved** |
| Q5 | `match d do Dq(_, f, b) -> sum_pos(f) + sum_pos(b) end`, `d : Dq({Int \| _ > 0})` | skip | **proved, proved** |
| Q1 | `sum_pos(Deque.to_list(Deque.filter(d, fn y -> y > 0)))` | `parametric-source-unproved` | **proved** |
| Q1c | the same with `fn y -> y >= 0` | skip | not proved (skip) |

The design's stated risk (whether `Deque.to_list` passes the parametric gate P1/P2)
did not materialise: Q1 proves.

## What changed

- `lib/refinecheck/refine_encode.ml`: `type field_role = Param of int | Self |
  Within of string * int option list | Other`. `Within (c, m)` means the field has
  type `c(args)` and `m.(k) = Some j` when `c`'s slot `k` holds this type's
  parameter `j`. `register_field_sorts`' new `within_of` admits it only when:
  - `c` is a registered container (every constructor already in
    `ctor_param_fields`) other than the type itself, with arity `length args`;
  - every argument is a bare parameter of this type or mentions none, and at least
    one is a parameter (`List(List(a))`, `List((k, v))`, `Result(a, List(a))` stay
    `Other`, i.e. hidden);
  - none of the mapped slots is in `c`'s own `ctor_hidden_params`.
  `hidden_of` treats a `Within` field like a `Param` field (it hides nothing), so a
  parameter that occurs only in `Within` fields is no longer in the type's hidden
  list; `ctor_field_params` follows from the same `hidden_of`.
- **Declaration order.** "Already registered" depends on declaration order, so
  `register_field_sorts` now runs its one-pass body (`register_field_sorts_once`) to a
  fixpoint of `ctor_param_fields` and `ctor_hidden_params` (bounded at 16 passes; two
  in practice, the second confirming nothing moved). The iteration is monotone: the
  first pass treats every container not yet registered as hiding everything, and a
  later pass can only turn an `Other` into a `Within`, so every intermediate state is
  sound. Measured cost: none visible (below).
- `lib/refinecheck/refine_check.ml`, `check_elements`' `ECon` arm: a `Within (c, m)`
  field is checked with `check_elements` against `(c, slots mapped through m)`. This
  is where new OBLIGATIONS appear (Q4). All-`None` mapped slots owe nothing.
- `refine_check.ml`, `match` facts: a `PatVar` at a `Within` field gets the `contenv`
  entry `(c, mapped slots)`, taken from the scrutinee's entry exactly as a `Param`
  field's slot is. So the binder fact is only as good as the scrutinee's entry: an
  unrefined scrutinee, a scrutinee whose call return was violated, or a retired
  (shadowed) entry gives nothing (controls below).
- `refine_param.ml`'s `container_paths` needed no change (re-read): once `Deque`'s
  slot 0 is not hidden, `Deque(a)` is a `Src_elem` path, which is what lets
  `Deque.to_list` carry the slot parametrically for Q1.
- `stdlib/deque.march`: `Deque.filter(d, pred : a -> Bool[p]) : Deque(a[p])` filters
  the front and back lists in place:
  `Deque(_, f, b) -> let f2 = filter_list(f, pred) … Deque(len(f2) + len(b2), f2, b2)`.
  Order is preserved: `to_list = f ++ reverse(b)` and filtering commutes with both.
  **Deviation from §6.5:** the design's body calls `List.filter`; that resolves to no
  definition when `stdlib/list.march` is itself the entry, which raised the CI
  ratchet's skip count 37 → 39 (two `unreflectable-subject` skips, measured). As
  phase D did for `Range.filter`, the body calls a private natural-style
  `pfn filter_list(xs : List(a), pred : a -> Bool[p]) : List(a[p])` (`List.filter`'s
  body; TRMC loop). Ratchet back to 37.

### Relations (multi-arg design §2.3/§2.5)

`Within` is a variant constructor, not a flag, so the relational builder can match on
it. A relation over slots `S` must not pair a `Within` field with a `Param` field
position-wise: a nested container holds many values per slot, so "the `k` and the
`v` of one entry" has no meaning across `Dq(k, List(v))`. Recommended rule for the
`ECon` row: a want relation whose slots are all mapped from ONE `Within (c, m)` field
becomes the nested container's own relation (the entry `(c, mapped slots, mapped
rels)` passed down to `check_elements`); a relation touching a slot reachable only
through `Within` fields together with a `Param` field, or through two different
`Within` fields, is a recorded skip, never vacuously true. On the `match` side, a
`Within` binder carries mapped rels inside its entry and never a path fact over
sibling binders. Comment at the type in `refine_encode.ml`.

## Tests

`test/test_refinecheck.ml`, group `abstract-leftovers-e` (21 cases). RED measured on
ee1c6512d with only the test file applied (and the old `Deque.filter`).

| Case | ee1c6512d | Branch |
|---|---|---|
| Q4, front list: violated | FAIL (2 skips) | OK |
| Q4, back list: violated | FAIL | OK |
| mk_ok: proved, proved | FAIL | OK |
| Q4 under `cap verified` is an error, not the hidden-field text | FAIL | OK |
| Q5: binders at both list fields proved | FAIL | OK |
| control: unrefined scrutinee, binder gets nothing | OK (guard) | OK |
| control: scrutinee from a VIOLATED return, binder not proved | FAIL (return was a skip) | OK |
| control: a shadowed refinement variable retires the binder fact | OK (guard) | OK |
| `Option(a)` and `Result(a, Int)` fields: violated/proved each | FAIL | OK |
| a user container declared LATER (`Outer(Inner(a))` before `Inner`) | FAIL | OK |
| nested `Outer(Dq(a))` | FAIL | OK |
| floor: `Int -> b`, `List(List(a))`, `Hw(Hid(a))` (hiding inner), `Result(a, List(a))` stay skips | OK (guard) | OK |
| floor: a hiding inner container keeps the parametric rule off (`need_pos(get(h))`) | OK (guard) | OK |
| floor: a binder at a `List(List(a))` field gets nothing | OK (guard) | OK |
| user field-wise `dfilter`: return proved ×2, `need_dq(dfilter(…))` proved | FAIL | OK |
| wrong `dfilter`: unfiltered back list kept, not proved | OK (guard) | OK |
| wrong `dfilter`: unfiltered back list moved to the front, not proved | OK (guard) | OK |
| `dfilter` swapping the two FILTERED lists still proves | FAIL | OK |
| `Deque.filter` definition side all proved (5: 2 in `filter`, 3 in `filter_list`) | FAIL | OK |
| Q1 proved | FAIL | OK |
| Q1c (weaker lambda) not proved | OK (guard) | OK |

On the "swaps fields" control the brief asked for: a pure swap of the two filtered
lists (`Dq(n, b2, f2)`) **is** a `Dq(a[p])`; element refinements say nothing about
order. It is pinned as proved, and order is pinned by the runtime tests instead. The
swap that is wrong for the refinement (an unfiltered list moved into the other field)
is pinned as not proved.

Moved, in group `hidden-field-elements` (the intended phase-E changes, explained in
their comments): "Q4: … is a recorded skip" is now "… is checked (a violation)", and
"mixed `P(a, List(a))`" now checks both fields (proved/violated each) instead of
skipping the list field.

Not claimed: `match dfilter(…) do Dq(_, f, _) -> sum_pos(f) end` is still a skip. A
call with an abstract return has no `contenv` entry by phase 2's design (a demand
re-examines the call through `lets`), and a `match` scrutinee is not re-examined.
Same as `match List.filter(…) do Cons(h, _) -> …` today.

### Perturbations (each reddens exactly the listed cases)

| Perturbation | Red |
|---|---|
| `ECon` `Within` arm returns `true` without checking | 13 cases: Q4 ×2, mk_ok, cap verified, the violated-scrutinee control, Option/Result, later-declared, nested, `dfilter` ×4 (both wrong-body controls go red: the vacuous return counts as proved), `Deque.filter` definition side |
| `match` `Within` arm adds nothing | Q5 only |
| fixpoint bounded at 1 pass | the later-declared container case only |
| `within_of` ignores the inner container's hidden list | the parametric-rule floor case only (constructions still skip through the recursion; the hole is the parametric rule) |

## Runtime

`test/stdlib/test_deque.march`: six new cases pinned on the OLD body first (41 tests,
0 failures before and after): order across front and back, a front-only deque, the
empty deque, all-pass, all-fail, and peek/pop at both ends of a filtered deque.

Compiled perf (`--compile --opt 2`, a 200k-element deque with 100k elements in each
list, `Deque.filter` ×50, three interleaved runs, warm): base 170 / 165 / 167 ms
(median 167), branch 77 / 74 / 75 ms (median 75), same output (5000000). The old body
went through `to_list` (append + reverse) and `from_list` (a closure fold of
`push_back`).

## Verification

- Named-target build: `dune build --root . bin/main.exe test/test_refinecheck.exe
  test/run_compiler.exe test/test_stdlib_march.exe`.
- `./_build/default/test/test_refinecheck.exe -e` with `.march/cas/vc` cleared once,
  z3 on PATH: 1279 tests, 0 failures, 0 SKIP (8m20s).
- `scripts/run-tests.sh -q compiler`: 1348 tests pass. `-q stdlib`: 825 pass.
  `stdlib_march`: 80 pass.
- `specs/lang/types/check_types.sh`: 479 passed, 0 failed (`accept/t430`,
  `reject/t431`; both fail on ee1c6512d: t430 has 5 skips under `cap verified`, t431
  exits 0 with 2 skips).
- `scripts/check-docs.sh`: passes.
- `scripts/refine-oracle.sh`: baseline on ee1c6512d in a detached worktree at the same
  directory depth (stdlib re-staged), check on the branch, both under the script's
  private HOME. Every one of the 549 fixtures moves the same way: `(user + stdlib)`
  **+5 proved, +5 preconditions** (`Deque.filter`'s 2 and `filter_list`'s 3), no skip,
  violation or trusted count moves anywhere. `stdlib_deque`'s own user-code line goes
  `0 → 5 proved`, and it gains the `non_tail_recursion` warning for `filter_list`
  (the same warning `List.filter` and `Range.filter_list` carry; TRMC makes it a
  loop). `stdlib_node_queue` (whose `Deque.filter` call at `:281` is over a closure
  of tuples) moves only by the uniform +5. **No new stdlib violation.**
- CI ratchet (`--check --stdlib-source --refine-report stdlib/list.march`, cold,
  private HOME): `user + stdlib` 100 → 105 proved, **37 skipped before and after**.
- `test/refine_audit/*.baseline` regenerated: every fixture's `(user + stdlib)` line
  `169 → 175 enforced, 0 unenforced` (the six new contract sites in `deque.march`),
  `stdlib_deque`'s user-code line `0 → 6 enforced`; `holes_tuple_element` keeps its 1
  unenforced.
- Cold `--check --refine-report --stdlib-source`, private HOME, three interleaved
  runs (load average ~10-18): `list.march` base 1.30 / 1.28 / 1.26 (median 1.28 s),
  branch 1.36 / 1.26 / 1.25 (median 1.26 s); `deque.march` base median 1.25 s,
  branch 1.23 s. Within the 110% budget.
- Not run: the ecosystem repos (`conduit`, `depot`) comparison from design §8.

## Filed

- `specs/todos/2026-10-18-hidden-field-shapes-unchecked-warning.md`: the shapes
  `Within` does not model (function fields, `List(List(a))`, tuples in containers,
  hiding inner containers, permuted/nested self-references, `Rose`-shaped fields)
  are recorded skips, but get no default-mode `refinement_unchecked` warning at the
  refined type argument (design §7 ✱).
