# String System Design

> **Status:** Supersedes the `Interpolatable`-based interpolation design in `specs/design.md`
> (lines 140–160). `Interpolatable` is replaced by `Display`. The `Textual` interface remains
> but `concat` is now provided through `IOList` rather than `++` chaining.

## Goal

Define March's complete string system: representation, building, parsing, and the type
hierarchy from raw bytes up to Unicode text. The design prioritises predictability —
every operation has an obvious cost and an obvious failure mode — while matching the
ergonomics of modern functional languages (Elixir's IO lists, Rust's format traits,
Roc's transparent slicing).

---

## Type Hierarchy

```
Bytes           -- raw binary data: file contents, network frames, encoded payloads
  ↑ from_bytes (Result)
String          -- UTF-8 text, immutable, the everyday type
  ↑ abstraction
Rope            -- stdlib: persistent tree for large/editor-style strings
IOList          -- building type: segments that flatten to Bytes/String on demand
```

### `String`

UTF-8, immutable, GC-managed. The default text type for all human-readable data.

**Runtime representation:**

- **Short strings (≤ 15 bytes):** stored inline in the fat-pointer struct itself
  (small-string optimisation, SSO). Never touches the heap.
- **Long strings:** heap-allocated. Substrings are transparent slices —
  `String.slice`, `String.split`, `String.trim` etc. return a `String` backed by
  `{ gc_ref: GCRef, start: usize, len: usize }`. Zero allocation, zero copy. The
  GC keeps the backing buffer alive as long as any slice references it.

Both representations are invisible to the programmer. `String` is just `String`.

**Slice retention policy:** when a slice is less than 1/4 of the backing buffer's
size, the runtime copies eagerly instead of sharing. This prevents small slices from
keeping large buffers alive (the Java `substring` problem). For explicit control,
`String.copy(s)` forces a fresh allocation regardless of the ratio.

```march
String.copy(s : String) : String   -- forces a fresh allocation, releases backing ref
```

### `Bytes`

Raw byte sequence, immutable. No encoding guarantee. Used for I/O, binary protocols,
and any data that is not necessarily valid UTF-8. Safe to share across actor
boundaries (immutability guarantees no data races).

```march
type Bytes   -- opaque in surface language; pattern-matchable (see Parsing section)
```

Conversions between `String` and `Bytes` are explicit:

```march
-- Infallible: String is always valid UTF-8
String.to_bytes(s : String) : Bytes

-- Fallible: not all byte sequences are valid UTF-8
String.from_bytes(b : Bytes) : Result(String, EncodingError)
```

```march
type EncodingError = {
  byte_offset : Int,     -- where the invalid UTF-8 sequence starts
  message : String,      -- human-readable description (e.g. "invalid start byte 0xFE")
}
```

There is no implicit coercion between `String` and `Bytes`. Treating binary data as
text is always an explicit, checked operation.

### `Rope`

Stdlib type for large strings where O(1) concatenation and O(log n) insert/split/index
matter (text editors, log assemblers, large-file transformations). Entirely optional —
most programs never use it.

```
Node { left: Rope, right: Rope, left_len: Int }   -- internal
Leaf { data: String }                              -- stores a flat fragment
```

| Operation | Cost |
|---|---|
| `Rope.concat(a, b)` | O(1) — new root node |
| `Rope.index(r, i)` | O(log n) |
| `Rope.split(r, i)` | O(log n) |
| `Rope.insert(r, i, s)` | O(log n) |
| `Rope.to_iolist(r)` | O(leaves) — wraps each leaf as IOList segment |
| Sequential scan | O(n), cache-unfriendly |

**Implementation note:** Rope leaves should store chunks of 64–4096 bytes, not
individual characters. SSO applies to the `String` inside each leaf but provides
only modest benefit (saves one allocation per leaf, but the GC-managed node object
is the dominant cost). Set a minimum leaf size to amortise GC overhead.

Rope is the right tool when a string is mutated many times and remains as a rope.
For building-then-outputting, prefer `IOList` (see below).

---

## String Operations

### Counting and iteration

Because grapheme cluster count and codepoint count can diverge for composed characters,
all axes are exposed under explicit names. There is no `String.length` function —
the name is ambiguous.

```march
String.grapheme_count(s)  : Int            -- grapheme clusters (human "characters")
String.byte_size(s)       : Int            -- bytes in the UTF-8 encoding
String.graphemes(s)       : GraphemeIter   -- lazy iterator over grapheme clusters
String.codepoints(s)      : CodepointIter  -- lazy iterator over Unicode scalar values
String.to_bytes(s)        : Bytes          -- raw UTF-8 byte sequence
```

Iterators are lazy — they yield one element at a time without allocating a full list.
Use `Iterator.to_list(iter)` when a `List` is needed.

```march
interface Iterator(iter, item) do
  fn next(it : iter) : Option((item, iter))
end
```

Example: the string `"é"` composed as `e` + combining-acute (U+0301):

```march
String.grapheme_count("é")       -- 1  (one grapheme)
String.byte_size("é")            -- 3  (UTF-8 bytes)
Iterator.to_list(
  String.graphemes("é"))         -- ["é"]  (one cluster, as a String)
Iterator.to_list(
  String.codepoints("é"))       -- ['e', '\u{0301}']  (two Chars)
```

### Common operations

```march
String.slice(s, start, len)     : String     -- zero-copy substring (grapheme indices)
String.slice_bytes(s, start, len) : Option(String) -- byte-indexed; None if mid-codepoint
String.split(s, sep)            : SplitIter  -- lazy iterator
String.split_first(s, sep)      : Option((String, String))
String.trim(s)                  : String
String.trim_start(s)            : String
String.trim_end(s)              : String
String.starts_with(s, prefix)   : Bool
String.ends_with(s, suffix)     : Bool
String.contains(s, sub)         : Bool
String.replace(s, from, to)     : String     -- first occurrence only
String.replace_all(s, from, to) : String     -- all occurrences
String.to_uppercase(s)          : String
String.to_lowercase(s)          : String
String.normalize(s, form)       : String     -- explicit; see NormForm below
String.copy(s)                  : String     -- force fresh allocation
```

**Cost model for `String.slice`:** the "zero-copy" refers to buffer allocation — no
new byte array is created. However, finding grapheme index `start` requires walking
the UTF-8 bytes from the beginning, running the UAX #29 grapheme break algorithm.
`String.slice(s, start, len)` is **O(start + len)** in bytes, not O(1). For
performance-critical random access, use `String.slice_bytes` which is O(1).

### Unicode normalization

Normalization is never implicit. `"café"` (precomposed é) and `"café"` (e + combining
accent) are different `String` values — they hash differently, compare differently,
and are different map keys. Use `String.normalize` when you need canonical equivalence
(before hashing, map keys, comparison across sources).

```march
type NormForm = NFC | NFD | NFKC | NFKD

String.normalize(s : String, form : NormForm) : String
```

Using a typed variant (not an atom) makes invalid forms a compile-time error.

**Footgun:** two strings that look identical to a human can be unequal if they use
different normalization forms. When building maps keyed by user-supplied strings,
or comparing strings from different sources (database vs file vs network), normalise
first:

```march
let key = String.normalize(user_input, NFC)
Map.get(lookup, key)
```

---

## Building Strings: IOList

### The problem

Chaining `++` allocates an intermediate string at every step:

```march
"Hello, " ++ name ++ "! You have " ++ int_to_string(n) ++ " items."
-- allocates: "Hello, John", then "Hello, John! You have ", then the full string
```

For k segments this is O(k²) in total bytes allocated.

### The `++` operator

`++` remains the string concatenation operator in expressions. It takes two `String`
values and returns a `String`, allocating a new buffer:

```march
(++) : String -> String -> String
```

This is unchanged from the current implementation. For small concatenations (2–3
segments), `++` is fine. For building output from many segments, use `IOList` or
`${}` interpolation.

### IOList

`IOList` is a first-class type representing a lazy tree of string segments. It is
only flattened to a contiguous buffer when forced (written to IO, passed to
`IOList.to_string`, etc.).

```march
type IOList =
  | Empty
  | Str(String)
  | Raw(Bytes)
  | Segments(List(IOList))
```

There is no binary `Concat` node. All multi-segment construction goes through
`Segments(List(IOList))`. This prevents deep left-spine chains from repeated
`append` that would blow the stack during traversal. The flush implementation uses
iterative traversal with an explicit stack.

`String` does **not** implicitly coerce to `IOList`. Use `IOList.from_string(s)`
for explicit wrapping. The compiler handles this internally for `${}` desugar; user
code is explicit.

Building is O(1) per segment. Flushing is a single O(n) traversal over the tree.

### IOList API (modelled on Elixir)

```march
IOList.empty              : IOList
IOList.from_string(s)     : IOList
IOList.from_bytes(b)      : IOList
IOList.append(a, b)       : IOList          -- O(1); creates Segments([a, b])
IOList.join(xs, sep)      : IOList          -- List(IOList), with separator
IOList.from_list(xs)      : IOList          -- List(IOList) with no separator
IOList.to_string(io)      : String          -- force: allocates once
IOList.to_bytes(io)       : Bytes           -- force to raw bytes
IOList.byte_size(io)      : Int             -- O(n) tree traversal, no allocation
```

`IOList.byte_size` walks the tree to sum byte lengths without allocating a flat
buffer. It is O(n) in tree nodes.

### String interpolation

`${}` always produces a `String`. The compiler uses IOList internally for the
assembly but flattens the result, so the user-visible type is always `String`:

```march
let msg = "Hello, ${name}! You have ${count} items."
-- msg : String
-- Internally desugars to IOList assembly + flatten, but the type is String
```

This means `${}` works everywhere a `String` is expected — no type mismatches, no
manual forcing. The compiler can optimise away the flatten when the result flows
directly into an IO function (see below).

**Optimisation:** when an interpolated string is passed directly to `println` or
another `Display`-consuming function, the compiler skips the flatten and passes the
IOList segments directly. This is an internal optimisation, not visible in the type
system.

For explicit IOList building without auto-flatten (template engines, web frameworks),
use the IOList API directly:

```march
let body = IOList.join(lines, "\n")
let page = IOList.from_list([header, body, footer])
File.write("output.html", page)   -- File.write accepts Display(a)
```

**Triple-quoted strings (`"""..."""`) support `${}` interpolation and escape
sequences**, matching Elixir's heredoc behaviour. Common leading whitespace is
stripped based on the indentation of the closing `"""`:

```march
let msg = """
  Hello, ${name}!
  You have ${count} items.
  """
-- msg : String = "Hello, ${name}!\nYou have ${count} items.\n"
```

---

## Display and Debug

Two separate interfaces, following Rust's model. IO functions are generic over
`Display(a)`, so both `String` and `IOList` (and any user type) work without
coercion:

```march
fn println(value : a) : Unit where Display(a)
fn print(value : a) : Unit where Display(a)
```

### `Display` — human-readable output

Used by `${}` interpolation and `println`. Produces output intended for end users.
Takes a `Formatter` to support format specifiers (width, precision, alignment).

```march
type Formatter   -- opaque; carries width, precision, fill, alignment, radix flags

interface Display(a) do
  fn display(value : a, fmt : Formatter) : IOList
end
```

`Formatter.default` carries no flags (plain display). Format specifiers in `${}`
construct a non-default `Formatter` and pass it to `display`.

**Formatter accessors** for custom `Display` implementations:

```march
Formatter.width(fmt)      : Option(Int)
Formatter.precision(fmt)  : Option(Int)
Formatter.fill(fmt)       : Char            -- default: ' '
Formatter.align(fmt)      : Option(Align)
```

```march
type Align = Left | Right | Center
```

Auto-implemented for `String`, `Int`, `Float`, `Bool`, `Char`.
User types opt in by implementing `Display`.

### `Debug` — programmer-readable output

Used by the REPL inspect, error messages, and `dbg!`-style introspection.
Intended to be unambiguous: strings are quoted, escape sequences visible.

```march
interface Debug(a) do
  fn debug(value : a) : IOList
end
```

`Debug` for `String` wraps in double quotes and escapes special characters.
`Debug` for `Option(Int)` produces `"Some(42)"` not `"42"`.

The REPL's `h(fn_name)` and inspect output use `Debug`. User-facing output uses
`Display`. They are never conflated.

### Format specifiers in `${}`

`${}` supports Rust-style format hints after `:`. The specifier is resolved at
compile time to a `Formatter` value passed to `Display.display`. Types that do not
support a given specifier produce a compile-time error.

```march
"${n:05}"       -- zero-pad integer to width 5:  "00042"
"${f:.2}"       -- float to 2 decimal places:    "3.14"
"${s:>20}"      -- right-align in 20 chars:      "               hello"
"${s:<20}"      -- left-align
"${s:^20}"      -- centre-align
"${n:x}"        -- lowercase hex:                "2a"
"${n:X}"        -- uppercase hex:                "2A"
"${n:b}"        -- binary:                       "101010"
"${n:e}"        -- scientific notation:           "4.2e1"
```

---

## Parsing

### String prefix/suffix patterns

Match arms can destructure strings using the `<>` operator (distinct from `++`
which is expression-level concatenation):

```march
match url with
| "https://" <> rest -> secure(rest)
| "http://"  <> rest -> insecure(rest)
| _                  -> unknown(url)
end
```

`"prefix" <> rest` desugars to `String.starts_with(s, "prefix")` + `String.slice`
for the tail. `rest` is a zero-copy slice.

Suffix matching:

```march
match filename with
| base <> ".march" -> compile(base)
| base <> ".md"    -> render(base)
end
```

Prefix + suffix matching (both ends are literals, middle is bound):

```march
match url with
| "http" <> middle <> ".com" -> handle(middle)
end
```

Desugars to: check `starts_with` + `ends_with` + verify
`total_len >= prefix_len + suffix_len`, bind middle to the slice between.

**Constraints on `<>` patterns:**

- At least one side must be a string literal
- `a <> b` with both sides as variables is **invalid** (ambiguous split point)
- `"prefix" <> mid <> "suffix"` is valid (two literals, one binder)
- `"a" <> x <> y <> "b"` is **invalid** (ambiguous split between x and y)

### Binary/byte patterns

`Bytes` can be destructured with `<<>>` syntax, specifying each field's type and size.
Bare integer literals and bindings default to `U8` (unsigned, 8-bit), following
Elixir's convention:

```march
match frame with
| <<0xFF, 0xFE, rest : Bytes>>                          -> handle_utf16_bom(rest)
| <<len : U16Be, payload : Bytes(len), rest : Bytes>>   -> handle_frame(payload, rest)
| <<r, g, b>>                                           -> Rgb(r, g, b)  -- all U8
end
```

**Type specifiers in `<<>>`:**

| Specifier | Meaning |
|---|---|
| `U8` | 1 byte, unsigned (default for bare values) |
| `U16Le` / `U16Be` | 2 bytes, unsigned, little/big endian |
| `U32Le` / `U32Be` | 4 bytes, unsigned |
| `U64Le` / `U64Be` | 8 bytes, unsigned |
| `I8`, `I16Le`, etc. | Signed variants |
| `F32Le` / `F32Be` | 32-bit float |
| `F64Le` / `F64Be` | 64-bit float |
| `Bytes(n)` | n bytes as a `Bytes` slice — zero-copy |
| `Bytes` | remaining bytes as a `Bytes` slice |

Binding a field to a previously-bound variable uses it as a length:
`payload : Bytes(len)` reads exactly `len` bytes, where `len` was bound earlier in
the same pattern. If `len` would be negative (from a signed specifier), the pattern
does not match.

Patterns that would read past the end of the buffer simply don't match (fall through
to the next arm). No exceptions, no undefined behaviour.

