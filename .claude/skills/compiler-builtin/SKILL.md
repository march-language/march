---
name: compiler-builtin
description: Add a new builtin function to the March compiler (typechecker, interpreter, C runtime, LLVM codegen, and the tables and tests that must agree). Use when a March primitive needs a runtime implementation or an existing builtin needs a new backend.
---

# Add a compiler builtin

A builtin is a name the typechecker accepts with no March definition. The interpreter implements
it in OCaml, and compiled code calls a `march_*` C function in `runtime/`. One builtin touches
about a dozen places. Several of them are tables or tests far from the change, so a missed one
fails somewhere unrelated, or not at all until run time.

**Template commit:** `39918c418` (`observe_query`, 2026-10-04) adds one builtin end to end.
`git show 39918c418 -- lib/ runtime/ test/` is the shortest worked example.

## The sites, in order

### 1. Typechecker: `lib/typecheck/typecheck_builtins.ml`

- **`builtin_bindings`**: the type. `("foo", Mono (TArrow (t_string, t_string)))`.
- **`builtin_cap_table`**, if it performs IO: `("foo", "IO.FileRead")`. A missing row lets an
  IO builtin run in a module that declared no `needs`.
- **Stdlib-only?** If user code should reach it through a stdlib module, not by name, add it to
  `Typecheck_env.stdlib_only` (`lib/typecheck/typecheck_env.ml`) with the message naming that
  module, and to the list in `test/test_stdlib_only.ml`.

### 2. Interpreter: `lib/eval/eval_builtins.ml`

A `VBuiltin` entry. Interpreted and compiled must agree: the oracle (`test/test_oracle.ml`)
compares them. A facility only the compiled runtime has gets a loud `eval_error` naming the
compiled backend, never a silent no-op.

### 3. C runtime: `runtime/`

`march_foo` in the file that owns the area (`runtime/march_extras.c` for general helpers),
declared in its header. Allocate with the `march_*` alloc helpers, never raw `malloc`.

- **New `.c` file:** add one line to `runtime/sources.list` with its role, or
  `scripts/check-runtime-sources.sh` (CI) fails.
- **Returning structured data:** `make_tuple2`, `make_cons` and friends are `static` in
  `runtime/march_runtime.c`, so define the builtin there. The runtime builds tuples and cons
  cells, not records: return nested pairs and destructure them in March. Ints inside a tuple
  are tagged, `(v << 1) | 1`.
- **Same name as a C library symbol:** a top-level March fn named like a C-symbol builtin gets
  its own symbol (commit `185a6001e`); check yours does not collide with a libc name.

### 4. Codegen: `lib/tir/llvm_builtins.ml`

Two separate edits, and both are needed:

```ocaml
{ march_name = "foo"; c_name = Some "march_foo"; ret_ty = Some Tir.TString;
  in_is_builtin = true; declare_sig = Some "declare ptr  @march_foo(ptr %s)" };
(* ... and in the preamble list: *)
PDeclare "march_foo";
```

The row alone gives `use of undefined value '@march_foo'`. A builtin whose body codegen
generates (a `define`, not a C symbol) sets `declare_sig = None`: a `declare` plus a `define`
is an LLVM redefinition error.

`Builtin_table` (`lib/tir/builtin_table.ml`) is the union of these rows and `Builtin_name.all`.
It is the one answer to "is this callee a builtin". An unknown callee is a compile error, and
`--verify-tir` check 1 uses the same table.

**Only if the emitter needs a dedicated arm** (it can't be a plain C call): add a constructor to
`Builtin_name.t` (`lib/tir/builtin_name.ml`) and its `to_string`/`all` rows. The build then
fails until you extend every exhaustive match over the type: `builtin_group` in
`lib/tir/llvm_emit.ml`, and `named_builtin_allocates` / `named_builtin_retains` in
`lib/tir/alloc_contract.ml`.

### 5. Defun: `builtin_names` in `lib/tir/defun.ml`

Without it Defun treats the name as a closure: the call becomes `call_ptr` through a
`foo$clo_wrap` trampoline, which still runs but adds a reduction check and blocks inlining.

### 6. Borrowing: `extern_borrow_table` in `lib/tir/borrow.ml`

One `bool` per parameter: `true` if the C function only reads it. A missing row means every
heap argument is passed owned. If the C code does not release it, that is a leak per call.

```ocaml
("foo", [true]);   (* march_foo only reads its String *)
```

### 7. Purity: `impure_builtins` in `lib/tir/purity.ml`

IO, clock, randomness and mutation are impure. A missing entry lets the optimiser treat two
calls as one (two clock reads CSE'd into one).

### 8. Capabilities: `lib/caps/cap_symbols.ml`

A cap-bearing builtin needs `("march_foo", "IO.FileRead")` here as well.
`test/test_cap_symbols.ml`'s "no drift from builtin_cap_table" names any row you missed.

### 9. JS backend (optional): `lib/tir/js_emit.ml` + `runtime/march_runtime.mjs`

A builtin with no JS mapping is rejected when compiling `--target js`, which is a fine answer
for a native-only facility. Otherwise add the call arm and the runtime function.

### 10. Tests that move with it

- **`test/test_codegen.ml` `golden_preamble_*`:** the runtime preamble is pinned
  byte for byte, so your `declare` line goes into the golden.
- **`test/test_builtin_compiled_lowering.ml`:** every `builtin_bindings` name must be
  accounted for, as a codegen row, a `Builtin_name` constructor, the SIMD grid, a listed
  special lowering, or `interpreter_only` (which must equal
  `Lower_expr.interpreter_only_builtins`). An unaccounted builtin fails here.
- **`test/test_stdlib_only.ml`**, for a stdlib-only builtin (step 1).
- **A new `test/native/*.march` fixture** needs the refinement audit baseline regenerated in the
  same commit (`UPDATE_SNAPSHOTS=1 ./_build/default/test/test_refinecheck.exe test audit-baseline`).

## Verify

```bash
dune build --root . @test/stage-source-trees bin/main.exe   # restages runtime/ and stdlib/
./_build/default/bin/main.exe prog.march                    # interpreted
./_build/default/bin/main.exe --compile -o /tmp/prog prog.march && /tmp/prog
./_build/default/bin/main.exe --verify-tir --emit-llvm prog.march   # checks 1-5
./_build/default/bin/main.exe query fn main prog.march --at tir-defun   # `call`, not `call_ptr`
```

- **Restage after a runtime edit:** a targeted `dune build bin/main.exe` does not restage
  `runtime/`, so a C edit is not in the build until something with a runtime dependency builds.
- **Cache:** use a private `HOME`, or clear both `.march/cas/artifacts-v2/` and
  `~/.march/cas/artifacts-v2/`.
- **Leaks:** for a heap-returning builtin, a `live_allocs()` loop around the call should be flat
  compiled. `--rc-trace` names the site if it is not (see the `compiler-rc` skill).

## Finish

- Move the todo to `specs/progress/` (`git mv`), and add a `CHANGELOG.md` bullet if users see it.
- If users call it by name, add it to the builtins tables in the `march-lang` skill.
- Expose it through a stdlib module (`doc` with a `march>` example) if it is stdlib-only.
