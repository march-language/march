# Interpreter FFI: even `Int` arguments were dropped as if they were heap pointers

Landed 2026-08-03.

## Symptom

Any March program calling an `extern` under the **interpreter** crashed with
SIGSEGV inside `march_decrc` as soon as it passed an `Int` argument that was
even and `>= 4096`.

It surfaced as "`forge test --coverage` breaks when tests enter FFI-backed file
operations" (reported against `~/code/mgrep`), because:

- `forge test --coverage` forces the interpreter path (`forge/lib/cmd_test.ml`
  gates on `coverage || MARCH_TEST_INTERPRETER=1`), and
- file-I/O externs are exactly the ones that pass large even integers — chunk
  sizes (`4096`, `65536`, `131072`, `262144`) and `FILE*` handles cast to
  `Int`.

Coverage instrumentation was **not** involved. The identical crash reproduced
with `MARCH_TEST_INTERPRETER=1 forge test` and no `--coverage` flag at all.

## Root cause

`dynamic_ffi_call` (`lib/eval/eval.ml`) marshalled each argument to an
`int64` march_value, then, after the call, decided which arguments to release
by **inspecting the marshalled bit pattern**:

```ocaml
List.iter (function
  | `GP i when Ffi_marshal.is_heap i -> Ffi_marshal.drop i
  | _ -> ()) classified;
```

`Int`/`Char`/`Bool` parameters are marshalled `Raw`, i.e. untagged — the word
handed to C is the integer itself. `Ffi_marshal.is_heap` is just
`v <> 0 && v land 1 = 0`, so every even non-zero `Int` argument was
indistinguishable from a pointer and was passed to `march_drop`, which
dereferenced the integer as an RC header.

The runtime's `IS_HEAP_PTR` (`runtime/march_runtime.h`) additionally requires
`>= 4096`, which is why small even arguments survived — and why the existing
`test/native/ffi_interp_shim.march` fixture (`shim_add(3, 4)`,
`shim_mul(6, 7)`) passed **vacuously** while never exercising the bug.

It also explains why one extern in mgrep worked and another didn't:
`mgrep_simd_contains_case`'s only `Int` parameter is an `ignore_case` flag that
is always `0` or `1` (zero, or odd) — it can never trip the predicate.

## Fix

Track ownership at marshal time instead of re-deriving it from the bits.

- New `ffi_marshal_owns : ty -> value -> bool` mirrors `ffi_marshal_iv`'s
  allocation cases: scalars (`Int`/`Char`/`Bool`/`Float`/`Unit`) own nothing;
  niche `Option` inherits its payload's ownership; `VResource` is owned
  (it is `dup`'d on the way in); everything else that marshals successfully
  allocates.
- `classify_arg` now returns `` `GP of int64 * bool `` carrying that flag, and
  the cleanup loop drops only owned references. The `is_heap` test is retained
  as a defensive second gate but is no longer what makes the code correct.

## Tests

`test/native/ffi_interp_shim.march` / `.expected` gained three cases that fail
(SIGSEGV) before the fix and pass after:

```
shim_add(65536, 1)      -> 65537
shim_mul(4096, 2)       -> 8192
shim_add(65536, 65536)  -> 131072
```

The values are chosen to sit above the runtime's 4096 `IS_HEAP_PTR` floor,
which the pre-existing `3/4/6/7` cases did not.

## Verification

- New fixture: SIGSEGV before, clean diff after.
- Full compiler suite green: 627 + 256 + 540 + 782 = 2205 tests, 0 failures.
- `~/code/mgrep`, same command / env / cwd, only the binary differs:

  | binary | result |
  | --- | --- |
  | `~/.march/versions/local-main/bin/march` (pre-fix) | exit 139 SIGSEGV after 28 tests |
  | this worktree's build | exit 0, **204/204 passed** |

### Apparatus note — cost most of the session

`forge` resolves its compiler through `~/.march/current`, *not* `PATH`:
`Toolchain.path_prefix` prepends the resolved toolchain's bin dir, which
overrides any ambient PATH shim. So `forge test --coverage` kept failing
deterministically at test 28 long after the fix, while every direct invocation
of the fixed binary passed — it was still running the previous day's installed
binary. Coverage, property tests, symlink resolution and `MARCH_LIB_PATH` were
each eliminated as hypotheses before the actual cause (binary mtime) was
checked.

**If `forge` and a direct invocation disagree deterministically, diff the two
binaries before bisecting anything else.** To point forge at a dev build:
`MARCH_HOME=<empty-dir> PATH=<shim>:$PATH forge …`, where the shim is a
cd-wrapper into the worktree (not a symlink).

## Note left open

The coverage reporter prints a nonsensical `Expressions: 2095 / 430 (487.2%)`
for mgrep — the hit numerator counts spans from `lib/` and stdlib while the
denominator counts only the target test file. Cosmetic, unrelated to this
crash, filed separately.