### Regex

A single `Regex` type operating on bytes internally. Unicode mode is on by default
(`.` matches a Unicode scalar value, `\w` is Unicode-aware), but matching is
performed against the UTF-8 byte representation.

```march
let re = Regex.compile("^[A-Za-z_][A-Za-z0-9_]*$")
-- re : Result(Regex, RegexError)
```

`Regex.compile` is fallible — invalid patterns return `Err(RegexError)`:

```march
type RegexError = {
  offset : Int,       -- position in the pattern string where the error was detected
  message : String,   -- human-readable description
}
```

Match operations:

```march
Regex.find(re, s)          : Option(Match)
Regex.find_all(re, s)      : MatchIter        -- lazy iterator
Regex.split(re, s)         : SplitIter        -- lazy iterator
Regex.replace(re, s, sub)  : String           -- first match, literal replacement
Regex.replace_all(re, s, sub) : String        -- all matches, literal replacement
```

Replacement strings are literal — no backreferences. Capture-group-aware replacement
may be added in a future version.

**`Match` type:**

```march
type Match = {
  text : String,                      -- the full matched substring
  byte_start : Int,                   -- byte offset in source (inclusive)
  byte_end : Int,                     -- byte offset in source (exclusive)
  groups : List(Option(String)),      -- capture groups; index 0 = full match
}

Match.group(m, n)    : Option(String)   -- nth capture group (0 = full match)
Match.start(m)       : Int              -- byte_start
Match.end_(m)        : Int              -- byte_end
```

