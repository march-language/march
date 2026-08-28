# March C Runtime Documentation

## Overview

The March language runtime is a C-based system providing core functionality for compiled March programs. The runtime implements:

- **Memory management**: Heap allocation, reference counting (RC), and deallocation
- **String system**: String literals, operations, conversions, and transformations
- **Actor runtime**: M:N work-stealing green-thread scheduler with message passing (`march_scheduler.c`)
- **Mathematical functions**: Floating-point and trigonometric operations
- **File system operations**: File and directory existence checks
- **HTTP/WebSocket support**: TCP networking, HTTP request/response parsing, and WebSocket protocol

All data on the heap follows a uniform layout starting with a reference-counted header. Compilation targets LLVM IR, which is then linked against the C runtime library during final assembly.

## Heap Object Layout

All heap-allocated March values share a common 16-byte header followed by zero or more 8-byte fields:

```
Offset  0 : int64_t  rc    (atomic reference count, initialized to 1)
Offset  8 : int32_t  tag   (constructor tag, 0-based variant index)
Offset 12 : int32_t  pad   (alignment padding)
Offset 16+: fields        (each 8 bytes: int64_t for Int/Bool, double for Float, pointer for others)
```

**Total allocation size**: `16 + (num_fields * 8)` bytes

**Note**: TInt fields store `int64_t`, TFloat fields store `double`, and all other types (strings, pointers, data structures) store `void*`.

## Source Files

There are ~19 C source files in `runtime/`. The principal ones:

| File | Purpose |
|------|---------|
| `runtime/march_runtime.c` | Memory, string, actor metadata (`march_actor_meta`), `march_spawn`/`send`/`kill`, math, FS, utility functions |
| `runtime/march_scheduler.c` | M:N work-stealing green-thread scheduler (`march_proc`, `march_sched_spawn`, `march_sched_send`) |
| `runtime/march_heap.c` | Per-process bump-allocator arena heaps (`march_heap_t`, `march_process_alloc`) |
| `runtime/march_gc.c` | Per-process semi-space copying collector (`march_gc_collect`) |
| `runtime/march_message.c` | Cross-heap message passing (`march_msg_copy`/`march_msg_move`), MPSC mailbox, `march_msg_node` |
| `runtime/march_http.c` | TCP, request reception, fallback thread-per-connection accept loop |
| `runtime/march_http_evloop.c` | Default event-loop HTTP server (kqueue/epoll, one thread per core) |
| `runtime/march_http_parse_simd.c` | SIMD (SSE4.2) HTTP/1.x request parser |
| `runtime/march_http_io.c` | Non-blocking I/O state machines for the event loop |
| `runtime/march_http_response.c` | Zero-copy HTTP/1.1 response builder |
| `runtime/march_tls.c` | OpenSSL-backed TLS (`march_tls_connect`/`march_tls_accept`) |
| `runtime/march_ffi.c` | FFI / extern call support |
| `runtime/march_dispatch.c`, `march_extras.c`, `march_compress.c`, `march_remote_registry.c`, `march_runtime_wasm.c` | Dispatch, channel/session builtins, compression, remote actor registry, WASM target |
| `runtime/base64.c` | Base64 encoder for WebSocket handshake |
| `runtime/sha1.c` | SHA-1 implementation for WebSocket handshake |

## Memory Management

### Reference Counting

The runtime uses **atomic reference counting** for thread-safe heap management. Each object starts with `rc = 1`.

> **Update (March 20, 2026, Track C):** RC operations are now fully atomic with proper memory ordering. `march_incrc` has been upgraded from `memory_order_relaxed` to proper atomic semantics, fixing the ABA race condition (H2 in correctness audit). All RC changes have passed ThreadSanitizer validation.

#### `march_alloc(int64_t sz)`: Lines 12-20
- **Purpose**: Allocate `sz` bytes on the heap (zeroed)
- **Returns**: Pointer to allocated block with `rc = 1`, `tag = 0`
- **Behavior**: Calls `calloc()`, initializes header, exits with error message on failure
- **Thread-safe**: Yes (RC initialized atomically)

```c
void *march_alloc(int64_t sz);
```

