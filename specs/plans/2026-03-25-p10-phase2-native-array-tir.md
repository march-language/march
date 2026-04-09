# P10 Phase 2 — NativeArray Flat Type in TIR + LLVM Emit

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `TNativeArray of ty` to the TIR type system and lower `NativeArray` builtins to vectorizable LLVM IR loops, enabling LLVM's auto-vectorizer to process numeric arrays at 4–8× compiled performance over the current interpreter fast path.

**Architecture:** Phase 1 (done) added interpreter builtins `VNativeIntArr`/`VNativeFloatArr` backed by flat OCaml arrays, wrapped in `stdlib/native_array.march`. Phase 2 extends the TIR and LLVM emission so `--compile` produces GEP-based load/store loops with vectorization hints. The runtime gains `march_native_arr_alloc` (32-byte aligned via `posix_memalign`) and the clang invocation switches from `-msse4.2` to `-mavx2` to unlock 256-bit vector registers.

**Tech Stack:** OCaml 5.3.0 (compiler), LLVM IR (textual), C11 (runtime allocator)

**Dependencies:** Monomorphization must resolve `NativeArray(Int)` / `NativeArray(Float)` to concrete `TNativeIntArr` / `TNativeFloatArr` before LLVM emit.

---

## Diagnosis

Currently, `NativeArray` builtins exist only in the interpreter (`eval.ml`). When compiling with `--compile`, calls to `native_int_arr_make`, `native_float_arr_sum`, etc. either fail at link time (unresolved symbols) or fall through to generic `@march_alloc` + boxed field layout. This means:

1. No flat memory layout — elements are boxed `i64`/`double` behind `ptr` indirection
2. No vectorization — LLVM sees pointer-chasing loops, not contiguous memory scans
3. No alignment guarantees — `march_alloc` uses `malloc` (8-byte aligned), not `posix_memalign` (32-byte for AVX2)

The fix threads a new `TNativeIntArr`/`TNativeFloatArr` type through TIR → mono → LLVM emit, with dedicated `ENativeArrayOp` expression nodes that lower to tight counted loops with vectorization metadata.

---

## File Map

| File | Change |
|---|---|
| `lib/tir/tir.ml` | Add `TNativeIntArr \| TNativeFloatArr` to `ty`; add `ENativeArrayOp` to `expr` |
| `lib/tir/lower.ml` | Recognize `native_*_arr_*` calls in `lower_expr`; emit `ENativeArrayOp` nodes |
| `lib/tir/mono.ml` | Pass-through for new types (already monomorphic, no type vars) |
| `lib/tir/perceus.ml` | RC rules for native arrays: single `EDecRC` frees the flat buffer |
| `lib/tir/llvm_emit.ml` | `is_builtin_fn` list + `builtin_ret_ty`; `emit_native_arr_op` for GEP loops with `!llvm.loop.vectorize.enable` metadata; `march_native_arr_alloc` extern declaration |
| `runtime/march_heap.h` | Declare `march_native_arr_alloc(i64 elem_count, i64 elem_size)` |
| `runtime/march_heap.c` | Implement `march_native_arr_alloc` using `posix_memalign(..., 32, ...)` |
| `bin/main.ml` | Change clang flag from `-msse4.2` to `-mavx2` (or `-march=native`) |
| `bench/array_numeric.march` | Add `--compile` timing comparison |
| `specs/optimizations.md` | Update P10 Phase 2 status to "done" |
| `specs/todos.md` | Move P10 Phase 2 to Done |
| `specs/progress.md` | Add NativeArray LLVM emit to feature list |

---

## Task 1: Add `TNativeIntArr` / `TNativeFloatArr` to TIR type system

**Files:**
- Modify: `lib/tir/tir.ml`

### Why
All downstream passes (mono, perceus, llvm_emit) pattern-match on `Tir.ty`. Adding dedicated type constructors — rather than encoding as `TCon("NativeIntArr", [])` — gives each pass a clear match arm and avoids string comparisons.

### Steps

- [ ] Add two new constructors to the `ty` type:
  ```ocaml
  | TNativeIntArr                    (* flat int array, 32-byte aligned *)
  | TNativeFloatArr                  (* flat float array, 32-byte aligned *)
  ```
