# March C Runtime Documentation

## Overview

The March language runtime is a C-based system providing core functionality for compiled March programs. The runtime implements:

- **Memory management**: Heap allocation, reference counting (RC), and deallocation
- **String system**: String literals, operations, conversions, and transformations
- **Actor runtime**: Lightweight process scheduler with message passing
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

| File | Lines | Purpose |
|------|-------|---------|
| `runtime/march_runtime.h` | ~114 | Core runtime function declarations |
| `runtime/march_runtime.c` | ~880 | Implementation of memory, string, actor, and utility functions |
| `runtime/march_http.h` | ~101 | HTTP and WebSocket function declarations |
| `runtime/march_http.c` | ~1130 | TCP, HTTP parsing/serialization, and WebSocket implementation |
| `runtime/base64.c` | ~50 | Base64 encoder for WebSocket handshake |
| `runtime/sha1.c` | ~72 | SHA-1 implementation for WebSocket handshake |

## Memory Management

### Reference Counting

The runtime uses **atomic reference counting** for thread-safe heap management. Each object starts with `rc = 1`.

> **Update (March 20, 2026, Track C):** RC operations are now fully atomic with proper memory ordering. `march_incrc` has been upgraded from `memory_order_relaxed` to proper atomic semantics, fixing the ABA race condition (H2 in correctness audit). All RC changes have passed ThreadSanitizer validation.

#### `march_alloc(int64_t sz)` — Lines 12-20
- **Purpose**: Allocate `sz` bytes on the heap (zeroed)
- **Returns**: Pointer to allocated block with `rc = 1`, `tag = 0`
- **Behavior**: Calls `calloc()`, initializes header, exits with error message on failure
- **Thread-safe**: Yes (RC initialized atomically)

```c
void *march_alloc(int64_t sz);
```

#### `march_incrc(void *p)` — Lines 24-27
- **Purpose**: Increment reference count of heap object
- **Behavior**: No-op if `p == NULL`
- **Thread-safe**: Yes (atomic fetch-add with relaxed memory order)

```c
void march_incrc(void *p);
```

#### `march_decrc(void *p)` — Lines 29-33
- **Purpose**: Decrement reference count and free object if count hits zero
- **Behavior**: No-op if `p == NULL`; uses `acquire-release` memory ordering for thread safety
- **Thread-safe**: Yes

```c
void march_decrc(void *p);
```

#### `march_decrc_freed(void *p)` — Lines 35-40
- **Purpose**: Decrement RC and return 1 if object was freed, 0 if still alive
- **Returns**: 1 (freed) or 0 (alive)
- **Use case**: Pattern matching when conditionally incrementing extracted child pointers
- **Thread-safe**: Yes

```c
int64_t march_decrc_freed(void *p);
```

#### `march_free(void *p)` — Lines 42-44
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

#### `march_string_lit(const char *utf8, int64_t len)` — Lines 49-57
- **Purpose**: Create a string from UTF-8 bytes
- **Parameters**: `utf8` pointer (not necessarily null-terminated), `len` byte count
- **Returns**: `march_string*` with `rc = 1`

```c
void *march_string_lit(const char *utf8, int64_t len);
```

#### `march_int_to_string(int64_t n)` — Lines 59-63
- **Purpose**: Convert integer to string (base 10)
- **Returns**: Allocated `march_string*`

```c
void *march_int_to_string(int64_t n);
```

#### `march_float_to_string(double f)` — Lines 65-69
- **Purpose**: Convert float to string (format: `%g`)
- **Returns**: Allocated `march_string*`

```c
void *march_float_to_string(double f);
```

#### `march_bool_to_string(int64_t b)` — Lines 71-73
- **Purpose**: Convert boolean (0 or nonzero) to "true" or "false"
- **Returns**: Allocated `march_string*`

```c
void *march_bool_to_string(int64_t b);
```

#### `march_string_concat(void *a, void *b)` — Lines 75-87
- **Purpose**: Concatenate two strings
- **Returns**: New string with combined content
- **Note**: Both `a` and `b` should be `march_string*` pointers