#### `march_incrc(void *p)`: Lines 24-27
- **Purpose**: Increment reference count of heap object
- **Behavior**: No-op if `p == NULL`
- **Thread-safe**: Yes (atomic fetch-add with relaxed memory order)

```c
void march_incrc(void *p);
```

#### `march_decrc(void *p)`: Lines 29-33
- **Purpose**: Decrement reference count and free object if count hits zero
- **Behavior**: No-op if `p == NULL`; uses `acquire-release` memory ordering for thread safety
- **Thread-safe**: Yes

```c
void march_decrc(void *p);
```

#### `march_decrc_freed(void *p)`: Lines 35-40
- **Purpose**: Decrement RC and return 1 if object was freed, 0 if still alive
- **Returns**: 1 (freed) or 0 (alive)
- **Use case**: Pattern matching when conditionally incrementing extracted child pointers
- **Thread-safe**: Yes

```c
int64_t march_decrc_freed(void *p);
```

#### `march_free(void *p)`: Lines 42-44
- **Purpose**: Direct free (bypass reference counting)
- **Rarely used**: Most deallocation goes through `march_decrc()`

```c
void march_free(void *p);
```

## String System

### Data Structure

March strings are heap objects with a custom layout distinct from the standard header:

```c
typedef struct {
    _Atomic int64_t rc;   /* reference count */
    int64_t len;          /* byte length (UTF-8) */
    char data[];          /* null-terminated UTF-8 data */
} march_string;
```

**Allocation size**: `sizeof(march_string) + len + 1` (includes null terminator)

### String Creation and Conversion

#### `march_string_lit(const char *utf8, int64_t len)`: Lines 49-57
- **Purpose**: Create a string from UTF-8 bytes
- **Parameters**: `utf8` pointer (not necessarily null-terminated), `len` byte count
- **Returns**: `march_string*` with `rc = 1`

```c
void *march_string_lit(const char *utf8, int64_t len);
```

#### `march_int_to_string(int64_t n)`: Lines 59-63
- **Purpose**: Convert integer to string (base 10)
- **Returns**: Allocated `march_string*`

```c
void *march_int_to_string(int64_t n);
```

#### `march_float_to_string(double f)`: Lines 65-69
- **Purpose**: Convert float to string (format: `%g`)
- **Returns**: Allocated `march_string*`

```c
void *march_float_to_string(double f);
```

#### `march_bool_to_string(int64_t b)`: Lines 71-73
- **Purpose**: Convert boolean (0 or nonzero) to "true" or "false"
- **Returns**: Allocated `march_string*`

```c
void *march_bool_to_string(int64_t b);
```

#### `march_string_concat(void *a, void *b)`: Lines 75-87
- **Purpose**: Concatenate two strings
- **Returns**: New string with combined content
- **Note**: Both `a` and `b` should be `march_string*` pointers

```c
void *march_string_concat(void *a, void *b);
```

#### `march_string_eq(void *a, void *b)`: Lines 89-93
- **Purpose**: Check if two strings are equal
- **Returns**: 1 (equal) or 0 (not equal)

```c
int64_t march_string_eq(void *a, void *b);
```

### String Query Operations

#### `march_string_byte_length(void *s)`: Lines 95-97
- **Returns**: Byte count (UTF-8 length)

```c
int64_t march_string_byte_length(void *s);
```

#### `march_string_is_empty(void *s)`: Lines 99-101
- **Returns**: 1 if empty or NULL, 0 otherwise

```c
int64_t march_string_is_empty(void *s);
```

#### `march_string_grapheme_count(void *s)`: Lines 774-782
- **Purpose**: Count Unicode grapheme clusters (approximate: counts non-continuation bytes)
- **Returns**: Grapheme count

```c
int64_t march_string_grapheme_count(void *s);
```

#### `march_string_contains(void *s, void *sub)`: Lines 518-527
- **Returns**: 1 if substring found, 0 otherwise; empty substring returns 1

```c
int64_t march_string_contains(void *s, void *sub);
```

#### `march_string_starts_with(void *s, void *prefix)`: Lines 529-534
- **Returns**: 1 if string starts with prefix, 0 otherwise

```c
int64_t march_string_starts_with(void *s, void *prefix);
```

#### `march_string_ends_with(void *s, void *suffix)`: Lines 536-541
- **Returns**: 1 if string ends with suffix, 0 otherwise