Groups use `Option(String)` because alternations can leave a group unmatched:

```march
-- Pattern: "(a)|(b)" matching "b"
-- groups = [Some("b"), None, Some("b")]
--           full match  grp1  grp2
```

Named capture groups are deferred to a future version.

`Regex` is not a literal syntax — compile at startup or use a `let` binding at
module scope. There is no `BytesRegex`; the single `Regex` type handles both text
and binary use-cases via its byte-level engine.

---

## Summary of design decisions

| Decision | Choice | Rationale |
|---|---|---|
| Representation | UTF-8, immutable, GC | Safe, predictable, universal |
| Substrings | Transparent slices with 1/4 threshold | Zero-copy for large slices; copies small slices to prevent retention |
| SSO | ≤15 bytes inline, runtime-only | Most short strings never touch the heap |
| Counting | `grapheme_count`, `byte_size` — no `length` | Explicit names prevent unit confusion |
| Iteration | Lazy iterators: `graphemes`, `codepoints`, `split` | Avoid allocating full lists for large strings |
| Unicode normalization | None by default; explicit `.normalize(s, NFC)` | Fast; honest about complexity |
| `NormForm` | Typed variant, not atom | Compile-time error on invalid form |
| Normalization footgun | Documented: same-looking strings can be unequal | Normalise before map keys, cross-source comparisons |
| String building | `IOList` — first-class stdlib type | O(n) builds, zero intermediate alloc |
| `++` operator | Kept for expression concatenation: `String -> String -> String` | Simple, familiar, fine for small chains |
| `${}` interpolation | Produces `String`; compiler uses IOList internally | Predictable types; compiler optimises IO paths |
| Triple-quoted strings | Support `${}` and escapes; strip common leading whitespace | Matches Elixir heredoc behaviour |
| IO functions | Generic: `println(a) where Display(a)` | Both String and IOList work without coercion |
| No implicit coercion | `String` ≠ `IOList`; explicit wrapping required | Predictable, no hidden allocations |
| Human output | `Display(a)` interface with `Formatter` | Clean separation of concerns |
| Debug output | `Debug(a)` interface | Unambiguous; used by REPL |
| Format specifiers | Rust-style `${n:05}`, `${f:.2}` via `Formatter` | Familiar, composable |
| Display model | Pull-based (return IOList) | Natural for functional language; push-based conflicts with IOList |
| Large persistent strings | `Rope` in stdlib (opt-in) | O(1) concat, O(log n) edit; most programs don't need it |
| Raw binary | `Bytes` type, immutable, no implicit coercion | Explicit boundary; safe for actor sharing |
| `Bytes → String` | Explicit fallible `Result(String, EncodingError)` | Encoding errors are real |
| `String → Bytes` | Infallible `String.to_bytes` | String is already valid UTF-8 |
| Slice cost model | `slice` is O(start+len) graphemes; `slice_bytes` is O(1) | Documented: grapheme indexing requires scanning |
| Buffer retention | 1/4 threshold heuristic + explicit `String.copy` | Prevents small slices retaining large buffers |
| String patterns | `<>` operator in patterns (not `++`) | No operator overload; `++` stays for expressions |
| Pattern constraints | At least one literal required; prefix+suffix allowed | Prevents ambiguous splits |
| Byte patterns | `<<U16Be, Bytes(n), ...>>`; bare values default to U8 | Elixir-inspired, typed, safe |
| Regex | Single `Regex`, byte engine, Unicode mode, `Result`-returning compile | Simple; no text/binary regex split |
| Match type | `{ text, byte_start, byte_end, groups }` | Standard fields; named captures deferred |
| Replacement | Literal only — no backreferences | Simple; backrefs in future version |
| `String.replace` | Both `replace` (first) and `replace_all` | Explicit, no ambiguity |
