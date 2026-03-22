# March Standard Library Documentation

## Overview

The March standard library consists of **21 modules** totaling **~4,894 lines of code** (as of March 22, 2026). The library is auto-loaded by the compiler into every March program and provides:

**Implementation:** `stdlib/` directory — see `bin/main.ml` for load order

- **Core data structures**: List, Option, Result, Seq
- **String and formatting**: String manipulation, IOList (lazy string builder)
- **Mathematics**: Transcendental functions, constants, min/max/clamp
- **Collections**: List operations (map, fold, filter, sort), Enum (higher-level list utilities), Seq (lazy folds), **Map** (persistent AVL tree ordered map)
- **Sorting**: Timsort, Introsort, AlphaDev optimal comparison networks (n ≤ 8)
- **HTTP networking**: Http (types), HttpTransport (TCP), HttpClient (high-level pipeline), HttpServer
- **WebSocket support**: WsSocket, frame types, multiplex operations
- **File I/O**: File (read, write, streaming), Dir (list, mkdir, rm_rf), Path (pure string operations), Csv (streaming parser)
- **Utilities**: Prelude (auto-imported helpers like panic, identity, compose)

### Module Loading

**Location**: `stdlib/` directory relative to the compiler executable
**Order**: Loaded in dependency order before user code (prelude first, then libraries)

**File List** (from `bin/main.ml` lines 71–90):
1. prelude.march — auto-imported into global scope
2. option.march
3. result.march
4. list.march
5. math.march
6. string.march
7. iolist.march
8. http.march
9. http_transport.march
10. http_client.march
11. seq.march
12. path.march
13. file.march
14. dir.march
15. sort.march
16. csv.march
17. websocket.march
18. http_server.march
19. enum.march
20. map.march — persistent AVL tree Map(k, v) with comparator-based operations
21. iterable.march — placeholder for future interface system

### Module System

- **Prelude functions** (panic, unwrap, head, tail, etc.) are unwrapped and placed in global scope
- **All other modules** are accessible via module-qualified names (e.g., `List.map`, `String.split`)
- **Type system**: Modules define both functions and types. Some types are built-in (List, Option, Result); others are custom (HttpServer.Conn, File.FileError)

---

## Module Reference

### 1. Prelude (`stdlib/prelude.march` — 159 lines)

**Auto-imported into every March program.**

Provides the most commonly needed functions and types.

#### Diverging Functions
- `panic(msg : String) : a` — Terminates with runtime error; propagates to actor boundary
- `todo(msg : String) : a` — Marks code as not yet implemented; typechecks as any type
- `unreachable() : a` — Asserts a code path is unreachable

#### Option Helpers
- `unwrap(opt : Option(a)) : a` — Extracts value from Some(x), panics on None
- `unwrap_or(opt : Option(a), default : a) : a` — Returns contained value or default

#### List Basics
- `head(xs : List(a)) : a` — First element; panics if empty
- `tail(xs : List(a)) : List(a)` — All but first element; panics if empty
- `length(xs : List(a)) : Int` — Number of elements (O(n))
- `reverse(xs : List(a)) : List(a)` — Reverses list (O(n))
- `fold_left(acc : b, xs : List(a), f : b -> a -> b) : b` — Left fold primitive (O(n))
- `filter(xs : List(a), pred : a -> Bool) : List(a)` — Filter by predicate (O(n))
- `map(xs : List(a), f : a -> b) : List(b)` — Transform each element (O(n))

#### Combinators
- `identity(x : a) : a` — Identity function
- `compose(f : b -> c, g : a -> b) : a -> c` — Function composition
- `flip(f : a -> b -> c) : b -> a -> c` — Flip argument order
- `const(x : a) : b -> a` — Returns constant function

#### I/O Convenience
- `debug(x : a) : Unit` — Print to string representation with newline
- `inspect(x : a) : String` — Convert to string representation

#### Runtime Functions (C builtins)
- `panic(msg)` — calls `panic` builtin
- `todo_(msg)` — calls `todo_` builtin
- `unreachable_()` — calls `unreachable_` builtin

---

### 2. Option (`stdlib/option.march` — 120 lines)

**Operations on `Option(a) = Some(a) | None`**

All functions are pure. Type is built-in with constructors `Some` and `None`.

#### Predicates
- `is_some(opt : Option(a)) : Bool` — True if Some
- `is_none(opt : Option(a)) : Bool` — True if None

#### Extraction
- `expect(opt : Option(a), msg : String) : a` — Extract Some with custom panic message
- `unwrap(opt : Option(a)) : a` — Extract Some, panic on None
- `unwrap_or(opt : Option(a), default : a) : a` — Extract Some or return default
- `unwrap_or_else(opt : Option(a), f : () -> a) : a` — Extract Some or call f()

#### Transformation
- `map(opt : Option(a), f : a -> b) : Option(b)` — Apply f to contained value
- `flat_map(opt : Option(a), f : a -> Option(b)) : Option(b)` — Apply f and flatten
- `filter(opt : Option(a), pred : a -> Bool) : Option(a)` — Return Some if predicate holds
- `or_else(opt : Option(a), f : () -> Option(a)) : Option(a)` — Return f() if None

#### Combining
- `zip(a : Option(a), b : Option(b)) : Option((a, b))` — Combine two Options, None if either is None

#### Conversion
- `to_result(opt : Option(a), err : e) : Result(a, e)` — Convert to Result with error value
- `to_list(opt : Option(a)) : List(a)` — Convert to List: Some(x) → [x], None → []

---

### 3. Result (`stdlib/result.march` — 118 lines)

**Operations on `Result(a, e) = Ok(a) | Err(e)`**

Primary error-handling mechanism; panics reserved for programmer errors only.

#### Predicates
- `is_ok(res : Result(a, e)) : Bool` — True if Ok
- `is_err(res : Result(a, e)) : Bool` — True if Err

#### Extraction
- `expect(res : Result(a, e), msg : String) : a` — Extract Ok with custom panic message
- `unwrap(res : Result(a, e)) : a` — Extract Ok, panic on Err
- `unwrap_err(res : Result(a, e)) : e` — Extract Err, panic on Ok
- `unwrap_or(res : Result(a, e), default : a) : a` — Extract Ok or return default

#### Transformation
- `map(res : Result(a, e), f : a -> b) : Result(b, e)` — Apply f to Ok value
- `map_err(res : Result(a, e), f : e -> f2) : Result(a, f2)` — Apply f to Err value
- `flat_map(res : Result(a, e), f : a -> Result(b, e)) : Result(b, e)` — Apply f and flatten
- `or_else(res : Result(a, e), f : e -> Result(a, f2)) : Result(a, f2)` — Apply f if Err

#### Collection Operations
- `collect(results : List(Result(a, e))) : Result(List(a), e)` — Collect list of Results; returns first Err or Ok with all values

#### Conversion
- `to_option(res : Result(a, e)) : Option(a)` — Convert to Option, discarding error

---

### 4. List (`stdlib/list.march` — 509 lines)

**Immutable singly-linked list operations**

Design: `List(a) = Cons(a, List(a)) | Nil` (built-in constructors)

- **Partial functions** (head, tail, nth, last) panic on empty/out-of-bounds
- **Safe variants** use `_opt` suffix and return Option
- **fold_left** is the primitive; fold_right recurses on structure
- **sort** uses merge sort (stable, O(n log n))

#### Construction
- `empty() : List(a)` — Empty list
- `singleton(x : a) : List(a)` — Single-element list
- `repeat(x : a, n : Int) : List(a)` — Repeat x n times
- `range(start : Int, stop : Int) : List(Int)` — [start, start+1, ..., stop-1], [] if start >= stop
- `range_step(start : Int, stop : Int, step : Int) : List(Int)` — [start, start+step, ...] up to stop