```c
int64_t march_string_ends_with(void *s, void *suffix);
```

### String Transformation Operations

#### `march_string_slice(void *s, int64_t start, int64_t len)`: Lines 543-551
- **Purpose**: Extract substring from `start` with length `len`
- **Behavior**: Clamps out-of-bounds parameters; negative `start` becomes 0
- **Returns**: New `march_string*`

```c
void *march_string_slice(void *s, int64_t start, int64_t len);
```

#### `march_string_split(void *s, void *sep)`: Lines 554-588
- **Purpose**: Split string on separator, return `List(String)`
- **Behavior**: Empty separator splits into individual characters
- **Returns**: March List (Cons-Nil linked list) of strings

```c
void *march_string_split(void *s, void *sep);
```

#### `march_string_split_first(void *s, void *sep)`: Lines 591-604
- **Purpose**: Split on first occurrence only
- **Returns**: `Option(Tuple(String, String))` (None if separator not found)

```c
void *march_string_split_first(void *s, void *sep);
```

#### `march_string_replace(void *s, void *old, void *new_)`: Lines 607-629
- **Purpose**: Replace first occurrence of `old` with `new_`
- **Returns**: New `march_string*` (or copy of original if not found)

```c
void *march_string_replace(void *s, void *old, void *new_);
```

#### `march_string_replace_all(void *s, void *old, void *new_)`: Lines 632-664
- **Purpose**: Replace all occurrences
- **Returns**: New `march_string*`

```c
void *march_string_replace_all(void *s, void *old, void *new_);
```

#### `march_string_to_lowercase(void *s)`: Lines 666-676
- **Purpose**: Convert ASCII characters to lowercase (UTF-8 aware)
- **Returns**: New `march_string*`

```c
void *march_string_to_lowercase(void *s);
```

#### `march_string_to_uppercase(void *s)`: Lines 678-688
- **Purpose**: Convert ASCII characters to uppercase
- **Returns**: New `march_string*`

```c
void *march_string_to_uppercase(void *s);
```

#### `march_string_trim(void *s)`: Lines 694-700
- **Purpose**: Remove leading and trailing whitespace
- **Returns**: New `march_string*`

```c
void *march_string_trim(void *s);
```

#### `march_string_trim_start(void *s)`: Lines 702-707
- **Purpose**: Remove leading whitespace only
- **Returns**: New `march_string*`

```c
void *march_string_trim_start(void *s);
```

#### `march_string_trim_end(void *s)`: Lines 709-714
- **Purpose**: Remove trailing whitespace only
- **Returns**: New `march_string*`

```c
void *march_string_trim_end(void *s);
```

#### `march_string_repeat(void *s, int64_t n)`: Lines 716-728
- **Purpose**: Repeat string `n` times
- **Behavior**: Returns empty string if `n <= 0`
- **Returns**: New `march_string*`

```c
void *march_string_repeat(void *s, int64_t n);
```

#### `march_string_reverse(void *s)`: Lines 730-740
- **Purpose**: Reverse string (byte-level, not grapheme-aware)
- **Returns**: New `march_string*`

```c
void *march_string_reverse(void *s);
```

#### `march_string_pad_left(void *s, int64_t width, void *fill)`: Lines 742-756
- **Purpose**: Left-pad to `width` with character from `fill` string
- **Returns**: New `march_string*` (or copy if already >= width)

```c
void *march_string_pad_left(void *s, int64_t width, void *fill);
```

#### `march_string_pad_right(void *s, int64_t width, void *fill)`: Lines 758-772
- **Purpose**: Right-pad to `width`
- **Returns**: New `march_string*`

```c
void *march_string_pad_right(void *s, int64_t width, void *fill);
```

### String Parsing and Search

#### `march_string_to_int(void *s)`: Lines 106-121
- **Purpose**: Parse string as decimal integer
- **Returns**: `Option(Int)` (None if invalid, Some(n) if valid)
- **Implementation**: Uses `strtoll()`, checks for trailing non-digit characters

```c
void *march_string_to_int(void *s);
```

#### `march_string_to_float(void *s)`: Lines 813-827
- **Purpose**: Parse string as float
- **Returns**: `Option(Float)` (None if invalid, Some(f) if valid)

