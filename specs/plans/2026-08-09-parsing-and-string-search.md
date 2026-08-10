# Parsing and String Search in March

Design notes. Covers the parser combinator core, error reporting (a first-class
design goal, not an afterthought), syntax options, and the separate question of
general string search. Status: exploratory, no implementation.

Revised 2026-08-09: examples rewritten in actual March syntax, two open
decisions closed against the repo, existing `Regex`/`String` search surface
reckoned with, and the error-design section expanded to a full contract.

---

## 1. Scope

Two related but distinct problems, deliberately kept apart:

1. **Parsing grammars we own.** Source files, markdown, config formats, wire
   protocols. We control the grammar. Backtracking is affordable because we can
   bound it.
2. **Searching strings.** Finding literals or patterns in a haystack, possibly
   very large, possibly with user-supplied patterns against untrusted input.

Conflating these is how combinator libraries end up as accidental regex engines
with no worst-case bound. (We already have one — see §6.0.) They share a `Span`
discipline and a zero-copy discipline. They should not share an execution
engine.

---

## 2. Parser core

### 2.1 Required pieces

**Zero-copy spans.** Parser state is a byte index into the original buffer;
results carry `(start, len)` pairs. No allocation per token. March strings are
immutable and reference-counted, so a span plus a retained reference to the
buffer is all this takes — no linearity or surface borrow machinery is
required. (The compiler's borrow analysis is an internal Perceus optimization,
not a user-facing type; nothing here gates on it.)

**Cheap backtracking.** With state as a byte position, snapshot and restore is
copying one integer. This is the difference between a combinator library being
fast or being garbage.

**Result-shaped replies that do not allocate on the success path.** See §3 —
the reply type is designed so the hot path carries integers, and rich error
structure is only built at failure time.

**FBIP for AST construction.** This is where March's existing strengths pay
off. Reusing cells in place while building the AST avoids the alloc/free churn
that dominates naive recursive descent elsewhere. Combinators should be
designed to trigger FBIP paths deliberately, not incidentally.

**Tail-call elimination.** Recursive descent leans on recursion for nested
grammar rules. March's compiled path has TCO (`lib/tir/` tco pass); the
combinator loops (`many`, `sep_by`) must be written in the tail-recursive
accumulator idiom so they actually hit it.

**First-class functions and generics.** Combinator style needs parametric
polymorphism over output types plus closures that do not force heap allocation
in the simple cases. Both exist today.

**`@noalloc` lexing.** Tokenization is the hot loop. `@noalloc` exists and is
checked (`check_noalloc`, `lib/tir/policy_dce.ml`), and `string_byte_at`
already provides allocation-free byte access — it returns 0..255, or -1 past
the end, with no heap traffic. The `Regex` module was recently rewritten from
char-strings to byte codes for exactly this reason (its header comment
documents 5.8 allocations per pattern byte in the old form — the strongest
in-repo evidence for this whole section).

### 2.2 Semantics

**PEG ordered choice, not full backtracking.** First alternative that succeeds
wins, no re-exploration. See §5 for why.

**Commit points.** A `commit` primitive marks the position past which failure
becomes a hard parse error rather than a backtrack into the next alternative.
Without it, a malformed `if` statement silently falls through to be parsed as
something else and the error message points at the wrong place. (SNOBOL called
this `FENCE`; Prolog calls it cut.)

```march
fn stmt() : Parser(Stmt) do
  alt(
    keyword("if") |> then_commit(if_tail()),   -- past "if", failure is hard
    expr_stmt()
  )
end
```

Commit is also the hook that makes error *context* work — see §3.3.

---

## 3. Errors are the product

A parser library's real output, most days, is not an AST — it is the message a
user reads when their input is wrong. The March compiler already has a voice
("I was expecting `=` in the let? binding here") and a diagnostic type with
spans (`lib/errors/errors.ml`). The combinator library must be able to produce
diagnostics of that quality for user-written grammars, or the markdown parser
and every forge-built tool on top of it will have worse errors than the
compiler hosting them. This section is the contract; the `Parser` type is
shaped around it.

### 3.1 The reply and error types