#### Access
- `head(xs : List(a)) : a` — First element, panics on empty
- `head_opt(xs : List(a)) : Option(a)` — First element as Option
- `tail(xs : List(a)) : List(a)` — All but first, panics on empty
- `tail_opt(xs : List(a)) : Option(List(a))` — Tail as Option
- `last(xs : List(a)) : a` — Last element, panics on empty
- `nth(xs : List(a), n : Int) : a` — 0-indexed element, panics if out-of-bounds
- `nth_opt(xs : List(a), n : Int) : Option(a)` — nth as Option

#### Measurement
- `length(xs : List(a)) : Int` — Number of elements (O(n))
- `is_empty(xs : List(a)) : Bool` — True if no elements

#### Transforming
- `reverse(xs : List(a)) : List(a)` — Reverse order (O(n))
- `append(xs : List(a), ys : List(a)) : List(a)` — Concatenate (O(|xs|))
- `map(xs : List(a), f : a -> b) : List(b)` — Apply f to each element
- `flat_map(xs : List(a), f : a -> List(b)) : List(b)` — Map then concatenate
- `filter(xs : List(a), pred : a -> Bool) : List(a)` — Keep elements satisfying predicate
- `filter_map(xs : List(a), f : a -> Option(b)) : List(b)` — Apply f, collect Some values
- `fold_left(acc : b, xs : List(a), f : b -> a -> b) : b` — Left fold (primitive)
- `fold_right(xs : List(a), acc : b, f : a -> b -> b) : b` — Right fold (recurses on structure)
- `scan_left(acc : b, xs : List(a), f : b -> a -> b) : List(b)` — Left fold with all intermediate values
- `concat(xss : List(List(a))) : List(a)` — Flatten list of lists
- `intersperse(xs : List(a), sep : a) : List(a)` — Insert sep between elements

#### Searching
- `find(xs : List(a), pred : a -> Bool) : Option(a)` — First element satisfying predicate
- `find_index(xs : List(a), pred : a -> Bool) : Option(Int)` — Index of first match
- `any(xs : List(a), pred : a -> Bool) : Bool` — True if any element satisfies predicate
- `all(xs : List(a), pred : a -> Bool) : Bool` — True if all satisfy predicate (vacuously true for [])

#### Sorting
- `sort_by(xs : List(a), cmp : a -> a -> Bool) : List(a)` — Merge sort (stable, O(n log n)); cmp(x,y)=true means x ≤ y

#### Splitting
- `take(xs : List(a), n : Int) : List(a)` — First n elements
- `drop(xs : List(a), n : Int) : List(a)` — Skip first n elements
- `take_while(xs : List(a), pred : a -> Bool) : List(a)` — Longest prefix satisfying predicate
- `drop_while(xs : List(a), pred : a -> Bool) : List(a)` — Drop elements while predicate holds
- `split_at(xs : List(a), n : Int) : (List(a), List(a))` — (take n, drop n)
- `partition(xs : List(a), pred : a -> Bool) : (List(a), List(a))` — (satisfying, not satisfying)
- `drop_last(xs : List(a)) : List(a)` — All but last element
- `chunks(xs : List(a), size : Int) : List(List(a))` — Split into chunks of up to size elements

#### Combining
- `zip(xs : List(a), ys : List(b)) : List((a, b))` — Pair elements; stops at shorter list
- `zip_with(xs : List(a), ys : List(b), f : a -> b -> c) : List(c)` — Pair with f applied
- `unzip(pairs : List((a, b))) : (List(a), List(b))` — Unzip pairs
- `enumerate(xs : List(a)) : List((Int, a))` — Pair each element with 0-based index

#### Reducing
- `sum_int(xs : List(Int)) : Int` — Sum of integers
- `product_int(xs : List(Int)) : Int` — Product of integers
- `minimum_int(xs : List(Int)) : Int` — Minimum integer, panics if empty
- `maximum_int(xs : List(Int)) : Int` — Maximum integer, panics if empty

#### Deduplication
- `dedup(xs : List(a)) : List(a)` — Remove consecutive duplicates (keeps first of each run); uses string comparison

---

### 5. String (`stdlib/string.march` — 365 lines)

**Functions for working with UTF-8 encoded strings**

March strings are immutable UTF-8 byte sequences with small-string optimization (SSO): strings ≤ 15 bytes stored inline.

**Naming conventions:**
- Functions with `byte_` prefix operate on byte offsets (O(1))
- Functions without prefix count graphemes (user-visible characters)
- Use `byte_size` for performance; use `grapheme_count` for user-facing results

#### Size and Slicing
- `byte_size(s) : Int` — Number of bytes in UTF-8 encoding (O(1))
- `slice_bytes(s, start, len) : String` — Byte-indexed substring; clamped to valid ranges
- `grapheme_count(s) : String` — Count Unicode codepoints (O(n)); not full grapheme cluster segmentation

#### Search
- `contains(s, substring) : Bool` — True if substring found (O(n*m) worst-case)
- `starts_with(s, prefix) : Bool` — True if s begins with prefix (O(|prefix|))
- `ends_with(s, suffix) : Bool` — True if s ends with suffix (O(|suffix|))
- `index_of(s, substring) : Option(Int)` — Byte offset of first occurrence
- `last_index_of(s, sub) : Option(Int)` — Byte offset of last occurrence

#### Concatenation and Replacement
- `concat(a, b) : String` — Concatenate two strings (O(|a|+|b|)); prefer `++` operator
- `replace(s, old, new) : String` — Replace **first** occurrence (O(n))
- `replace_all(s, old, new) : String` — Replace **every** occurrence (O(n))

#### Splitting and Joining
- `split(s, sep) : List(String)` — Split on every occurrence of sep (O(n)); empty sep returns whole string
- `split_first(s, sep) : Option((String, String))` — Split on **first** occurrence; useful for key-value parsing
- `join(xs, sep) : String` — Join list with separator (O(total bytes + (n-1)*|sep|))

#### Trimming
- `trim(s) : String` — Remove leading/trailing ASCII whitespace (O(n))
- `trim_start(s) : String` — Remove leading whitespace only
- `trim_end(s) : String` — Remove trailing whitespace only

#### Case Conversion
- `to_uppercase(s) : String` — Convert ASCII letters to uppercase (O(n))
- `to_lowercase(s) : String` — Convert ASCII letters to lowercase (O(n))
- Note: Only ASCII affected; use external library for full Unicode case mapping

#### Formatting
- `repeat(s, n) : String` — Repeat string n times (O(n * |s|))
- `reverse(s) : String` — Reverse bytes (not graphemes; primarily for ASCII)
- `pad_left(s, width, fill) : String` — Pad on left until byte length reaches width
- `pad_right(s, width, fill) : String` — Pad on right until byte length reaches width

#### Predicates
- `is_empty(s) : Bool` — True if no bytes (O(1))

#### Parsing
- `to_int(s) : Result(Int, String)` — Parse decimal integer
- `to_float(s) : Result(Float, String)` — Parse floating-point number

