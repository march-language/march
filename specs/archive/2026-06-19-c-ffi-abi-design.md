# March External Function Interface — C-first ABI design

**Status:** Draft / design
**Date:** 2026-06-19
**Scope:** The stable native ABI ("March FFI ABI") plus the C-language binding path
built on it. Rust and OCaml are designed-for but specified only as future consumers
of the same ABI (see §15).

---

## 1. Summary

March needs a real foreign-function interface. A minimal `extern` scaffold already
exists end-to-end (parse → typecheck → lower → codegen), but it only maps a March
name to a C symbol named `<lib>_<fn>` and lowers primitive types directly. There is
no data marshalling, no opaque native state, no ownership story for Perceus
reference counting, no scheduler interaction, and no error protocol.

This spec defines the **March FFI ABI**: a stable C ABI (`march_ffi.h`) that any
native language can link against, modelled on what BEAM's `erl_nif.h`, the
WebAssembly Component Model's Canonical ABI, and Swift's `Unmanaged` ARC bridge do
well — but specialised to March's two defining traits:

- **Perceus reference counting** (non-moving, deterministic) — so no GC-root
  registration is needed, but *ownership transfer at the boundary must be explicit*.
- **A green-thread scheduler** — so foreign calls must be classified `fast` vs
  `blocking`, the latter dispatched to an OS-thread pool (BEAM's "dirty NIF" idea).

The marshalling model is a **tiered hybrid pulled toward canonical/copy-safe by
default**: primitives pass by value; structured data is marshalled by
compiler-generated codecs; opaque native state lives behind refcounted **resource**
handles with destructors; and a narrow **zero-copy borrow** escape hatch exists for
hot paths. Because March is statically typed, the marshalling glue is *generated*,
which keeps refcount discipline out of the binding author's hands in the common case.

### 1.1 Goals

- A documented, versioned C ABI that decouples native code from March internals.
- Effortless binding of *existing* C libraries (declare a symbol, no native build
  for thin cases).
- Correct interaction with Perceus: no leaks, no double-frees, no use-after-free,
  enforced by an RC-accounting test suite.
- Consistent FFI semantics across the three execution modes (interpreter, JIT,
  compiled), or an explicit, diagnosable boundary where a mode cannot support a call.
- Capability-gated, like the current `extern` block.

### 1.2 Non-goals (this spec)

- Rust `#[march]` proc-macro and OCaml stub generation (future; §15). The ABI is
  designed so they slot in without ABI changes.
- Native → March callbacks / upcalls (future; §13.5). Reserved in the ABI.
- Crash isolation (a C segfault kills the process — inherent to in-process C FFI;
  §13.4 documents the boundary and a subprocess-isolation future).

---

## 2. Background: what exists today

| Stage | Today | File |
|---|---|---|
| Syntax | `extern "libc": Cap(LibC) do fn malloc(n: Int): Int end` | `lib/parser/parser.mly:751` |
| AST | `DExtern of extern_def`; `extern_fn {ef_name; ef_params; ef_ret_ty}` | `lib/ast/ast.ml:328` |
| Typecheck | registers each fn as a monomorphic binding; cap-gates the block against `needs` | `lib/typecheck/typecheck.ml:6300`, `:4927` |
| Lower/TIR | emits `extern_decl {ed_march_name; ed_c_name = "<lib>_<fn>"; ed_params; ed_ret}` | `lib/tir/lower.ml:2139`, `lib/tir/tir.ml:83` |
| Codegen | declares the C symbol; LLVM links it; primitive type lowering only | `lib/tir/llvm_emit.ml` |
| Interpreter | binds each name to a `VForeign(lib,sym)` stub; **calling it is unimplemented** | `lib/eval/eval.ml:920,7742` |

Runtime facts this spec builds on (from `runtime/march_runtime.h`):

- Heap object header: `march_hdr { int64_t rc; int32_t tag; int32_t pad; }` — 16 bytes,
  fields begin at offset 16, each field is an 8-byte slot.
- `void *march_alloc(int64_t sz)`, `void march_incrc(void *)`, `void march_decrc(void *)`,
  `int64_t march_decrc_freed(void *)`.
- Strings: `march_string { int64_t rc; int32_t tag; int32_t pad; int64_t len; char data[]; }`,
  `tag == MARCH_STRING_TAG (-1)`; `march_string_alloc(len)`, `march_string_lit(utf8, len)`.
- Lists: `Nil` is `tag=0` (a 16-byte cell), `Cons` is `tag=1` with head at offset 16,
  tail at offset 24.
- A live-bytes counter is maintained (`march_decrc_local` decrements it) — the basis
  for the RC-leak test harness (§14.4).
- Value words use a **conditional-untag tagged-word convention**: odd words are
  tagged integers (`value = word >> 1`), even words are heap pointers used verbatim.
  This convention is subtle and easy to corrupt, so **the ABI never exposes raw tag
  bits** — all access goes through accessor functions (§4.3).

---

## 3. Design overview

```
 March source                         Native side (C)
 ────────────                         ───────────────
 extern "crc" : Cap(Ffi) do           // thin: bind an existing symbol directly,
   fn crc32(data: Bytes): Int         //   no C code needed
     = "crc32_compute"
 end                                  // or: a shim .c compiled by forge that
                                      //   #include "march_ffi.h" and marshals

        │  typecheck: marshallability + ownership + caps
        ▼
   TIR extern_decl (+ param modes, blocking flag, resource info)
        │
        ├── compiled: llvm_emit generates a wrapper that unwraps args,
        │             calls the C symbol, wraps the result, applies RC
        │
        └── interpreter/JIT: dlopen + libffi call the same symbol (§11)

        ▼
   Stable boundary defined by  runtime/march_ffi.h  (the erl_nif.h analog)
```

The compiler-generated **wrapper** is the heart of the design. The binding author
writes (or binds) a plain C function in natural C types; the wrapper does all
unwrapping/wrapping and all refcount bookkeeping dictated by the declared ownership
modes. Authors touch `march_ffi.h` directly only for resources, the borrow escape
hatch, and constructing structured return values.

---

## 4. The ABI: `runtime/march_ffi.h`

A single public header, versioned, that native bindings include. It re-exports a
curated, *stable* subset of the runtime plus FFI-specific helpers. Internal runtime
headers (`march_runtime.h`, `march_heap.h`) remain private.

### 4.1 Versioning & handshake

```c
#define MARCH_FFI_ABI_VERSION 1

/* Every compiled binding object exports this so the loader can reject skew. */
__attribute__((visibility("default")))
int32_t march_ffi_abi_version(void);   /* returns MARCH_FFI_ABI_VERSION */
```

The linker step (compiled) and `dlopen` step (interpreter) verify the version and
emit a clear diagnostic on mismatch (§13.7).

### 4.2 Core types

```c
typedef int64_t march_value;   /* an opaque March value word (tagged; see §4.3) */
typedef struct march_env march_env;  /* per-call context: scheduler, error slot */
```

`march_env *env` is threaded as a hidden first parameter into every binding that
needs to allocate, raise an error, or register a resource. Thin bindings to plain C
symbols (no marshalling) do not receive it.

### 4.3 Value accessors (never touch tag bits directly)

```c
/* Primitives — the generated wrapper normally unwraps these for you, but
 * resources / hand-written shims use them. */
march_value march_make_int(int64_t n);     /* traps if n exceeds 63-bit range, §13.1 */
int64_t     march_get_int(march_value v);
march_value march_make_float(double f);
double      march_get_float(march_value v);
march_value march_make_bool(int b);
int         march_get_bool(march_value v);

int         march_is_heap(march_value v);  /* even word → heap pointer */
void       *march_as_ptr(march_value v);   /* heap pointer, verbatim (no untag) */
march_value march_from_ptr(void *p);       /* wrap a heap pointer (no |1) */
```

### 4.4 Reference counting (tag-aware; safe to call on any value)

```c
march_value march_dup(march_value v);   /* heap: incrc; tagged int: no-op. returns v */
void        march_drop(march_value v);  /* heap: decrc (may free); tagged int: no-op */
```

`march_dup`/`march_drop` are the *only* RC entry points bindings use. They wrap
`march_incrc`/`march_decrc` but are tag-aware so authors never branch on
representation.

### 4.5 Strings & bytes

```c
/* Borrowed view into a march String/Bytes value — valid for the call only.
 * ptr is NOT NUL-terminated; honor len. UTF-8 for String, raw for Bytes. */
typedef struct { const uint8_t *ptr; size_t len; } march_slice;
march_slice march_str_borrow(march_value s);
march_slice march_bytes_borrow(march_value b);

/* Construct an owned String/Bytes (rc=1) by copying len bytes. */
march_value march_str_new(march_env *env, const uint8_t *utf8, size_t len);  /* validates UTF-8, §13.2 */
march_value march_bytes_new(march_env *env, const uint8_t *data, size_t len);

/* Convenience for legacy C APIs needing a NUL-terminated copy.
 * Returns a malloc'd buffer the caller must march_ffi_free(). Fails on embedded NUL. */
char *march_str_to_cstr(march_value s);
void  march_ffi_free(void *p);
```

### 4.6 Option / Result constructors

```c
march_value march_none(void);                 /* Option None  (tag 0) */
march_value march_some(march_value v);        /* Option Some  (tag 1), consumes v */
march_value march_ok(march_value v);          /* Result Ok    (tag 0), consumes v */
march_value march_err(march_value e);         /* Result Err   (tag 1), consumes e */
```

### 4.7 Structured access — records, variants, lists (borrow tier, v1)

```c
/* Variants (sum types): inspect tag and borrow fields (no copy). */
int32_t     march_variant_tag(march_value v);
march_value march_variant_field(march_value v, int32_t i);   /* borrowed */

/* Records: field access by index resolved from the runtime record-shape registry.
 * The generated codec (§6.4) is preferred; this is the manual/borrow path. */
march_value march_record_field(march_value v, int32_t i);    /* borrowed */

/* Lists (Nil=0 / Cons=1). */
int         march_list_is_nil(march_value v);
march_value march_list_head(march_value v);                  /* borrowed */
march_value march_list_tail(march_value v);                  /* borrowed */
march_value march_cons(march_env *env, march_value head, march_value tail); /* consumes both */
march_value march_nil(void);
```

Generated copy-codecs (`march_decode_<T>` / `march_encode_<T>`) for records and
variants land in v1.1 (§6.4, §16). The borrow accessors above are sufficient for v1
correctness and for hand-written shims.

### 4.8 Resources (opaque native state)

```c
/* Register a resource type once at module init; returns a type id. */
typedef void (*march_destructor)(void *native_ptr);
int32_t     march_resource_type(march_env *env, const char *name, march_destructor dtor);

/* Wrap a native pointer as an owned March resource value (rc=1).
 * When Perceus drops it to rc=0, the runtime calls dtor(native_ptr). */
march_value march_resource_new(march_env *env, int32_t type_id, void *native_ptr);

/* Borrow the native pointer back. Traps if v is not a resource of type_id. */
void       *march_resource_get(march_value v, int32_t type_id);
```

Runtime change required: a new `MARCH_RESOURCE_TAG` heap cell carrying
`{ type_id, native_ptr, dtor }`; `march_decrc`'s free path must, on reaching rc=0 for
such a cell, invoke `dtor(native_ptr)` before freeing the cell (§10.6).

### 4.9 Errors

```c
/* Signal a recoverable error from a binding declared to return Result.
 * The wrapper turns this into Err(e); the binding should return immediately. */
void march_raise(march_env *env, march_value error_value);

/* Fatal, unrecoverable (programmer error in the binding): aborts with a message. */
_Noreturn void march_fatal(const char *msg);
```

---

## 5. Surface syntax (extended `extern` block)

The existing block is extended with: an explicit C symbol name, per-parameter
ownership modes, a `blocking` modifier, resource type declarations, and a borrow
escape hatch. All additions are backward compatible (the `malloc` example still
parses).

```march
mod Crc do
  needs Ffi                       -- capability, gates the extern block

  resource Hasher                 -- opaque native handle, destructor on the C side

  extern "crc" : Cap(Ffi) do
    -- thin binding to an existing C symbol; no native code, no marshalling beyond primitives
    fn crc32(data: Bytes): Int = "crc32_compute"

    -- consumes its argument (refcount transferred to C); returns owned Result
    fn parse_u64(s: String): Result(Int, String) = "crc_parse_u64"

    -- resource lifecycle
    fn hasher_new(): Hasher = "crc_hasher_new"
    fn hasher_update(h: borrow Hasher, data: Bytes): Unit = "crc_hasher_update"
    fn hasher_finish(consume h: Hasher): Int = "crc_hasher_finish"

    -- long-running / IO: run on the blocking OS-thread pool, park the green thread
    blocking fn compress_file(path: String): Result(Bytes, String) = "crc_compress_file"
  end
end
```

Syntax additions, each independently parseable:

| Construct | Meaning |
|---|---|
| `= "symbol"` after a fn | bind this exact C symbol (default stays `<lib>_<fn>`) |
| `borrow T` param (default) | non-owning view, valid for the call only |
| `consume T` param | refcount transferred to the binding; it must drop or store it |
| `blocking fn` | dispatch to the OS-thread pool; park the calling green thread |
| `resource Name` decl | declares an opaque native type usable in extern signatures |
| `raw T` param (escape hatch) | pass `march_value` verbatim, no marshalling (§7) |

Default parameter mode is **borrow**; default return is **owned** (binding transfers
the result to March). These defaults make the common, safe case implicit.

---

## 6. Marshalling specification

### 6.1 Ownership conventions (the Perceus contract)

This is the single most important, irreversible part of the design.

- **Borrowed parameter** (default): March retains its refcount. The binding receives
  a view valid only until it returns. It must **not** `march_drop` it and must
  `march_dup` it before retaining it past the call (e.g. storing it in a resource).
- **Consumed parameter** (`consume`): the refcount is transferred. The binding now
  owns it and must eventually `march_drop` it (or hand it to `march_resource_new` /
  store it). The wrapper does **not** drop it after the call.
- **Returned value**: always **owned** — the binding transfers a refcount to March,
  which will drop it later. A binding that returns one of its *borrowed* inputs must
  `march_dup` it first (§13.3 — a classic bug, covered by a test).

The generated wrapper enforces the caller side: for borrowed args it keeps March's
count and drops nothing extra; for consumed args it omits the post-call drop it would
otherwise do; for the return it assumes rc-ownership.

### 6.2 Primitive tier (Int, Float, Bool, Char)

Passed/returned **by value, unwrapped**. The wrapper unwraps `march_value` →
`int64_t`/`double`/`int` before the call and wraps the result after, so a thin
binding's C signature is plain: `int64_t crc32_compute(const uint8_t*, size_t)`.
No `march_env`, no RC. (Char is a Unicode scalar passed as `int64_t`.)

### 6.3 String / Bytes tier

- **Borrowed (default):** wrapper passes a `march_slice {ptr,len}`. Zero-copy view
  into the `march_string` data region.
- **Consumed:** wrapper passes the `march_value`; binding owns it.
- **Returned:** binding builds an owned value via `march_str_new`/`march_bytes_new`,
  or returns a consumed input it dup'd.

### 6.4 Record / variant tier

- **v1 (borrow accessors):** wrapper passes the `march_value`; binding uses
  `march_variant_tag` / `march_*_field` to read, `march_cons` / constructors to build.
- **v1.1 (generated codecs):** for each FFI-reachable record/variant type `T`, the
  compiler emits `march_decode_T(march_value) -> struct T_c` and
  `march_encode_T(march_env*, struct T_c) -> march_value`, plus a `#repr(C)` mirror
  struct in a generated `march_ffi_types.h`, using the runtime record-shape registry
  for field offsets. This is the "canonical copy" default; the borrow path remains as
  the escape hatch.

### 6.5 Option / Result tier

`Option(T)` ↔ `march_none()` / `march_some(v)`. `Result(T,E)` is the **error
protocol**: a binding declared `: Result(T,E)` returns the Ok payload normally on
success, or calls `march_raise(env, e)` and returns; the wrapper materialises
`Ok(payload)` or `Err(e)`. (Bindings may also return an explicit `march_ok/err`
value when they prefer to build it themselves.)

### 6.6 List tier

- **v1:** borrow accessors (`march_list_is_nil/head/tail`, `march_cons/nil`).
- **v1.1:** for lists of primitives, optional canonical copy to/from a C array
  (`int64_t*`, `double*`, ...) with length, to avoid per-element calls in hot loops.

### 6.7 Marshallability rule (typecheck-enforced)

A type is **FFI-marshallable** iff it is a primitive, `String`/`Bytes`, a declared
`resource`, `Option`/`Result` of marshallable types, or (v1.1) a record/variant whose
fields are marshallable, or appears under `raw`. Function types, channels, actors,
and capabilities are **not** marshallable as data (capabilities are erased to null at
runtime). Typecheck rejects non-marshallable extern signatures with a pointed
diagnostic (§13.10).

---

## 7. Zero-copy escape hatch (`raw`)

A `raw T` parameter or `raw` return passes the `march_value` verbatim with **no
marshalling and no automatic RC** — the binding is fully responsible for dup/drop per
the declared ownership mode. This is the BEAM-`erl_nif` direct-term style, available
only when explicitly requested, for hot paths (e.g. handing a 10 MB `Bytes` to a
hashing loop without the slice indirection). Documented as unsafe; covered by a
dedicated adversarial RC test (§14).

---

## 8. Error & panic safety

- **C bindings** cannot unwind, but may fail. The `Result` protocol (§6.5) is the
  supported failure channel. Bindings **must not** `longjmp` across the boundary
  (a `longjmp` past the wrapper leaks/corrupts refcounts) — documented constraint.
- **Foreign unwinding never crosses the boundary.** For C this is a discipline; for
  the future Rust layer the generated wrapper will `catch_unwind` and convert a panic
  to `march_raise` (§15) — the ABI already routes errors through `march_env`, so no
  ABI change is needed to add this.
- **Segfaults / aborts** in C take down the process. This is inherent to in-process C
  FFI and matches every comparable system; §13.4 records the boundary and a future
  subprocess-isolation option.

---

## 9. Scheduler integration (`fast` vs `blocking`)

March runs user code on green threads over a small pool of scheduler OS threads
(`runtime/march_scheduler.h`). A long or blocking foreign call on a scheduler thread
stalls every green thread multiplexed onto it — exactly the problem BEAM's dirty
schedulers solve.

- **`fast` (default):** the wrapper calls the C symbol inline on the current
  scheduler thread. Contract: bounded, non-blocking, "microseconds." Misusing `fast`
  for a blocking call is a latency bug, not a safety bug.
- **`blocking`:** the wrapper hands the call to a dedicated **blocking OS-thread
  pool**, parks the calling green thread, and resumes it with the result when the
  native call completes. New runtime entry point:

```c
/* Runtime-internal: run fn(args) on the blocking pool; park the current green
 * thread until it returns. Emitted by codegen for `blocking` externs. */
march_value march_run_blocking(march_env *env, void *fnptr, march_value *args, int n);
```

Phasing: v1 may implement `blocking` as "run on the pool, park the green thread";
if the pool is not yet wired, `blocking` runs inline **and the compiler emits a
warning** so the semantics are never silently wrong (§16).

---

## 10. Compiler pipeline changes

### 10.1 Parser (`lib/parser/parser.mly`)

Extend `extern_fn_decl` and add `resource` decls:

```ocaml
(* extern_fn_decl: optional `blocking`, per-param modes, optional `= "symbol"` *)
extern_fn_decl:
  | blk = boption(BLOCKING); FN; name = lower_name;
    LPAREN; params = separated_list(COMMA, ffi_param); RPAREN;
    COLON; ret = ty; sym = option(EQ STRING)
    { { ef_name = name; ef_params = params; ef_ret_ty = ret;
        ef_blocking = blk; ef_symbol = sym } }

ffi_param:
  | BORROW?; name = lower_name; COLON; t = ty   { (name, t, ParamBorrow) }   (* default *)
  | CONSUME;  name = lower_name; COLON; t = ty   { (name, t, ParamConsume) }
  | RAW;      name = lower_name; COLON; t = ty   { (name, t, ParamRaw) }
```

New tokens: `BLOCKING`, `CONSUME`, `BORROW`, `RAW`, `RESOURCE` (contextual where
possible to avoid stealing identifiers). `resource Name` becomes a new decl
`DResource of name * span`.

### 10.2 AST (`lib/ast/ast.ml`)

```ocaml
and param_mode = ParamBorrow | ParamConsume | ParamRaw

and extern_fn = {
  ef_name      : name;
  ef_params    : (name * ty * param_mode) list;   (* was (name * ty) list *)
  ef_ret_ty    : ty;
  ef_blocking  : bool;
  ef_symbol    : string option;                   (* explicit C symbol *)
}
(* + DResource of name * span in decl *)
```

### 10.3 Typecheck (`lib/typecheck/typecheck.ml`)

Keeps the existing monomorphic binding registration and cap gating (`:4927`,
`:6300`). Adds:

1. Register `resource` types as opaque nominal types (no constructors;
   marshallable; only producible/consumable via externs).
2. Validate every extern param/return is FFI-marshallable (§6.7) — else error.
3. Validate ownership: `consume`/`borrow` only on heap types (not on `Int`/`Float`/
   `Bool`, where they are meaningless) → warning/normalised to by-value.
4. Thread `ef_blocking`, modes, symbol through to the typed decl.

### 10.4 Lower / TIR (`lib/tir/tir.ml`, `lib/tir/lower.ml`)

Extend `extern_decl`:

```ocaml
type extern_decl = {
  ed_march_name : string;
  ed_c_name     : string;          (* ef_symbol if given, else "<lib>_<fn>" *)
  ed_params     : (ty * param_mode) list;   (* carries modes now *)
  ed_ret        : ty;
  ed_blocking   : bool;
  ed_needs_env  : bool;            (* true if any non-primitive param/ret or resource *)
}
```

### 10.5 Codegen (`lib/tir/llvm_emit.ml`)

For each extern call site, generate the **wrapper** inline (or as a shared thunk):

1. Declare the C symbol with its *unwrapped* LLVM signature.
2. For each arg: unwrap per tier (§6) and apply the borrow/consume RC rule (§6.1).
3. If `ed_needs_env`, materialise/pass the `march_env*`.
4. Emit either a direct call (`fast`) or `march_run_blocking` (`blocking`).
5. Wrap the return (owned) and, for `Result`, branch on the env error slot to build
   `Ok`/`Err`.

### 10.6 Runtime (`runtime/march_ffi.c` + header; `march_runtime.c`)

- New `march_ffi.c` implementing §4 helpers (most are thin wrappers over existing
  runtime functions; `march_dup/drop` add the tag check; string/bytes/option/result
  reuse existing alloc helpers).
- `MARCH_RESOURCE_TAG` cell + destructor invocation in the `march_decrc` free path.
- `march_run_blocking` in the scheduler.
- The CAS cache key already digests `runtime/*.c|*.h`, so adding these invalidates
  cached artifacts automatically.

---

## 11. Interpreter / JIT parity

The canonical ABI is implementable in the tree-walking interpreter, giving the
interpreter/JIT/compiled parity the existing Slow test suite already checks.

- Replace the inert `VForeign` stub: on the first call, `dlopen` the binding's shared
  library (compiled by forge, §12), resolve the symbol, and call it through **libffi**
  with arguments marshalled by the same tier rules, implemented in OCaml against the
  *same* `march_ffi.h` helpers (the interpreter's heap values already share the
  runtime layout for compiled-compatible types).
- **Capability boundary:** v1 interpreter supports primitives, String/Bytes, Option/
  Result, and resources via libffi. Record/variant *generated codecs* are
  compiled-only until v1.1; an extern using them in the interpreter raises a clear
  `this extern requires compilation (record marshalling not yet supported in the
  interpreter)` diagnostic rather than misbehaving.
- `blocking` in the interpreter runs on an OCaml thread; the parity tests assert
  identical *results* (not timing).

---

## 12. Build integration (forge)

Bindings that need native code (shims, or resource destructors) declare it in
`forge.toml`:

```toml
[[ffi]]
name    = "crc"            # matches the extern "crc" lib string
sources = ["native/crc.c"] # compiled with march_ffi.h on the include path
link    = ["z"]            # extra -l flags (e.g. system libz)
```

- forge compiles each `sources` file with `cc -I<runtime>` (where `march_ffi.h`
  lives), producing objects linked into the final binary (compiled mode) and a shared
  library for the interpreter (`dlopen`, §11).
- Thin bindings to a *system* library with no shim need only `link = ["foo"]`.
- The CAS cache key is extended to digest `[[ffi]].sources` so editing a shim
  invalidates the cached binary, mirroring the existing runtime-source digesting.

---

## 13. Edge cases

1. **63-bit Int overflow.** A tagged March `Int` carries 63 bits. A C `int64_t`
   return with bit 63 set cannot be represented. `march_make_int` **traps** (fatal)
   on out-of-range; bindings that legitimately need full 64-bit must return `Bytes`
   or a boxed type. Tested (§14.7).
2. **Invalid UTF-8 from C.** `march_str_new` validates and, in a `Result`-returning
   binding, routes to `Err`; in a non-`Result` binding it `march_fatal`s. `Bytes` is
   the escape for arbitrary octets.
3. **Returning a borrowed input without `dup`.** Premature free when March later
   drops the "returned" value while the caller still holds the original. Mitigation:
   docs + the borrow/consume contract + an adversarial RC test that fails loudly
   under the sanitizer (§14.5).
4. **Segfault / abort in C.** Kills the process; documented as inherent. Future:
   `blocking` + subprocess isolation for untrusted bindings.
5. **Double-free / use-after-free from a buggy binding.** Not preventable in C, but
   detectable: `MARCH_SANITIZE` mode adds rc-underflow assertions; a deliberately
   buggy binding is a *negative* test that the sanitizer catches it.
6. **Embedded NUL in String.** `march_str_borrow` is length-based and safe;
   `march_str_to_cstr` fails (returns NULL) on embedded NUL rather than truncating.
7. **NULL pointer returned from C.** A binding returning `Option(T)` maps NULL →
   `None`; a binding returning a bare resource/heap type and yielding NULL is a
   contract violation → `march_fatal`.
8. **ABI version skew.** `march_ffi_abi_version()` checked at link (compiled) and
   `dlopen` (interpreter); mismatch → clear error naming the binding (§13.7).
9. **Capability bypass.** Resources, `blocking`, and `raw` are all inside the
   cap-gated `extern` block; no path produces a resource or blocking call without the
   declared capability. Tested.
10. **Non-marshallable type in signature.** (function, channel, actor, capability)
    → typecheck error pointing at the offending param with the marshallability rule.
11. **Re-entrancy / stable pointers.** Because Perceus never moves objects, a
    borrowed pointer stays valid for the whole call even if the binding triggers
    March allocation — unlike moving-GC FFIs (JNI/Go). Documented as a March
    advantage; no pinning needed.
12. **Double resource-type registration.** `march_resource_type` is idempotent per
    `(module, name)`; a second registration returns the existing id.
13. **`blocking` fn that never returns.** Ties up one blocking-pool thread; the pool
    is bounded and growable; documented as the author's responsibility (same as any
    OS thread).