```march
type Expected =
  ExpLit(String)          -- expected the literal "then"
  | ExpLabel(String)      -- expected an <expression> (human-named class)
  | ExpEof                -- expected end of input

type ParseErr = {
  pos      : Int,                    -- furthest byte offset reached
  expected : List(Expected),         -- merged expected-set AT that offset
  context  : List((String, Int))     -- ("if statement", start_pos) stack
}

type Reply(a) =
  ROk(a, Int, Int)        -- value, new pos, furthest-failure pos (an Int only)
  | RFail(ParseErr)       -- soft failure: ordered choice may try the next arm
  | RCut(ParseErr)        -- hard failure: a commit point was passed; propagate

type Parser(a) = Parser((String, Int) -> Reply(a))
```

Two deliberate asymmetries:

- **Success carries only an integer** for error bookkeeping (the furthest
  position any sub-parse failed at). Expected-sets and context stacks are
  allocated only on the failure paths. This keeps `ROk` chains `@noalloc`-
  friendly, which is the resolution of the "no allocation on the success path"
  requirement in §2.1 — deferred error construction, not absence of error
  information.
- **Soft vs hard failure is in the type**, not a flag. `alt` pattern-matches:
  `RFail` → try the next alternative (merging errors, §3.2); `RCut` → stop and
  propagate. You cannot forget to check the commit bit.

### 3.2 Furthest-failure merging

The single highest-leverage rule for message quality: when ordered choice
exhausts its alternatives, report the failure that got *furthest* into the
input, and if several tied at the same offset, merge their expected-sets.

```
input:   if x then
                ^-- alt(if_stmt, expr_stmt): if_stmt died here (pos 5),
                    expr_stmt died at pos 0. Report pos 5.
```