```c
void *march_string_to_float(void *s);
```

#### `march_string_index_of(void *s, void *sub)`: Lines 785-796
- **Purpose**: Find index of first occurrence
- **Returns**: `Option(Int)` (None if not found, Some(index) if found)
- **Behavior**: Empty substring returns `Some(0)`

```c
void *march_string_index_of(void *s, void *sub);
```

#### `march_string_last_index_of(void *s, void *sub)`: Lines 799-810
- **Purpose**: Find index of last occurrence
- **Returns**: `Option(Int)` (None if not found, Some(index) if found)
- **Behavior**: Empty substring returns `Some(len)`

```c
void *march_string_last_index_of(void *s, void *sub);
```

#### `march_string_join(void *list, void *sep)`: Lines 130-171
- **Purpose**: Join list of strings with separator
- **Parameters**: `list` is `List(String)`, `sep` is separator string
- **Returns**: New `march_string*`
- **Algorithm**: Two-pass (count + allocate, then fill)

```c
void *march_string_join(void *list, void *sep);
```

## List Operations

### `march_list_append(void *a, void *b)`: Lines 832-840
- **Purpose**: Append list `b` to list `a`
- **Parameters**: Both are March `List` values (Cons-Nil linked lists)
- **Returns**: New list (or `b` if `a` is Nil)
- **Note**: Recursive implementation, may be inefficient for very long lists

```c
void *march_list_append(void *a, void *b);
```

### `march_list_concat(void *lists)`: Lines 843-850
- **Purpose**: Flatten `List(List(a))` to `List(a)`
- **Returns**: Single flattened list

```c
void *march_list_concat(void *lists);
```

## Input/Output

### `march_print(void *s)`: Lines 175-178
- **Purpose**: Write string to stdout without newline
- **Behavior**: Uses `fwrite()` directly on string data

```c
void march_print(void *s);
```

### `march_println(void *s)`: Lines 180-184
- **Purpose**: Write string to stdout with trailing newline
- **Behavior**: `fwrite()` + `putchar('\n')`

```c
void march_println(void *s);
```

### `march_panic(void *s)`: Lines 188-195
- **Purpose**: Print error message to stderr and exit with status 1
- **Behavior**: Outputs "panic: " prefix, then message, then newline

```c
void march_panic(void *s);
```

## Actor Runtime

The actor runtime implements **lightweight processes with message-passing concurrency**. Each actor is a heap object containing state and a dispatch function. Actors run as **green threads** on the M:N work-stealing scheduler in `runtime/march_scheduler.c`. The public actor API (`march_spawn`/`march_send`/`march_kill`/`march_is_alive`) lives in `runtime/march_runtime.c` and is declared in `march_runtime.h`; all of these take a `void *actor` (the actor heap object), not a separate handle struct.

> **Note (architecture).** An earlier design used a `struct march_process` with a per-process mutex/condvar mailbox, a global run queue, and a fixed pool of `scheduler_worker()` threads tuned by `MARCH_SCHEDULER_THREADS`. **That design has been deleted.** None of `march_process`, `msg_node` (the run-queue node), `scheduler_worker`, or `MARCH_SCHEDULER_THREADS` exist in the runtime any longer. The current design is the green-thread scheduler described below.

### Data Structures

#### Actor Layout
An actor is a heap object with this layout:
- Field 0 (offset 16): `dispatch`, a pointer to closure for message handling
- Field 1+ (offset 24+): **state fields** (user-defined)

`march_spawn` returns the actor pointer itself; there is no separate handle object.

#### Actor metadata (`march_actor_meta`, in `runtime/march_runtime.c`)
A side table (`g_actor_tbl`, a hash table keyed by actor pointer) maps each actor to its scheduling metadata:

```c
typedef struct march_actor_meta {
    march_proc                *green_thread;  /* Green thread running this actor's loop */
    struct march_actor_meta   *tbl_next;      /* Hash-table chain */
    /* ... liveness / link bookkeeping ... */
} march_actor_meta;
```

Each actor runs as a green thread (`march_proc`, defined in `march_scheduler.c`). The green-thread loop (`actor_green_thread`) blocks in the scheduler until a message arrives in the process's mailbox, then calls the actor's dispatch closure (FBIP: dispatch may mutate state in place when RC is 1).