- [ ] Add `native_arr_op` type to represent the 9 operations per element type:
  ```ocaml
  type native_arr_op =
    | NAMake | NALength | NAGet | NASet
    | NASum | NAMap | NAFold
    | NAFromList | NAToList
  [@@deriving show]

  type native_arr_elem = NAInt | NAFloat
  [@@deriving show]
  ```
- [ ] Add `ENativeArrayOp` to the `expr` type:
  ```ocaml
  | ENativeArrayOp of native_arr_elem * native_arr_op * atom list
  ```
- [ ] Run `dune build` — fix any exhaustiveness warnings in downstream passes by adding `| TNativeIntArr | TNativeFloatArr -> ...` and `| ENativeArrayOp _ -> ...` stubs that raise `failwith "TODO: NativeArray"`.

### Verification
```
dune build   # must compile clean, no warnings
```

---

## Task 2: Lower `native_*_arr_*` calls to `ENativeArrayOp` nodes

**Files:**
- Modify: `lib/tir/lower.ml`

### Why
The lowering pass converts `EApp(native_int_arr_sum, [arr])` into `ENativeArrayOp(NAInt, NASum, [arr])`. This separates the "what operation" from the "how to emit it" concern — LLVM emit only sees structured ops, not string-named builtins.

### Steps

- [ ] Add a helper to recognize native array builtin names and return `(native_arr_elem * native_arr_op) option`:
  ```ocaml
  let classify_native_arr_builtin name =
    match name with
    | "native_int_arr_make"      -> Some (Tir.NAInt, Tir.NAMake)
    | "native_int_arr_length"    -> Some (Tir.NAInt, Tir.NALength)
    | "native_int_arr_get"       -> Some (Tir.NAInt, Tir.NAGet)
    | "native_int_arr_set"       -> Some (Tir.NAInt, Tir.NASet)
    | "native_int_arr_sum"       -> Some (Tir.NAInt, Tir.NASum)
    | "native_int_arr_map"       -> Some (Tir.NAInt, Tir.NAMap)
    | "native_int_arr_fold"      -> Some (Tir.NAInt, Tir.NAFold)
    | "native_int_arr_from_list" -> Some (Tir.NAInt, Tir.NAFromList)
    | "native_int_arr_to_list"   -> Some (Tir.NAInt, Tir.NAToList)
    (* float variants *)
    | "native_float_arr_make"      -> Some (Tir.NAFloat, Tir.NAMake)
    (* ... all 9 float variants ... *)
    | _ -> None
  ```
- [ ] In the `EApp` lowering branch, check `classify_native_arr_builtin` before the generic call path. If matched, emit `ENativeArrayOp(elem, op, lowered_args)`.
- [ ] Add return-type mapping: `NASum` with `NAInt` → `TInt`, `NASum` with `NAFloat` → `TFloat`, `NAMake`/`NAMap`/`NASet`/`NAFromList` → `TNativeIntArr`/`TNativeFloatArr`, `NALength`/`NAGet` → `TInt`/`TFloat`, `NAToList` → `TCon("List", [...])`, `NAFold` → context-dependent.
- [ ] Run `dune build`.

### Verification
```
dune build   # clean compile
```

---

## Task 3: Thread new types through monomorphization and Perceus

**Files:**
- Modify: `lib/tir/mono.ml`
- Modify: `lib/tir/perceus.ml`

### Why
`TNativeIntArr`/`TNativeFloatArr` are already monomorphic (no type parameters), so mono is a pass-through. Perceus needs to know that native arrays are heap-allocated single-owner values: `EDecRC` on a native array calls `march_native_arr_free` (or the standard `free`).

### Steps

- [ ] **mono.ml**: In the type substitution function, add pass-through arms for `TNativeIntArr`/`TNativeFloatArr` (they contain no type variables). In the expression walk, add a recursive arm for `ENativeArrayOp` that walks its atom list.
- [ ] **perceus.ml**: Add `ENativeArrayOp` to the expression walker. The RC rules:
  - `NAMake` / `NAMap` / `NAFromList` / `NASet` — result is a fresh allocation, gets RC=1
  - `NAGet` / `NALength` / `NASum` / `NAFold` — reads from array, no new allocation (scalar result)
  - `NAToList` — allocates a new List, the array argument's RC is decremented after conversion
  - For the array argument in all ops: it's consumed (dec after use) unless the op is read-only (`NAGet`, `NALength`, `NASum`, `NAFold`), in which case it's borrowed
