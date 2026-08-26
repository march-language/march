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