14. **dlopen failure / missing symbol** (interpreter). Clear diagnostic naming the
    library and symbol; suggests checking `[[ffi]]` in `forge.toml`.
15. **Endianness / alignment** for v1.1 record mirrors. Codecs use the runtime
    shape registry offsets; mirror structs are `#repr(C)`-equivalent and host-native
    (FFI is in-process, single host — no cross-endian concern).

---

## 14. Testing strategy

Tests follow the existing harness conventions (`scripts/run-tests.sh`, alcotest
suites in `test/`, and the Slow-marked parity/adversarial suites). FFI tests link a
small **C conformance library** (`test/ffi/conformance.c`) built against
`march_ffi.h`.

### 14.1 Parser/typecheck unit tests (`run_compiler`)
- New syntax parses: `consume`/`borrow`/`raw` params, `blocking`, `= "sym"`,
  `resource` decls.
- Cap gating still fires (extern without `needs` → error).
- Marshallability errors: function/channel/capability param rejected with the right
  message.
- Ownership validation: `consume Int` normalised/warned.

### 14.2 Codegen round-trip tests (`run_codegen`)
For each tier, a March program calls a C conformance function and asserts the result:
- `int`/`float`/`bool` identity and arithmetic.
- `String`/`Bytes` borrow in, construct out; embedded NUL; multibyte UTF-8.
- `Option`/`Result` both arms.
- variant tag/field read; `cons`/`nil` build (v1 borrow path).
- resource: create → use (borrow) → finish (consume) → assert destructor ran.