Without this, `alt` reports whichever alternative was listed last — the
classic "expected expression" at column 0 while the real mistake is at column
40. With it, the merged tie case reads "I was expecting `do` here" (and never
"expected `then`" — but a curated `ExpLit("do")` merge can even carry the
compiler's existing hint that March uses do/end, see §3.5). This is why `ROk`
threads the furthest-failure Int even on success: a later failure at an
earlier position must not shadow an earlier sub-parse's deeper progress.

### 3.3 Commit points carry context

`commit` does two things: it upgrades subsequent `RFail`s to `RCut`, and it
pushes a `(label, start_pos)` frame onto the error's context stack. That stack
is what turns

```
error at 14:3: I was expecting `end`
```

into

```
error at 14:3: I was expecting `end` to close the `if` that started at 12:1
```

The primitive is `ctx(name, p)`: run `p`, and if it fails hard, prepend
`(name, start_pos)` to the error's context. `then_commit` composes `commit`
and `ctx` because in practice you always want both at the same place — the
keyword that commits you is the thing worth naming.

### 3.4 Labels replace noise

Raw expected-sets degrade into token soup ("expected `-`, `0`..`9`, `(`, or
`fn`"). `label(p, "expression")` runs `p` and, if it fails **without consuming
input**, replaces its expected-set with `ExpLabel("expression")`. If `p`
failed after consuming, the inner (more specific) error is kept — the
consumed/not-consumed distinction is what stops labels from hiding real
progress. Every public nonterminal in a grammar should be labeled; the
markdown grammar becomes its own test of whether the labeling ergonomics are
good enough that people actually do it.

### 3.5 Rendering

Offsets are bytes; line/column conversion happens once, at render time, never
in the hot path. The renderer produces the March diagnostic shape — span,
message in the compiler's first-person voice, optional hint — so library
errors and compiler errors are visually indistinguishable and LSP integration
(squiggles from a forge-tool's config parser, say) is free. A `to_diagnostic`
that yields the `lib/errors` type is part of the core API, not an example.

### 3.6 Error recovery, for the markdown case

Markdown never fails — every byte sequence is "valid" — but its structure
parses can fail locally, and a good tool reports *all* the problems, not the
first. Two recovery combinators, both opt-in:

- `recover(p, sync, default)` — if `p` fails hard, record the error, skip to
  the synchronization parser `sync` (e.g. blank line, next heading), and
  yield `default`. The driver accumulates a `List(ParseErr)` alongside the
  partial AST — the same multiple-diagnostics-per-run shape as the compiler.
- `fence(p)` — run `p` but downgrade its `RCut` back to `RFail` at this
  boundary, so one block's hard failure cannot abort sibling blocks. (This is
  the *other* half of SNOBOL's `FENCE`: commit is scoped, not global.)

### 3.7 Testing the errors

Message quality regresses silently unless pinned. From day one: a golden
corpus of bad inputs with expected rendered diagnostics, exactly like the
compiler's `reject/` corpus and the `@types-check` diagnostic-text corpus.
The acceptance bar for step 1 of the sequencing (§9) includes the error
goldens, not just the accept cases.

---

## 4. Syntax options

Ranked by investment. Build 4.1 first regardless of where we end up.

### 4.1 Plain combinators

Zero new syntax. Needs only generics, ADTs, and pipe — all present.

```march
fn digit() : Parser(Char) do
  satisfy(fn c -> char_is_digit(c))
end

fn integer() : Parser(Int) do
  many1(digit()) |> map(fn cs -> chars_to_int(cs))
end

fn expr() : Parser(Expr) do
  alt(
    integer() |> map(fn n -> Lit(n)),
    between(chr('('), expr(), chr(')'))
  )
end
```

Safe baseline. Gets noisy for real grammars, but it is where the semantics —
and per §3, the error contract — get proven.

### 4.2 Operator sugar — BLOCKED on a language feature

```march
-- HYPOTHETICAL — not currently expressible in March:
-- (integer ~> Lit) <|> (chr('(') *> expr <* chr(')'))
```

Parsec-lineage infix operators (`<|>` choice, `*>` / `<*` sequence-discard,
`~>` map-into-constructor) require user-defined infix operators with declared
precedence and associativity. **Verified 2026-08-09: March does not have
these** — the operator set in `lib/parser/parser.mly` is fixed. This option is
therefore gated on a significant language feature whose costs (formatter, LSP,
error messages for precedence mistakes) extend far beyond parsing. Ranked
last unless user-defined operators are wanted on independent grounds.

### 4.3 Monadic binding sugar

March already ships two pieces of precedent here: `let?` (Result propagation,
shipped and conformance-tested — `specs/lang/let-propagation.md`) and
`with ... do ... else ... end` (multi-step Result chaining). A generalized
bind sugar is a sibling of an existing feature, not a novelty. In March's
block style (no `in` — March lets never take one):

```march
fn add_expr() : Parser(Expr) do
  parse do
    let* a  = integer()
    let* _  = ws()
    let* op = optional(chr('+'))
    match op do
      Some(_) ->
        let* b = expr()
        pure(Add(Lit(a), b))
      None -> pure(Lit(a))
    end
  end
end
```

Reads like ordinary March control flow; desugars to `flat_map`. The argument
for this over 4.2 is that the same sugar pays off well beyond parsing:
`Option`, `Result`, and actor message handling all want it, and it composes
with the `let?` design work already done. Open sub-question: whether `let*`
generalizes `let?` (one mechanism, `Result` as an instance) or sits beside it.

### 4.4 `~p` sigil grammar DSL

```march
let grammar = ~p"""
  expr    := term (('+' / '-') term)*
  term    := factor (('*' / '/') factor)*
  factor  := INT / '(' expr ')'
"""
```

Compile-time desugaring into combinator calls, PEG ordered choice (`/`) in the
syntax itself. Closest to writing a grammar rather than writing code that
happens to parse. The sigil *syntax* is real precedent — the lexer accepts
`~name`/`~Name` prefixes generically (`lib/lexer/lexer.mll:173`) and stdlib
`Sigil` ships `h`, `toml`, `xml`, `yaml`. **Open question:** the existing
sigils process string content through ordinary functions; the compile-time
expansion this option needs (grammar errors at compile time, generated
combinator calls) may be new machinery wearing familiar syntax. Also note the
labeling/context discipline of §3.3–3.4 must survive the DSL — a grammar
file that produces worse errors than hand-written combinators would be a
regression, so the DSL needs label and commit annotations in its syntax, not
just `/`. Biggest payoff, biggest investment. Build on top of a proven 4.1
core.

---

## 5. What SNOBOL and Icon actually teach

SNOBOL4 is the deepest prior art here and predates the Wadler/Hutton
combinator formalization by decades.

**Take: patterns as first-class composable values.** SNOBOL's `PATTERN` is its
own data type. Concatenation is sequence, `|` is alternation, and the result
is a value you can bind and reuse. This is combinator style, and it is the
model.

**Take: primitives instead of a nested mini-language.** `LEN(n)`,
`SPAN(chars)`, `BREAK(chars)`, `ARB`, `FENCE` were ordinary pattern values
composed like anything else. No separate string-based regex DSL to escape
into. Worth using as a checklist for our combinator primitives. `FENCE` in
particular is both the `commit` idea in §2.2 and the recovery boundary in
§3.6.

**Take: Icon's generators.** Icon made backtracking explicit as lazy
generators you iterate. This maps onto streaming and incremental parsing,
which combinator libraries usually bolt on awkwardly. If our actor and
capability model has anything coroutine-shaped, this is the fit.

**Leave: pervasive backtracking.** SNOBOL and Icon made every expression
capable of failing and resuming a prior choice point. Elegant, but you cannot
tell by reading whether a given match is linear or exponential. Modern fast
parsers give this up for PEG ordered choice precisely for predictability. This
is the one place SNOBOL is a cautionary tale rather than a model — and §6.0
shows we have already lived it.

**Confirms, adds nothing: cursor threading.** SNOBOL's `POS` / `RPOS`
implicitly threaded a position through matches. Same as our byte-index state,
in 1962-vintage clothing. Useful as evidence the approach is well-tested.

---

## 6. String search, as a separate module

### 6.0 What already exists (this section was missing from draft 1)

String search in March is not greenfield:

- **`stdlib/regex.march` is a shipped, public, backtracking regex engine** —
  greedy `*`/`+`, pure March, byte-code atoms. It is exactly the "accidental
  regex engine with no worst-case bound" §1 warns about: a pattern like
  `(a+)+$` against adversarial input is a live ReDoS today, and `Regex` is
  the obvious thing an app author reaches for with user-supplied patterns.
  The linear-worst-case engine below is therefore not a hypothetical fourth
  module — it is a decision about an existing API: swap the engine underneath
  `Regex` (the supported feature set — no backreferences, no lookaround — is
  already NFA-compatible), add a parallel module and deprecate, or gate by
  pattern class. Swapping underneath is the working assumption; the feature
  list in regex.march's header was seemingly chosen by someone who read the
  same literature.
- **Single-literal search already has an API surface**: `String.contains` /
  `index_of` / `last_index_of` and the `string_index_of` /
  `string_contains` builtins. The "single literal" work item below is an
  upgrade of these (check what the C runtime already does — it may already
  sit on `memmem`) plus a span-returning `find_all`, not a new function
  family.

### 6.1 Why separate from the parser

Anchored match and unanchored search are the same pattern with a different
driver. `find(pattern, haystack)` is just trying the match at successive
positions. That falls out of the combinator core for free. It is also the
slow way to do it, and for user-supplied patterns against untrusted input it
has no worst-case bound at all. So: PEG combinators for grammars we own, a
purpose-built search module for everything else.

### 6.2 The three cases

**Single literal.** `find(haystack, needle) : Option(Int)` (byte offset)
backed by two-way matching or Boyer-Moore-Horspool, SIMD-accelerated in the C
runtime. Vectorized byte scanning is an order of magnitude faster than
character-at-a-time combinator driving. This is the `memchr` / `memmem` role,
upgrading the existing `String.index_of` family in place.

**Multiple literals.** Aho-Corasick automaton, single pass matching all
patterns at once. Note this is exactly what lexers *written in March* need
for keyword-versus-identifier dispatch — the markdown parser's inline lexer,
forge-built user tools — so it earns its place in the stdlib twice over
rather than being hand-rolled per lexer. (The March compiler's own lexer is
ocamllex and is not a customer.)

**User-supplied patterns.** Thompson NFA or DFA engine with guaranteed linear
worst case, RE2 style, replacing the backtracking core of `stdlib/regex.march`
per §6.0. Kept on a separate code path from the backtracking combinators. If
a pattern can come from a config file, a user search box, or any untrusted
source, it goes here.

### 6.3 Shared discipline

Search returns byte-offset `Span`s or an iterator of `Span`s into the
original buffer. Never allocate substrings (`Regex.find` returning
`Option(String)` today is the shape to migrate away from). Same zero-copy win
as the parser, applied to a different problem.

---

## 7. Very large haystacks

At real scale the memory access pattern usually dominates the algorithm
choice.

**Skip, do not step.** The point of Boyer-Moore-Horspool and two-way matching
is skip distance: jump forward by up to the pattern length on mismatch instead
of one byte. SIMD widens this further, checking 16 to 64 bytes per
instruction. As the haystack grows, the search increasingly *is* the amortized
scan-past-non-matching case, so this matters more, not less.

**Two access shapes.**

- Memory-mapped file, sequential scan. Let the OS page cache prefetch. Good
  default for on-disk data.
- Chunked streaming read — `File.with_chunks` is the existing surface for
  this — or a socket. No full buffer available, so the algorithm must carry
  state across chunk boundaries.

**Boundary matches are the sharp edge.** A match straddling a chunk boundary
is missed by naive chunked search. Two fixes: keep an overlap buffer of
`pattern_len - 1` bytes, or use an algorithm where the automaton state *is*
the carry (KMP failure position, Aho-Corasick trie node). The second fits our
zero-copy bias better. No re-buffering, no copy, a few bytes of state between
reads. Prefer it.

**Parallelism.** Large-haystack search is embarrassingly parallel if
approximate boundaries are tolerable: split into N chunks with
`pattern_len - 1` overlap at each seam, search concurrently, merge and dedupe
matches falling in overlap regions. This maps directly onto the shipped
`Parallel` / `RRB` stdlib surface (`pmap`, `preduce`, `RRB.chunk` yielding
`Array(Slice(a))`) — large-string search is close to a specialization of that
same infrastructure.

**Repeated queries.** If the same large string is searched many times, build a
suffix array or FM-index once and query in roughly O(pattern length)
afterwards. Different tradeoff, upfront build cost plus index memory, only
pays past some query count. Worth having as an opt-in `Index.build(haystack)`
alongside the one-shot streaming scan, not as a default.

**Large-input parsing is a different problem.** Parsing something too large to
hold in memory does not want search machinery. It wants streaming incremental
parsing that yields partial ASTs or tokens as bytes arrive. That loops back to
the Icon generator idea in §5.

---

## 8. Open decisions

1. ~~User-defined infix operators.~~ **Closed 2026-08-09: March does not
   support them** (fixed operator set in `lib/parser/parser.mly`). Option 4.2
   is gated on a full language feature and ranked last accordingly.
2. ~~Byte versus codepoint offsets for `Span`.~~ **Closed: byte offsets** —
   this is already the codebase's answer (`string_byte_at`,
   `String.slice_bytes`, the byte-code rewrite of `Regex`), consistent with
   SIMD search and `@noalloc`. Unicode-aware search opts into a slower path
   explicitly, as `string_grapheme_count` already does for length.
3. **Buffer or capability-typed stream.** Does `find` take a buffer, a
   stream, or both? Affects the streaming design in §7 and should be decided
   before the search module is built.
4. **Fate of `stdlib/regex.march`'s engine** (§6.0): swap to linear engine
   under the same API (working assumption), parallel module, or pattern-class
   gating. Decide before, not after, `Regex` grows more callers.
5. **`let*` vs `let?`** (§4.3): does general bind sugar subsume Result
   propagation or coexist with it?
6. **Sigil compile-time expansion** (§4.4): does the existing sigil mechanism
   support compile-time desugaring, or is that new machinery?

---

## 9. Suggested sequencing

1. Combinator core, syntax option 4.1, **error contract included** (§3):
   reply type with soft/hard failure, furthest-failure merging, commit +
   context, labels, `to_diagnostic`. No syntax decisions required. The
   acceptance bar is the golden *error* corpus (§3.7) alongside the accept
   cases — PEG semantics proven AND messages pinned.
2. Prove it on the markdown parser. Markdown is the right forcing function:
   it exercises backtracking, nesting, and — via §3.6's recovery combinators —
   multi-error reporting at once, and it is already the one genuine gap
   blocking Cadence.
3. Decide syntax sugar. 4.3 (`let*`/`parse do`) versus the `~p` sigil, with
   the combinator semantics already settled underneath; 4.2 only if
   user-defined operators land for independent reasons.
4. Search module separately. SIMD literal scan first (upgrading the existing
   `String.index_of` family), then Aho-Corasick (which March-written lexers
   want anyway), then the linear-worst-case engine — which is not optional
   "if untrusted patterns become a real requirement" but a scheduled fix for
   the shipped backtracking `Regex` (§6.0).
