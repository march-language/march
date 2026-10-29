# `[P2]` `--refine-infer` skips programs that `--check` accepts, on stdlib errors it never shows

Filed 2026-10-29 from the second inference evaluation
(`specs/progress/2026-10-29-refine-infer-evaluation-2.md`).

`bin/main.ml` gates inference on `typed_ok = not (Errors.has_errors errors)`, taken over
EVERY diagnostic of the compile-path typecheck. The diagnostics printed afterwards are
filtered to user files (`user_diag`), and `--check` itself goes through `run_check_cmd`'s
seeded check. So a typecheck error located in a stdlib file is never printed, `--check`
exits 0, and `--refine-infer` prints only:

```
--refine-infer: skipped, the program has errors (fix them first)
```

The user has nothing to fix. The gate should read the same user-file condition that
`--check` uses (`has_user_errors`), or print the errors it gates on.

## Minimal repro

```march
mod Repro do
  type NodeInfo = { id : String, last_seen : Int }

  fn main() : Int do 0 end
end
```

- `march --check repro.march`: exit 0, no output.
- `march --check --refine-infer repro.march`: `--refine-infer: skipped, the program has errors`.

A debug build that prints the gated errors shows the error: it is in the stdlib, not the
user's program:

```
stdlib/cluster_node.march:2747 expected `NodeInfo` but got `NodeInfo`.
```

The same happens with `type Member = { … }` (also a `ClusterNode` record name), and when the
`NodeInfo` is in a nested module (`mod Inner do type NodeInfo = … end`). `type Request`,
`type Response`, `type ClusterOps` and `type Other` do not trigger it. `--compile` of the
repro succeeds, so the hidden error does not reach codegen. The underlying collision, where a
user record type with the same short name as a `ClusterNode` record breaks the stdlib's own
typecheck in the compile path, is a typechecker bug of its own. This item is the gate. Fixing
the gate alone would let inference run on a tree the typechecker considers ill-typed in the
stdlib part, so both need a look.

## Effect seen

- `~/code/conduit` defines `Conduit.NodeInfo` (`lib/conduit.march:461`). Every
  `forge refine --infer` run on conduit therefore reports all 45 files as "no inference", even
  with depot resolved and the cap errors fixed. Renaming the type (on a copy) is enough to make
  conduit infer.
- Checking a stdlib module as its own entry (`march --check --stdlib-source --refine-infer
  copy/option.march`) shadows the stdlib module, and the shadowed combined check reports
  hidden errors in `dataframe.march:1015` and `control.march:1253`. This blocks a per-module
  stdlib sweep through the obvious route.