### 14.3 ABI conformance suite
A single program that round-trips **every** marshallable type March→C→March and
asserts structural equality, run in compiled mode. The canonical "does the ABI
actually work" gate.

### 14.4 RC-leak tests (the critical correctness gate)
Using the runtime live-bytes counter: snapshot `live_bytes` before and after a loop
of N FFI calls; assert it returns to baseline (±0) for:
- borrowed args (March keeps the count; binding drops nothing),
- consumed args (binding drops; no leak, no double-free),
- returned owned values (caller drops; no leak),
- resource create/drop (destructor runs exactly once; cell freed).

```c
/* test/ffi/conformance.c — borrowed arg must not be dropped by the binding */
int64_t conf_strlen_borrow(march_slice s) { return (int64_t)s.len; }

/* consumed arg: binding owns it and must drop it */
int64_t conf_strlen_consume(march_env *env, march_value s) {
    march_slice v = march_str_borrow(s);
    int64_t n = (int64_t)v.len;
    march_drop(s);                 /* required: we own this count */
    return n;
}
```

```march
-- test: 100k calls, live_bytes must be flat
fn rc_leak_borrow_test() do
  let base = __live_bytes()        -- test-only intrinsic
  let s = "the quick brown fox"
  repeat 100000 do conf_strlen_borrow(s) end
  assert_eq(__live_bytes(), base)
end
```

