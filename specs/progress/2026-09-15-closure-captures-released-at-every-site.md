# A capturing lambda's environment is released at every site, not just inside its apply function

**Landed 2026-09-15.** Closes items 2 and 3 of
`specs/todos/2026-09-06-closure-capture-release-widening.md` and the two
leftovers named in
`specs/progress/2026-09-14-closure-calls-consume-their-arguments.md`.

## The defect

```march
let xs = List.map([int_to_string(n), "ab"], fn s -> string_length(s) + k)  -- 1 object per call
let step = fn (a, b) -> a + b + List.length(ys)
List.fold_left(ys, 0, step)                                               -- 3 objects per call
```

Measured on `origin/main` ed7af146c, Darwin arm64, `--compile --opt 2`, over
10,000 iterations: `map` and `filter` over a capturing lambda leaked exactly one
object per call, a local closure handed to `fold_left` leaked three. Two
independent sites, both releasing a closure environment shallowly.

### 1. The HOF's own loop released through an alias

`List.map`/`List.filter` build an internal `go` closure over the callback and
call it recursively. Perceus binds `$clo` to a local alias with a dup
(`let go = inc_rc $clo; $clo`), hands `go` down the recursion, and splices its
`dec_rc $clo` after the capture-read prefix. `Drop.rewrite_apply_clo_drop`
rewrote *that* release into `march_decrc_freed` — but with the dup outstanding
it never reaches zero, so the guarded capture releases never fired. The release
that does reach zero is the last iteration's `dec_rc go`, and it was shallow.

### 2. The outer release of a closure VALUE

`List.fold_left` ends with `dec_rc f`. That is a bare release of a closure
value, whose TIR type is a function type — which names no layout, and one
function type admits many closure shapes. `Drop`'s module doc had this as the
open case: *"resolving it would need a runtime table keyed by the code pointer
in field 0"*. That is what landed.

## What landed

- **`lib/tir/drop.ml`, `rewrite_apply_clo_drop`**: the self-binding alias's
  release is rewritten the same way as `$clo`'s. Both become
  `march_decrc_freed`, and only one of them can reach zero, so exactly one
  guard fires.
- **`lib/tir/drop.ml`, `synth_clo_drop`**: one `__drop_clo$<Clo>` per closure
  type whose environment owns its captures, reading each capture out of the
  cell and releasing it. Gated on the same `owning_clo_types` verdict as the
  apply-function side — releasing a BORROWED capture is a double free.
- **`lib/tir/clo_drops.ml`** (new): carries the (apply fn, drop fn) pairs from
  `Drop` to `Llvm_toplevel`, which emits a constructor registering them with
  the runtime. A constructor rather than a call from `main`, because the same
  module is also linked as a shared object and as a hot-reload patch.
- **`runtime/march_runtime.c`**: `march_register_clo_drop` / `march_drop_closure`
  — a pointer-keyed table, and a release that runs the drop before the cell's
  own decrement when that decrement is the last one.
- **`lib/tir/llvm_emit.ml`**: an `EDecRC` of a function-typed value emits
  `march_drop_closure`.
- **`lib/tir/dce.ml`**: a closure's deep drop is reachable exactly when the
  apply function of its closure is.

## Two things this cost, both caught by tests

- **Rewriting the release in TIR forced closures onto the heap.** A call in the
  TIR makes its argument escape, so a stack-promoted environment was heap
  allocated again and `@[no_alloc]` functions stopped compiling
  (`alloc_contract` case 20). Hence the emission-time rewrite: the TIR keeps the
  bare `EDecRC` it always had.
- **Rooting the drops through `tm_exports` silenced the capability ceiling.**
  `Dce.root_names` applies its caller-supplied roots only when nothing else
  rooted the module, so an export made a main-less module look like it had an
  entry point and its own capability use stopped being charged
  (`cap_ceiling` case 15). The DCE rule above replaced the rooting; it also
  keeps the binary honest, emitting 6 drops for the probe instead of 2,455.

## Not closed here

- A closure released by the C runtime itself (the fold/map helpers'
  `march_decrc(f)`) is still shallow. It could call `march_drop_closure`; not
  done here because those helpers' closure arguments are also reachable from
  the caller, and the ownership there wants its own measurement.
- `clo_call_dbl_dbl` / `clo_call_dbl_dbl_dbl` still leak a Float box per call.
- The REPL/JIT registers nothing (ORC does not run module constructors), so it
  keeps the shallow release. Leak, never a double free — the direction every
  unregistered path degrades in.

## Verification

- `test/native/closure_capture_outer_release_probe.march`: 6 legs — `map` and
  `filter` over a capturing lambda, a closure value released by a fold, one
  dropped unapplied, one inside a constructor, and one whose capture is read on
  every call (an over-eager release shows up as a wrong number, not a leak).
  Flat over 5,000 iterations; the golden matches the interpreter.
- **RED controls**, each half reverted with the other in place, on the fixture:

  | alias release deepened | runtime table | legs not flat |
  |---|---|---|
  | no  | no  | map, filter, fold, unapplied |
  | yes | no  | fold, unapplied |
  | no  | yes | — |
  | yes | yes | — |

  So the table subsumes the alias rewrite for compiled code, and the alias
  rewrite is what covers the REPL/JIT, where no constructor runs and nothing is
  registered. Reverting it alone therefore shows no red; the second row is its
  evidence.
- **ASAN** (linux/arm64 container): `sanitize.sh` 47 golden + 25 native clean,
  plus 14 native programs 3 runs each — including `node_discovery`, the fixture
  whose guard-page crash is why this pass's gate exists, and `actor_enumeration`.
- Local: full `@test/runtest` and `scripts/run-tests.sh` green.
- **Benchmarks** (compiled `--opt 2`, interleaved against `origin/main`
  ed7af146c, 5 timed rounds, load ~9): `list_ops` 0.069 s vs 0.069 s,
  `tree_transform` 0.648 s vs 0.655 s, `binary_trees` 0.225 s vs 0.224 s;
  outputs byte-identical.
- Emitted code: 6 drop functions and 6 registrations for the fixture. Rooting
  them through `tm_exports` instead emitted 2,455.