### Scheduler (`runtime/march_scheduler.c`)

The scheduler is **M:N**: N OS threads each run a scheduler loop, and each owns a **Chase-Lev work-stealing deque** of READY processes. The owner pushes/pops from the bottom (LIFO for cache locality); idle schedulers steal from the top of other schedulers' deques (FIFO for load balance). Context switching uses `ucontext_t` / `swapcontext` stackful coroutines, each `march_proc` having its own `mmap`'d stack. Preemption is reduction-budget-based (each process gets a reduction quantum, reset on schedule-in).

#### `march_sched_spawn(void (*fn)(void *), void *arg)` → `march_proc *`
Allocates a `march_proc`, sets up its stack/context with a trampoline that calls `march_sched_exit()` on return, and enqueues it READY.

#### `march_sched_send(march_proc *p, void *msg)`
Pushes `msg` into the target process's mailbox and wakes it if WAITING. This is the primitive that `march_send` delegates to.

### Spawn and Send

#### `march_spawn(void *actor)`: `runtime/march_runtime.c`
- **Purpose**: Create the green thread that runs an actor's message loop
- **Parameters**: `actor` is a March heap object with a dispatch field
- **Returns**: the `actor` pointer (no wrapper handle)
- **Behavior**: looks up or creates a `march_actor_meta`, spawns `actor_green_thread` via `march_sched_spawn`, and stores the resulting `march_proc *` in `meta->green_thread`

```c
void *march_spawn(void *actor);
```

#### `march_send(void *actor, void *msg)`: `runtime/march_runtime.c`
- **Purpose**: Deliver a message to the actor's mailbox
- **Returns**: the result of dispatch (or a synchronous reply for call-style sends)
- **Behavior**: finds the actor's `march_actor_meta`, then calls `march_sched_send(meta->green_thread, msg)` to enqueue and wake the green thread

> **Note.** `march_send` does **not** call `march_incrc` on the message; Perceus at the call site handles the ownership transfer.

```c
void *march_send(void *actor, void *msg);
```

### Query and Control

#### `march_is_alive(void *actor)`: `runtime/march_runtime.h`
- **Returns**: 1 (alive) or 0 (dead)

```c
int64_t march_is_alive(void *actor);
```

#### `march_kill(void *actor)`: `runtime/march_runtime.h`
- **Purpose**: Mark the actor dead so its green thread stops processing messages

```c
void march_kill(void *actor);
```

#### `march_actor_get_int(void *actor, int64_t index)`: `runtime/march_runtime.c`
- **Purpose**: Drain pending messages, then read an integer state field by index

```c
int64_t march_actor_get_int(void *actor, int64_t index);
```

## Float Operations

### Float Conversions

#### `march_int_to_float(int64_t n)`: Line 442
```c
double march_int_to_float(int64_t n);
```

### Float Arithmetic and Rounding

#### `march_float_abs(double f)`: Line 437
```c
double march_float_abs(double f);
```

#### `march_float_ceil(double f)`: Line 438
```c
int64_t march_float_ceil(double f);
```

#### `march_float_floor(double f)`: Line 439
```c
int64_t march_float_floor(double f);
```

#### `march_float_round(double f)`: Line 440
```c
int64_t march_float_round(double f);
```

#### `march_float_truncate(double f)`: Line 441
```c
int64_t march_float_truncate(double f);
```

## Math Functions

All trigonometric and transcendental functions are thin wrappers around C math library functions.

### Trigonometric Functions (Lines 446-452)
```c
double march_math_sin(double f);
double march_math_cos(double f);
double march_math_tan(double f);
double march_math_asin(double f);
double march_math_acos(double f);
double march_math_atan(double f);
double march_math_atan2(double y, double x);
```

### Hyperbolic Functions (Lines 453-455)
```c
double march_math_sinh(double f);
double march_math_cosh(double f);
double march_math_tanh(double f);
```

### Exponential and Logarithmic Functions (Lines 456-462)
```c
double march_math_sqrt(double f);
double march_math_cbrt(double f);
double march_math_exp(double f);
double march_math_exp2(double f);
double march_math_log(double f);
double march_math_log2(double f);
double march_math_log10(double f);
double march_math_pow(double b, double e);
```