```c
void *march_string_concat(void *a, void *b);
```

#### `march_string_eq(void *a, void *b)` — Lines 89-93
- **Purpose**: Check if two strings are equal
- **Returns**: 1 (equal) or 0 (not equal)

```c
int64_t march_string_eq(void *a, void *b);
```

### String Query Operations

#### `march_string_byte_length(void *s)` — Lines 95-97
- **Returns**: Byte count (UTF-8 length)

```c
int64_t march_string_byte_length(void *s);
```

#### `march_string_is_empty(void *s)` — Lines 99-101
- **Returns**: 1 if empty or NULL, 0 otherwise

```c
int64_t march_string_is_empty(void *s);
```

#### `march_string_grapheme_count(void *s)` — Lines 774-782
- **Purpose**: Count Unicode grapheme clusters (approximate: counts non-continuation bytes)
- **Returns**: Grapheme count

```c
int64_t march_string_grapheme_count(void *s);
```

#### `march_string_contains(void *s, void *sub)` — Lines 518-527
- **Returns**: 1 if substring found, 0 otherwise; empty substring returns 1

```c
int64_t march_string_contains(void *s, void *sub);
```

#### `march_string_starts_with(void *s, void *prefix)` — Lines 529-534
- **Returns**: 1 if string starts with prefix, 0 otherwise

```c
int64_t march_string_starts_with(void *s, void *prefix);
```

#### `march_string_ends_with(void *s, void *suffix)` — Lines 536-541
- **Returns**: 1 if string ends with suffix, 0 otherwise

```c
int64_t march_string_ends_with(void *s, void *suffix);
```

### String Transformation Operations

#### `march_string_slice(void *s, int64_t start, int64_t len)` — Lines 543-551
- **Purpose**: Extract substring from `start` with length `len`
- **Behavior**: Clamps out-of-bounds parameters; negative `start` becomes 0
- **Returns**: New `march_string*`

```c
void *march_string_slice(void *s, int64_t start, int64_t len);
```

#### `march_string_split(void *s, void *sep)` — Lines 554-588
- **Purpose**: Split string on separator, return `List(String)`
- **Behavior**: Empty separator splits into individual characters
- **Returns**: March List (Cons-Nil linked list) of strings

```c
void *march_string_split(void *s, void *sep);
```

#### `march_string_split_first(void *s, void *sep)` — Lines 591-604
- **Purpose**: Split on first occurrence only
- **Returns**: `Option(Tuple(String, String))` (None if separator not found)

```c
void *march_string_split_first(void *s, void *sep);
```

#### `march_string_replace(void *s, void *old, void *new_)` — Lines 607-629
- **Purpose**: Replace first occurrence of `old` with `new_`
- **Returns**: New `march_string*` (or copy of original if not found)

```c
void *march_string_replace(void *s, void *old, void *new_);
```

#### `march_string_replace_all(void *s, void *old, void *new_)` — Lines 632-664
- **Purpose**: Replace all occurrences
- **Returns**: New `march_string*`

```c
void *march_string_replace_all(void *s, void *old, void *new_);
```

#### `march_string_to_lowercase(void *s)` — Lines 666-676
- **Purpose**: Convert ASCII characters to lowercase (UTF-8 aware)
- **Returns**: New `march_string*`

```c
void *march_string_to_lowercase(void *s);
```

#### `march_string_to_uppercase(void *s)` — Lines 678-688
- **Purpose**: Convert ASCII characters to uppercase
- **Returns**: New `march_string*`

```c
void *march_string_to_uppercase(void *s);
```

#### `march_string_trim(void *s)` — Lines 694-700
- **Purpose**: Remove leading and trailing whitespace
- **Returns**: New `march_string*`

```c
void *march_string_trim(void *s);
```

#### `march_string_trim_start(void *s)` — Lines 702-707
- **Purpose**: Remove leading whitespace only
- **Returns**: New `march_string*`

```c
void *march_string_trim_start(void *s);
```

