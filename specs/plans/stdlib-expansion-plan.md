# Stdlib Expansion — Implementation Plan

## Current State

### What Exists

**20 stdlib modules** (~4,512 lines of March code) in `stdlib/`:

| Module | File | Lines | Status |
|--------|------|-------|--------|
| prelude | `prelude.march` | ~100 | Complete — auto-imported |
| list | `list.march` | ~500 | Complete — map, filter, fold, head, tail, etc. |
| option | `option.march` | ~100 | Complete — map, flat_map, unwrap, etc. |
| result | `result.march` | ~100 | Complete — map, flat_map, unwrap_or, etc. |
| string | `string.march` | ~400 | Partial — split, concat, trim, case; missing interpolation |
| math | `math.march` | ~80 | Complete — trig, sqrt, exp, log |
| sort | `sort.march` | ~750 | Complete — merge sort, polymorphic |
| seq | `seq.march` | ~150 | Complete — church-encoded lazy sequences |
| iolist | `iolist.march` | ~80 | Basic — append, flatten |
| enum | `enum.march` | ~100 | Partial — map, filter |
| iterable | `iterable.march` | ~50 | Stub |
| path | `path.march` | ~100 | Complete — pure path operations |
| file | `file.march` | ~100 | Basic — read, write, exists |
| dir | `dir.march` | ~60 | Basic — list, exists |
| csv | `csv.march` | ~150 | Basic — streaming and eager parsing |
| http | `http.march` | ~350 | Complete — types, Request, Response |
| http_transport | `http_transport.march` | ~200 | Complete — TCP connect/send/recv |
| http_client | `http_client.march` | ~500 | Complete — middleware pipeline, redirects |
| http_server | `http_server.march` | ~250 | Basic — Conn type, pipeline runner |
| websocket | `websocket.march` | ~150 | Basic — frame types, handshake |

**C runtime builtins** (`runtime/march_runtime.c`, `runtime/march_http.c`):
- 49+ registered builtins covering float, math, string, list, file/dir, actor, HTTP operations
- All March stdlib functions ultimately call these C builtins

### What's Missing

**String system** — Per `2026-03-19-string-system-design.md`:
- No 3-tier string hierarchy (Bytes → String → Rope)
- No short string optimization (≤15 bytes inline)
- No zero-copy substrings
- No string interpolation (`${}` syntax)
- No `Display` interface for custom formatting
- No `Debug` interface for debug output
- `IOList` is basic; no efficient builder pattern

**Collections**:
- No `Map` (hash map or tree map)
- No `Set` (hash set or tree set)
- No `Queue` / `Deque`
- No `Array` (mutable, contiguous)
- No `Vector` (growable array)
- `List` is the only collection type

**Standard interfaces** — Per `specs/stdlib_design.md`:
- `Eq`, `Ord`, `Show`, `Hash`, `Num`, `Fractional`, `Default`, `Mappable`, `Iterable`, `Interpolatable`, `Textual` are designed but not implemented as enforceable interfaces
- Currently these are conventions, not checked by the compiler

**Missing modules**:
- `json` — JSON parsing and serialization
- `regex` — Regular expressions
- `time` / `datetime` — Date and time handling
- `random` — Random number generation
- `crypto` — Cryptographic primitives (beyond BLAKE3 which is in the compiler)
- `env` — Environment variable access
- `process` — Subprocess management
- `channel` — Synchronous channels for task communication
- `format` / `printf` — Formatted output
- `bytes` — Raw byte manipulation

---

## Target State (from specs)

Per `specs/stdlib_design.md`, `2026-03-19-string-system-design.md`, `specs/design.md`:

1. **3-tier string system**: `Bytes` (raw), `String` (validated UTF-8 with SSO), `Rope` (for large strings/editors)
2. **Standard interfaces**: `Eq`, `Ord`, `Show`, `Hash` implemented and enforced for all stdlib types
3. **Collections**: `Map`, `Set` as persistent functional data structures (HAMTs or balanced trees)
4. **String interpolation**: `"Hello, ${name}!"` calls `Display.show` on interpolated values
5. **IOList**: Efficient string building via cons-list of fragments; `to_string` for final concatenation
6. **File I/O**: Scoped resource cleanup (`with_lines`, `with_chunks`), streaming, Result-based errors
7. **JSON**: Parse/serialize with streaming support
8. **Formatting**: `Display` for user-facing output, `Debug` for developer-facing output