## File System Operations

### `march_file_exists(void *s)`: Lines 854-859
- **Purpose**: Check if file exists and is a regular file
- **Parameters**: `s` is a `march_string*` path
- **Returns**: 1 (exists) or 0 (does not exist)
- **Implementation**: Uses `stat()` and `S_ISREG()` macro

```c
int64_t march_file_exists(void *s);
```

### `march_dir_exists(void *s)`: Lines 861-866
- **Purpose**: Check if directory exists
- **Returns**: 1 (exists) or 0 (does not exist)
- **Implementation**: Uses `stat()` and `S_ISDIR()` macro

```c
int64_t march_dir_exists(void *s);
```

## Value Pretty-Printing

### `march_value_to_string(void *v)`: Lines 873-880
- **Purpose**: Convert arbitrary March value to string representation
- **Current implementation**: Returns "nil" for NULL, "#<tag:N>" for heap objects
- **Returns**: New `march_string*`
- **Future**: Can register constructor names for better output

```c
void *march_value_to_string(void *v);
```

## HTTP and Networking Runtime

The HTTP runtime provides TCP networking, HTTP protocol handling, and WebSocket support. For detailed documentation, see `specs/features/http.md`.

### Key Components

- **TCP**: `march_tcp_listen()`, `march_tcp_accept()`, `march_tcp_recv_http()`, `march_tcp_send_all()`, `march_tcp_close()`
- **HTTP**: `march_http_parse_request()`, `march_http_serialize_response()`
- **HTTP Server**: `march_http_server_listen()` dispatches to `march_evloop_server_listen()` (kqueue/epoll event loop, default) and falls back to a bounded thread-per-connection loop
- **WebSocket**: `march_ws_handshake()`, `march_ws_recv()`, `march_ws_send()`, `march_ws_select()`

### Supporting Functions

- **Base64**: `base64_encode()` (in `base64.c`) for WebSocket accept key
- **SHA-1**: `sha1()` (in `sha1.c`) for WebSocket handshake hash

## Compiler Integration

The compiler (in `lib/tir/llvm_emit.ml`) maps March builtin names to C runtime function names and generates calls to these functions.

### Builtin Function Mapping

The `mangle_extern()` function (lines 250-335 of `llvm_emit.ml`) defines the mapping:

| March Name | C Function | Lines |
|------------|-----------|-------|
| `panic` | `march_panic` | 251 |
| `print` | `march_print` | 253 |
| `println` | `march_println` | 252 |
| `string_concat`, `++` | `march_string_concat` | 257 |
| `string_eq` | `march_string_eq` | 258 |
| `string_byte_length` | `march_string_byte_length` | 259 |
| `string_is_empty` | `march_string_is_empty` | 260 |
| `string_to_int` | `march_string_to_int` | 261 |
| `string_join` | `march_string_join` | 262 |
| `spawn` | `march_spawn` | 266 |
| `send` | `march_send` | 265 |
| `kill` | `march_kill` | 263 |
| `is_alive` | `march_is_alive` | 264 |
| `actor_get_int` | `march_actor_get_int` | 267 |
| All string operations | `march_string_*` | 307-327 |
| All math functions | `march_math_*` | 288-305 |
| All float functions | `march_float_*` | 281-286 |
| All list operations | `march_list_*` | 329-330 |
| All file operations | `march_file_*`, `march_dir_*` | 332-333 |
| All HTTP operations | `march_tcp_*`, `march_http_*`, `march_ws_*` | 268-279 |

### Return Type Declarations

The `builtin_ret_ty()` function (lines 186-247) declares return types for builtins:
- **String functions**: Return `TString` or specialized `Option`/`List` types
- **Actor functions**: Return `TUnit`, `TBool`, or `Option(Unit)`
- **Math functions**: Return `TFloat`
- **List functions**: Return `TCon("List", [...])`

### Linking Process

The compiler:
1. Emits LLVM IR with function calls to external C runtime functions
2. Compiles IR to object files using LLVM
3. Links against `runtime/march_runtime.c` and `runtime/march_http.c`
4. Produces final executable

## Reference Counting Semantics

### RC Initialization
- New heap objects start with `rc = 1`
- Constructor calls consume their inputs (caller owns result)