### 14.5 Adversarial RC tests (Slow, compiled)
Mirrors the existing adversarial regression suite. Includes the "return a borrowed
input" trap (correct version dups; a buggy version is caught by the sanitizer), and
the `raw` escape hatch with hand-managed dup/drop.

### 14.6 Interpreter/JIT/compiled parity (Slow)
The same FFI program through all three backends → byte-identical stdout, joining the
existing parity suite.

### 14.7 Edge-case tests
63-bit int overflow traps; invalid UTF-8 → `Err`; NULL → `None`; double resource
registration returns the same id; ABI version mismatch is rejected.

### 14.8 Scheduler test (Slow)
Spawn M green threads; one calls a `blocking` FFI that sleeps; assert the other M-1
make progress meanwhile (proves `blocking` doesn't stall the scheduler).

### 14.9 forge integration test
A fixture project with `[[ffi]]` + a shim `.c`; `forge build` compiles and links it;
`forge test` runs a doctest calling the binding. Verifies CAS invalidation when the
shim changes.

### 14.10 Benchmarks
Per CLAUDE.md, exercise the relevant bench after changes: FFI call overhead
(`bench/` new `ffi_call.march` — tight loop over a `fast` primitive binding) and a
`Bytes`-heavy `raw` path; watch for regressions in closure/HOF benches if the
wrapper thunking touches shared codegen paths.

---

## 15. Worked example: wrapping a small C library

A self-contained library exposing a primitive function, a fallible parse, and an
opaque incremental hasher (resource). This exercises primitive, borrowed `Bytes`,
`Result`, and resource lifecycle end to end.

### 15.1 Native side — `native/crc.c`

```c
#include "march_ffi.h"
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

int32_t march_ffi_abi_version(void) { return MARCH_FFI_ABI_VERSION; }

/* --- thin primitive binding: no env, plain C types --- */
int64_t crc32_compute(const uint8_t *data, size_t len) {
    uint32_t c = 0xFFFFFFFFu;
    for (size_t i = 0; i < len; i++) {
        c ^= data[i];
        for (int k = 0; k < 8; k++) c = (c >> 1) ^ (0xEDB88320u & -(c & 1));
    }
    return (int64_t)(c ^ 0xFFFFFFFFu);
}

/* --- fallible: declared `: Result(Int, String)` --- */
int64_t crc_parse_u64(march_env *env, march_value s /* consume */) {
    march_slice v = march_str_borrow(s);
    char buf[32];
    if (v.len == 0 || v.len >= sizeof buf) {
        march_drop(s);
        march_raise(env, march_str_new(env, (const uint8_t*)"empty/too long", 14));
        return 0;                      /* wrapper builds Err; this is ignored */
    }
    memcpy(buf, v.ptr, v.len); buf[v.len] = 0;
    char *end; long long n = strtoll(buf, &end, 10);
    march_drop(s);
    if (*end != 0) { march_raise(env, march_str_new(env,(const uint8_t*)"not a number",12)); return 0; }
    return n;                          /* wrapper wraps as Ok(n) */
}

/* --- resource: opaque incremental hasher --- */
typedef struct { uint32_t state; } Hasher;
static int32_t HASHER_TID;            /* resolved at module init */
static void hasher_dtor(void *p) { free(p); }

march_value crc_hasher_new(march_env *env) {
    Hasher *h = malloc(sizeof *h); h->state = 0xFFFFFFFFu;
    return march_resource_new(env, HASHER_TID, h);
}
void crc_hasher_update(march_env *env, march_value h /* borrow */, march_slice data) {
    Hasher *st = march_resource_get(h, HASHER_TID);
    for (size_t i = 0; i < data.len; i++) {
        st->state ^= data.ptr[i];
        for (int k = 0; k < 8; k++) st->state = (st->state>>1) ^ (0xEDB88320u & -(st->state & 1));
    }
}
int64_t crc_hasher_finish(march_env *env, march_value h /* consume */) {
    Hasher *st = march_resource_get(h, HASHER_TID);
    int64_t out = (int64_t)(st->state ^ 0xFFFFFFFFu);
    march_drop(h);                     /* consumed → we drop; dtor frees st */
    return out;
}
```

### 15.2 March side

```march
mod Crc do
  needs Ffi
  resource Hasher

  extern "crc" : Cap(Ffi) do
    fn crc32(data: Bytes): Int                  = "crc32_compute"
    fn parse_u64(consume s: String): Result(Int, String) = "crc_parse_u64"
    fn hasher_new(): Hasher                      = "crc_hasher_new"
    fn hasher_update(h: borrow Hasher, data: Bytes): Unit = "crc_hasher_update"
    fn hasher_finish(consume h: Hasher): Int     = "crc_hasher_finish"
  end

  fn checksum(data: Bytes): Int do crc32(data) end

  fn streamed(parts: List(Bytes)): Int do
    let h = hasher_new()
    each(parts, fn p -> hasher_update(h, p))     -- borrow: h survives the loop
    hasher_finish(h)                              -- consume: dtor runs after this
  end
end
```

### 15.3 forge.toml

```toml
[[ffi]]
name    = "crc"
sources = ["native/crc.c"]
```

This single example is the backbone of the §14.2/§14.4 tests: `checksum` covers the
primitive + borrowed-`Bytes` path, `parse_u64` covers `Result` both arms, and
`streamed` covers the full resource lifecycle including destructor accounting.

---

## 16. Rust bindings (Rustler-style layer)

Specified here for completeness; **not part of the C v1 implementation** (§18). It
adds *zero* ABI surface — the Rust layer is a pure consumer of `march_ffi.h`, and the
error protocol of §8 already gives it everything it needs.

### 16.1 Why Rust rides on the C ABI

Rust has **no stable ABI** and mangles symbol names, so it cannot be bound the way a
C symbol is. Every March↔Rust call goes through `extern "C"` + `#[no_mangle]` — i.e.
the C ABI is the substrate, and the job is to *generate that shim* while letting the
author write idiomatic Rust.

### 16.2 The ownership mapping (why Rust is a better partner than C)

Rust's ownership system maps **1:1** onto the §6.1 borrow/consume contract, and the
borrow checker enforces it for free:

| March mode | Rust type | meaning |
|---|---|---|
| `borrow` (default) | `&str`, `&[u8]`, `&T` | view valid for the call; don't retain |
| `consume` | `String`, `Vec<u8>`, `T` | owned; may keep, store, or drop |
| owned return | `-> T` | transferred to March |

The macro reads the signature and emits matching ABI modes — the author never calls
`march_dup`/`march_drop`.

### 16.3 The `march` Rust crate (the Rustler analog)

```rust
use march::{march, Encoder, Decoder, ResourceArc, Error};

#[march]                                          // generates the extern "C" shim:
fn parse(s: &str) -> Result<Json, Error> {        //   decode args (s = borrow),
    serde_json::from_str(s)                        //   catch_unwind the body,
        .map_err(|e| Error::msg(e.to_string()))   //   encode the result, apply RC
}

#[derive(Encoder, Decoder)]                        // struct/enum <-> March record/variant
struct Point { x: i64, y: i64 }                    //   by field name / ctor tag

#[march]
fn reader_open(path: String) -> Result<ResourceArc<File>, Error> { /* ... */ }
#[march]
fn reader_next(r: ResourceArc<File>) -> Option<String> { /* ... */ }

march::init!("json", [parse, reader_open, reader_next]);  // emits the binding manifest
```

Four pieces give the Rustler feel:
- **`#[march]` attribute** — generates the whole `#[no_mangle] extern "C"` shim.
- **`#[derive(Encoder, Decoder)]`** — record/variant marshalling, no hand code.
- **`ResourceArc<T>`** — §4.8 resources as an `Arc`-like smart pointer whose `Drop`
  is wired to the C destructor.
- **Mandatory `catch_unwind`** in every wrapper — a Rust panic becomes a March `Err`
  via `march_raise`, never UB (unwinding across `extern "C"` is undefined behavior).

### 16.4 Hard parts (honest)

- **Async (tokio):** futures can't cross. Map `async fn` → a `blocking` extern that
  `block_on`s on the §9 pool. Scheduler-driven futures are a later option.
- **Generics / trait objects:** can't cross — expose concrete monomorphizations.
- **Toolchain weight:** needs cargo + a Rust toolchain; Rust std bloats the binary.
  The C path stays the zero-extra-toolchain default.

---

## 17. Binding generation

The cross-boundary *glue* is fully auto-generated; a complete, correct binding to an
arbitrary third-party API is **not** — and the boundary between the two is precise.
For **C**, the generators (§17.2) are in-scope tooling; the **Rust** direction
(§17.3) belongs to the §16 future layer.

### 17.1 The 80/20 boundary

What a generator **can** infer is in the type signature. What it **cannot** infer
lives in documentation: ownership (borrow vs consume), nullability (→ `Option`),
error conventions (NULL/`errno` → `Result`), string length vs NUL-termination, and
*which* functions to expose. `char *parse(char *in)` does not say who frees the
return or whether `in` is consumed. So `bindgen`-class tools emit raw `unsafe`
declarations, never safe idiomatic bindings. The design target is therefore
**"generate the 80%, declare the 20% once"** — capture the irreducible semantic
decisions in annotations / the `extern` block / a sidecar file, then re-apply them
mechanically on regeneration.

### 17.2 Three generation directions

| Direction | Automatable | Tool |
|---|---|---|
| Native annotations → **March `extern` block** | **100%** | `forge add-rust` / manifest (§17.3) |
| March `extern` block → **native C shim skeleton** | **100% of glue** | `forge ffi gen-c` |
| Existing C header → **draft `extern` block** | **~80%**, ownership flagged | `forge ffi import` |

**`forge ffi gen-c <lib>`** (declare direction — recommended for C). You write the
`extern` block (stating ownership in March, where the type system is authoritative);
the tool emits a C shim with marshalling stubs prefilled — `march_str_to_cstr`, the
`Result` wrapper, resource construction — leaving only the actual library call:

```march
extern "sqlite" : Cap(Ffi) do
  fn open(consume path: String): Result(Db, String) = "my_sqlite_open"
end
```
```
forge ffi gen-c sqlite   # → native/sqlite.c with my_sqlite_open() stubbed;
                         #   you fill in the sqlite3_open(...) call.
```

**`forge ffi import <header.h>`** (import direction). libclang parses the header and
emits a draft `extern` block: primitive signatures complete; every pointer/string/
struct param emitted with a conservative `borrow` default plus a
`-- REVIEW: ownership?` marker. **Round-trippable:** re-running merges newly-added
symbols without clobbering your edits, and a sidecar `<lib>.ffi.toml` records your
ownership/nullability/error decisions so regeneration re-applies them:

```toml
# sqlite.ffi.toml — the captured "20%"
[sqlite3_open]
params = ["consume", "out"]   # 2nd arg is an out-param
returns = "errno_to_result"   # nonzero return -> Err
[sqlite3_column_text]
returns = "nullable"          # NULL -> None
```

### 17.3 Rust direction (future, §16)

There is no header to import; you scaffold a wrapper crate and the *March side is
100% generated* from the crate's manifest:

```
forge add-rust serde_json   # scaffolds native/json-binding (march dep, crate-type)
# ...write #[march] wrappers (the irreducible API-selection step)...
forge build                 # cargo builds staticlib (compiled) / cdylib (interp),
                            # reads march::init!, GENERATES the March extern block, links
```

The only human input is *which* functions to expose and the idiomatic wrapper bodies
— selecting and shaping the API surface, which no tool can infer.

### 17.4 What is never promised

Pointing at `serde_json` or `libcurl` and getting a working, safe binding with **zero
input** is not achievable — the semantics aren't in the types. Every honest system
(bindgen, cxx, uniffi, wit-bindgen) requires someone to declare the safe surface; the
generators above shrink that to the smallest declarative core.

---

## 18. Implementation phases

1. **ABI core + primitives.** `march_ffi.h` (§4.1–4.4), `march_ffi.c`, value
   accessors, `dup/drop`. Extend parser/AST/typecheck/lower/codegen for `= "sym"` and
   primitive marshalling. Tests §14.1, §14.2 (primitives), §14.4 (borrow leak).
2. **Strings/Bytes + Option/Result + error protocol.** §4.5–4.6, §6.3, §6.5, §8.
   Tests §14.2 (strings, result), §14.7 (UTF-8, overflow).
3. **Resources.** `MARCH_RESOURCE_TAG`, destructor in the decrc path, §4.8.
   Tests §14.2 (resource), §14.4 (destructor accounting).
4. **Interpreter parity (libffi + dlopen).** §11. Tests §14.6.
5. **forge `[[ffi]]` build + CAS digesting.** §12. Tests §14.9.
6. **`blocking` scheduler dispatch.** §9 (until then, inline + warn). Tests §14.8.
7. **C binding generators.** `forge ffi gen-c` + `forge ffi import` + sidecar
   `.ffi.toml` round-tripping (§17.2). Tests: golden-file generation + re-import merge.
8. **v1.1: generated record/variant codecs + primitive-list copy.** §6.4, §6.6.
9. **`raw` escape hatch hardening + adversarial suite.** §7, §14.5.

Per CLAUDE.md, each phase updates `specs/todos.md` (Done) and `specs/progress.md`
(feature list + counts) in the same commit, and runs the relevant benchmark.

---

## 19. Future (designed-for, out of scope here)

- **Rust `#[march]` layer (Rustler feel).** Fully sketched in §16; adds no ABI
  surface. Pairs with the `forge add-rust` generation direction (§17.3).
- **OCaml consumer.** OCaml C stubs calling the same `march_ffi.h`; March's host
  language, so the cheapest third binding.
- **Native → March callbacks (upcalls).** Reserve an `march_call(env, fn_value,
  args...)` entry point; requires passing March closures across the boundary as
  resources. Deferred.
- **Crash isolation** for untrusted bindings via subprocess + the `blocking` pool.