#### `march_string_trim_end(void *s)` — Lines 709-714
- **Purpose**: Remove trailing whitespace only
- **Returns**: New `march_string*`

```c
void *march_string_trim_end(void *s);
```

#### `march_string_repeat(void *s, int64_t n)` — Lines 716-728
- **Purpose**: Repeat string `n` times
- **Behavior**: Returns empty string if `n <= 0`
- **Returns**: New `march_string*`

```c
void *march_string_repeat(void *s, int64_t n);
```

#### `march_string_reverse(void *s)` — Lines 730-740
- **Purpose**: Reverse string (byte-level, not grapheme-aware)
- **Returns**: New `march_string*`

```c
void *march_string_reverse(void *s);
```

#### `march_string_pad_left(void *s, int64_t width, void *fill)` — Lines 742-756
- **Purpose**: Left-pad to `width` with character from `fill` string
- **Returns**: New `march_string*` (or copy if already >= width)

```c
void *march_string_pad_left(void *s, int64_t width, void *fill);
```

#### `march_string_pad_right(void *s, int64_t width, void *fill)` — Lines 758-772
- **Purpose**: Right-pad to `width`
- **Returns**: New `march_string*`

```c
void *march_string_pad_right(void *s, int64_t width, void *fill);
```

### String Parsing and Search

#### `march_string_to_int(void *s)` — Lines 106-121
- **Purpose**: Parse string as decimal integer
- **Returns**: `Option(Int)` (None if invalid, Some(n) if valid)
- **Implementation**: Uses `strtoll()`, checks for trailing non-digit characters

```c
void *march_string_to_int(void *s);
```

#### `march_string_to_float(void *s)` — Lines 813-827
- **Purpose**: Parse string as float
- **Returns**: `Option(Float)` (None if invalid, Some(f) if valid)

```c
void *march_string_to_float(void *s);
```

#### `march_string_index_of(void *s, void *sub)` — Lines 785-796
- **Purpose**: Find index of first occurrence
- **Returns**: `Option(Int)` (None if not found, Some(index) if found)
- **Behavior**: Empty substring returns `Some(0)`

```c
void *march_string_index_of(void *s, void *sub);
```

#### `march_string_last_index_of(void *s, void *sub)` — Lines 799-810
- **Purpose**: Find index of last occurrence
- **Returns**: `Option(Int)` (None if not found, Some(index) if found)
- **Behavior**: Empty substring returns `Some(len)`

```c
void *march_string_last_index_of(void *s, void *sub);
```

#### `march_string_join(void *list, void *sep)` — Lines 130-171
- **Purpose**: Join list of strings with separator
- **Parameters**: `list` is `List(String)`, `sep` is separator string
- **Returns**: New `march_string*`
- **Algorithm**: Two-pass (count + allocate, then fill)

```c
void *march_string_join(void *list, void *sep);
```

## List Operations

### `march_list_append(void *a, void *b)` — Lines 832-840
- **Purpose**: Append list `b` to list `a`
- **Parameters**: Both are March `List` values (Cons-Nil linked lists)
- **Returns**: New list (or `b` if `a` is Nil)
- **Note**: Recursive implementation, may be inefficient for very long lists

```c
void *march_list_append(void *a, void *b);
```

### `march_list_concat(void *lists)` — Lines 843-850
- **Purpose**: Flatten `List(List(a))` to `List(a)`
- **Returns**: Single flattened list

```c
void *march_list_concat(void *lists);
```

## Input/Output

### `march_print(void *s)` — Lines 175-178
- **Purpose**: Write string to stdout without newline
- **Behavior**: Uses `fwrite()` directly on string data

```c
void march_print(void *s);
```

### `march_println(void *s)` — Lines 180-184
- **Purpose**: Write string to stdout with trailing newline
- **Behavior**: `fwrite()` + `putchar('\n')`

```c
void march_println(void *s);
```

### `march_panic(void *s)` — Lines 188-195
- **Purpose**: Print error message to stderr and exit with status 1
- **Behavior**: Outputs "panic: " prefix, then message, then newline

