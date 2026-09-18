# FIXED 2026-09-18 — the "macOS REPL/JIT string miscompile" was a cache-key bug

Not a miscompile. The parsed-stdlib cache was shared between checkouts, and one
checkout ran on another's AST.

## Why it looked like a layout-sensitive miscompile

The original filing below found a deterministic trigger (5/5) that turned on
edits to an unrelated module's doc comment. On 2026-09-18 that trigger no
longer reproduced — not on `main`, and not on the tree it was found on (`#505`,
both the merge `2f2d75ccc` and the head `d4370d1cd`) **with an isolated
`HOME`**. With the real shared `~/.cache/march` it failed 3/3 on both trees.
It was never about the code; it was about which cache blob a run picked up.

## The mechanism

`bin/toolchain.ml`'s `load_stdlib` caches the parsed stdlib as a Marshal of
`March_ast.Ast.decl list`, under

    stdlib_ast_<compiler-identity>_<hash of stdlib source bytes>.bin

Every span in those declarations carries the **absolute path** of the file it
came from, and the key does not include the directory. So two checkouts with the
same stdlib text and the same compiler build — two worktrees, which the shared
dune cache makes byte-identical — got the same key, and whichever parsed first
stamped its paths into the other's AST.

The blob in question: `stdlib_ast_ba48eb538f6c_6bfc8e18e8345f1c.bin`, written
2026-09-17 11:10 by a different worktree, its spans naming
`…/worktrees/epic-booth-33e11d/stdlib/…`, loaded by a run in a different
checkout.

That was not cosmetic. Everything downstream digests these declarations — the
tcenv caches and the JIT's stdlib prelude key both marshal the decls — so the
foreign paths propagated faithfully. Same compiler, same source, two HOMEs, two
different prelude keys (`c72b75c52fef57bb` fresh vs `2ac0f25e99018587`
shared), and the prelude built from the foreign-path AST answered
`Path.is_absolute("/etc")` with `false`.

## Proof it is causal

Swapping ONLY that blob into an otherwise clean isolated cache:

| cache | `path.march` doctests |
|---|---|
| clean isolated HOME | 34 run, 0 failed |
| same, with just the foreign-path `stdlib_ast` blob copied in | **1 failed** — `Path.is_absolute("/etc")` |

## The fix

The stdlib directory is now part of the key
(`stdlib_ast_<id>_<dir tag>_<source hash>.bin`). The tcenv caches did not need
changing: they key on the marshaled declarations, spans included, so they were
already path-sensitive and merely inherited whatever paths the AST blob carried.

## Verification

- The reproducing tree (`2f2d75ccc`) with the fix, against the real shared cache
  that still held the foreign blob: **1 failed → 0 failed, 3/3.**
- `test/test_tcenv_cli_cache.ml`: two byte-identical copies of the stdlib under
  one HOME must produce two blobs, each naming its own directory and never both.
  **RED on the old key: 1 blob, shared.**

## What this does NOT change

`.github/workflows/ci.yml` still scopes the stdlib doctest gate off macOS, and
this fix is not a reason to re-enable it. That exclusion cites a residual
nondeterminism on the GitHub `macos-15` runner, which runs with a fresh `HOME`
and a single checkout — so it cannot be this cross-checkout collision. It is a
separate issue and stays open under that comment.

The cache directory accumulates: this machine's `~/.cache/march` was 12 GB,
with 1,482 `stdlib_ast` blobs. The old-key blobs are simply never read again
under the new naming. Nothing sweeps them.

The original filing follows.

---

# macOS REPL/JIT: a docstring in one stdlib module makes `String.starts_with` wrong in another

Logged 2026-09-17. `[P2]`

`.github/workflows/ci.yml` scopes the stdlib doctest gate OFF macOS with the
reason "the JIT's core cross-dylib string miscompile". That bug has been
described but not, as far as `specs/` records, pinned to a **deterministic
minimal trigger**. This is one, found while adding `NativeArray.sort_int`.

## Repro (macOS, arm64)

On a tree with `NativeArray.sort_int` and its `march>` doctest in
`stdlib/native_array.march`:

```bash
dune build --root . bin/main.exe stdlib/native_array.march
MARCH_BIN="$PWD/_build/default/bin/main.exe" \
  python3 scripts/check-stdlib-doctests.py --check stdlib/path.march
```

```
FAIL stdlib/path.march:29  Path.is_absolute("/etc")
      expected: 'true'
      actual:   'false'
```

`Path.is_absolute` is `String.starts_with(path, "/")`. The REPL returns
**false** for `"/etc"`. Deterministic: 5 runs, 5 failures.

Note what is and is not being checked here. The command asks only for
`stdlib/path.march`'s doctests — 34 of them, none in `native_array.march`. The
edit that changes the answer is in a **different module**, and it is inside a
**doc comment**.

## Bisected trigger

Four configurations, everything else identical (same compiler, same branch,
only `stdlib/native_array.march` swapped):

| `native_array.march` contents | `path.march` doctests |
|---|---|
| `origin/main`'s version | 34 run, 0 failed |
| main's + ~4 lines of added prose in an existing `doc` | 34 run, 0 failed |
| with `fn sort_int`, doc but **no** `march>` line | 34 run, 0 failed |
| with `fn sort_int` **and** its `march>` doctest line | **1 failed** |

So it is not "any edit", and not docstring size — padding prose of comparable
length does nothing. It takes the function plus that particular doctest line.
That pattern says layout/fragment sensitivity rather than anything semantic
about `sort_int`, which is consistent with a cross-dylib string constant
resolving to the wrong fragment.

## Why this is not blocking

- macOS only. The CI doctest gate is Linux-only by design, and the Linux leg
  passed this same tree (PR #505, `conformance (ubuntu-24.04)` green).
- Compiled code is unaffected: `test/native/native_arr_sort.march` and the full
  `dune build @runtest` are green on the same tree.
- The underlying bug predates the change. Any stdlib edit that perturbs
  fragment layout could surface it at some other call site; this one just
  happens to be reproducible on demand.

It is still **user-visible on macOS**: a developer in `march repl` gets `false`
from `Path.is_absolute("/etc")`. That is a wrong answer from a correct program,
which is worse than a crash.

## Where to look

`lib/jit/`, and `bin/toolchain.ml`'s `ensure_runtime_so` — its own comment
describes an earlier incarnation where two worktrees could ping-pong one fixed
`libmarch_runtime.so` and dlopen each other's ABI. Related recorded behaviour:
REPL-JIT fragments cannot forward-reference the next fragment because macOS
`dlopen` binds eagerly, which is the same class of cross-fragment symbol
resolution problem.

A first experiment worth running: dump the JIT fragment for `String.starts_with`
in the failing and passing configurations and diff the string-constant
references, rather than the March-level source.