---

## Implementation Steps

### Phase 1: Standard Interfaces (Medium complexity, depends on type-system-completion-plan.md Part A)

**Step 1.1: Define core interfaces in stdlib**
- File: `stdlib/prelude.march` or new `stdlib/interfaces.march`
- Define `Eq`, `Ord`, `Show`, `Hash`, `Default` as March interfaces
- These are the foundation for all collection operations
- Estimated effort: 1 day

**Step 1.2: Implement interfaces for primitive types**
- Files: `stdlib/prelude.march`, `lib/typecheck/typecheck.ml`
- `impl Eq for Int`, `impl Eq for Float`, `impl Eq for String`, `impl Eq for Bool`
- Same for `Ord`, `Show`, `Hash`
- For builtins (Int, Float, String), these delegate to C runtime functions
- Estimated effort: 2 days
- Dependency: Interface constraint discharge (type-system-completion-plan.md Part A) must work for these to be enforced

**Step 1.3: Implement interfaces for compound types**
- File: `stdlib/list.march`, `stdlib/option.march`, `stdlib/result.march`
- `impl Eq for List(a) where a: Eq`
- `impl Ord for List(a) where a: Ord` (lexicographic)
- `impl Show for List(a) where a: Show`
- Estimated effort: 3 days

**Step 1.4: Display and Debug interfaces**
- File: `stdlib/prelude.march` or `stdlib/display.march`
- `Display` — user-facing string representation
- `Debug` — developer-facing representation (shows structure, e.g., `Some(42)` not `42`)
- `impl Display for Int`, etc.
- Estimated effort: 2 days

### Phase 2: String System (High complexity, Medium risk)

**Step 2.1: Short string optimization in C runtime**
- File: `runtime/march_runtime.c`
- Current string representation: heap-allocated byte array
- Add SSO: strings ≤15 bytes stored inline in the value slot (no heap allocation)
- Representation: tag bit to distinguish inline vs. heap
- Estimated effort: 5 days
- Risk: All string builtins need to handle both representations; extensive testing required

**Step 2.2: Zero-copy substrings**
- File: `runtime/march_runtime.c`
- `string_slice(s, start, end)` returns a view into the original string (pointer + offset + length)
- Reference count the parent string to prevent premature deallocation
- Eager copy when substring length < 1/4 of parent (avoid holding large strings alive for small substrings)
- Estimated effort: 3 days

**Step 2.3: String interpolation**
- Files: `lib/lexer/lexer.mll`, `lib/parser/parser.mly`, `lib/desugar/desugar.ml`
- Lexer: recognize `${` inside string literals, switch to expression mode
- Parser: parse interpolated expressions inside strings
- Desugar: `"Hello, ${name}!"` → `string_concat("Hello, ", Display.show(name), "!")`
- Alternatively: desugar to `IOList.append(...)` for efficiency
- Estimated effort: 5 days
- Risk: Lexer state management for nested interpolation (`"${a + "${b}"}"`); may need a stack

**Step 2.4: IOList enhancement**
- File: `stdlib/iolist.march`, `runtime/march_runtime.c`
- Add builder pattern: `IOList.new() |> IOList.add("hello") |> IOList.add(42) |> IOList.to_string()`
- Efficient `to_string`: single allocation, copy all fragments once
- C runtime support: `march_iolist_to_string` that computes total length, allocates, copies
- Estimated effort: 3 days

**Step 2.5: Rope type**
- File: new `stdlib/rope.march`, `runtime/march_runtime.c`
- Balanced binary tree of string chunks
- O(log n) insert/delete at arbitrary position
- O(1) concatenation
- Useful for text editors and large document manipulation
- Estimated effort: 5 days
- Risk: Complex balancing logic; defer to post-v1 if time-constrained

### Phase 3: Collections (Medium complexity, Medium risk)

**Step 3.1: Persistent hash map (HAMT)**
- File: new `stdlib/map.march`, `runtime/march_runtime.c`
- Hash Array Mapped Trie: O(log32 n) lookup/insert/delete, effectively O(1) for practical sizes
- Structural sharing for persistence (functional updates create new paths, share unchanged subtrees)
- Requires `Hash` interface on keys, `Eq` for collision resolution
- Estimated effort: 8 days
- Risk: HAMT is complex; alternative is simpler balanced BST (red-black tree) with O(log n) operations

