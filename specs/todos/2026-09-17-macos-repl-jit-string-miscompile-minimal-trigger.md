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
