# `~/.cache/march` creation is not recursive — the stdlib caches silently disable themselves

**Filed:** 2026-08-26, at `cde69dfb`. Found while investigating an oracle for
`specs/plans/2026-08-19-compiler-file-decomposition.md` Phase 6. **Not fixed** —
this is a report, and the Phase 6 oracle works around it with `mkdir -p`.

## Symptom

On a machine (or under a `HOME` override) where `~/.cache` does not already
exist, **every** `march` invocation prints:

```
[warn] could not save the stdlib typecheck cache (Unix.Unix_error(Unix.ENOENT, "mkdir", "<HOME>/.cache/march")); stdlib will be re-typechecked on every invocation
```

and the stdlib is in fact re-parsed and re-typechecked on every invocation. The
warning is emitted on stdout/stderr *ahead of the program's own output*, so it
also corrupts anything that parses `march`'s output — including
`--emit-core-ast`, whose one-JSON-document contract becomes a warning line
followed by a JSON line.

## Reproduction

```bash
D=$(mktemp -d); mkdir -p "$D/home"          # note: no $D/home/.cache
HOME="$D/home" ./_build/default/bin/main.exe \
  --emit-core-ast specs/lang/types/accept/t07_generic_option_two_types.march | head -c 200
```

Measured: 177 bytes of warning prefix per invocation. With
`mkdir -p "$D/home/.cache"` instead, the output is byte-identical to a run under
the real (warm) `HOME`.

## Cause

`bin/main.ml` has four `Unix.mkdir` sites. One of them —
`ensure_runtime_so` at `bin/main.ml:872` — creates the chain properly:

```ocaml
  (* Create parent directories recursively *)
  List.iter (fun d ->
    try Unix.mkdir d 0o755
    with Unix.Unix_error (Unix.EEXIST, _, _) -> ()
  ) [dot_cache; cache_dir];
```

The other three — the stdlib **AST** cache (`:539`), the stdlib **typecheck-env**
cache (`:732`), and the site at `:1108` — create only the leaf:

```ocaml
  (try Unix.mkdir cache_dir 0o755
   with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
```

`Unix.mkdir` is not recursive, and only `EEXIST` is caught, so `ENOENT` on the
missing `~/.cache` parent escapes to the enclosing handler and disables the
cache.

## Fix

Apply `ensure_runtime_so`'s two-element `List.iter` idiom at all three sites (or
factor it into one `ensure_cache_dir ()` helper and call it from all four —
that is the better shape, since there are now four copies of the same intent).

## Why it has gone unnoticed

`~/.cache` exists by default on essentially every developer machine and on the
CI runners, so the only people who hit it are agents and scripts using a private
`HOME` for cache hygiene — which `scripts/refine-oracle.sh` already does, and
`scripts/types-oracle.sh` (Phase 6, Task 6.1) will.

## Severity

Low but not zero: a spurious warning on every invocation, a multi-second
per-invocation cost, and output corruption for `--emit-core-ast` and
`--check-json` consumers.

---

# Fixed 2026-08-27

Landed alongside Target A of
`specs/plans/2026-08-27-remaining-decomposition-targets.md`.

## The fix

One helper, `Toolchain.mkdir_p`, replaces all four sites. It creates the whole
parent chain and ignores `EEXIST` (the cache dir is shared across concurrent
sessions, so two racing processes must both succeed); any other error is still
left to the caller's handler, so a directory that genuinely cannot be created
degrades to "no cache" rather than crashing.

Three of the four sites had the broken leaf-only `Unix.mkdir`; the fourth
(`ensure_runtime_so`) had a correct but hand-rolled two-element `List.iter`,
and now calls the helper too — the report's preferred shape, since there were
four copies of one intent. After the change `grep -n 'Unix.mkdir' bin/` matches
exactly one line: `mkdir_p`'s own.

Two of the sites moved to `bin/toolchain.ml` in task A1; `get_stdlib_tc_env`'s
stayed in `bin/main.ml` and reaches the helper through `open Toolchain`.

## Verification, and the trap that made the first three attempts vacuous

A naive before/after (fresh `HOME`, run twice) is **not** a valid test here, and
three consecutive attempts at it produced confidently wrong readings.

The worktree-local `.march/cas` (`vc` especially) short-circuits the stdlib path
entirely on any run after the first, so a second invocation costs ~0.08s and
writes nothing **whether or not the fix is present**. Worse, the "first run
after a rebuild" is the only run that exercises the path at all, so the outcome
depended on whether the probe happened to follow a rebuild — which made the fix
look present in the pre-fix binary and absent in the post-fix one, in different
orderings.

The valid probe clears `.march/cas/vc` and `.march/cas/artifacts-v2` **and** uses
a fresh `HOME` with no `.cache`. Under those controlled conditions, with only the
binary differing:

| | run 1 | run 2 | files in `~/.cache/march` | run-1 stderr |
|---|---:|---:|---:|---|
| before | 1.40s | 0.08s | **0** | 185 B warning |
| after  | 1.31s | 0.08s | **2** | 0 B |

The 185 bytes are exactly the reported warning, naming `ENOENT`, `mkdir` and the
missing path. After the fix both blobs (`stdlib_ast_*.bin`,
`stdlib_tcenv_cli_*.bin`) are written and the run is silent.

## One correction to the report

The report says the warning "corrupts anything that parses `march`'s output —
including `--emit-core-ast`, whose one-JSON-document contract becomes a warning
line followed by a JSON line". Measured: the warning goes to **stderr**, and
`--emit-core-ast`'s stdout alone parses as valid JSON both before and after the
fix. The corruption is real but scoped to consumers that merge the two streams
(`2>&1`) — which is what `scripts/types-oracle.sh` does, and why it carries the
`mkdir -p "$DIR/home/.cache"` workaround.

The "multi-second per-invocation cost" is likewise not observable on the
`--check` path used above, because the repo-local CAS masks it after the first
run. What is demonstrably fixed: the warning, the merged-stream corruption, and
the caches actually being created and populated instead of silently disabled.

The `scripts/types-oracle.sh` workaround is now unnecessary, but is deliberately
left in place — it is harmless, and removing it would make the script depend on
a compiler new enough to contain this fix.
