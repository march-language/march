# Parsing and String Search in March

Design notes. Covers the parser combinator core, error reporting (a first-class
design goal, not an afterthought), syntax options, and the separate question of
general string search. Status: exploratory, no implementation.

Revised 2026-08-09 (a): examples rewritten in actual March syntax, two open
decisions closed against the repo, existing `Regex`/`String` search surface
reckoned with, and the error-design section expanded to a full contract.

Revised 2026-08-09 (b): prior-art survey added (§5.2–5.3). Four changes fell
out of it — pipe-as-sequence is available today and unblocks much of §4.1
without new syntax; the case for `let*` is now a typing argument rather than a
convenience one (§4.3); the commit model is an argued decision rather than an
inherited default (§2.2); and the validation corpus moves from markdown to the
four hand-written stdlib parsers, which are better ground truth (§5.3, §10).

Revised 2026-08-09 (c): §8 added — inline parser probes in the LSP, run
against sample input in the editor. Folded in as part of this plan rather than
a separate LSP item because it is the feedback loop that makes §3's error
quality visible while the grammar is being written, and because it shares the
doctest and golden-error-corpus machinery §3.7 already needs.

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

**Which commit model — an argued choice, not an inherited default.** There are
two established answers and we should pick deliberately:

- **PEG + explicit cut** (this plan, fastparse's `~/`, Prolog): backtracking is
  free by default, `commit` opts into hard failure. Predictable, but every
  good error message depends on someone having placed a cut. Forget one and
  the message silently degrades — cut placement is the known way people get
  PEG parsers wrong.
- **Consumption commits** (Parsec, Megaparsec): consuming any input commits
  you to the current alternative, and `try` opts back *into* backtracking.
  Error locality comes for free because a partially-consumed alternative
  cannot be silently abandoned. The cost is the well-documented surprise of
  needing `try` in front of alternatives that share a prefix.

We take PEG + explicit cut, because predictability of *backtracking* is the
property §1 is built around and because `try`-forgetting failures are
mis-parses while cut-forgetting failures are merely worse messages. But note
that §3.4's label rule already turns on the consumed/not-consumed
distinction, so the reply type must track consumption regardless. Having paid
for that bookkeeping, a `commit_on_consume` combinator that opts a single
nonterminal into Parsec's behavior is nearly free, and grammars with heavy
shared prefixes will want it. Provide both; default to neither being implicit.

---

## 3. Errors are the product

A parser library's real output, most days, is not an AST — it is the message a
user reads when their input is wrong. The March compiler already has a voice
("I was expecting `=` in the let? binding here") and a diagnostic type with
spans (`lib/errors/errors.ml`). The combinator library must be able to produce
diagnostics of that quality for user-written grammars, or every forge-built
tool on top of it will have worse errors than the compiler hosting it. This
section is the contract; the `Parser` type is shaped around it.

**PEG makes this harder, not easier, and there is proof.** Ordered choice
actively destroys error information: when the last alternative fails, the
reasons the earlier ones failed have already been discarded. CPython is the
large-scale demonstration. PEP 617 replaced CPython's LL(1) parser with a PEG
parser; the diagnostics regressed so badly that CPython now runs a **second
parsing pass with a dedicated family of `invalid_*` grammar rules** whose only
purpose is producing good messages. That is the cost of treating error design
as downstream of the engine. Everything below exists so we do not pay it.

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

type ParseReply(a) =
  ROk(a, Int, Int)        -- value, new pos, furthest-failure pos (an Int only)
  | RFail(ParseErr)       -- soft failure: ordered choice may try the next arm
  | RCut(ParseErr)        -- hard failure: a commit point was passed; propagate

type Parser(a) = Parser(String -> Int -> ParseReply(a))
```

Two naming notes, both learned from writing the implementation:

- The reply type is `ParseReply`, not the more natural `Reply`, because
  `channel.march` already declares a `Reply` constructor and the stdlib shares
  one global namespace.
- March writes multi-argument function *types* curried (`f : b -> a -> b`) but
  *calls* them uncurried (`f(x, y)`) — see `sort.march`'s comparator
  signatures. Hence `String -> Int -> ParseReply(a)` for a function invoked as
  `f(input, i)`.

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
The acceptance bar for step 1 of the sequencing (§10) includes the error
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
    between(lit("("), expr(), lit(")"))
  )
end
```

Safe baseline. Gets noisy for real grammars, but it is where the semantics —
and per §3, the error contract — get proven.

**Pipe-as-sequence: NimbleParsec's trick, available today.** Draft 1 treated
the absence of `<|>` / `*>` as forcing a choice between deeply nested
`alt(seq(...))` calls and a whole language feature. There is a third option,
and Elixir's NimbleParsec is the proof it works: **make sequencing be the pipe
operator.** Each combinator takes the accumulated parser as its first argument
and returns a new one, so `a |> then(b) |> then(c)` reads as "a, then b, then
c". March's pipe desugars as `x |> f(a)` → `f(x, a)`, which is exactly the
shape this needs — no new syntax, no new language feature, works right now:

```march
fn date() : Parser((Int, Int, Int)) do
  integer(4)
  |> skip_then(lit("-"))
  |> and_then(integer(2))
  |> skip_then(lit("-"))
  |> and_then(integer(2))
  |> map(fn ((y, m), d) -> (y, m, d))
end
```

The catch is types, and it is the whole argument for §4.3 — see there. In
short: `and_then` accumulates **left-nested tuples** (`((y, m), d)`), which is
fine at two or three elements and becomes unreadable past four. So
pipe-as-sequence is the right tool for short, flat, linear sequences, and it
should exist in the core API. It is not a general answer to grammar
ergonomics.

### 4.2 Operator sugar — BLOCKED on a language feature

```march
-- HYPOTHETICAL — not currently expressible in March:
-- (integer ~> Lit) <|> (lit("(") *> expr <* lit(")"))
```

Parsec-lineage infix operators (`<|>` choice, `*>` / `<*` sequence-discard,
`~>` map-into-constructor) require user-defined infix operators with declared
precedence and associativity. **Verified 2026-08-09: March does not have
these** — the operator set in `lib/parser/parser.mly` is fixed. This option is
therefore gated on a significant language feature whose costs (formatter, LSP,
error messages for precedence mistakes) extend far beyond parsing. Ranked
last unless user-defined operators are wanted on independent grounds.

### 4.3 Monadic binding sugar — CHOSEN (2026-08-12), IMPLEMENTED (2026-08-14)

**Shipped as `let*`.** Full design, corpus, and diagnostics:
`specs/lang/let-star-generalized-bind.md`. One correction from the plan
below: `Self(a) -> (a -> Self(b)) -> Self(b)` was never attempted as a
constrained-polymorphism interface (§9 decision 5 already anticipated this
was infeasible) — the shipped mechanism is exactly what this section
predicts (§4.3's own text: "`let*` must be what `let?` already is: a native
AST node, typechecked natively, resolving `flat_map` from the inferred type
of its right-hand side"), with the dispatch convention made precise: `M`'s
`flat_map` lives in a module of the SAME NAME as `M`. One real gap found
during implementation, not anticipated here: `stdlib/parse.march`'s
`Parser` type lives in a module named `Parse`, breaking that convention —
`let*` does not (yet) work with `Parser`, and the fix (a module rename, or
an explicit second resolution path) is filed as a follow-up, not bundled in.

**Decision: build `let*`.** Rejected `~p` and confirmed `<|>` blocked; the
evidence and costs are below and in §9 decisions 1, 5 and 6.

The mechanism is settled too, and it is *not* the obvious one. A general
`Bind`/`Monad` interface would need `Self(a) -> (a -> Self(b)) -> Self(b)`, and
March cannot express that: `interface Name(param)` takes exactly ONE type
parameter (`lib/parser/parser.mly:838`), `Self` is never applied to a type
argument anywhere in the stdlib or the language specs, and there is no
higher-kinded machinery. `Iterable`'s own interface sketch
(`stdlib/iterable.march`) is commented out as "future" and sidesteps this by
fixing the element type.

So `let*` must be what `let?` already is: a **native AST node, typechecked
natively**, resolving `flat_map` from the inferred type of its right-hand side.
`let?` is the worked precedent — `ELetQ`, hardwired to `Result` in
`typecheck.ml`'s `infer_expr` — so the shape, the cost, and the diagnostic
style are all known rather than speculative. `Parse.flat_map` now exists, so
the parser side is ready for it.


**This is the option the type system chooses for us.** The argument is not
primarily about reuse (that comes second); it is that static typing forecloses
the alternatives.

Work through why NimbleParsec's ergonomics (§4.1) are as good as they are.
Elixir is dynamically typed, so a pipeline of combinators can accumulate its
results onto a single flat, heterogeneous list — `integer(4) |> string("-") |>
integer(2)` just pushes three values of three different shapes into one
accumulator and lets you sort them out at the end. **March cannot express
that.** Under Hindley-Milner a list is homogeneous, so a typed
pipe-of-combinators has exactly two escapes:

1. **Left-nested tuples** — `and_then` grows `((a, b), c)`, then `(((a, b), c),
   d)`. Readable at two elements, tolerable at three, actively hostile at six,
   and every intermediate `map` has to spell out the whole nest. This is why
   §4.1 is scoped to short linear sequences.
2. **Applicative operators with curried constructors** — `Ctor <$> p1 <*> p2
   <*> p3`, the Haskell answer. It composes beautifully and stays flat at any
   arity. It also *requires user-defined infix operators*, which §4.2 verified
   March does not have. The escape from the typing problem lands us straight
   back on the blocked language feature.

Monadic binding is the third door, and it is the reason OCaml and Haskell —
both statically typed, both without NimbleParsec's freedom — converged on
`let*` and `do` notation for precisely this problem. Named binders stay flat at
any arity, each sub-result gets a name instead of a tuple position, and it
needs no new operators. Sequencing, branching on an intermediate result, and
early return all read as ordinary control flow:

```march
fn add_expr() : Parser(Expr) do
  parse do
    let* a  = integer()
    let* _  = ws()
    let* op = optional(lit("+"))
    match op do
      Some(_) ->
        let* b = expr()
        pure(Add(Lit(a), b))
      None -> pure(Lit(a))
    end
  end
end
```

(Spelling is illustrative — whether the block marker is `parse do`, a general
`do`-block over any bind-able type, or something else is part of the design
work, not settled here.)

Note what the `match` in the middle buys: **context-sensitive parsing**, where
what you parse next depends on what you just parsed. Applicative operators
cannot express that at all (that is the formal difference between applicative
and monadic), and pipe-as-sequence can only fake it with an escape hatch. Any
grammar with length-prefixed data, indentation sensitivity, or version
negotiation needs it — which covers most wire protocols and both YAML and
Markdown.

The reuse argument is now the *secondary* one, and it is still good: March
already ships `let?` (Result propagation, conformance-tested —
`specs/lang/let-propagation.md`) and `with ... do ... else ... end` (multi-step
Result chaining), so a generalized bind is a sibling of shipped features rather
than a novelty, and the same sugar pays off for `Option`, `Result`, and actor
message handling — and it composes with design work already done rather than
starting cold.

Desugars to `flat_map`. Open sub-question, carried to §9: whether `let*`
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

## 5. Prior art

### 5.1 What SNOBOL and Icon actually teach

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

### 5.2 The modern landscape

| Library | Language | Execution model | Error quality |
|---|---|---|---|
| NimbleParsec | Elixir | macro-compiled, pipe-sequenced | basic |
| fastparse | Scala | macro-compiled PEG, `~/` cut | good, cut traces |
| Megaparsec | Haskell | runtime combinators | best in class |
| attoparsec / angstrom | Haskell / OCaml | runtime, incremental | deliberately poor |
| nom | Rust | byte slices, zero-copy | opt-in, mediocre |
| chumsky | Rust | runtime, recovery-first | excellent, recovery built in |
| pest | Rust | PEG DSL, derive macro | good (rule names are labels) |
| menhir | OCaml | LR generator | good, but LR not PEG |

**NimbleParsec (Elixir)** compiles combinators — which are *data*, not
closures — into ordinary function heads at macro-expansion time, so what ships
is BEAM bytecode doing binary pattern matching. Two lessons, pulling opposite
ways. Its pipe-as-sequence ergonomics port to March for free (§4.1); its
result-accumulation model does not port at all, because it depends on dynamic
typing (§4.3). Its errors are not a model to copy: failure point, reason
string, remaining input, line and offset, with a `label` but no expected-set
merging and no furthest-failure heuristic.

**fastparse (Scala) is the closest sibling** — a statically typed language
doing PEG with an explicit cut operator (`~/`, exactly our `commit`) and
macro-compilation for speed. If §4.4's sigil DSL happens, fastparse and `pest`
are the two implementations to read first. fastparse also ships a failure
*trace* showing which cuts were crossed, which is the practical answer to the
"cut placement is where people get PEG wrong" hazard named in §2.2.

**Megaparsec (Haskell) is where §3 should shop.** Expected/unexpected sets,
`label`, furthest-position merging, custom error components, and a rendered
error bundle are all there and battle-tested; §3.1–3.5 is essentially an
argument for porting its ideas onto a PEG-with-cut engine rather than its
consumption-commit engine.

**chumsky (Rust) is the reference for §3.6.** Recovery strategies
(`skip_until`, nested-delimiter recovery) were designed in from the start
rather than retrofitted, which is exactly the bet §3 is making.

**nom (Rust) is the cautionary version of our own thesis.** It is the
zero-copy byte-slice model §2.1 describes, and its error type churned across
seven major versions precisely because error design was retrofitted onto a
speed-first core. **attoparsec** is the honest counterweight: it documents
discarding error detail *in exchange for* speed. Together they say the
success-path-carries-only-an-integer design in §3.1 is the interesting needle
to thread, not a free lunch.

**Rust's `regex` crate validates §6.2 wholesale.** It is a linear-time engine
with a documented no-backtracking guarantee, using `memchr`-style SIMD literal
prefilters and an Aho-Corasick automaton for alternations. That is precisely
the three-case architecture proposed in §6.2, shipped and proven at scale.

### 5.3 Two findings that changed this document

**PEG's error problem is empirical, not theoretical** — see the CPython
`invalid_*` second-pass story in §3. It is the strongest available argument
for treating error design as load-bearing rather than downstream.

**Markdown is a weak forcing function, and the stdlib is a strong one.**
Draft 1 made the markdown parser step 2 of the sequencing. But essentially no
production markdown parser is combinator-based: cmark, Elixir's Earmark,
markdown-it, and comrak all use a line-oriented block scanner with a container
stack, followed by a separate inline pass whose emphasis resolution uses a
delimiter-run algorithm that is deliberately not context-free. CommonMark is
*specified* in those operational terms. Making markdown the proving ground
therefore risks one of two bad outcomes: contorting the library toward a shape
only markdown wants, or concluding the library failed when the correct answer
was "markdown wants a hand-written block scanner, with combinators only for
inline spans."

Meanwhile the repo already contains a far better corpus. `stdlib/toml.march`
(1045 lines), `stdlib/yaml.march` (958), `stdlib/xml.march` (894), and
`stdlib/json.march` (734) are roughly 3,600 lines of hand-written recursive
descent — and they already carry position-aware error types
(`TomlError(msg, line, col)`, `YamlError`, `XmlError`) and thread
`Err((message, failure_index))` through their character loops. That is the
state-plus-positioned-failure shape §3 proposes to formalize, independently
arrived at four times by hand. They come with existing tests, existing
performance characteristics, and existing messages to beat. See §10.

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

## 8. Editor integration: inline parser probes

Run a parser against sample input directly in the editor, inline, while you
write the grammar.

This belongs in *this* document rather than a separate LSP plan because it is
what makes §3 self-enforcing. Error quality is the stated product, but error
quality is also the thing that silently rots — nobody notices a message got
worse until a user complains. If a grammar author sees their parser's actual
rendered diagnostic, on their actual malformed sample, as they type, then §3
stops being an aspiration in a design doc and becomes the thing they are
looking at all day. That is a much stronger enforcement mechanism than the
golden corpus in §3.7, and it is cheap because §3.5 already requires a
`to_diagnostic` that produces the compiler's own diagnostic type.

### 8.1 The sample lives in the source, as a doctest

March already has doctests — the `march>` convention, extracted and run by
`lib/doctest/doctest.ml` and `forge test`. Parser probes should be a form of
doctest rather than a new mechanism, so that one annotation serves two
consumers: the inline editor preview *and* the test suite.

```march
doc """
    parse> json_value() @ "{\"a\": [1, true]}"
    Ok(JObject([("a", JArray([JNumber(1.0), JBool(true)]))]))

    parse> json_value() @ "{\"a\": }"
    error 1:8: I was expecting a value
"""
fn json_value() : Parser(Json) do ... end
```

Note the second probe pins **rendered error text**, not just failure. That
collapses two things the plan currently treats separately: the golden error
corpus of §3.7 and the doctest suite become the same artifact, living next to
the grammar rule they constrain instead of in a parallel fixture tree. A
message regression then fails `forge test` for the same reason a wrong AST
does.

### 8.2 What the editor shows

Three surfaces, all of which the LSP already has the capability registered
for:

- **CodeLens** above each parser declaration — `▶ 3 probes · 2 ok, 1 error`.
  `codeLensProvider` is already advertised (`lsp/lib/server.ml:654`, with the
  handler at `:1131`).
- **Inlay hints** showing each probe's result inline, behind a
  `march.inlayHints.parserProbes` client setting, following the existing
  `march.inlayHints.performanceAnnotations` / `.parameterNames` pattern
  (`lsp/lib/server.ml:15–51`).
- **Diagnostics positioned inside the sample string** — the important one.
  When a probe fails, take the `ParseErr.pos` byte offset from §3.1, map it
  into the sample literal's own extent, and publish the rendered diagnostic as
  a squiggle *on that character of the sample*. Your parser's errors become
  editor squiggles on your test input. This is the feature; the other two are
  convenience.

**Prerequisite — and it was a real blocker. FIXED 2026-08-11.** March
string-literal spans collapsed to a single column: for `"hello"` at column 0,
the recorded span was 6–7 — the **closing** quote. (An earlier note recorded
this as the *opening* quote; measurement says closing, which follows directly
from the mechanism below.) Integer and other literal spans were always
correct; this was specific to strings.

Mechanism: the main `token` rule in `lib/lexer/lexer.mll` matches only `'"'`
and hands off to a separate `read_string` sub-rule, which recurses once per
character or escape. Every re-entry makes ocamllex reset `lex_start_p` to the
current lexeme, so by the time the closing quote is matched and `STRING` is
returned, `lex_start_p` points at that closing quote — and menhir builds the
literal's span from it.

The fix records the opening quote's position on handoff and restores
`lex_start_p` in the actions that actually produce a token (`STRING` and
`INTERP_START`, in both the plain and triple-quoted sub-rules). `Token_filter`
reads `lex_start_p` immediately after each lexer call, so patching it in the
action is sufficient to reach the parser. Regression coverage lives in the
`ast` group of `test/test_compiler.ml`: base case, escapes (source extent ≠
value length), non-zero start column, and a multi-line triple-quoted literal.

Worth recording *why* this survived so long: consumers worked around it rather
than fixing it. `forge refactor bundle` hit exactly this — rewriting
`f("x", 1)` produced a corrupted `a = "` — and the fix there was a
string-aware comma splitter that avoids trusting spans at all. A workaround is
the right call for one consumer; it is the wrong call for the fourth.

### 8.3 Architecture: follow `refine_command.ml`

`lsp/lib/refine_command.ml` is a near-exact precedent and its design notes
apply almost verbatim:

- **The code action or lens carries a *command*, not a result.** Running a
  parser needs a fully loaded module — stdlib load, import resolution,
  typecheck, then evaluation — which is far too much to spend on cursor
  movement. `refine_command` makes exactly this argument for Z3 queries.
- **The work happens in the compiler behind a flag** (`march
  --parse-probe-json`, alongside the existing `--refine-suggest-json`),
  because the pipeline that turns a file into a checkable module lives in
  `bin/main.ml`, not in a library the LSP can link.
- **Shared implementation with the doctest runner**, so that a probe shown in
  the editor and the same probe run by `forge test` produce identical bytes.
  This is the stated design goal of `refine_command` and it is what stops the
  editor preview and CI from disagreeing.
- **Expose it in `lsp/lib/query_cli.ml`** next to `hover` / `type` /
  `definition` / `diagnostics`, so the feature is testable headlessly. Every
  other LSP feature here is tested that way; a feature that requires a live
  editor to test will not stay working.

Execution is interpreted (`lib/eval`), not compiled — no compile step, and the
interpreter already handles arbitrary modules.

### 8.4 This runs user code, which needs saying out loud

A parser probe evaluates arbitrary March from the open file. `forge test`
already does that, but with an important difference: the user asked. The LSP
would do it as a side effect of typing. Consequences:

- **Out-of-process with a hard timeout and cancellation on document change.**
  The shell-out in 8.3 gives the isolation for free; the timeout is
  non-negotiable. **A left-recursive PEG rule is an infinite loop** — and a
  grammar under active editing is unusually likely to pass through a
  left-recursive intermediate state on the way to a correct one. This is the
  normal case, not the adversarial one.
- **Detect left recursion and report it as a diagnostic**, rather than letting
  it surface as a mysterious timeout. The probe harness is the natural place
  for that check, and it is useful independent of the editor: PEG's inability
  to handle left recursion is the single most common way people new to PEG
  write a broken grammar.
- **Debounce, and run on save or explicit invocation by default**, not per
  keystroke.
- **Default the setting off.** Executing file contents without a per-run
  request is a meaningful trust escalation over the LSP's current behavior,
  which only ever *analyzes*. Turning it on should be a deliberate act, and it
  should respect whatever workspace-trust signal the client offers.

### 8.5 Do not generalize this yet

The underlying mechanism — "evaluate this expression against this literal and
render the result inline" — has nothing parser-specific about it, and the
temptation to ship a general expression-evaluator lens will be immediate.
Resist it until the parser case is proven. A general evaluator is a much
larger surface for both scope and the trust question in 8.4, and the parser
case is the one with a concrete forcing argument (§3) behind it.

---

## 9. Open decisions

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
5. ~~`let*` vs `let?`~~ **Closed 2026-08-12: they CAN be one mechanism, but
   ship them coexisting.** `let? x = e` is exactly `let* x = e` resolved at
   `Result`, since `Result.flat_map` gives precisely the Err-propagating
   semantics. But `let?` is shipped, conformance-tested, and carries three
   bespoke diagnostics; re-expressing it in terms of a new general mechanism
   would put those messages at risk for no user-visible gain. Build `let*`
   alongside, and only fold `let?` into it if the diagnostics survive.
6. ~~Sigil compile-time expansion~~ **Closed 2026-08-12: it is new machinery,
   and more than the plan assumed.** Sigils are NOT a general expansion
   mechanism. Every sigil except `~H` desugars to a runtime call —
   `~xml"..."` becomes `Sigil.xml(content)`, handed one already-concatenated
   string that the handler parses at runtime (and interpolation into those is
   refused outright, since a spliced value would change the parsed structure).
   `~H` alone does compile-time work, and it does so as a **hardcoded special
   case** in `desugar.ml`'s `ESigil` arm. A compile-time `~p` therefore means
   adding a PEG-grammar parser to the compiler's desugar pass and emitting
   well-typed combinator calls from it — not reusing anything.
7. ~~Commit model.~~ **Closed 2026-08-09: PEG + explicit cut**, with a
   `commit_on_consume` opt-in for shared-prefix grammars, since the reply
   type must track consumption anyway for §3.4's label rule. Rationale in
   §2.2.
8. **The acceptable speed factor versus hand-written recursive descent**
   (§10 step 2). Must be chosen before the JSON/TOML measurement, not after,
   or the number will be rationalized to whatever the result turns out to
   be. A plausible failure mode is a good one: combinators for config
   formats, hand-written for hot paths.
9. **Do parser probes default on or off?** (§8.4) They execute file contents
   without a per-run request, which is a trust escalation over an LSP that
   otherwise only analyzes. Recommendation is off-by-default plus
   workspace-trust awareness, but this is a product call, not a technical one.
10. **Does the probe annotation extend `march>` doctests or sit beside them?**
   (§8.1) Sharing the extractor in `lib/doctest/doctest.ml` is the point of
   the design; whether `parse>` is a new prefix in that grammar or a distinct
   block type affects how much of the runner is reusable.

---

## 10. Suggested sequencing

1. Combinator core, syntax option 4.1, **error contract included** (§3):
   reply type with soft/hard failure, furthest-failure merging, commit +
   context, labels, `to_diagnostic`. No syntax decisions required. The
   acceptance bar is the golden *error* corpus (§3.7) alongside the accept
   cases — PEG semantics proven AND messages pinned.
2. **Prove it against the stdlib parsers, not markdown** (revised — see
   §5.3). Reimplement `stdlib/json.march` first, then `stdlib/toml.march`,
   with the existing hand-written versions as the control. This is real
   ground truth: existing tests, existing performance, existing error
   messages. Three explicit acceptance gates, all measured against the
   hand-written original on the same box:
   - **Correctness:** passes the existing test suites unchanged.
   - **Speed:** within a stated factor of hand-written recursive descent.
     Decide the acceptable factor *before* measuring, and if it is missed,
     the honest outcome may be "combinators for config formats, hand-written
     for hot paths" rather than a rewrite.
   - **Errors:** strictly better messages than `TomlError(msg, line, col)`
     on a corpus of malformed inputs. If §3's machinery cannot beat four
     hand-rolled parsers that each independently reinvented
     position-carrying errors, it has not earned its complexity.
2b. **Then markdown, scoped to what it actually tests.** Markdown is still
   the genuine gap blocking Cadence, but treat it as the exercise for §3.6's
   recovery combinators and for inline-span parsing — not as proof that
   block structure should be combinator-shaped. Expect the block phase to be
   a hand-written line scanner with a container stack, as it is in every
   production implementation (§5.3); that is a finding about CommonMark, not
   a failure of the library.
3. Decide syntax sugar. §4.3 (`let*`) is the recommended target and §4.3 now
   argues it is what the type system forces, not merely what is convenient;
   evaluate it against the `~p` sigil with the combinator semantics already
   settled underneath. §4.2 only if user-defined operators land for
   independent reasons. Note that §4.1's pipe-as-sequence may cover enough
   of the common cases to make this less urgent than draft 1 assumed —
   measure how much of the JSON/TOML rewrite is genuinely context-sensitive
   before committing to new sugar.
3b. **Inline parser probes (§8), starting with the CLI half.** The doctest
   form (§8.1) and the `march --parse-probe-json` path (§8.3) are useful on
   their own — they give the JSON/TOML rewrite in step 2 its error-corpus
   mechanism, so build them *during* step 2 rather than after it. The editor
   surfaces follow once there is something to surface; the in-sample
   diagnostic squiggle additionally waits on the string-literal span fix
   (§8.2), which is worth scheduling early since it is small, independent,
   and already has three consumers working around it.
4. Search module separately. SIMD literal scan first (upgrading the existing
   `String.index_of` family), then Aho-Corasick (which March-written lexers
   want anyway), then the linear-worst-case engine — which is not optional
   "if untrusted patterns become a real requirement" but a scheduled fix for
   the shipped backtracking `Regex` (§6.0).