### RC Operations in Code
- **Function returns**: Caller receives `rc = 1` ownership
- **Function parameters**: Callee receives ownership (caller's ref is consumed)
- **Pattern matching**: `march_decrc_freed()` returns 1 if object is freed; used to avoid redundant IncRC on extracted sub-values

### Thread Safety
- All RC operations use atomic operations
- `memory_order_relaxed` for non-critical increments
- `memory_order_acq_rel` for decrements (ensures happens-before semantics)

## Known Limitations

1. **Cycle collection**: Reference counting is the primary memory discipline; in addition, each process has a semi-space copying collector (`march_gc.c`, see Phase 5 below) that reclaims dead objects within its arena. Cross-process reference cycles still leak (per-process GC cannot trace across heaps).
2. **String operations are UTF-8 aware but not fully Unicode-aware**: Reverse, grapheme counting, etc. may not handle all edge cases
3. **HTTP server limitations**:
   - The default server is the event loop (`march_http_evloop.c`); the thread-per-connection path (`march_http.c`) is a bounded fallback
   - `max_conns` / `idle_timeout` parameters not fully enforced on every path (TODO)
5. **WebSocket frame size limit**: 16 MB per frame
6. **No dynamic memory pool**: All allocations go through `malloc()`/`calloc()`
7. **SHA-1 for WebSocket is not cryptographically secure**: Only for handshake use

## Typical Compilation Flow

1. **March source** → (March compiler) → **TIR (typed intermediate representation)**
2. **TIR** → (llvm_emit.ml) → **LLVM IR text**
3. **LLVM IR** → (llc) → **object file**
4. **Object file + runtime** → (linker) → **executable**

The compiler generates function definitions in LLVM and declares external references to C runtime functions. The linker resolves these references to the implementations in `march_runtime.o` and `march_http.o`.

## Example: Allocating and Freeing a List Node

```c
/* Allocate a Cons(head, tail) list node */
void *head = /* some value */;
void *tail  = /* some list */;

void *node = march_alloc(16 + 16);  /* header + 2 pointer fields */
int32_t *tp = (int32_t *)((char *)node + 8);
tp[0] = 1;  /* tag = Cons */
void **fields = (void **)((char *)node + 16);
fields[0] = head;  /* first field: head */
fields[1] = tail;  /* second field: tail */

/* node now has rc = 1, owned by caller */

/* Later: free when no longer needed */
march_decrc(node);  /* rc becomes 0, object is freed */
```

## Perceus and FBIP

The runtime works in concert with **Perceus** reference counting (compiler-generated RC operations) and **FBIP (First-class In-place Functional Programming)**.

- **Perceus**: Compiler inserts `march_incrc()` and `march_decrc()` calls based on usage analysis
- **FBIP**: When an object's RC is 1, the actor dispatch code temporarily sets it to 1 again (from saved value) to allow in-place mutation, then restores the original count

This allows actors to mutate their state in-place efficiently while maintaining reference counting invariants.

> **Update (March 20, 2026, Track C):** The FBIP RC data race has been fixed. The save/restore of RC during actor dispatch now uses proper synchronization to prevent concurrent RC modifications from being silently clobbered. The scheduler also now processes multiple messages per cycle (fixing starvation under high throughput) and the `scheduled` flag race has been resolved. All changes passed ThreadSanitizer.

---

## Phase 5: Per-Process Heap and Message Passing (2026-03-25)

This phase adds Layer 3 of the stratified GC design (`specs/gc_design.md`), per-actor arena heaps, along with cross-heap message passing and a per-process semi-space GC.

### Per-Process Bump Allocator (`runtime/march_heap.h`, `runtime/march_heap.c`)

Each process owns a `march_heap_t` with a linked list of 64 KiB arena blocks.  All allocation uses a bump pointer: no locks, no synchronization.

```c
march_heap_t h;
march_heap_init(&h);

/* Allocate a 1-field object (24 bytes: 16-byte header + 8-byte field) */
void *obj = march_process_alloc(&h, 24);

/* O(1) arena death: frees all blocks regardless of how many objects */
march_heap_destroy(&h);
```

Key properties:
- **Bump pointer**: each allocation is a pointer increment + memset (~5 ns)
- **No locks**: safe only from the owning process (no cross-thread access)
- **Hidden metadata**: a `march_alloc_meta` (8 bytes) is stored before each object; the returned pointer is the standard `march_hdr` start
- **Arena growth**: blocks double from 64 KiB up to 4 MiB; oversized objects get their own block
- **O(1) process death**: `march_heap_destroy` frees one `malloc` per block, not one per object

#### Fragmentation tracking

`march_heap_record_death(heap, sz)` is called by `march_decrc_local` when an RC hits zero.  It decrements `live_bytes`, enabling `march_heap_should_gc` to detect when >50% of allocated memory is dead.

### Cross-Heap Message Passing (`runtime/march_message.h`, `runtime/march_message.c`)

Two operations for value transfer between process heaps:

**`march_msg_copy(src, dst, value)`**: deep copy for non-linear values:
- Recursively copies all reachable values from `src` into `dst`
- Uses a hash-table forwarding map to handle DAG sharing (prevents exponential blowup on shared subgraphs)
- String objects (tag = -1) are copied as raw byte arrays
- Unboxed scalars (values < 4096) are returned unchanged

**`march_msg_move(src, dst, value)`**: zero-copy transfer for linear values:
- Pointer is unchanged (same address, no data movement)
- Only updates heap accounting: `src.live_bytes -= size`, `dst.live_bytes += size`
- The linear type system guarantees no other references exist in `src` after the move

The LLVM emitter (`lib/tir/llvm_emit.ml`) chooses between these at compile time: when a `send` call's message argument has `v_lin = Lin` in the TIR, it emits `march_send_linear` (which uses the move path) instead of `march_send` (copy path).

### MPSC Mailbox with Selective Receive (`march_mailbox_t` in `march_message.h`)

A per-process lock-free mailbox:
- **Producers** push to an atomic Treiber stack (`inbox`)
- **Consumer** pops from a save queue first, then flips the inbox stack into delivery (FIFO) order
- **Selective receive**: `march_mailbox_save(mb, msg)` parks a message for later without losing it; the save queue is checked before the inbox on the next `pop`

```c
march_mailbox_t mb;
march_mailbox_init(&mb);

/* Multi-producer push (any thread) */
march_mailbox_push(&mb, msg);

/* Single-consumer pop (owning process only) */
void *m = march_mailbox_pop(&mb);

/* Skip a message for now (selective receive) */
march_mailbox_save(&mb, m);
```

### Semi-Space Copying Collector (`runtime/march_gc.h`, `runtime/march_gc.c`)

When `march_heap_should_gc` returns true, `march_gc_collect` runs a two-pass semi-space collection:

1. **Pass 1 (scan from-space)**: Walk all arena blocks.  For each object with `rc > 0`, copy to `to_heap`.  Record `(from_ptr → to_ptr)` in a forwarding table.
2. **Pass 2 (fix up pointers)**: Walk `to_heap`.  For each pointer-sized field, look up the forwarding table and update if found.
3. **Teardown**: Free all from-space blocks.  Install `to_heap` as the new heap.

Properties:
- **Per-process only**: never pauses other processes
- **Only runs at safe points**: the owning process must be yielded (PROC_WAITING or similar); Perceus RC ensures all live objects have `rc > 0`
- **Exact pointer scan**: uses `n_fields` from `march_alloc_meta` to bound the field scan; the forwarding-table lookup guards against scalar field confusion

### Linear Send Optimization in the LLVM Emitter

`lib/tir/llvm_emit.ml` now has a special `EApp` case:

```ocaml
(* Send with linear message: emit march_send_linear (zero-copy move) *)
| Tir.EApp (f, [actor_atom; msg_atom])
  when f.Tir.v_name = "send"
    && (match msg_atom with
        | Tir.AVar v -> v.Tir.v_lin = Tir.Lin
        | _ -> false) ->
  (* emit march_send_linear instead of march_send *)
```

When the TIR typechecker has proved the message is linear, the emitted code calls `march_send_linear` rather than `march_send`.  This is a compile-time hint that propagates to the runtime's message-passing layer without any overhead at the call site.

The LLVM preamble now also declares `march_msg_copy`, `march_msg_move`, and `march_process_alloc` for future use by the compiler backend when direct heap access is needed.