**Step 3.2: Persistent set**
- File: new `stdlib/set.march`
- Implemented as `Map(a, Unit)` wrapper
- `add`, `remove`, `member`, `union`, `intersection`, `difference`
- Estimated effort: 2 days (given Map exists)

**Step 3.3: Queue and Deque**
- File: new `stdlib/queue.march`
- Banker's deque: two lists (front and rear) for amortized O(1) push/pop on both ends
- Estimated effort: 3 days

**Step 3.4: Array (mutable, contiguous)**
- Files: new `stdlib/array.march`, `runtime/march_runtime.c`
- Fixed-size mutable array with O(1) indexed access
- Requires linear/affine type for safe mutation
- C runtime: `march_array_new(size)`, `march_array_get(arr, idx)`, `march_array_set(arr, idx, val)`
- Estimated effort: 5 days
- Risk: Mutable arrays interact with linearity checking and RC; need careful design

### Phase 4: File I/O Enhancement (Low complexity, Low risk)

**Step 4.1: Scoped resource cleanup**
- File: `stdlib/file.march`, `runtime/march_runtime.c`
- `File.with_open(path, fn(handle) -> a) -> Result(a, FileError)` — guaranteed close
- Implementation: open file, call function, close in finally block (or use linear types)
- Estimated effort: 2 days

**Step 4.2: Streaming file operations**
- File: `stdlib/file.march`
- `File.with_lines(path, fn(line) -> Step(acc))` — fold over lines without loading entire file
- `File.with_chunks(path, chunk_size, fn(chunk) -> Step(acc))` — fold over byte chunks
- `Step(a)` type: `Continue(a)` or `Stop(a)` for early termination
- Estimated effort: 3 days

**Step 4.3: FileError ADT**
- File: `stdlib/file.march`
- `type FileError = NotFound | Permission | IsDirectory | NotEmpty | IoError(String)`
- Map C errno values to FileError variants
- Estimated effort: 1 day

### Phase 5: Additional Modules (Medium complexity, Low risk)

**Step 5.1: JSON module**
- File: new `stdlib/json.march`, `runtime/march_runtime.c`
- `type Json = Null | Bool(Bool) | Number(Float) | Str(String) | Array(List(Json)) | Object(Map(String, Json))`
- `Json.parse(string) -> Result(Json, ParseError)`
- `Json.to_string(json) -> String`
- Streaming parser for large JSON documents
- Estimated effort: 8 days

**Step 5.2: Random module**
- File: new `stdlib/random.march`, `runtime/march_runtime.c`
- `Random.int(min, max)`, `Random.float(min, max)`, `Random.choice(list)`
- Uses xoshiro256** or similar fast PRNG
- Requires `Cap(Random)` or `Cap(IO)` capability
- Estimated effort: 3 days

**Step 5.3: Time module**
- File: new `stdlib/time.march`, `runtime/march_runtime.c`
- `Time.now() -> Timestamp` (requires `Cap(IO.Clock)`)
- `Time.diff(t1, t2) -> Duration`
- `Time.format(t, pattern) -> String`
- Estimated effort: 4 days

**Step 5.4: Environment module**
- File: new `stdlib/env.march`, `runtime/march_runtime.c`
- `Env.get(key) -> Option(String)` (requires `Cap(IO.Process)`)
- `Env.set(key, value)` (requires `Cap(IO.Process)`)
- `Env.args() -> List(String)` — command-line arguments
- Estimated effort: 2 days

**Step 5.5: Process module**
- File: new `stdlib/process.march`, `runtime/march_runtime.c`
- `Process.run(cmd, args) -> Result(Output, ProcessError)` (requires `Cap(IO.Process)`)
- `Output` type with `stdout`, `stderr`, `exit_code`
- Streaming variants for long-running processes
- Estimated effort: 5 days

**Step 5.6: Channel module**
- File: new `stdlib/channel.march`
- Synchronous channel for task-to-task communication
- `Channel.new() -> (Sender(a), Receiver(a))`
- `send(sender, value)` — blocks until receiver is ready
- `recv(receiver) -> a` — blocks until sender sends
- Implemented on top of the scheduler's mailbox infrastructure
- Estimated effort: 4 days
- Dependency: Concurrency plan Phase 1 (mailbox wiring)

---

## Dependencies

