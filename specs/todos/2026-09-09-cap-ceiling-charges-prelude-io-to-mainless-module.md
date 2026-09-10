# `[P2]` The capability ceiling charges the prelude's `IO.Console` to a module with no `main`

Reopened 2026-09-09. Originally filed 2026-09-03 and closed 2026-09-08; that
closure was wrong and its follow-up broke CI on `main`. Re-investigated
2026-09-10 with a red/green control — **still live at `de5444ec`** (current
`main`, including #428–#431).

## Minimal repro (three lines, any platform)

```march
mod P do
  fn add(a : Int, b : Int) : Int do a + b end
end
```

```
$ march --compile -o p.bin p.march
-- ERROR --
module `P` uses `IO.Console` but does not declare `needs IO.Console`.
```

`--no-cap-strict` makes it compile. The module never mentions console IO; the
charge comes from the injected prelude.

## What the 2026-09-09 write-up got wrong

The reopening recorded this as String-dependent, macOS-and-Linux, and specific
to `--report-contracts`. Measured 2026-09-10, **none of those three hold**:

- **Not String-dependent.** The repro above contains no `String`. The
  `Box(Int, Int)` vs `Box(Int, String)` pair that produced that conclusion also
  differed by a *second function*, which is the actual variable (below).
- **Not platform-specific.** It reproduces on macOS arm64 as readily as on
  Linux. The earlier "Linux-only" reading came from testing a module shape that
  does not trigger it on either platform.
- **Not `--report-contracts`-specific.** Plain `march --compile` fails
  identically. `forge fix --contracts` is merely the first caller that tripped
  over it.

## The actual discriminator: a function with no heap-typed signature

Measured with plain `march --compile`, same invocation for all three:

| module contents | result |
|---|---|
| `bump(b : Box) : Box` only | exit 0 |
| `bump(b : Box) : Box` + `add(a : Int, b : Int) : Int` | exit 1, ceiling |
| `add(a : Int, b : Int) : Int` alone | exit 1, ceiling |

A module whose only function takes and returns a heap type compiles clean.
Adding an ordinary scalar helper is enough to trigger the charge, and a scalar
helper on its own triggers it with nothing else in the module.

**Why that is so is NOT established.** Do not treat the table as a mechanism —
it is the reproduction condition, nothing more. Three separate attempts to
reason about this bug from the shape of the code reached three different wrong
conclusions; measure first.

## Blast radius (measured)

| path | uses | affected |
|---|---|---|
| `forge build` on a lib project | `--check` | **no** — `--check` on the repro exits 0 |
| `march --compile` on a main-less module | `--compile` | **yes** |
| `forge fix --contracts` | `march --compile --report-contracts` | **yes** (worked around) |

`--check` is clean on the exact module that `--compile` rejects, which is why
ordinary library development never sees this. It bites only paths that
genuinely compile a module with no `main`.

## How to reproduce the CI failure specifically

The guarding test is `forge/test/test_build_check.ml`'s `forge fix --contracts`
cases 0 and 2. Two things about running it:

- `scripts/run-tests.sh` does **not** run `forge/test/` at all, so a fully green
  local `run-tests.sh` says nothing here. Use `dune build @forge/test/runtest`
  (from a Claude worktree: `dune build --root . @forge/test/runtest`).
- The suite is already hermetic — `setup_hermetic_march ()` symlinks
  `%{bin:march}` onto PATH and empties `MARCH_HOME`, so it always exercises the
  freshly built compiler, not an installed toolchain. No dev-compiler shim is
  needed.

For a full CI-fidelity check, the Ubuntu leg reproduces locally in Docker at
native speed on an arm64 Mac (~19 min per cycle, no CI round trip):

```bash
git archive --format=tar <rev> -o /tmp/src.tar
docker run --rm -v /tmp:/host -w /tmp march-ci-ubuntu bash -c '
  cd /tmp && rm -rf t && mkdir t && cd t && tar xf /host/src.tar
  sed -i "s|march --compile --no-cap-strict --report-contracts|march --compile --report-contracts|" forge/lib/cmd_fix.ml
  opam exec -- dune build @forge/test/runtest'
```

Verified red at `db44fbb3` (2 failures / 20 tests — matching the CI failure that
`db44fbb3` produced) and red at `de5444ec` with the workaround removed. The
control mattering is the point: prove the harness goes red on a known-bad tree
before trusting any green.

## Original analysis (still current, still unverified)

`bin/main.ml`'s attribution already has machinery for exactly this
(`transparent_fns` marks stdlib-span top-level declarations see-through
precisely because `println$String`'s console use was being charged to the entry
module), plus a `Dce.prune_unreachable` `~extra_root` for the main-less case.
One of the two is not covering this shape.

Suggested first step: compare `stdlib_span_files` against the spans actually
carried by prelude declarations for a main-less module, and check whether the
`extra_root` branch in `Dce.root_names` (which only fires when no other root
exists) is reached at all here. Note the heap-vs-scalar discriminator above may
be a clue about which functions survive DCE as roots.

## Call-site workaround

`forge/lib/cmd_fix.ml` passes `--no-cap-strict` to
`march --compile --report-contracts`. That is a workaround, not a fix, and
should be removed once the attribution is corrected — but only together with a
green `@forge/test/runtest`, checked on Linux via the Docker recipe above.

**History, so this is not closed wrongly a third time.** The 2026-09-08 closure
re-ran a hand-written module, saw exit 0, removed the workaround, and turned
`main` red. The 2026-09-09 reopening then recorded a String dependence and a
platform dependence that further measurement did not support. Both errors have
the same root: a hand-written module that does not reproduce, treated as
evidence about a bug the guarding test does reproduce. The three-line repro at
the top of this file does reproduce; use it, and confirm through
`@forge/test/runtest` before touching the workaround.
