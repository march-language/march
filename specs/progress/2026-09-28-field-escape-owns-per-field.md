# `field_escape_owns` decides per FIELD, not per TYPE (DONE, 2026-09-28)

**Filed:** 2026-09-03 as `specs/todos/2026-09-03-field-escape-owns-is-per-type-not-per-field.md`.
**Closed:** 2026-09-28.

## What changed (`lib/tir/borrow.ml`)

`field_escape_owns` marked a parameter OWNED as soon as any field extracted from
it met an owning use. Since 2026-09-03 it skipped variants whose every field is a
scalar (`_scalar_only`), but a MIXED type still lost: the `Int` in
`Node(Int, Tree, Tree)` meeting `+` owned the whole tree.

1. **Per-field resolution.** `ctor_field_is_scalar scrut_ty ctor n i` answers
   "is field `i` of constructor `ctor` a scalar" from the scrutinee's
   `TCon (name, args)` and the module's `TDVariant` declarations (the `br_vars`
   themselves carry a placeholder type). A declaration's type variables are
   bound to `args` in first-appearance order, the rule
   `Llvm_toplevel.build_ctor_info` uses for codegen's `type_params`, so
   `Cell(a)`'s `a` field is scalar under `Cell(Int)` and not under
   `Cell(String)`. It stays conservative ("not scalar") for a non-`TCon` or
   unknown scrutinee type, an unknown constructor, an arity or argument-count
   mismatch, and a short type name declared more than once unless EVERY
   declaration agrees. `field_escape_owns` now skips a binder whose field is
   scalar; everything else is unchanged.
2. **`has_matching_alloc` recognises TRMC's `EAllocHole`.** The FBIP
   "reconstruct" detector only saw `EAlloc`. TRMC'd producers such as
   `append`-shaped `Nil -> ys` / `Cons(h, f(t, ys))` over an `Int` list had
   stayed owned only because their `Int` head counted as an escaping field;
   with (1) they became borrowed and lost `reuse_hole`'s in-place cell reuse.
   A hole allocation of the scrutinee's type is the same reconstruct shape
   (Perceus_fbip pairs it with the scrutinee's drop), so it now keeps the
   parameter owned.

## Measurements

Same-box A/B: a compiler built from origin/main (`lib/` identical to 14ec3b71f)
vs this branch, same stdlib and runtime, compiled `--opt 2`, 7 alternating runs,
min. Load average 10-14 (other sessions). Outputs identical in every case.

| program | origin/main | this change |
|---|---:|---:|
| the todo's shape: `tsum` over a shared `Node(Int, Tree, Tree)` of depth 16, x300 | 0.296 s | **0.108 s** |
| `List.sum_int` + `List.fold_left` + `List.nth` over one shared 10k `List(Int)`, x3000 | 0.457 s | **0.367 s** |
| `bench/tree_transform.march` | 0.728 s | 0.728 s |
| `bench/list_ops.march` | 0.084 s | 0.084 s |
| `bench/binary_trees.march` | 0.244 s | 0.246 s |
| `bench/list_producers.march` | 0.543 s | 0.543 s |

`tsum(t:own)` became `tsum(t:borrow)`: a borrowed reader of a shared structure pays
no inc/dec per node, which is where the time went.

Static, over the 48 `bench/` programs (`--emit-llvm --opt 2`, each program's
reachable stdlib included, so shared stdlib functions count once per program):
2,034 parameter slots move from owned to borrowed (854,422 -> 852,388 owned),
static `march_decrc` calls 8,324 -> 8,277 and `march_incrc` 4,642 -> 4,629. The
todo's suggested instrument, byte-array stack cells (`alloca [N x i8]`), is 0 in
both builds across `bench/`: a cell that still holds a heap field (the `Tree`
beside the `Int`) is not a stack-promotion candidate, so this change does not add
any. The flips are readers: `List.fold_left`/`sum`/`nth`/`head`/`member`/`any`/
`all` over `Int` lists, `Option.unwrap_or` over `Option(Int)`, `Stats.*` and the like.

A known cost, not measured as a regression: when a borrowed scrutinee's scalar
field is used at an owning position, Perceus still emits `inc_rc` on the extracted
field (its binder has the placeholder type), which is a runtime no-op on a tagged
`Int` but a call. Giving Perceus the same per-field answer would remove it.

## Tests

- `test/test_eval.ml` `borrow_inference`: a mixed type's scalar-only field escape
  stays borrowed (RED on origin/main); a heap field escape still owns; a
  type-parameter field is resolved through the scrutinee's arguments (RED on
  origin/main); a TRMC'd append over `List(Int)` keeps `xs` owned in the entry
  and `$dps` helper (RED with (1) but without (2)).
- TIR snapshots regenerated: `nested_generic_adt` and `no_wildcard_panic`
  (`head_opt`/`unwrap_or_die` over `Int` payloads are now borrowed: the callee's
  `dec_rc` moves to the caller). `scrutinee_borrowed_conservatism` now uses
  `List(String)`: over `List(Int)` its scrutinee became borrowed, so it no longer
  pinned the owned-scrutinee Perceus path it exists for; with `String` its
  Perceus output has the same structure as before.
- `scripts/run-tests.sh` (full): passes. `run_snapshots`: 45/45.
- ASAN sweep in a Linux container (arm64, `MARCH_SANITIZE=1`, `detect_leaks=0`) over
  284 programs (`bench/`, `test/native/` minus JS, FFI and network programs, plus
  the probes above): **0 memory-safety errors**. Non-zero exits were all explained:
  three `*_panic` fixtures and `topology_hook_timeout` exit 1 by design,
  `array_sort` was killed under 6-way parallel ASAN and passes alone, and
  `sched_stress` passes without ASAN but under it cannot map shadow memory for its
  green-thread stacks (errno 12), even run alone.
- `dune build @test/oracle`: 2 un-triaged MISMATCHes, `bench/array_numeric.march`
  and `bench/simd_f32.march`. Both print wall-clock timings; with the timing lines
  removed, interpreter and compiled output are identical for both. They are
  missing from `test_oracle.ml`'s `nondeterministic_allowlist`, and show up whenever
  the interpreter finishes inside the oracle's timeout; not this change.