```
Phase 1 (Interfaces) ← depends on type-system-completion-plan.md Part A (constraint discharge)
Phase 2 (Strings) ← no blockers for Steps 2.1-2.2; Step 2.3 depends on Phase 1 for Display
Phase 3 (Collections) ← depends on Phase 1 (Hash, Eq interfaces)
Phase 4 (File I/O) ← no blockers
Phase 5 (Modules) ← Step 5.1 depends on Phase 3 (Map); Step 5.6 depends on concurrency plan

Internal:
- Phase 3 Step 3.2 (Set) depends on 3.1 (Map)
- Phase 5 Step 5.1 (JSON) depends on Phase 3 Step 3.1 (Map)
```

## Testing Strategy

### Interfaces
1. **Positive**: Sort a list of records with `Ord` impl — compiles and works
2. **Negative**: Sort a list of records without `Ord` impl — compile error
3. **Derived**: Show a `List(Option(Int))` — recursively calls Show impls
4. **Property**: `Eq` is reflexive, symmetric, transitive (property-based tests)

### Strings
1. **SSO**: Strings ≤15 bytes don't heap-allocate (verify with instrumented allocator)
2. **Zero-copy**: `slice(large_string, 0, 5)` shares memory with original
3. **Interpolation**: `"1 + 1 = ${1 + 1}"` → `"1 + 1 = 2"`
4. **Unicode**: UTF-8 multi-byte characters handled correctly (grapheme_count, slice at codepoint boundaries)
5. **IOList**: Building a 1MB string from 1000 fragments — single allocation at `to_string`

### Collections
1. **Map**: Insert 1M elements, lookup all — correct values returned
2. **Persistence**: `let m2 = Map.insert(m1, k, v)` — `m1` unchanged, `m2` has new entry
3. **Performance**: Map lookup faster than linear List scan for N > 50
4. **Set operations**: union, intersection, difference produce correct results

### File I/O
1. **Scoped cleanup**: `with_open` closes file even if function throws
2. **Streaming**: `with_lines` processes a 1GB file without OOM
3. **Error types**: File not found → `NotFound`; permission denied → `Permission`

## Open Questions

1. **HAMT vs. Red-Black Tree for Map**: HAMT has better constant factors for small maps and is more cache-friendly. Red-black trees have simpler implementation and guaranteed O(log n). Which is the right default?

2. **Mutable arrays and linearity**: Should `Array` be a linear type (must be consumed exactly once) or use unique references (like Rust's `&mut`)? Linear arrays prevent aliasing bugs but require threading the array through every operation.

3. **String encoding**: March strings are UTF-8. Should `String.get(s, i)` return the i-th byte, codepoint, or grapheme cluster? Byte is fastest but confusing for users; grapheme is most correct but O(n). Recommendation: default to codepoint, provide `bytes` module for raw access.

4. **JSON number precision**: JSON numbers can be arbitrarily precise. `Float` loses precision for large integers. Should the JSON module use a `Number` type that can represent both Int and Float, or always use Float (like JavaScript)?

5. **Stdlib bundling**: Should stdlib modules be compiled and cached in the CAS, or always loaded from source? CAS integration (see `cas-integration-plan.md`) would make stdlib loading near-instant.

6. **Backwards compatibility**: As interfaces get added, existing code that doesn't use them should continue to work. How do we phase in interface requirements without breaking existing programs?

## Estimated Total Effort

| Phase | Effort | Risk |
|-------|--------|------|
| Phase 1: Interfaces | 8 days | Medium |
| Phase 2: String system | 21 days | Medium-High |
| Phase 3: Collections | 18 days | Medium |
| Phase 4: File I/O | 6 days | Low |
| Phase 5: Additional modules | 26 days | Low |
| **Total** | **79 days** | |

## Suggested Priority

1. **Phase 1** (Interfaces) — foundational; everything else depends on Eq/Ord/Show/Hash
2. **Phase 2 Steps 2.1, 2.3** (SSO + interpolation) — high user-visible impact
3. **Phase 3 Step 3.1** (Map) — unblocks JSON, many user programs need key-value stores
4. **Phase 4** (File I/O) — practical utility for real programs
5. **Phase 5 Steps 5.2, 5.4** (Random, Env) — small modules, high utility
6. **Phase 2 Steps 2.4, 2.5** (IOList, Rope) — performance refinement, defer Rope
7. **Phase 5 Step 5.1** (JSON) — important but can use external library initially
8. **Phase 3 Steps 3.3, 3.4** (Queue, Array) — nice to have
