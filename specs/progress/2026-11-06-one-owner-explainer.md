# A third scrolling explainer: what one owner is worth

`docs/one-owner.md` (`/docs/one-owner/`, in the sidebar after "What a Deploy Is Allowed
to Do"). Ownership, in-place reuse (Perceus and FBIP), linear and affine types, and the
allocation contracts, told as one 31-cell binary tree followed through the question "is
anyone else holding this?". Inside the 20-minute budget the first page set
(`scripts/check-explainer-budget.py` prints the live count).

## What the page follows

`inc_leaves`, the Memory Model chapter's canonical tree transform, on a tree of depth 4
(16 leaves + 15 nodes), in `docs/assets/explainer/ownership/programs/`:

1. `owned.march`: `inc_leaves(t)` is the last use; `--why-copies` finds nothing;
   `inc_leaves` allocates 0 cells (the runtime trace).
2. `shared.march`: `sum_leaves(t)` afterwards; `copy_shared` names the second use;
   `inc_leaves` allocates 31.
3. `vault.march`: the tree is `Vault.set` before the call. `--why-copies` finds no copy
   (the static view sees only the code) and the run allocates 31 anyway (the count sees
   the Vault's reference). The page makes this contrast its point about the division of
   labour between the compiler and the count.
4. `parallel.march`: the two halves through `List.pmap_n([l, r], …, 2)`: two tasks,
   `inc_leaves` allocates 0, the list/chunk/task plumbing a dozen small cells. `pmap_n`
   rather than `pmap` because `pmap` below its threshold delegates to `List.map`.
5. `linear_ok`, `linear_twice`, `linear_never`, `affine_ok`, `affine_twice`: the type
   checker's verdicts (`linear_used_twice`, `linear_never_used`; affine drop accepted).
6. `contract_pinned` (`@[no_alloc] inc_leaves` compiles), `contract_bare` (`width_bare`
   calls `describe`, which allocates), `contract_transient` (`@[no_alloc(transient)]`
   passes), `contract_boxed` (`Vec3` stored into `Hit` is boxed), `contract_caller`
   (the contract holds while a sharing caller makes the function allocate at run time),
   plus the `no_alloc_candidate` line from `--report-contracts`.

## Where the numbers come from

`scripts/gen-ownership-data.py` writes `docs/_data/ownership.json`. It needs the compiler
(`$MARCH_BIN` or `_build/default/bin/main.exe`) and no forge. In a scratch directory under
a private `HOME` it runs `--why-copies`, `--check`, `--compile`, `--compile
--report-contracts`, and for the tree programs `--rc-trace --compile` followed by a run
under `MARCH_TRACE_GC=1`, folding `trace/gc/gc.jsonl` into allocations per function the
way `scripts/gc-trace-report.py` does. `non_tail_recursion` warnings the tree functions
raise are stripped from the quoted text. The generator pins phrases in
`specs/lang/memory-model.md` and `specs/lang/linear-types.md` that the page quotes, and
the existence of `specs/2026-11-04-alloc-bound-design.md` and its todo.

Not measured, and said on the page:

- **`@[alloc_bound(N)]`** is a design (`specs/todos/2026-11-04-alloc-bound-contract.md`);
  the page's last card describes it as unshipped.
- **The walk's order and timing** in the heap figure are drawn; its counts are measured.
- **"The count disappears" for linear values** is quoted from the chapter, not measured:
  no trace of the linear program is compared with the plain one.

## Two things found while grounding the page

- The Memory Model's `bump_copied` anti-pattern, put under `@[no_alloc]`, is not a
  contract failure in the form the chapter gives: the chapter's version fails for the
  tuple it returns, and a version returning only a `Box` passes. The page therefore
  demonstrates the contract on `describe`/`width_bare` and on the boxed `Vec3`, which do
  fail for the reason stated.
- `--why-copies` is a static report: it finds no copy in the Vault program, and a
  closure capture it does flag (`task_spawn(fn _ -> inc_leaves(l))`) allocated nothing at
  run time because the task consumed the closure once. The page uses `pmap_n`, which
  neither tool flags, and lists the Vault case under "What this does not do".

## Machinery

Shared with the first two pages (`docs/_includes/explainer.html`, `chapters.js`,
`scroll.js`, `rng.js`, `scripts/render-explainer-fallbacks.js`,
`scripts/check-explainer.sh`). New: `sim-heap.js` (the walk, no DOM/clock/random),
`draw-ownership.js`, `figures-ownership.js` (the token and the ledger as SVG),
`chapters-ownership.js` (card tables and registrations), `test/explainer/ownership.test.js`,
`test/explainer/test_gen_ownership.py`, fallback posters `heap.svg`, `token.svg`,
`contract.svg`. Wiring: `check-explainer.sh`, `check-docs.sh` Check H
(`--check-inputs`), `affected.sh`/`test-affected.sh`, and a CI step that reruns the
generator with `--check`.

## Checks run

`scripts/check-explainer.sh`, `scripts/check-docs.sh`, `scripts/test-affected.sh`,
`gen-ownership-data.py --check` on fresh data (exit 0) and on perturbed data (exit 1); the
page in the browser at phone width and in two columns. Not checked: reduced motion,
JavaScript disabled, the light theme, a timed read-through.