- [ ] Run `dune build`.

### Verification
```
dune build   # clean compile, no exhaustiveness warnings
```

---

## Task 4: Runtime allocator — `march_native_arr_alloc` / `march_native_arr_free`

**Files:**
- Modify: `runtime/march_heap.h`
- Modify: `runtime/march_heap.c`

### Why
AVX2 vectorization requires 32-byte aligned memory. The standard `march_alloc` uses `malloc` which only guarantees 16-byte alignment on macOS. A dedicated allocator uses `posix_memalign` for 32-byte alignment and stores the element count in a header for bounds checking.

### Layout

```
NativeArray memory layout (32-byte aligned):
  offset  0 : i64  rc           (reference count)
  offset  8 : i64  length       (element count)
  offset 16 : i64  elem_size    (bytes per element: 8 for both int and double)
  offset 24 : i8   padding[8]   (align data to 32 bytes)
  offset 32 : T[]  data         (contiguous elements, 32-byte aligned)

Total header = 32 bytes. Data starts at a 32-byte boundary.
```

### Steps

- [ ] In `runtime/march_heap.h`, declare:
  ```c
  void* march_native_arr_alloc(int64_t elem_count, int64_t elem_size);
  void  march_native_arr_free(void* arr);
  int64_t march_native_arr_length(void* arr);
  void*   march_native_arr_data(void* arr);  /* returns ptr to data region */
  ```
- [ ] In `runtime/march_heap.c`, implement:
  - `march_native_arr_alloc`: compute `32 + elem_count * elem_size`, call `posix_memalign(&ptr, 32, total)`, write header fields, `memset` data region to zero, return ptr.
  - `march_native_arr_free`: just `free(arr)` (posix_memalign memory is free-compatible).
  - `march_native_arr_length`: read `*(int64_t*)(arr + 8)`.
  - `march_native_arr_data`: return `(char*)arr + 32`.
- [ ] Run `dune build` to ensure the runtime compiles.

### Verification
```
dune build   # runtime .o files compile
```

---

## Task 5: LLVM emission — register builtins and emit `ENativeArrayOp`

**Files:**
- Modify: `lib/tir/llvm_emit.ml`

### Why
This is the core of Phase 2 — turning `ENativeArrayOp` nodes into LLVM IR that LLVM's auto-vectorizer can process. The key operations are `NASum`, `NAMap`, and `NAFold`, which emit counted `for` loops with `!llvm.loop.vectorize.enable` metadata.

### Steps

- [ ] **Register builtins**: Add all 18 `native_*_arr_*` names to `is_builtin_fn`. Add return types to `builtin_ret_ty`.

- [ ] **Add extern declarations** to the preamble:
  ```llvm
  declare ptr  @march_native_arr_alloc(i64 %count, i64 %elem_size)
  declare void @march_native_arr_free(ptr %arr)
  declare i64  @march_native_arr_length(ptr %arr)
  declare ptr  @march_native_arr_data(ptr %arr)
  ```

- [ ] **Emit `NAMake`**: Call `@march_native_arr_alloc(count, 8)`, then emit a loop to fill each element with the init value via GEP + store.

- [ ] **Emit `NALength`**: Call `@march_native_arr_length(arr)` → `i64` result.

- [ ] **Emit `NAGet`**: Call `@march_native_arr_data(arr)`, GEP to `data + i * 8`, load.

- [ ] **Emit `NASet`**: Allocate a new array (`@march_native_arr_alloc`), memcpy from old, store new value at index. (Functional update — immutable semantics.)

