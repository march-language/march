# `.mli` files for the remaining interface-less modules

Landed 2026-08-27.

Finishes the pass begun in
[`2026-08-25-mli-interfaces-top-churn-files.md`](2026-08-25-mli-interfaces-top-churn-files.md)
(four files, PR #368a) and continued by the nine-module decomposition follow-up
(PR #368). Six more files now have an interface; one candidate was deliberately
skipped.

## What landed

One `.mli` per file, one commit each, **no `.ml` line moved and no call site
adjusted**. Where a value had a caller anywhere — including a test — it was
exposed and the interface says so; nothing was hidden by editing a consumer.

| File | Inferred vals | Curated vals | Internal |
|---|---:|---:|---:|
| `lib/typecheck/typecheck_env.ml` | 42 | 40 | 5% |
| `lib/typecheck/typecheck_types.ml` | 23 | 19 | 17% |
| `lsp/lib/analysis_util.ml` | 36 | 33 | 8% |
| `lib/tir/perceus.ml` | 36 | 25 | 31% |
| `lib/tir/mono.ml` | 21 | 14 | 33% |
| `lib/tir/llvm_builtins.ml` | 34 | 22 | 35% |
| `lib/tir/llvm_toplevel.ml` | 21 | 18 | 14% |
| **total** | **213** | **171** | **20%** |

20% against #368's 73% is the honest headline, and the split inside the table
explains it. See "What the numbers mean" below.

## Skipped, on purpose: `lsp/lib/analysis_types.ml`

302 lines, **zero `let` bindings** — twenty-odd record and variant declarations
and nothing else. An interface for it could only be a verbatim copy of every
one of those declarations, all necessarily manifest (`Code_actions_ast`,
`Code_actions_diag` and `Analysis` all pattern-match the fields), hiding
nothing and abstracting nothing, and requiring a lockstep edit on every field
added anywhere. That is pure cost. The file is left as it is.

## What the numbers mean

The table splits cleanly in two, and the reason is *when the file was written*,
not how carefully it was curated.

**The three extracted modules — `typecheck_env` (5%), `analysis_util` (8%),
`typecheck_types` (17%) — are supposed to be near zero.** They were lifted
verbatim out of their parents as coherent units within the last few days. They
never had time to accumulate accidental surface, so there is almost none to
remove. Manufacturing a reduction here would mean hiding something a sibling
reaches through an alias.

**The four older `lib/tir/` files (31–35%) are the ones with real rot,** and it
is the same shape every time: a private table plus its public accessor, both
exported. `llvm_builtins` alone had five `Hashtbl`s (`is_builtin_fn_tbl`,
`builtin_ret_ty_tbl`, `builtin_declare_sig_tbl`, `mangle_extern_tbl`,
`called_syms`) sitting in the public surface next to the five functions that
read them.

### The `include` hazard

`typecheck_env` and `typecheck_types` are `include`d by `typecheck.ml`;
`analysis_util` `include`s `analysis_types` and is itself `include`d by
`analysis.ml`, which has no interface of its own. For those, an `.mli`
restricts **what the parent re-exports** — a name dropped here vanishes from
`Typecheck.` or `Analysis.` and breaks a consumer two removes away, reached
through `let open` or a `Tc.` / `TC.` / `T.` / `An.` alias that no grep can
see. Curation there was deliberately minimal, and `dune build @check` (which
typechecks `test/` and `lsp/`) was the only oracle that could confirm it.

The four `lib/tir/` files are `include`d by nothing, which is most of why they
could be cut harder.

### Three values that are declared but are not API

Hiding a value that *nothing* mentions — not even its own file — makes it an
unused-value error under warnings-as-errors. Since this pass edits no `.ml`,
three had to be declared anyway, each with a comment saying so:

- `llvm_builtins.reserved_ctor_tag_limit`
- `llvm_toplevel.target_arch`
- `llvm_toplevel.emit_main_wrapper`

The last is worth a look. It is a real function body at
`lib/tir/llvm_toplevel.ml:725`, not a one-line re-export, and nothing calls it —
so the compiler emits its main wrapper by some other path. Compare
`march_println`'s `writev` path, dead for thirteen months behind a live-looking
declaration. #368 left the same class of note against three re-exports in
`lower.ml` and thirty-three in `llvm_emit.ml`.

### One counter that had to stay

`perceus.fresh_rc_var` is hidden but its counter `_rc_fresh_ctr` is exported:
`lower_state.ml` resets it and `test_snapshots.ml` depends on that reset to keep
the TIR golden snapshots deterministic across run order. The counter is API;
the generator is not.

## Verification

- `dune build @check` after **every** module: 17 errors throughout, the same 17
  pre-existing ones in `forge/test/` and `js/` from a missing optional opam
  dependency, never an 18th. Baselined before the first edit.
- `dune build bin/main.exe` after every module: exit 0.
- `scripts/ir-oracle.sh check` after each group: **IR IDENTICAL across 240
  programs**, every time. An `.mli` changes visibility, never emitted code.
- `scripts/run-tests.sh` and `scripts/check-docs.sh` at the end.

### An oracle trap worth recording

The first oracle check came back with a large-looking diff that was **not** an
IR change. Every `+` line carried a hash *identical* to the context line above
it: the manifest had 141 duplicated tags. Two other agents were running
concurrently against the same session scratchpad — one of them running
`ir-oracle.sh` itself, one running `main.exe --emit-llvm` with a *relative*
path — and the shared work directory was being written by both. The baseline
manifest was later truncated from 243 lines to 2 by the same interference.

Deduplicating both manifests and diffing showed them exactly equal, and a clean
re-run in a private directory (`/tmp/ir-<worktree-slug>`) reported IR IDENTICAL.

The lesson generalises: **give the IR oracle a private directory suffixed with
the worktree slug**, never the shared scratchpad. A hash-identical `+`/context
pair is the signature of manifest duplication, not of a refactor that moved
code — read the diff before believing the exit code.

## Follow-ups

- Delete the three dead values above together with their `val`s, plus #368's
  three in `lower.ml` and thirty-three in `llvm_emit.ml`.
- `lib/eval/eval.ml` and `bin/main.ml` remain the largest files with no
  interface.