#### Conversion
- `from_int(n) : String` — Convert integer to decimal string (O(digits))
- `from_float(f) : String` — Convert float to string (OCaml's default format)

#### Runtime Functions (C builtins)
Wrapper around:
- `string_byte_length` — byte size
- `string_slice` — slice_bytes
- `string_contains`, `string_starts_with`, `string_ends_with`
- `string_concat`, `string_replace`, `string_replace_all`
- `string_split`, `string_split_first`, `string_join`
- `string_trim`, `string_trim_start`, `string_trim_end`
- `string_to_uppercase`, `string_to_lowercase`
- `string_repeat`, `string_reverse`
- `string_pad_left`, `string_pad_right`, `string_is_empty`
- `string_grapheme_count`, `string_index_of`, `string_last_index_of`
- `string_to_int`, `string_to_float` (C functions; return Option)
- `int_to_string`, `float_to_string`

---

### 6. Math (`stdlib/math.march` — 193 lines)

**Mathematical functions and constants**

Transcendental functions delegate to C libm; pure functions implemented in March.

#### Constants
- `pi() : Float` — 3.14159265...
- `e() : Float` — 2.71828182...
- `tau() : Float` — 2*pi = 6.28318530...

#### Basic
- `abs(x : Float) : Float` — Absolute value (O(1) via `float_abs` builtin)
- `min_int(a : Int, b : Int) : Int` — Smaller of two integers
- `max_int(a : Int, b : Int) : Int` — Larger of two integers
- `min_float(a : Float, b : Float) : Float` — Smaller of two floats
- `max_float(a : Float, b : Float) : Float` — Larger of two floats
- `clamp_int(x : Int, low : Int, high : Int) : Int` — Clamp to [low, high]
- `clamp_float(x : Float, low : Float, high : Float) : Float` — Clamp to [low, high]

#### Powers and Roots
- `sqrt(x : Float) : Float` — Square root (C: `math_sqrt`)
- `cbrt(x : Float) : Float` — Cube root (C: `math_cbrt`)
- `pow(base : Float, exp : Float) : Float` — Power (C: `math_pow`)
- `exp(x : Float) : Float` — e^x (C: `math_exp`)
- `exp2(x : Float) : Float` — 2^x (C: `math_exp2`)

#### Logarithms
- `log(x : Float) : Float` — Natural log (C: `math_log`)
- `log2(x : Float) : Float` — Log base 2 (C: `math_log2`)
- `log10(x : Float) : Float` — Log base 10 (C: `math_log10`)

#### Trigonometry
- `sin(x : Float) : Float` — Sine in radians (C: `math_sin`)
- `cos(x : Float) : Float` — Cosine in radians (C: `math_cos`)
- `tan(x : Float) : Float` — Tangent in radians (C: `math_tan`)
- `asin(x : Float) : Float` — Arc sine, returns radians in [-pi/2, pi/2] (C: `math_asin`)
- `acos(x : Float) : Float` — Arc cosine, returns radians in [0, pi] (C: `math_acos`)
- `atan(x : Float) : Float` — Arc tangent, returns radians in (-pi/2, pi/2) (C: `math_atan`)
- `atan2(y : Float, x : Float) : Float` — Arc tangent of y/x with quadrant handling (C: `math_atan2`)

#### Hyperbolic
- `sinh(x : Float) : Float` — Hyperbolic sine (C: `math_sinh`)
- `cosh(x : Float) : Float` — Hyperbolic cosine (C: `math_cosh`)
- `tanh(x : Float) : Float` — Hyperbolic tangent (C: `math_tanh`)

#### Rounding
- `floor(x : Float) : Float` — Largest integer ≤ x (C: `float_floor`, converted to Float)
- `ceil(x : Float) : Float` — Smallest integer ≥ x (C: `float_ceil`, converted to Float)
- `round(x : Float) : Float` — Nearest integer (C: `float_round`, converted to Float)
- `truncate(x : Float) : Float` — Round toward zero (C: `float_truncate`, converted to Float)

#### Interpolation
- `lerp(a : Float, b : Float, t : Float) : Float` — Linear interpolation: a + t*(b-a); equals a at t=0, b at t=1

---

### 7. Sort (`stdlib/sort.march` — 616 lines)

**Timsort, Introsort, and AlphaDev optimal comparison networks**

Internal module — users should prefer Enum module which wraps these.

**Design**: All functions operate on `List(a)` with a comparator `cmp : a -> a -> Bool` where `cmp(x)(y) = true` means x should come before y.

#### Shared Helpers (internal)
- `reverse_list(xs : List(a)) : List(a)` — Reverse a list (O(n))
- `append_list(xs : List(a), ys : List(a)) : List(a)` — Append two lists (O(|xs|))
- `list_len(xs : List(a)) : Int` — Length (O(n))
- `nth_unsafe(xs : List(a), k : Int) : a` — Unsafe nth access without bounds checking
- `cmp2(cmp : a -> a -> Bool, x : a, y : a) : Bool` — Apply curried comparator to two args
- `cmp_swap(a : a, b : a, cmp : a -> a -> Bool) : (a, a)` — Return (min, max) according to cmp

#### Mergesort (fallback algorithm)
- `merge_sorted(xs : List(a), ys : List(a), cmp : a -> a -> Bool) : List(a)` — Merge two sorted lists; stable (left preferred on ties)
- `mergesort_by(xs : List(a), cmp : a -> a -> Bool) : List(a)` — Top-down mergesort; stable, O(n log n); used as fallback for sort_small_by and Introsort

#### AlphaDev Optimal Sorting Networks (n=2..8)

Networks from Bert Dobbelaere's catalog, proven optimal by Floyd & Knuth (1966):
- `sort2(a, b, cmp) : List(a)` — 1 comparator (optimal)
- `sort3(a, b, c, cmp) : List(a)` — 3 comparators (optimal)
- `sort4(a, b, c, d, cmp) : List(a)` — 5 comparators (optimal)
- `sort5(a, b, c, d, e, cmp) : List(a)` — 9 comparators (optimal)
- `sort6(a, b, c, d, e, f, cmp) : List(a)` — 12 comparators (optimal)
- `sort7(a, b, c, d, e, f, g, cmp) : List(a)` — 16 comparators (optimal)
- `sort8(a, b, c, d, e, f, g, h, cmp) : List(a)` — 19 comparators (optimal)
- `sort_small_by(xs : List(a), cmp : a -> a -> Bool) : List(a)` — Sort ≤8 elements with optimal networks; fall back to mergesort for n>8; stable

#### Insertion Sort
- `insert_sorted(x : a, sorted : List(a), cmp : a -> a -> Bool) : List(a)` — Insert x into sorted list at correct position (O(n) per insertion)
- `insertion_sort_by(xs : List(a), cmp : a -> a -> Bool) : List(a)` — Insertion sort; stable, O(n²); used for small sublists (n<16)

#### Timsort
- `extend_run(run, run_len, rest, cmp)` — Extend run to MIN_RUN=16 via insertion sort; returns (extended_run, new_len, remaining)
- `detect_runs(xs, cmp)` — Scan list into natural ascending runs; reverse descending runs; extend short runs to MIN_RUN=16; returns list of (run, length) pairs
- `tim_merge(a, b, cmp)` — Merge two sorted lists (stable)
- `enforce_invariants(stack, cmp)` — Enforce Timsort merge stack invariants: |Z| > |Y|+|X| and |Y| > |X|
- `drain_stack(stack, cmp)` — Drain merge stack by merging bottom to top
- `timsort_by(xs : List(a), cmp : a -> a -> Bool) : List(a)` — **Timsort implementation**: stable, O(n log n) worst-case, O(n) on sorted input; exploits natural runs; prefer for nearly-sorted data

**Timsort invariants ensure O(n log n) total merge work on linked lists even without cache benefits.**

#### Heap (for Introsort fallback)
- `type Heap(a) = HLeaf | HNode(Int, a, Heap(a), Heap(a))` — Leftist heap; rank=rightmost path length
- `heap_rank(h)` — Get rank (O(1))
- `make_hnode(x, l, r)` — Make node maintaining rank invariant
- `heap_merge_h(h1, h2, cmp)` — Merge heaps (O(log n) per node)
- `heap_insert(x, h, cmp)` — Insert element (O(log n))
- `heap_extract_min(h, cmp)` — Extract minimum (O(log n))
- `heap_build(xs, cmp)` — Build heap from list (O(n log n))
- `heap_drain(h, cmp, acc)` — Extract all elements in order (O(n log n))
- `heapsort_by(xs : List(a), cmp : a -> a -> Bool) : List(a)` — Heapsort using leftist heap; O(n log n) worst-case guaranteed

#### Introsort
- `partition3(xs, pivot, cmp)` — Three-way partition into (lt, eq, gt) relative to pivot; O(n)
- `median_of_3(a, b, c, cmp)` — Return median of three values
- `log2_floor(n)` — Floor of log₂(n)
- `introsort_by(xs : List(a), cmp : a -> a -> Bool) : List(a)` — **Introsort implementation**: unstable, O(n log n) worst-case guaranteed; starts with median-of-3 quicksort; switches to heapsort when depth exceeds 2*floor(log₂(n)); uses AlphaDev networks for n<16; suitable for adversarial/unknown-shape data

**Introsort guarantees:** Prevents quicksort's O(n²) worst-case via heapsort fallback.

---

### 8. Enum (`stdlib/enum.march` — 315 lines)

**Elixir-style enumeration over `List(a)`**

All functions operate on `List(a)`. When runtime dispatch lands, Iterable interface will generalize these to any collection.

**Comparator convention**: `cmp : a -> a -> Bool` is curried; `cmp(x)(y) = true` means x should come before y.

#### Traversal
- `map(xs : List(a), f : a -> b) : List(b)` — Transform each element (O(n))
- `flat_map(xs : List(a), f : a -> List(b)) : List(b)` — Map and concatenate (O(n*m))
- `filter(xs : List(a), pred : a -> Bool) : List(a)` — Keep elements matching predicate (O(n))
- `each(xs : List(a), f : a -> b) : Unit` — Apply f for side effects, return Unit (O(n))

#### Reduction (fold)
- `fold(zero : b, xs : List(a), f : b -> a -> b) : b` — Left fold; primitive from which others derive (O(n))
- `reduce(xs : List(a), f : a -> a -> a) : Option(a)` — Fold using first element as initial value; None for empty lists (O(n))

#### Predicates and Queries
- `count(xs : List(a)) : Int` — Number of elements (O(n))
- `any(xs : List(a), pred : a -> Bool) : Bool` — True if any element satisfies predicate; short-circuits (O(n))
- `all(xs : List(a), pred : a -> Bool) : Bool` — True if all elements satisfy predicate; short-circuits on failure (O(n))
- `find(xs : List(a), pred : a -> Bool) : Option(a)` — First element matching predicate (O(n))

#### Grouping and Zipping
- `group_by(xs : List(a), key : a -> k) : List((k, List(a)))` — Group **consecutive** elements with same key into (key, [elements]) pairs (O(n)); note: only consecutive equal keys are grouped (unlike hash group-by)
- `zip_with(xs : List(a), ys : List(b), f : a -> b -> c) : List(c)` — Zip two lists applying f to pairs; stops at shorter (O(min(|xs|,|ys|)))

#### Sorting Wrappers
These wrap the Sort module functions for convenience:

- `sort_by(xs : List(a), cmp : a -> a -> Bool) : List(a)` — Timsort (stable, O(n log n) worst-case, O(n) on sorted)
- `timsort_by(xs : List(a), cmp : a -> a -> Bool) : List(a)` — Explicit timsort (stable, exploits natural runs)
- `introsort_by(xs : List(a), cmp : a -> a -> Bool) : List(a)` — Introsort (unstable, O(n log n) guaranteed worst-case)
- `sort_small_by(xs : List(a), cmp : a -> a -> Bool) : List(a)` — Sort ≤8 elements with optimal networks; falls back to mergesort

---

### 9. IOList (`stdlib/iolist.march` — 222 lines)

**Lazy, tree-structured string builder**

Represents sequence of string segments as a tree, deferring concatenation until flushed to I/O. Avoids O(n²) copying when building large strings from many pieces.

**Internal representation**:
- `Empty` — zero bytes
- `Str(s)` — single String segment
- `Segments(xs)` — list of IOList nodes (children)

No binary Concat node; chains of Segments avoid deep left-spine trees that overflow stack when flattening.

#### Construction
- `empty() : IOList` — Empty IOList (O(1))
- `from_string(s : String) : IOList` — Wrap String as leaf node; no copy made (O(1))
- `from_strings(xs : List(String)) : IOList` — Build IOList from List(String) (O(n))
- `append(a : IOList, b : IOList) : IOList` — Append two IOLists; no bytes copied until to_string (O(1))
- `prepend(s : String, iol : IOList) : IOList` — Prepend String to IOList (O(1))
- `push(iol : IOList, s : String) : IOList` — Append String to IOList (O(1))

#### Flattening
- `to_string(iol : IOList) : String` — Flatten to single String; only function that allocates full concatenated result (O(total bytes))

#### Inspection
- `byte_size(iol : IOList) : Int` — Total byte size of all segments without flattening (O(number of nodes))
- `is_empty(iol : IOList) : Bool` — True if no bytes; O(1) for Empty/Str, O(n) for Segments

**Usage pattern**: Accumulate with append/push, call to_string once at end to avoid O(n²) copying.

#### Runtime Functions
- `string_join` — used by to_string to concatenate collected strings

---

### 10. Seq (`stdlib/seq.march` — 252 lines)

**Lazy fold-based sequences (Church-encoded)**

`Seq(a)` wraps a closure of type `fn(b, fn(b, a) -> b) -> b` (church encoding).

**Design**: Enum operates eagerly on Lists; Seq operates lazily over I/O or generated sequences.

#### Types
- `type Step(a) = Continue(a) | Halt(a)` — Used by fold_while for early termination

#### Construction
- `from_list(xs : List(a)) : Seq(a)` — Convert List to Seq
- `empty() : Seq(a)` — Empty sequence
- `unfold(seed : a, next : a -> Option((b, a))) : Seq(b)` — Build Seq by iterating next function until None

#### Composition
- `concat(s1 : Seq(a), s2 : Seq(a)) : Seq(a)` — Concatenate two sequences

#### Transformation (lazy)
All transformations return new Seq without evaluating:

- `map(seq : Seq(a), f : a -> b) : Seq(b)` — Transform each element
- `filter(seq : Seq(a), pred : a -> Bool) : Seq(a)` — Keep elements matching predicate
- `flat_map(seq : Seq(a), f : a -> Seq(b)) : Seq(b)` — Map and flatten
- `take(seq : Seq(a), n : Int) : Seq(a)` — Take first n elements
- `drop(seq : Seq(a), n : Int) : Seq(a)` — Skip first n elements
- `zip(s1 : Seq(a), s2 : Seq(b)) : Seq((a, b))` — Zip two sequences
- `batch(seq : Seq(a), n : Int) : Seq(List(a))` — Group elements into batches of size n

#### Consumption (eager)
These evaluate the Seq and return concrete results:

- `to_list(seq : Seq(a)) : List(a)` — Convert Seq to List
- `fold(seq : Seq(a), start : b, f : b -> a -> b) : b` — Left fold
- `fold_while(seq : Seq(a), start : b, f : b -> a -> Step(b)) : b` — Fold with early termination via Halt

**Note**: fold_while does NOT truly short-circuit; all elements are visited but accumulation skipped after Halt. For file streaming, file reads to EOF even after Halt. This is a known limitation of fold-based model.

- `each(seq : Seq(a), f : a -> b) : Unit` — Apply f for side effects
- `count(seq : Seq(a)) : Int` — Number of elements
- `find(seq : Seq(a), pred : a -> Bool) : Option(a)` — First element matching predicate
- `any(seq : Seq(a), pred : a -> Bool) : Bool` — True if any element matches
- `all(seq : Seq(a), pred : a -> Bool) : Bool` — True if all elements match

#### Practical Use Cases

File streaming:
```march
File.with_lines(path, fn(lines) ->
  Seq.from_list(lines) |> Seq.map(String.trim) |> Seq.to_list
)
```

Generating ranges:
```march
Seq.unfold(0, fn(i) -> if i < 10 then Some((i, i+1)) else None)
```

---

### 11. Http (`stdlib/http.march` — 339 lines)

**Pure HTTP protocol types, constructors, and transforms**

**Layer 1** of March's HTTP library — no I/O, only data types and functions for building/inspecting requests and responses.

#### Types

```march
type Method = Get | Post | Put | Patch | Delete | Head | Options | Trace | Connect | Other(String)
type Scheme = SchemeHttp | SchemeHttps
type Status = Status(Int)
type Header = Header(String, String)
type UrlError = InvalidScheme(String) | MissingHost | InvalidPort(String) | MalformedUrl(String)
type Request(body) = Request(Method, Scheme, String, Option(Int), String, Option(String), List(Header), body)
type Response(body) = Response(Status, List(Header), body)
```

#### Method Operations
- `method_to_string(m : Method) : String` — Convert Method to HTTP verb string

#### Status Operations
- `status_code(s : Status) : Int` — Extract numeric code
- `status_ok() : Status` — 200 OK
- `status_created() : Status` — 201 Created
- `status_no_content() : Status` — 204 No Content
- `status_moved() : Status` — 301 Moved Permanently
- `status_found() : Status` — 302 Found
- `status_bad_request() : Status` — 400 Bad Request
- `status_unauthorized() : Status` — 401 Unauthorized
- `status_forbidden() : Status` — 403 Forbidden
- `status_not_found() : Status` — 404 Not Found
- `status_server_error() : Status` — 500 Internal Server Error

#### Status Categorization
- `is_informational(s : Status) : Bool` — 100–199
- `is_success(s : Status) : Bool` — 200–299
- `is_redirect(s : Status) : Bool` — 300–399
- `is_client_error(s : Status) : Bool` — 400–499
- `is_server_error(s : Status) : Bool` — 500–599

#### Request Accessors
- `method(req : Request(b)) : Method`
- `scheme(req : Request(b)) : Scheme`
- `host(req : Request(b)) : String`
- `port(req : Request(b)) : Option(Int)`
- `path(req : Request(b)) : String`
- `query(req : Request(b)) : Option(String)`
- `headers(req : Request(b)) : List(Header)`
- `body(req : Request(b)) : b`

#### Request Transforms
- `set_method(req : Request(b), m : Method) : Request(b)`
- `set_scheme(req : Request(b), s : Scheme) : Request(b)`
- `set_host(req : Request(b), new_host : String) : Request(b)`
- `set_port(req : Request(b), new_port : Int) : Request(b)`
- `set_path(req : Request(b), new_path : String) : Request(b)`
- `set_body(req : Request(a), new_body : b) : Request(b)`
- `set_header(req : Request(b), name : String, value : String) : Request(b)` — Prepend header to list
- `set_query(req : Request(b), params : List((String, String))) : Request(b)` — Encode and set query string

#### Response Accessors
- `response_status(resp : Response(b)) : Status`
- `response_headers(resp : Response(b)) : List(Header)`
- `response_body(resp : Response(b)) : b`
- `response_status_code(resp : Response(b)) : Int` — Convenience
- `response_is_success(resp : Response(b)) : Bool` — True if 200–299
- `response_is_redirect(resp : Response(b)) : Bool` — True if 300–399

#### Header Lookup (case-insensitive)
- `get_header(resp : Response(b), name : String) : Option(String)` — Find header value by name
- `get_request_header(req : Request(b), name : String) : Option(String)` — Find request header value

#### URL Parsing
- `parse_url(url : String) : Result(Request(Unit), UrlError)` — Parse URL string into a Request with empty body and no headers

Parses: `http://host[:port]/path[?query]` or `https://...`

#### Convenience Constructors
- `get(url : String) : Result(Request(Unit), UrlError)` — Create GET request
- `post(url : String, bdy : b) : Result(Request(b), UrlError)` — Create POST request
- `put(url : String, bdy : b) : Result(Request(b), UrlError)` — Create PUT request
- `patch(url : String, bdy : b) : Result(Request(b), UrlError)` — Create PATCH request
- `delete(url : String) : Result(Request(Unit), UrlError)` — Create DELETE request
- `head(url : String) : Result(Request(Unit), UrlError)` — Create HEAD request
- `options(url : String) : Result(Request(Unit), UrlError)` — Create OPTIONS request

#### Query String Encoding
- `encode_query(params : List((String, String))) : String` — Encode query parameters as `key1=val1&key2=val2...`

#### Runtime Functions (C builtins)
- `string_starts_with`, `string_slice`, `string_index_of`, `string_is_empty`, `string_to_int`

---

### 12. HttpTransport (`stdlib/http_transport.march` — 181 lines)

**Low-level HTTP transport layer**

Sends raw HTTP/1.1 requests over TCP sockets.

**Layer 2** of March's HTTP library — handles connection management and raw request/response exchange.

**NOTE**: Only supports HTTP (not HTTPS/TLS) in this version.

#### Types

```march
type TransportError =
  ConnectionRefused(String)
  | ConnTimeout(String)
  | SendError(String)
  | RecvError(String)
  | ConnParseError(String)
  | Closed
```

#### Connection
- `connect(req : Request(b)) : Result(Int, TransportError)` — Open TCP connection to request's host:port; returns file descriptor

#### Request/Response Exchange
- `request_on(fd : Int, req : Request(b)) : Result(Response(String), TransportError)` — Send request on existing fd, receive response; does NOT close connection (suitable for keep-alive)
- `request(req : Request(b)) : Result(Response(String), TransportError)` — Send request, receive response; opens connection, closes after response
- `stream_request_on(fd : Int, req : Request(b), on_chunk : String -> Unit) : Result((Int, List(Header), Unit), TransportError)` — Send request on fd, stream response body; calls on_chunk for each chunk as it arrives

#### Helper Functions
- `stream_chunked_body(fd, on_chunk, status_code, resp_headers)` — Stream chunked-encoded response body
- `stream_fixed_body(fd, remaining, on_chunk, status_code, resp_headers)` — Stream fixed-size response body

#### Convenience
- `simple_get(url : String) : Result(Response(String), TransportError)` — Parse URL and send GET request

#### Runtime Functions (C builtins)
- `tcp_connect(host : String, port : Int) : Result(Int, String)` — Create TCP connection
- `tcp_send_all(fd : Int, data : String) : Result(Unit, String)` — Send all bytes
- `tcp_recv_http(fd : Int, max_bytes : Int) : Result(String, String)` — Receive full HTTP response
- `tcp_recv_http_headers(fd : Int) : Result((String, Int, Bool), String)` — Receive headers, return (headers_str, content_length, is_chunked)
- `tcp_recv_chunk(fd : Int, size : Int) : Result(String, String)` — Receive up to size bytes
- `tcp_recv_chunked_frame(fd : Int) : Result(String, String)` — Receive one chunked frame
- `tcp_recv_all(fd : Int, max_bytes : Int, timeout_ms : Int) : Result(String, String)` — Receive with timeout
- `tcp_close(fd : Int) : Unit` — Close connection
- `http_serialize_request(method, host, path, query, headers, body) : String` — Serialize to HTTP/1.1 wire format
- `http_parse_response(raw : String) : Result((Int, List(Header), String), String)` — Parse response into (status_code, headers, body)

---

### 13. HttpClient (`stdlib/http_client.march` — 441 lines)

**High-level composable HTTP client with step pipeline**

**Layer 3** of March's HTTP library — provides Req-style three-phase pipeline (request steps, response steps, error steps) built on HttpTransport.

#### Types

```march
type HttpError =
  HttpTransportError(TransportError)
  | StepError(String, String)
  | TooManyRedirects(Int)

type RequestStepEntry = RequestStepEntry(String, a)
type ResponseStepEntry = ResponseStepEntry(String, a)
type ErrorRecovery = Recover(a) | Fail(HttpError)
type ErrorStepEntry = ErrorStepEntry(String, a)

type Client = Client(
  List(RequestStepEntry),
  List(ResponseStepEntry),
  List(ErrorStepEntry),
  Int,      -- max_redirects
  Int,      -- max_retries
  Int       -- retry_backoff_ms
)
```

#### Client Construction
- `new_client() : Client` — Create bare client with no steps, no redirect/retry

#### Step Registration (pipeable)
- `add_request_step(client, name, step) : Client` — Register request transformation step
- `add_response_step(client, name, step) : Client` — Register response transformation step
- `add_error_step(client, name, step) : Client` — Register error recovery step

#### Pipeline Behavior
- `with_redirects(client, max : Int) : Client` — Enable automatic redirect following (max=0 disables)
- `with_retry(client, max_attempts, backoff_ms) : Client` — Enable automatic retry on failure

#### Step Introspection
- `list_steps(client) : List(String)` — List all registered steps as "request:name", "response:name", "error:name"

#### Execution
- `run(client, req) : Result(Response(String), HttpError)` — Run request through full step pipeline (1. request steps → 2. transport with retry → 3. handle redirects → 4. response steps → 5. error recovery on failure)

- `with_connection(client, url, callback) : Result(a, HttpError)` — Open keep-alive connection and run callback with do_request function; connection closed after callback

- `stream_get(client, url, on_chunk) : Result((Int, List(Header), a), HttpError)` — Stream GET response body

#### Convenience Methods
- `get(client, url) : Result(Response(String), HttpError)`
- `post(client, url, bdy) : Result(Response(String), HttpError)`
- `put_request(client, url, bdy) : Result(Response(String), HttpError)`
- `delete(client, url) : Result(Response(String), HttpError)`

#### Built-in Steps

**Request Steps**:
- `step_default_headers(req) : Result(Request(String), HttpError)` — Add User-Agent and Accept headers
- `step_bearer_auth(token) : (Request(b) -> Result(Request(b), HttpError))` — Add Bearer auth
- `step_basic_auth(user, pass) : (Request(b) -> Result(Request(b), HttpError))` — Add Basic auth
- `step_base_url(base) : (Request(b) -> Result(Request(b), HttpError))` — Set base URL
- `step_content_type(ct) : (Request(b) -> Result(Request(b), HttpError))` — Set Content-Type header

**Response Steps**:
- `step_raise_on_error(req, resp) : Result((Request(b), Response(String)), HttpError)` — Return Err for 4xx/5xx status codes

#### Internal Pipeline Functions
- `run_request_steps(steps, req) : Result(Request(b), HttpError)` — Run all request steps in order
- `run_response_steps(steps, req, resp) : Result((Request(b), Response(String)), HttpError)` — Run response steps
- `run_error_steps(steps, req, err) : Result(Response(String), HttpError)` — Run error recovery steps
- `handle_redirects(req, resp, max, count) : Result(Response(String), HttpError)` — Follow redirects up to max

---

### 14. HttpServer (`stdlib/http_server.march` — 234 lines)

**Server-side HTTP types and pipeline runner**

**Built on Http** (for Method, Header types) and **WebSocket** modules.

Provides the Conn type (modeled on Elixir's Plug.Conn), pipeline composition, and server startup.

#### Types

```march
type Upgrade = NoUpgrade | WebSocketUpgrade(WsSocket -> Unit)

type Conn = Conn(
  Int,                    -- fd (TCP socket)
  Method,                 -- request method
  String,                 -- request path (raw, e.g. "/users/42")
  List(String),           -- path_info (split on "/", empty filtered)
  String,                 -- query_string (raw, e.g. "page=1&limit=10")
  List(Header),           -- request headers
  String,                 -- request body
  Int,                    -- response status (0 = not yet set)
  List(Header),           -- response headers
  String,                 -- response body
  Bool,                   -- halted? (true after send_resp)
  List((String, String)), -- assigns (user-defined key-value store)
  Upgrade                 -- websocket upgrade
)

type Server = Server(
  Int,                 -- port
  List(Conn -> Conn),  -- pipeline (list of plugs)
  Int,                 -- max_connections
  Int                  -- idle_timeout_secs
)
```

#### Conn Accessors
- `method(conn) : Method`
- `path(conn) : String`
- `path_info(conn) : List(String)` — Parsed path segments
- `query_string(conn) : String`
- `req_headers(conn) : List(Header)`
- `req_body(conn) : String`
- `status(conn) : Int` — 0 if not set
- `resp_headers(conn) : List(Header)`
- `resp_body(conn) : String`
- `halted(conn) : Bool`
- `assigns(conn) : List((String, String))` — User-defined data
- `fd(conn) : Int` — Underlying file descriptor

#### Header and Assign Lookup
- `get_req_header(conn, name) : Option(String)` — Case-insensitive request header lookup
- `get_assign(conn, key) : Option(String)` — Get assigned value by key

#### Conn Transforms
- `put_resp_header(conn, name, value) : Conn` — Add response header
- `assign(conn, key, value) : Conn` — Store key-value pair for later retrieval
- `send_resp(conn, status : Int, body : String) : Conn` — Set status and body, mark halted
- `halt(conn) : Conn` — Mark as halted without sending response

#### Convenience Response Helpers
- `text(conn, status : Int, body : String) : Conn` — Send plain text response
- `json(conn, status : Int, body : String) : Conn` — Send JSON response (with Content-Type)
- `html(conn, status : Int, body : String) : Conn` — Send HTML response (with Content-Type)
- `redirect(conn, url : String) : Conn` — Send 302 redirect to url

#### Pipeline Execution
- `run_pipeline(conn, plugs : List(Conn -> Conn)) : Conn` — Run list of plugs in order; stops at first halted conn

#### Server Construction and Configuration
- `new(port : Int) : Server` — Create server on port (defaults: 1000 max connections, 60 sec timeout)
- `plug(server, p : Conn -> Conn) : Server` — Add a plug (middleware) to pipeline
- `max_connections(server, n : Int) : Server` — Set max concurrent connections
- `idle_timeout(server, secs : Int) : Server` — Set idle timeout in seconds
- `listen(server) : Unit` — Start listening (blocks forever); calls http_server_listen builtin with pipeline

#### Runtime Functions (C builtins)
- `http_server_listen(port, max_conns, idle_timeout_secs, pipeline_fn) : Unit` — Start HTTP server

---

### 15. WebSocket (`stdlib/websocket.march` — 53 lines)

**Types and API for WebSocket connections**

WebSocket connections are upgraded from HTTP via WebSocket.upgrade(conn, handler).

#### Types

```march
type WsFrame = TextFrame(String) | BinaryFrame(String) | Ping | Pong | Close(Int, String)
type WsSocket = WsSocket(Int)
type SelectResult = WsData(WsFrame) | ActorMsg | Timeout
```

#### Operations
- `upgrade(conn : Conn, handler : WsSocket -> Unit) : Conn` — Upgrade HTTP connection to WebSocket; marks conn halted with WebSocketUpgrade

- `recv(socket : WsSocket) : WsFrame` — Block until frame arrives

- `send_frame(socket : WsSocket, frame : WsFrame) : Unit` — Send a frame

- `close(socket : WsSocket, code : Int, reason : String) : Unit` — Send close frame (equivalent to send_frame with Close)

- `select(socket : WsSocket, timeout_ms : Int) : SelectResult` — Multiplex: wait on socket OR actor mailbox OR timeout; returns WsData(frame), ActorMsg, or Timeout

#### Runtime Functions (C builtins)
- `ws_recv(fd : Int) : WsFrame` — Receive frame
- `ws_send(fd : Int, frame : WsFrame) : Unit` — Send frame
- `ws_select(fd : Int, actor_mailbox : Int, timeout_ms : Int) : SelectResult` — Multiplex on socket, mailbox, timeout

---

### 16. File (`stdlib/file.march` — 140 lines)

**Filesystem I/O**

All functions return `Result(value, FileError)`.

Use `with_lines`/`with_chunks` for streaming (handle closed after callback returns).

**Note**: No exception-safe cleanup; if callback raises unhandled exception, handle may leak (March lacks try/finally).

#### Types

```march
type FileError = NotFound(String) | Permission(String) | IsDirectory(String) | NotEmpty(String) | IoError(String)
type FileKind = RegularFile | Directory | Symlink | OtherKind
type FileStat = FileStat(Int, FileKind, Int, Int)  -- (size, kind, modified_time, accessed_time)
```

#### Read Operations
- `read(path : String) : Result(String, FileError)` — Read entire file as string
- `read_lines(path : String) : Result(List(String), FileError)` — Read file as list of lines (strips trailing newlines)
- `exists(path : String) : Bool` — True if file/directory exists (use Dir.exists for directory-specific check)
- `stat(path : String) : Result(FileStat, FileError)` — Get file metadata

#### Write Operations
- `write(path : String, data : String) : Result(Unit, FileError)` — Write entire contents (overwrites)
- `append(path : String, data : String) : Result(Unit, FileError)` — Append to file
- `delete(path : String) : Result(Unit, FileError)` — Delete file
- `copy(src : String, dest : String) : Result(Unit, FileError)` — Copy file
- `rename(src : String, dest : String) : Result(Unit, FileError)` — Rename file

#### Streaming (handle closed after callback)
- `with_lines(path, callback : Seq(String) -> a) : Result(a, FileError)` — Open file, create single-pass Seq of lines, call callback, close handle

- `with_chunks(path, size, callback : Seq(String) -> a) : Result(a, FileError)` — Open file, create Seq of chunks of up to size bytes, call callback, close

#### Side-Effect Iteration
- `each_line(path, f : String -> Unit) : Result(Unit, FileError)` — Recursively read and process each line

- `each_chunk(path, size, f : String -> Unit) : Result(Unit, FileError)` — Recursively read and process each chunk

#### Runtime Functions (C builtins)
- `file_read(path) : Result(String, FileError)`
- `file_exists(path) : Bool`
- `file_stat(path) : Result(FileStat, FileError)`
- `file_write(path, data) : Result(Unit, FileError)`
- `file_append(path, data) : Result(Unit, FileError)`
- `file_delete(path) : Result(Unit, FileError)`
- `file_copy(src, dest) : Result(Unit, FileError)`
- `file_rename(src, dest) : Result(Unit, FileError)`
- `file_open(path) : Result(Int, FileError)` — Return file handle (fd)
- `file_read_line(fd) : Option(String)` — Read one line; None at EOF
- `file_read_chunk(fd, size) : Option(String)` — Read up to size bytes; None at EOF
- `file_close(fd) : Unit` — Close handle

---

### 17. Dir (`stdlib/dir.march` — 50 lines)

**Directory I/O**

All operations return `Result(value, FileError)` except `exists` which returns `Bool`.

**Safety**: rm_rf does not follow symlinks; symlink entries are removed, targets left intact. rm_rf refuses to operate on "/" or "" (returns Err).

#### Operations
- `list(path : String) : Result(List(String), FileError)` — List directory entries (bare names, no paths)

- `list_full(path : String) : Result(List(String), FileError)` — List entries with full paths (prepend path prefix)

- `mkdir(path : String) : Result(Unit, FileError)` — Create directory (fails if parent doesn't exist)

- `mkdir_p(path : String) : Result(Unit, FileError)` — Create directory and all parent directories

- `rmdir(path : String) : Result(Unit, FileError)` — Remove empty directory

- `rm_rf(path : String) : Result(Unit, FileError)` — Recursively delete directory tree (no symlink following)

- `exists(path : String) : Bool` — True if directory exists

#### Runtime Functions (C builtins)
- `dir_list(path) : Result(List(String), FileError)`
- `dir_mkdir(path) : Result(Unit, FileError)`
- `dir_mkdir_p(path) : Result(Unit, FileError)`
- `dir_rmdir(path) : Result(Unit, FileError)`
- `dir_rm_rf(path) : Result(Unit, FileError)`
- `dir_exists(path) : Bool`

---

### 18. Path (`stdlib/path.march` — 92 lines)

**Pure path manipulation (no I/O)**

All operations are pure string functions.

#### Operations
- `join(a : String, b : String) : String` — Join path segments with "/" separator

- `is_absolute(path : String) : Bool` — True if path starts with "/"

- `components(path : String) : List(String)` — Split path on "/" and filter empty components

- `basename(path : String) : String` — Last path component; returns path if no components

- `dirname(path : String) : String` — All but last component; returns "/" for absolute paths with no parent, "." for relative

- `extension(path : String) : String` — File extension after last "."; "" if no dot or leading dot (e.g., ".bashrc" → "")

- `strip_extension(path : String) : String` — Remove extension; handles leading dots

- `normalize(path : String) : String` — Resolve "." and ".." components; preserves absolute/relative distinction

**Examples**:
- `Path.join("/usr", "bin")` → "/usr/bin"
- `Path.basename("/usr/local/bin")` → "bin"
- `Path.dirname("/usr/local/bin")` → "/usr/local"
- `Path.extension("file.tar.gz")` → "gz"
- `Path.normalize("/a/./b/../c")` → "/a/c"

---

### 19. Csv (`stdlib/csv.march` — 101 lines)

**Streaming CSV parser**

Two consumption modes:
- `each_row(path, delimiter, mode, callback)` — Streaming with guaranteed cleanup
- `read_all(path, delimiter, mode)` — Eager (for small files)

**Modes**:
- `:simple` — Split on delimiter only; no quoting
- `:rfc4180` — Full RFC 4180: quoted fields, "" escapes, embedded newlines

#### Types

```march
type CsvError = FileError(String) | CsvParseError(String)
```

#### Operations

**Streaming**:
- `each_row(path, delimiter, mode, callback : List(String) -> Unit) : Result(Unit, CsvError)` — Open file, parse rows, call callback for each, close handle

- `each_row_with_header(path, delimiter, mode, callback : (List(String), List(String)) -> Unit) : Result(Unit, CsvError)` — Like each_row but first row treated as header; callback receives (header, row)

**Eager**:
- `read_all(path, delimiter, mode) : Result(List(List(String)), CsvError)` — Read all rows eagerly

#### Convenience
- `read_csv(path : String) : Result(List(List(String)), CsvError)` — Comma-delimited, RFC 4180, eager
- `each_csv_row(path, callback) : Result(Unit, CsvError)` — Comma-delimited, RFC 4180, streaming

#### Runtime Functions (C builtins)
- `csv_open(path, delimiter, mode) : Result(Int, CsvError)` — Open handle
- `csv_next_row(handle) : Union(Row(List(String)), :eof)` — Get next row
- `csv_close(handle) : Unit` — Close handle

---

### 20. Iterable (`stdlib/iterable.march` — 29 lines)

**Placeholder for future runtime-dispatch generalization**

Currently all Enum functions operate on `List(a)` directly. When runtime gains interface dispatch, this module will expose an `Iterable(a)` interface that List, Array, Range, and other collections can implement.

**Status**: No callable functions yet. Intended shape documented as comments.

```march
-- Placeholder: interface declaration syntax not yet stable.
-- Intended interface:
--
--   interface Iterable(a) do
--     fn next(self : Self) : Option((a, Self))
--   end
--
-- impl Iterable(a) for List(a) do
--   fn next(xs : List(a)) : Option((a, List(a))) do
--     match xs with
--     | Nil        -> None
--     | Cons(h, t) -> Some((h, t))
--     end
--   end
-- end
```

---

## Summary Table

| Module | Lines | Purpose | Runtime Dependencies | Test Coverage |
|--------|-------|---------|----------------------|---|
| prelude.march | 159 | Auto-imported helpers | panic, todo, unreachable | Core |
| option.march | 120 | Option(a) operations | None | Core |
| result.march | 118 | Result(a,e) error handling | None (uses List.reverse) | Core |
| list.march | 509 | List operations (map, fold, sort) | to_string (dedup) | Core |
| string.march | 365 | UTF-8 string functions | 20+ C string functions | Core |
| math.march | 193 | Math functions and constants | 15+ C libm functions | Partial |
| sort.march | 616 | Timsort, Introsort, AlphaDev networks | None | Extensive (benchmarks) |
| enum.march | 315 | Elixir-style list enumeration | Sort module (wraps) | Partial |
| iolist.march | 222 | Lazy string builder | string_join | Partial |
| seq.march | 252 | Church-encoded lazy sequences | None | Partial |
| http.march | 339 | HTTP types and URL parsing | string functions | Partial |
| http_transport.march | 181 | TCP socket and raw HTTP | 8 C TCP/HTTP functions | Partial |
| http_client.march | 441 | High-level HTTP pipeline | HttpTransport | WIP |
| http_server.march | 234 | HTTP server types and pipeline | http_server_listen C builtin | WIP |
| websocket.march | 53 | WebSocket frame types and I/O | ws_recv, ws_send, ws_select | WIP |
| file.march | 140 | File I/O (read, write, streaming) | 10 C file functions | Partial |
| dir.march | 50 | Directory operations | 6 C dir functions | Partial |
| path.march | 92 | Path manipulation (pure) | String functions | Partial |
| csv.march | 101 | Streaming CSV parser | 3 C CSV functions | Partial |
| iterable.march | 29 | Interface placeholder | None (not yet implemented) | N/A |
| **TOTAL** | **4512** | | **50+ C builtins** | |

---

## Runtime Function Dependencies

The stdlib depends on **50+ runtime C functions** in `runtime/march_runtime.c`, `march_http.c`, `sha1.c`, `base64.c`:

### String Functions (10)
string_byte_length, string_slice, string_contains, string_starts_with, string_ends_with, string_concat, string_replace, string_replace_all, string_split, string_split_first, string_join, string_trim, string_trim_start, string_trim_end, string_to_uppercase, string_to_lowercase, string_repeat, string_reverse, string_pad_left, string_pad_right, string_is_empty, string_grapheme_count, string_index_of, string_last_index_of, string_to_int, string_to_float, int_to_string, float_to_string

### Math Functions (15)
float_abs, float_floor, float_ceil, float_round, float_truncate (local; rest delegate to libm)
math_sqrt, math_cbrt, math_pow, math_exp, math_exp2, math_log, math_log2, math_log10, math_sin, math_cos, math_tan, math_asin, math_acos, math_atan, math_atan2, math_sinh, math_cosh, math_tanh

### TCP Functions (8)
tcp_connect, tcp_send_all, tcp_recv_http, tcp_recv_http_headers, tcp_recv_chunk, tcp_recv_chunked_frame, tcp_recv_all, tcp_close

### HTTP Functions (3)
http_serialize_request, http_parse_response

### File Functions (10)
file_read, file_exists, file_stat, file_write, file_append, file_delete, file_copy, file_rename, file_open, file_read_line, file_read_chunk, file_close

### Dir Functions (6)
dir_list, dir_mkdir, dir_mkdir_p, dir_rmdir, dir_rm_rf, dir_exists

### CSV Functions (3)
csv_open, csv_next_row, csv_close

### HTTP Server (1)
http_server_listen

### WebSocket (3)
ws_recv, ws_send, ws_select

### Other
panic, todo_, unreachable_, to_string

---

## Module Interdependencies

```
prelude (auto-imported)
  ↓
option.march → (no stdlib deps)
result.march → List.reverse (from prelude)
list.march → (no stdlib deps)
math.march → (no stdlib deps)
string.march → (no stdlib deps)
sort.march → (no stdlib deps)
enum.march → Sort.timsort_by, Sort.introsort_by, Sort.sort_small_by
iolist.march → string_join (C builtin)
seq.march → (no stdlib deps)
http.march → String functions (C builtins)
http_transport.march → Http module
http_client.march → Http, HttpTransport modules
http_server.march → Http, WebSocket modules
websocket.march → (no stdlib deps)
file.march → String.split, List.reverse
dir.march → String functions
path.march → String functions, List.filter, List.fold_left, List.drop_last
csv.march → List.reverse, File module
iterable.march → (placeholder; no deps)
```

---

## Known Limitations and WIP Modules

### Incomplete/Work-in-Progress Modules
1. **http_client.march** (441 lines) — High-level HTTP client largely functional but error handling incomplete; redirect following and retry logic under development
2. **http_server.march** (234 lines) — Server types defined, pipeline execution works, but WebSocket integration and TLS support not yet implemented
3. **websocket.march** (53 lines) — Frame types and basic API defined; full multiplexing (select) implementation in progress
4. **csv.march** (101 lines) — RFC 4180 parser logic relies on C runtime; edge cases in quoted fields being tested

### Known Issues
1. **Seq.fold_while** does NOT truly short-circuit. All elements visited but accumulation skipped after Halt. File streaming reads to EOF even after Halt (fold-based model limitation)
2. **No exception-safe cleanup** in File/Csv streaming. Unhandled exceptions in callbacks can leak handles (March lacks try/finally)
3. **String grapheme operations** count Unicode codepoints, not true grapheme clusters (no combining character support)
4. **HttpTransport** only supports HTTP; HTTPS/TLS not yet implemented
5. **Sorting on linked lists** has higher constant factors than array implementations due to O(n/2) walk for median-of-3 pivot in Introsort

### Features Not Yet Implemented
1. **Iterable interface** — Enum functions not yet generalized to other collections (Array, Range, etc.)
2. **Runtime dispatch** — Modules cannot yet declare or implement interfaces
3. **Parallel/concurrent operations** — No built-in support for parallelism in sort or map operations
4. **Async/await** — HTTP client uses blocking I/O
5. **Connection pooling** — HttpClient creates new connections per request (no keep-alive pool)

---

## Testing

**Test file**: `test/test_march.ml` (82,702 tokens; contains stdlib-specific tests for List, String, Sort, Enum, Option, Result, Math)

**Benchmarks**: `bench/` directory includes performance benchmarks for:
- Sort algorithms: insertion_sort, mergesort, timsort, introsort, alphadev_sort
- List operations: list_ops
- String pipeline operations: string_build, string_pipeline
- HTTP: http_get, http_get_keepalive, http_get_close
- Fibonacci and tree transforms

---

## Compiler Integration

The stdlib is loaded **before user code** in **dependency order** (see `bin/main.ml` lines 65–93):

```ocaml
(** Load order: prelude first so its globals are available to subsequent modules. *)
let files = [
  "prelude.march";      (* unwrapped into global scope *)
  "option.march";
  "result.march";
  "list.march";
  ...
  "http_server.march";
]
```

**Prelude special handling**: Inner declarations of prelude.march are extracted and placed directly in the user module's top-level scope, so `panic`, `unwrap`, `head`, etc. are available without qualification.

All other modules are wrapped in `DMod` so they're accessible as module-qualified names (e.g., `String.split`, `List.map`).

---

## Version Information

- **Snapshot date**: March 20, 2026
- **Total stdlib lines**: 4,512
- **Number of modules**: 21
- **Number of public functions**: ~250+
- **Number of types**: ~30+ (including built-ins)
- **C runtime dependencies**: 50+ functions

---