- [ ] **Emit `NASum`** (the vectorization target):
  ```llvm
  ; Get data pointer and length
  %data = call ptr @march_native_arr_data(ptr %arr)
  %len  = call i64 @march_native_arr_length(ptr %arr)

  ; Accumulator loop
  br label %sum.header
  sum.header:
    %i   = phi i64 [0, %entry], [%i.next, %sum.body]
    %acc = phi double [0.0, %entry], [%acc.next, %sum.body]  ; or i64 0 for int
    %cmp = icmp slt i64 %i, %len
    br i1 %cmp, label %sum.body, label %sum.exit, !llvm.loop !1
  sum.body:
    %ptr = getelementptr double, ptr %data, i64 %i
    %val = load double, ptr %ptr, align 8
    %acc.next = fadd double %acc, %val    ; or add i64 for int
    %i.next   = add i64 %i, 1
    br label %sum.header
  sum.exit:
    ; %acc is the result

  ; Vectorization hint metadata
  !1 = !{!1, !2}
  !2 = !{!"llvm.loop.vectorize.enable", i1 true}
  ```

- [ ] **Emit `NAMap`**: Allocate output array, loop over input with GEP load → call closure → GEP store into output. Add vectorization metadata. Closure calls prevent full vectorization but the loop structure still benefits from LLVM's unrolling.

- [ ] **Emit `NAFold`**: Loop with accumulator phi, calling the closure each iteration. No vectorization metadata (closure call is opaque to LLVM).

- [ ] **Emit `NAFromList`**: Call a runtime helper `@march_native_arr_from_list(ptr list)` that traverses the cons-cell chain and copies elements into a flat array. (Or inline the loop in LLVM IR — runtime helper is simpler.)

- [ ] **Emit `NAToList`**: Reverse loop building `Cons` cells from the end. Call `@march_alloc` per element.

- [ ] **Add vectorization metadata** to the module-level metadata section:
  ```llvm
  !llvm.module.flags = !{!0}
  !0 = !{i32 1, !"march.native_array", i32 1}
  ```

### Verification
```
dune build
# Compile a test file and inspect the IR:
dune exec march -- --compile --emit-llvm bench/array_numeric.march 2>&1 | grep -c "llvm.loop.vectorize"
# Should show at least 1 match
```

---

## Task 6: Switch clang to `-mavx2` and add alignment attributes

**Files:**
- Modify: `bin/main.ml` (or wherever the clang invocation is assembled)

### Steps

- [ ] Find the clang invocation that compiles the `.ll` file and change `-msse4.2` to `-mavx2` (or `-march=native` for maximum portability across development machines).
- [ ] Ensure `-O2` is passed (LLVM's auto-vectorizer requires at least `-O2`).
- [ ] Run `dune build`.

### Verification
```
dune build
dune exec march -- --compile bench/array_numeric.march
./a.out   # should run successfully
```

---

## Task 7: Integration test — compiled NativeArray benchmark

**Files:**
- Modify: `bench/array_numeric.march` (add compiled-path timing)
- New: `test/stdlib/test_native_array_compiled.march` (correctness under `--compile`)

### Steps

- [ ] Add a test file that exercises all 18 NativeArray operations with known inputs/outputs and runs under `--compile`:
  ```march
  mod TestNativeArrayCompiled do
    test "int sum" do
      let arr = NativeArray.make_int(100, 1)
      assert (NativeArray.sum_int(arr) == 100)
    end

    test "float map" do
      let arr = NativeArray.make_float(10, 3.0)
      let arr2 = NativeArray.map_float(arr, fn x -> x *. 2.0)
      assert approx_eq(NativeArray.get_float(arr2, 0), 6.0)
    end

    -- ... all ops
  end
  ```
- [ ] Run correctness tests in both interpreter and compiled modes.
- [ ] Update `bench/array_numeric.march` to print compiled-path timings alongside interpreter timings.

### Verification
```
dune exec march -- test test/stdlib/test_native_array_compiled.march
dune exec march -- --compile test/stdlib/test_native_array_compiled.march && ./a.out
```

---

## Task 8: Update specs and docs

**Files:**
- Modify: `specs/optimizations.md`
- Modify: `specs/todos.md`
- Modify: `specs/progress.md`

### Steps

- [ ] In `specs/optimizations.md`, update P10 Phase 2 status from "planned" to "done" with the date and a summary of files changed.
- [ ] In `specs/todos.md`, move P10 Phase 2 to the Done section.
- [ ] In `specs/progress.md`, add "NativeArray LLVM emit with AVX2 vectorization hints" to the feature list and update test counts.

### Verification
```
grep -c "done" specs/optimizations.md   # should show Phase 2 as done
```