```c
void march_panic(void *s);
```

## Actor Runtime

The actor runtime implements **lightweight processes with message-passing concurrency**. Each actor is a heap object containing state and a dispatch function. A separate `march_process` structure wraps the actor and manages its mailbox and scheduler state.

### Data Structures

#### Actor Layout
An actor is a heap object with this layout:
- Field 0 (offset 16): `dispatch` — pointer to closure for message handling
- Field 1+ (offset 24+): **state fields** (user-defined)

#### Handle Layout
A handle (returned by `march_spawn`) is a standard March heap object (16 bytes header + 1 field):
- Field 0 (offset 16): `process_ptr` — cast to `march_process*`

#### Process Structure (Lines 213-223)
```c
typedef struct march_process {
    void               *actor;           /* reference to actor object */
    pthread_mutex_t     lock;            /* mailbox synchronization */
    pthread_cond_t      idle_cond;       /* signals when mailbox emptied */
    msg_node           *mbox_head;       /* message queue head */
    msg_node           *mbox_tail;       /* message queue tail */
    int                 scheduled;       /* 1 if currently on run queue */
    int                 processing;      /* 1 if worker thread is handling msg */
    int                 alive;           /* 0 if killed */
    struct march_process *next_runnable; /* run queue linking */
} march_process;
```

### Scheduler

The scheduler uses a **global run queue** and a **fixed thread pool** (default: 4 threads, configurable via `MARCH_SCHEDULER_THREADS`).

#### `enqueue_runnable()` — Lines 243-254
- **Purpose**: Add process to global run queue
- **Synchronization**: Locks scheduler mutex, signals work condition

#### `dequeue_runnable()` — Lines 256-268
- **Purpose**: Remove next process from run queue (blocks if empty)
- **Synchronization**: Locks scheduler mutex, waits on work condition

#### `scheduler_worker()` — Lines 272-321
- **Purpose**: Worker thread main loop
- **Algorithm**:
  1. Dequeue a process
  2. Extract one message from its mailbox
  3. Call the dispatch closure (FBIP: forces RC=1 for in-place mutation)
  4. Check for more messages; if none, unschedule and wake waiters
- **Special handling**: Temporarily sets actor RC to 1 during dispatch to enable FBIP (first-class in-place functional programming), then restores original RC. **Update (Track C):** The FBIP RC data race in actor dispatch has been fixed — RC save/restore now uses proper synchronization to prevent concurrent RC modifications from being clobbered.

#### `init_scheduler_once()` — Lines 323-331
- **Purpose**: Create fixed thread pool (one-time initialization)
- **Threads**: Created detached, run until program exits

### Spawn and Send

#### `march_spawn(void *actor)` — Lines 341-360
- **Purpose**: Create a lightweight process for an actor
- **Parameters**: `actor` is a March heap object with dispatch field
- **Returns**: Handle (24-byte object with process pointer in field 0)
- **Behavior**:
  - Creates `march_process` structure
  - Increments actor RC (process owns a reference)
  - Initializes mutex and condition variable
  - Sets alive = 1, scheduled = 0
- **Thread-safe**: Yes (all fields initialized before returning)

```c
void *march_spawn(void *actor);
```

#### `march_send(void *handle, void *msg)` — Lines 364-402
- **Purpose**: Send message to process mailbox
- **Parameters**: `handle` returned by `march_spawn`, `msg` is any March value
- **Returns**: `Option(Unit)` (None if dead, Some(()) if enqueued)
- **Algorithm**:
  1. Check if alive; return None if dead
  2. Allocate message node, append to mailbox tail
  3. If process not scheduled, enqueue it; else signal existing scheduled state
- **Thread-safe**: Yes (locks process mutex)

> **Update (March 20, 2026, Track C):** `march_send` no longer increments message RC. The previous double-increment (once by Perceus, once by `march_send`) caused every sent message to leak. The ownership semantics have been resolved: Perceus handles the ownership transfer, and `march_send` no longer takes a redundant reference.

```c
void *march_send(void *handle, void *msg);
```

### Query and Control

#### `march_is_alive(void *handle)` — Lines 416-419
- **Purpose**: Check if process is still alive
- **Returns**: 1 (alive) or 0 (dead)

```c
int64_t march_is_alive(void *handle);
```

#### `march_kill(void *handle)` — Lines 406-412
- **Purpose**: Mark process as dead (no longer processes messages)
- **Behavior**: Sets alive = 0, broadcasts condition to wake waiters

```c
void march_kill(void *handle);
```

#### `march_actor_get_int(void *handle, int64_t index)` — Lines 423-433
- **Purpose**: Drain remaining messages, then read integer state field
- **Parameters**: `index` is the field number (0-based; index 0 refers to first user-defined field)
- **Behavior**: Blocks until mailbox is drained and processing completes
- **Returns**: `int64_t` value of `actor[4 + index]` (field layout offset)

```c
int64_t march_actor_get_int(void *handle, int64_t index);
```

## Float Operations

### Float Conversions

#### `march_int_to_float(int64_t n)` — Line 442
```c
double march_int_to_float(int64_t n);
```

### Float Arithmetic and Rounding

#### `march_float_abs(double f)` — Line 437
```c
double march_float_abs(double f);
```

#### `march_float_ceil(double f)` — Line 438
```c
int64_t march_float_ceil(double f);
```

#### `march_float_floor(double f)` — Line 439
```c
int64_t march_float_floor(double f);
```

#### `march_float_round(double f)` — Line 440
```c
int64_t march_float_round(double f);
```

#### `march_float_truncate(double f)` — Line 441
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

### `march_file_exists(void *s)` — Lines 854-859
- **Purpose**: Check if file exists and is a regular file
- **Parameters**: `s` is a `march_string*` path
- **Returns**: 1 (exists) or 0 (does not exist)
- **Implementation**: Uses `stat()` and `S_ISREG()` macro

```c
int64_t march_file_exists(void *s);
```

### `march_dir_exists(void *s)` — Lines 861-866
- **Purpose**: Check if directory exists
- **Returns**: 1 (exists) or 0 (does not exist)
- **Implementation**: Uses `stat()` and `S_ISDIR()` macro

```c
int64_t march_dir_exists(void *s);
```

## Value Pretty-Printing

### `march_value_to_string(void *v)` — Lines 873-880
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
- **HTTP Server**: `march_http_server_listen()` (thread-per-connection model)
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

1. **No GC**: Only reference counting; circular data structures will leak
2. **String operations are UTF-8 aware but not fully Unicode-aware**: Reverse, grapheme counting, etc. may not handle all edge cases
3. **Scheduler thread pool is fixed-size**: Configured at compile-time via `MARCH_SCHEDULER_THREADS`
4. **HTTP server limitations**:
   - `max_conns` parameter not enforced (TODO)
   - `idle_timeout` parameter not set (TODO)
   - Thread-per-connection model may not scale to thousands of concurrent connections
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

This phase adds Layer 3 of the stratified GC design (`specs/gc_design.md`) — per-actor arena heaps — along with cross-heap message passing and a per-process semi-space GC.

### Per-Process Bump Allocator (`runtime/march_heap.h`, `runtime/march_heap.c`)

Each process owns a `march_heap_t` with a linked list of 64 KiB arena blocks.  All allocation uses a bump pointer — no locks, no synchronization.

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

**`march_msg_copy(src, dst, value)`** — deep copy for non-linear values:
- Recursively copies all reachable values from `src` into `dst`
- Uses a hash-table forwarding map to handle DAG sharing (prevents exponential blowup on shared subgraphs)
- String objects (tag = -1) are copied as raw byte arrays
- Unboxed scalars (values < 4096) are returned unchanged

**`march_msg_move(src, dst, value)`** — zero-copy transfer for linear values:
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
- **Only runs at safe points**: the owning process must be yielded (PROC_WAITING or similar) — Perceus RC ensures all live objects have `rc > 0`
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
