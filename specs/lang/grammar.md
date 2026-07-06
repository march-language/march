# March — Resolved Surface Grammar

> Part of the March Language Reference — see [specs/lang/index.md](index.md).

**v1 (in progress) · 2026-07-06 · Task 1: preprocessing layers (lexer +
`token_filter`) formalized; expression/statement/pattern/type/declaration
grammar (§4–§9) not yet written.**

**Depends on:** `specs/plans/2026-07-06-resolved-grammar-plan.md` (the
implementation plan this chapter is built task-by-task from).
**Companions:** [`core-march.md`](core-march.md) (operational semantics),
[`core-march-types.md`](core-march-types.md) (static semantics),
[`surface-syntax.md`](surface-syntax.md) (the friendly grammar
cheatsheet — this chapter is its normative, resolved counterpart; see the
note at the end of §1).

---

## How to read this grammar

- **EBNF conventions.** Productions use `::=`; `|` separates alternatives;
  `( … )` groups; `?` = optional; `*` = zero-or-more; `+` = one-or-more;
  `SHOUTING_NAME` denotes a lexer/token-filter **token** (a terminal);
  `lower_case` denotes a grammar **nonterminal**. Where useful, a production
  is annotated with the exact `parser.mly` rule name it corresponds to (e.g.
  `expr_add`) so the EBNF can be cross-checked against the source
  mechanically.
- **The EBNF in §4 onward takes a TOKEN-FILTERED stream as input** — not the
  raw lexer output. Two preprocessing layers sit between source text and the
  context-free grammar: the lexer (§2) and `token_filter` (§3). Both are
  documented here as **normative rules**, because the productions in later
  sections are only correct once those transformations have already
  happened (most importantly: most `NL` tokens have already been deleted by
  the time menhir sees the stream). Read §2–§3 before treating any later
  EBNF as literal truth about what raw source text is accepted.
- **`parser.mly` is the ultimate authority.** This chapter states its
  *resolved* behavior — precedence/associativity made explicit, ambiguities
  named and explained, unreachable productions flagged — but the grammar the
  compiler actually implements is whatever `lib/parser/parser.mly` (plus
  `lib/lexer/lexer.mll` and `lib/parser/token_filter.ml`) says. Every claim
  in this chapter is cited to a specific, re-grepped line in one of those
  three files; if a citation and the live source ever disagree, the source
  wins and this chapter has rotted.
- **"Resolved, not transcribed."** The value added here is stating what the
  three source files leave implicit: which of menhir's shift/reduce
  resolutions is actually taken, why a token exists but can never appear in
  a valid program (`THEN`, §4), which AST constructors have no surface
  syntax that reaches them (`PatRecord`/`PatAs`, deferred to Task 4), and —
  the hardest part — the exact algorithm `token_filter.ml` uses to decide
  where a block expression ends. A line-by-line copy of `parser.mly`'s
  productions would not be worth a separate chapter; this is not that.

## 1. The three-layer pipeline

March source text passes through three distinct stages before it becomes an
AST, and all three are normative parts of "the grammar" even though only the
last one is commonly called that:

1. **Lexer** (`lib/lexer/lexer.mll`) — turns raw characters into a token
   stream. Almost entirely context-free/regular, with exactly one
   non-regular wrinkle: string-interpolation brace-depth tracking (§2.3).
2. **`token_filter`** (`lib/parser/token_filter.ml`) — a stateful,
   stack-based automaton that consumes the lexer's token stream and produces
   a *filtered* token stream for the parser. It performs soft-keyword
   demotion, `choose…by` disambiguation, and — the hard part — decides,
   using unbounded lookahead, which `NL` tokens are significant block/arm
   separators and which are insignificant layout to be deleted (§3). This
   layer is genuinely **not context-free**: it is why a single resolved EBNF
   over raw tokens cannot describe March's surface syntax, and why every
   later section in this chapter (§4 onward) states its grammar *in terms
   of the filtered stream* `token_filter` produces, not the lexer's raw
   output.
3. **menhir** (`lib/parser/parser.mly`) — the context-free grammar proper.
   Every parse entry point wires the same three-stage composition —
   `March_parser.Parser.module_ (March_parser.Token_filter.make
   March_lexer.Lexer.token) lexbuf` — visible verbatim at, e.g.,
   `bin/main.ml:123` (and repeated at each of the compiler's other parse
   call sites: `lib/repl/repl.ml`, `lib/format/format.ml`,
   `lib/resolver/resolver.ml`, `lib/modules/module_registry.ml`,
   `lib/tir/lower_decls.ml`, `lib/lint/lint.ml`, `lib/search/search.ml`,
   `lib/refactor/refactor.ml`). `parser.mly` is the **ultimate authority**
   for what parses; this chapter states menhir's *resolved* behavior —
   which of its shift/reduce conflicts resolve which way, given the
   `%left`/`%right`/`%nonassoc` declarations and `%prec` annotations —
   rather than leaving readers to infer it from the raw `.mly` file.

**On the "~59 conflicts" figure.** The project's 2026-07-05 grammar-consolidation
survey reported that menhir resolves approximately 59 shift/reduce conflicts
in `parser.mly` via its declared precedence/associativity table. This chapter
**inherits that figure rather than re-deriving it**: regenerating menhir's
`.conflicts` report requires `dune build --root . <target> 2>&1` (menhir's
`--dump`/conflict-report flags run as part of the dune build rule), and this
task is expressly forbidden from running `dune` (see the plan's Global
Constraints — concurrent compiler sessions saturate the shared dune daemon).
No rule or claim in this chapter *depends* on the exact count; instead, the
chapter validates the parser's resolved behavior **empirically** — precedence
and associativity claims (Task 2) are witnessed by value-producing corpus
programs that only have one possible correct parse under the claimed rule,
run against the real pre-built compiler — rather than by auditing menhir's
conflict list conflict-by-conflict. Treat "~59" as provenance, not a number
this document re-verified.

**Relationship to `surface-syntax.md`.** [`surface-syntax.md`](surface-syntax.md)
is the terse, friendly cheatsheet over nearly the whole surface grammar; it
explicitly defers to `parser.mly` as authoritative and does not attempt to
resolve ambiguities or formalize the preprocessing layers. This chapter is
that resolution: normative, cited by line, and backed by a parse/reject
conformance corpus (`specs/lang/grammar/`, see §"Conformance corpus" below).
The two are complementary, not duplicates — read `surface-syntax.md` first
for orientation, then this chapter for the precise, checkable rules.

## 2. The lexical layer

Source: `lib/lexer/lexer.mll` (279 lines, one `ocamllex` rule set: `token`
plus five auxiliary string/comment sub-lexers).

### 2.1 Token classes

- **Identifiers.** `ident = alpha (alpha | digit | ')*` where
  `alpha = ['a'-'z' 'A'-'Z' '_']` (`lexer.mll:95–96`). After matching, the
  lexer looks the identifier up in a keyword table (`lexer.mll:181–188`); if
  it's not a keyword, it is classified purely by the **first character's
  case**: `id.[0] >= 'A' && id.[0] <= 'Z'` yields `UPPER_IDENT id`
  (`lexer.mll:185–186`), otherwise `LOWER_IDENT id` (`lexer.mll:187`).
  Upper-initial identifiers name types/constructors/modules; lower-initial
  identifiers name variables/functions. There is no separate "operator
  identifier" class.
- **Keywords.** A fixed table of ~70 reserved words (`lexer.mll:16–89`,
  e.g. `fn`, `let`, `do`, `end`, `if`, `then`, `else`, `match`, `type`,
  `mod`, `actor`, `protocol`, `interface`, `impl`, `derive`, `for`, `in`,
  `test`, `describe`, …). Being in this table removes the identifier from
  ordinary `LOWER_IDENT`/`UPPER_IDENT` space entirely at the lexer level —
  some of these keywords are later **demoted back to ordinary identifiers**
  in specific contexts by `token_filter` (§3.1); the lexer itself does no
  such demotion.
- **Literals.**
  - `INT` — `digit+` (`lexer.mll:106–119`); parsed with `int_of_string_opt`
    and raises a positioned `ParseError` (not an uncaught exception) if the
    literal exceeds a 63-bit OCaml `int` (`lexer.mll:110–119`).
  - `FLOAT` — `digit+ '.' digit+` (`lexer.mll:105`); note this requires at
    least one digit on both sides of `.`, matched *before* the bare `INT`
    rule so `1.5` lexes as one `FLOAT` token, not `INT DOT INT`.
  - `STRING` — `'"' … '"'` (`lexer.mll:121`, sub-lexer `read_string` at
    `lexer.mll:204–227`) and triple-quoted `"""…"""` (`lexer.mll:120`,
    sub-lexer `read_triple_string` at `lexer.mll:231–241`), both supporting
    the escapes `\n \t \r \b \f \0 \\ \" \$` and `\xHH` (`lexer.mll:212–224`).
    Triple-quoted strings additionally preserve raw newlines
    (`lexer.mll:239`) rather than requiring `\n`.
  - `BOOL` — the keywords `true`/`false` map directly to `BOOL true`/`BOOL
    false` (`lexer.mll:40–41`), not a separate literal rule.
  - `ATOM` — `':' atom_name` where `atom_name = ['a'-'z'] (alpha | digit)*`
    (`lexer.mll:97, 122`) — a colon immediately followed by a
    lowercase-initial identifier-shaped word, e.g. `:ok`, `:error1`. Note
    `atom_name` disallows `'`, unlike `ident`.
- **Operators.** Each is its own fixed-string token: arithmetic `+ - * /
  %` and their float-suffixed forms `+. -. *. /.` (`lexer.mll:152–161`),
  comparison `< > == != <= >=` (`lexer.mll:162–167`), boolean `&& ||`
  (`lexer.mll:168–169`), `++` (list/string append, `lexer.mll:152`), `->`
  (`ARROW`, `lexer.mll:143`), `<-` (`GETS`, `lexer.mll:144`), `|>`
  (`PIPE_ARROW`, `lexer.mll:145`), `\\` (`DSLASH`, default-arg separator,
  `lexer.mll:146`), and the punctuation `( ) { } [ ] @ = : , | . ! _ ?`
  (`lexer.mll:123–172`). Longest-match-first ordering in the `.mll` source
  ensures e.g. `==` lexes as one `EQEQ` token rather than two `EQUALS`
  tokens — ocamllex's rule-order/longest-match semantics, not a special
  lookahead the grammar needs to reason about separately.
- **Sigils and capability annotations.** `~Upper`/`~lower_ident` lex as a
  single `SIGIL_PREFIX` token carrying the name (`lexer.mll:173–174`); the
  five `cap ...`/`proof cap` two-word forms (`cap no_panic`, `cap pure`,
  `cap no_extern`, `cap deterministic`, `cap no_alloc`, `proof cap`) are
  matched as fixed multi-word lexer patterns with the whitespace between
  the words baked into the rule (`lexer.mll:175–180`), so e.g. `cap  pure`
  (two spaces) still lexes as one `CAP_PURE` token but `cappure` (no space)
  would not match at all and instead lexes as the ordinary identifier
  `cappure`.

### 2.2 Significant vs. insignificant whitespace

- **Insignificant:** runs of plain spaces/tabs (`whitespace = [' ' '\t']+`,
  `lexer.mll:92, 101`) are consumed with no token emitted at all — they
  never reach the parser in any form.
- **Significant (at the lexer level):** newlines (`newline = '\r' | '\n' |
  "\r\n"`, `lexer.mll:93`) DO produce a token — `NL` — via
  `Lexing.new_line lexbuf; NL` (`lexer.mll:102`). The lexer itself does not
  decide whether a given newline matters to the grammar; it always emits
  `NL` and defers that decision entirely to `token_filter` (§3), which
  deletes most of them. This split is why "significant newlines" is a
  property of the *filtered* stream, not the raw lexer output — the lexer's
  contribution is only that newline position information survives at all
  for `token_filter` to act on.
- **Comments** are whitespace-equivalent and never produce a token:
  line comments `-- ...` run to end-of-line (sub-lexer `line_comment`,
  `lexer.mll:103, 192–195` — note the line-comment sub-lexer still emits
  `NL` for the newline that ends it, so a comment does not swallow the
  newline that follows it) and block comments `{- ... -}` nest via a depth
  counter (sub-lexer `block_comment`, `lexer.mll:104, 197–202`) and may
  span multiple lines (each internal newline calls `Lexing.new_line` for
  position tracking but emits no token, `lexer.mll:200`).

### 2.3 The one non-context-free lexer behavior: string-interpolation brace depth

String interpolation (`"...${expr}..."` / `"""...${expr}..."""`) is the
**one place the lexer itself is not a simple regular scanner**: it needs a
counter, not just regexes, because the interpolated `expr` can itself
contain `{` `}` (e.g. a record literal or a nested block) that must not be
confused with the `}` that closes the interpolation.

**Normative rule** (`lexer.mll:7–14` doc comment, mechanism at
`lexer.mll:11, 125–139, 206–211, 233–237, 246–250, 258–263`):

- A mutable ref `interp_depth` (`lexer.mll:11`, module-level, reset
  implicitly to `0` at start) tracks nesting; `interp_triple`
  (`lexer.mll:13`) remembers whether the enclosing string is triple-quoted
  so the lexer knows which sub-lexer to resume into.
- On seeing `"${"` inside a string body, the lexer sets `interp_depth := 1`
  and emits `INTERP_START <prefix>` (the string text seen so far,
  `lexer.mll:206–211` non-triple, `lexer.mll:233–237` triple), then falls
  through to the **ordinary `token` lexer** — i.e. the interpolated
  expression is lexed with the FULL token grammar (identifiers, operators,
  nested strings, everything), not a restricted sub-grammar.
- While `interp_depth > 0`, every `{` increments the counter and every `}`
  decrements it (`lexer.mll:125, 127–128`) — both still emit ordinary
  `LBRACE`/`RBRACE` tokens to the parser (`lexer.mll:125, 136, 138`), so a
  nested record literal or block inside an interpolation parses completely
  normally.
- The interpolation actually **closes** only on the `}` that would bring
  `interp_depth` to `0` (`lexer.mll:129`): at that point the lexer does NOT
  emit `RBRACE` for that closing brace; instead it resumes the appropriate
  string sub-lexer (`read_triple_string_interp` or `read_string_interp`,
  chosen by `interp_triple`, `lexer.mll:130–134`), which reads the next
  span of literal string text and emits `INTERP_MID <text>` (another `${`
  follows — more interpolation segments) or `INTERP_END <text>` (the
  closing `"`/`"""` follows — no more segments, `lexer.mll:245, 249,
  257, 262`).
- Consequently a string with `N` interpolation segments lexes to
  `INTERP_START, expr-tokens…, INTERP_MID, expr-tokens…, …, INTERP_END`
  (parsed by `parser.mly`'s `interp_parts`, cited in §4's string-literal
  entry), and brace balance inside each interpolated expression is
  necessarily well-formed by construction — the parser never has to
  disambiguate an interpolation-closing `}` from a nested one; the lexer's
  counter has already resolved that before menhir ever sees a token.

## 3. The `token_filter` pre-pass

Source: `lib/parser/token_filter.ml` (398 lines, one entry point `make`,
`token_filter.ml:38`). This is the layer that makes March's grammar
genuinely **not context-free**: it is a stateful automaton with unbounded
lookahead sitting between the lexer and menhir, and every later section's
EBNF (§4 onward) describes the grammar **as this layer's output**, not as
the lexer's raw token stream. Concretely: `token_filter.make base_lexer`
returns a replacement lexing function with the same type
(`Lexing.lexbuf -> Parser.token`) that menhir is fed instead of the raw
lexer (`token_filter.ml:38`) — from menhir's point of view there is only one
lexer, and this section documents what that lexer (lexer + filter combined)
actually emits.

The filter maintains: a context stack (`Match | Block | Paren`,
`token_filter.ml:16, 78`) tracking what kind of bracketed region each nested
`do…end`/`(...)`/`[...]`/`{...}` is; a parallel stack of per-match mutable
state (`ms_suppress_nl`, `ms_in_arm_body`, `ms_is_cond`,
`token_filter.ml:19–26, 89`); a paren-depth counter
(`token_filter.ml:84`) used to correlate a `MATCH` keyword with its `DO`
even across intervening parens; and a lookahead re-queue buffer
(`token_filter.ml:87, 102–120`) so that tokens consumed during lookahead can
be replayed to menhir with their original source positions preserved
(critical for correct error spans).

### 3.1 Soft-keyword demotion (one-token lookahead)

**Rule.** Four lexer keywords — `TEST`, `DESCRIBE`, `SETUP`, `SETUP_ALL` —
are only real keywords when immediately followed by a specific next token;
everywhere else they demote back to `LOWER_IDENT` so they remain usable as
ordinary identifiers (function/parameter/variable names). This runs as a
wrapper around the base lexer, *before* the rest of the filter's stack
machinery sees any token (`token_filter.ml:47–77`):

- `TEST` / `DESCRIBE` stay keywords only when the **next** token is
  `STRING` (i.e. `test "name" do` / `describe "name" do`,
  `token_filter.ml:69, 72–73`); otherwise each demotes to `LOWER_IDENT
  "test"` / `LOWER_IDENT "describe"` (`token_filter.ml:67`).
- `SETUP` / `SETUP_ALL` stay keywords only when the next token is `DO`
  (`token_filter.ml:70, 74–75`); otherwise each demotes to `LOWER_IDENT
  "setup"` / `LOWER_IDENT "setup_all"`.
- The lookahead token itself is buffered (`pending`,
  `token_filter.ml:49–50, 65`) and replayed with its own original lexbuf
  positions (`token_filter.ml:53–57`) on the following call, so demotion
  costs one token of buffering but never corrupts span info for either
  token.

Before/after example — `test` used as a plain function name (no following
`STRING`):

```
source:            test(x, y)
raw lexer tokens:   TEST  LPAREN  LOWER_IDENT("x")  COMMA  LOWER_IDENT("y")  RPAREN
after §3.1 demotion: LOWER_IDENT("test")  LPAREN  LOWER_IDENT("x")  COMMA  LOWER_IDENT("y")  RPAREN
```

versus the DSL form (`STRING` follows, stays `TEST`):

```
source:             test "adds" do ... end
raw lexer tokens:   TEST  STRING("adds")  DO  ...  END
after §3.1:         TEST  STRING("adds")  DO  ...  END   -- unchanged, keep_when matched
```

### 3.2 `choose…by` disambiguation

**Rule.** `CHOOSE` is ambiguous at the lexer level between two unrelated
surface forms: the protocol-DSL `choose by chooser: … end` block (no `DO`
keyword — it opens directly on `BY`) and an ordinary expression like
`Chan.choose(ch1, ch2)` (an application, reached via `expr_field; DOT;
CHOOSE` in `parser.mly:1188`). The filter peeks exactly one token past
`CHOOSE` (`token_filter.ml:277–288`):

- If the next token is `BY`, this is the protocol-DSL form: the filter
  pushes a `Match` context and a fresh match-state (`ms_is_cond = false`)
  right here at `CHOOSE` (`token_filter.ml:282–283`) — *not* at a `DO`,
  because this form has no `DO` — so that `NL` inside the `choose…by…end`
  body is governed by the same arm-boundary machinery as a real `match`
  (§3.3), letting each `choose` branch use `NL`/`PIPE` as its separator
  exactly like a match arm. The peeked `BY` token is re-queued
  (`token_filter.ml:284`) so downstream dispatch sees it normally.
  Grammar-side, `parser.mly:624` (`CHOOSE; BY; chooser = upper_name; COLON;
  …; branches = separated_nonempty_list(arm_sep, choose_branch); END`)
  confirms `arm_sep` (`NL | PIPE`, `parser.mly:1275–1277`) is exactly what
  this Match-context push is needed to supply.
- Otherwise (any other next token, e.g. `LPAREN` for `Chan.choose(...)`),
  no context is pushed; `CHOOSE` is re-emitted as an ordinary token feeding
  into `expr_field DOT CHOOSE`-shaped application syntax
  (`token_filter.ml:286–288`).

Before/after:

```
source:  choose by Chooser: BranchA -> a() | BranchB -> b() end
tokens:  CHOOSE BY UPPER_IDENT("Chooser") COLON UPPER_IDENT("BranchA") ARROW ... PIPE UPPER_IDENT("BranchB") ARROW ... END
effect:  Match context pushed at CHOOSE (not at a DO — there is none);
         the PIPE between branches works as arm_sep exactly as inside `match do ... end`.
```

```
source:  Chan.choose(ch1, ch2)
tokens:  UPPER_IDENT("Chan") DOT CHOOSE LPAREN ... RPAREN
effect:  no context pushed; CHOOSE flows straight through to expr_field/expr_app.
```

### 3.3 The newline-glom / match-arm-boundary lookahead — the core mechanism

This is the central non-context-free behavior. **Baseline rule
(`token_filter.ml:334, 392–393`): `NL` is significant (kept) only while the
top of the context stack is `Match`; everywhere else (top-level module
body, inside a `Block` i.e. a `do…end` that is not a match, inside any
`Paren` — parens/brackets/braces) every `NL` the lexer emits is silently
swallowed** (recursing straight to the next token, `token_filter.ml:393`).
This is why `block_body` in `parser.mly` (`nonempty_list(block_expr)`,
`parser.mly:992–994`) has **no explicit separator token between successive
block expressions at all** — the grammar doesn't need one, because by the
time menhir sees the stream, the newlines that separated them have already
been deleted; block-expression sequencing is purely "keep reading
`block_expr`s until something that isn't one," not "expressions separated
by `NL`."

Example — a plain function body (`Block` context, no `Match` on the stack):

```
source:
  fn main() do
    let a = 1
    let b = 2
    a + b
  end

raw lexer:      FN LOWER_IDENT("main") LPAREN RPAREN DO NL
                LET LOWER_IDENT("a") EQUALS INT(1) NL
                LET LOWER_IDENT("b") EQUALS INT(2) NL
                LOWER_IDENT("a") PLUS LOWER_IDENT("b") NL
                END
after filter:   FN LOWER_IDENT("main") LPAREN RPAREN DO
                LET LOWER_IDENT("a") EQUALS INT(1)
                LET LOWER_IDENT("b") EQUALS INT(2)
                LOWER_IDENT("a") PLUS LOWER_IDENT("b")
                END
```

All four `NL`s vanish — `DO` pushes a plain `Block` context
(`token_filter.ml:290, 303–304`, since no `MATCH…DO` pairing was pending at
this paren depth), and every `NL` while `Block` is on top is swallowed by
the `else next lexbuf` branch (`token_filter.ml:392–393`).

**Inside a `Match` context, it's the opposite default (`NL` is kept by
default) but with three suppression rules layered on top**, because a
`match` body's arms can themselves contain multi-expression bodies that
need their *internal* newlines deleted while still preserving the newlines
that separate one arm from the next:

1. **`NL` right after `ARROW` is suppressed** (`token_filter.ml:325–332`):
   crossing an arm's `->` sets `ms_suppress_nl := true`, and every
   subsequon `NL` seen while that flag holds recurses past it
   (`token_filter.ml:337–339`) until a non-`NL` token arrives — this
   absorbs blank/comment-only lines between `->` and the arm body's first
   real token, then `check_arm_body_transition` (`token_filter.ml:244–253`)
   flips the state to `ms_in_arm_body := true` right before that first
   token is dispatched.
2. **`NL` immediately before `END`, at any point, is suppressed**
   (`token_filter.ml:350–354` from inside an arm body; `token_filter.ml:379,
   386–388` before the first arm) — the filter peeks past a run of `NL`s
   (`skip_nls`, `token_filter.ml:343–348, 379–384`) and if the next
   non-`NL` token is `END`, it recurses to dispatch `END` directly, so the
   parser never has to special-case a trailing `NL` before the closing
   keyword.
3. **`NL` while inside an arm body (`ms_in_arm_body = true`) triggers the
   arm-boundary lookahead** (`token_filter.ml:340–375`, the
   `lookahead_is_new_arm` function at `token_filter.ml:165–239`): the
   filter peeks past the run of `NL`s to the next real token
   (`skip_nls`). If that token is `END`, rule 2 applies. If it is `PIPE`
   (explicit arm separator), the `NL` is emitted as the arm boundary
   immediately, no further lookahead needed (`token_filter.ml:355–359`).
   Otherwise, IF that token could start a pattern
   (`is_pattern_start`, §3.4) the filter performs **unbounded lookahead**:
   it feeds tokens one at a time into `lookahead_is_new_arm`
   (`token_filter.ml:165–239`), tracking a bracket-nesting `depth` (opened
   by `LPAREN`/`LBRACKET`/`LBRACE`, closed by the matching
   `RPAREN`/`RBRACKET`/`RBRACE`, `token_filter.ml:198–205`) and scanning
   until, **at depth 0**, it sees:
   - `ARROW` → **this is a new arm**: result `true`
     (`token_filter.ml:186–188`);
   - `NL` → **not** a new arm (a plain blank line mid-continuation):
     result `false` (`token_filter.ml:189–191`);
   - `END` → not a new arm: `false` (`token_filter.ml:195–197`);
   - an unmatched closing bracket (depth would go negative) → not a new
     arm: `false` (`token_filter.ml:200, 203–205`);
   - `EQUALS`, `DO`, `LET`, `IF`, `MATCH`, `FN`, `PFN`, or `ASSERT` at depth
     0 → not a new arm: `false` (`token_filter.ml:209–213`) — these tokens
     can only ever appear inside a body continuation (e.g. the body itself
     starts a nested `let`/`if`/`match`/lambda), so seeing one before any
     `ARROW` proves the `NL` did not start a new pattern;
   - one of the binary-operator tokens `PLUS STAR SLASH PERCENT PIPE_ARROW
     LEQ GEQ EQEQ NEQ AND OR PLUSPLUS` at depth 0 → not a new arm: `false`
     (`token_filter.ml:214–219`) — UNLESS `suppress_operators` is true
     (`is_cond` for a scrutinee-less `match do` where "patterns" are full
     boolean expressions, or a `WHEN` guard has already been seen at depth
     0 during this same scan, `token_filter.ml:176–184, 206–208, 217`), in
     which case these operators are legitimate parts of the boolean
     expression/guard being scanned and scanning continues instead of
     bailing;
   - `WHEN` at depth 0 → not itself a decision, but sets `seen_when := true`
     so subsequent binary operators (the guard expression) don't
     falsely trigger the bail-out above (`token_filter.ml:206–208`).

   If the lookahead concludes `true`, the pending `NL` is emitted as the
   arm separator (and `ms_in_arm_body` resets to `false` since the "body"
   has ended); if `false`, the `NL` is swallowed and scanning continues as
   a body continuation (`token_filter.ml:364–371`). Either way, every token
   consumed during the lookahead scan is pushed into the re-queue buffer
   (`Queue.transfer`, `token_filter.ml:237`) so it is replayed to menhir
   exactly once, with original positions, regardless of which branch fired.

Before/after — a multi-expression arm body followed by a genuine next arm
(the load-bearing case; corpus witness:
[`grammar/parse/p02_match_multi_expr_arms.march`](grammar/parse/p02_match_multi_expr_arms.march)):

```
source:
  match s do
    Circle(r) ->
      let doubled = r * 2
      let squared = doubled * doubled
      squared
    Square(side) ->
      side * side
  end

raw lexer (elided): ... ARROW NL LET ... NL LET ... NL LOWER_IDENT("squared") NL
                     UPPER_IDENT("Square") LPAREN ... RPAREN ARROW ...

after filter:
  - NL right after the first ARROW: suppressed (rule 1).
  - NL after "let doubled = r * 2": ms_in_arm_body=true, next real token
    is LET -> lookahead_is_new_arm sees LET at depth 0 -> bails false
    immediately (LET is a structural bail-out token) -> NOT a new arm ->
    NL suppressed, "let squared = ..." is a body continuation.
  - NL after "let squared = ...": same reasoning, LET bails -> suppressed.
  - NL after "squared": next real token is UPPER_IDENT("Square"), which
    IS is_pattern_start -> full lookahead scan: Square, LPAREN (depth->1),
    side, RPAREN (depth->0), ARROW (depth 0) -> lookahead_is_new_arm =
    true -> THIS NL is emitted as the arm boundary.
  parser sees:     ... ARROW LET ... LET ... squared NL Square LPAREN side RPAREN ARROW ...
                                                        ^^ the one NL that survives
```

The `p02` corpus program is well-typed and its `main` prints `36` then `16`
when run (`_build/default/bin/main.exe`, non-`--check` mode) — the specific
values (`(3*2)^2 = 36`, `4*4 = 16`) only come out right if the arm boundary
resolved exactly where this section says it does, so the program is a
value-witness of the rule, not just a parse-witness.

### 3.4 `⚠️ is_pattern_start` — a hand-maintained shadow of the pattern grammar

`is_pattern_start` (`token_filter.ml:130–143`) decides, during the
arm-boundary lookahead (§3.3), whether the token *after* a candidate `NL`
could possibly begin a new arm's pattern — a fast pre-filter before paying
for the full unbounded lookahead scan. Its own doc comment
(`token_filter.ml:122–129`) is explicit that this is meant to track
`parser.mly`'s `pattern`/`simple_pattern` productions:

> "Kept in sync with the grammar's `pattern` / `simple_pattern` rules
> (parser.mly): `pattern` accepts qualified_upper (UPPER_IDENT), ATOM, and
> simple_pattern; `simple_pattern` accepts UNDERSCORE, soft_lower_name
> (LOWER_IDENT plus the soft keywords below), INT, MINUS INT, FLOAT, MINUS
> FLOAT, STRING, BOOL, LPAREN, and LBRACKET."

This is a **hand-maintained duplicate**, not a derived table: nothing
generates `is_pattern_start` from `parser.mly`'s grammar automatically, so
every time a production is added to `pattern`/`simple_pattern`/
`soft_lower_name`, a human has to remember to update this predicate too —
and a prior review of this exact predicate on an earlier checkout found it
**already drifted out of sync** (missing the `FLOAT` case and some
soft-keyword cases at that point in time). That is exactly the "resolved,
not transcribed" hazard this whole chapter exists to name: a second,
informal copy of part of the grammar living outside `parser.mly`, kept
correct only by discipline.

**Live cross-check performed for this chapter (re-grepped, not assumed):**

- `soft_lower_name` in the current `parser.mly` (`parser.mly:1353–1367`)
  accepts exactly: `LOWER_IDENT`, `STATE`, `INIT`, `LOOP`, `ON`,
  `PROTOCOL`, `APP`, `AS`, `WITH`, `WHEN`, `USE`, `IN`, `FOR`, `TAG` — 13
  keyword alternatives plus `LOWER_IDENT`.
- `simple_pattern` (`parser.mly:1322–1341`) accepts: `UNDERSCORE`,
  `soft_lower_name`, `INT`, `MINUS INT`, `FLOAT`, `MINUS FLOAT`, `STRING`,
  `BOOL`, `LPAREN … RPAREN` (parenthesized/tuple), `LBRACKET … RBRACKET`
  (list-literal pattern) — so the tokens that can START a `simple_pattern`
  are `UNDERSCORE`, `LOWER_IDENT`+the 13 soft keywords above, `INT`,
  `MINUS`, `FLOAT`, `STRING`, `BOOL`, `LPAREN`, `LBRACKET`.
- `pattern` (`parser.mly:1311–1320`) adds on top of `simple_pattern`:
  `qualified_upper` (i.e. `UPPER_IDENT`, possibly `UPPER_IDENT DOT
  UPPER_IDENT`, `parser.mly:1305–1309`) and `ATOM` (with or without a
  parenthesized argument list).
- `is_pattern_start` itself (`token_filter.ml:130–143`) currently lists:
  `UPPER_IDENT`, `LOWER_IDENT`, `UNDERSCORE`, `INT`, `FLOAT`, `STRING`,
  `BOOL`, `LPAREN`, `LBRACKET`, `MINUS`, `ATOM`, and the 13 soft keywords
  `STATE INIT LOOP ON PROTOCOL APP AS WITH WHEN USE IN FOR TAG`.

**Result of this cross-check: `is_pattern_start` is currently IN SYNC with
`parser.mly`'s `pattern`/`simple_pattern`/`soft_lower_name` first-token set.**
Every token class the grammar's pattern productions can start with is
present in the predicate, with the same 13-keyword soft set, and nothing
extra is listed (`LBRACE` is correctly absent — there is no record-pattern
production for it to start, see the reachability note in §6, to be written
in Task 4). This chapter documents that finding as of this pass rather than
asserting it as a timeless property: **the predicate is maintained by hand
and can drift again the next time `pattern`/`simple_pattern`/
`soft_lower_name` changes without a matching edit here.** Anyone changing
those `parser.mly` productions should grep `is_pattern_start` in the same
change; anyone reviewing a `token_filter.ml` change that touches this
predicate should re-run this same three-way cross-check rather than trust
this paragraph, which will itself go stale.

### 3.5 Why this layer is not context-free

`lookahead_is_new_arm` (§3.3) performs **unbounded lookahead with its own
bracket-depth accounting and its own notion of "structural" tokens** to
decide where one arm ends and the next begins — this cannot be expressed as
a context-free production over the raw token stream, because the decision
depends on scanning forward past an arbitrary number of tokens (including,
in the cond/guard case, past an arbitrary boolean expression) to find the
first depth-0 `ARROW`/`NL`/`END`/bail-out token. A context-free grammar's
production for "what follows an arm body" cannot be conditioned on "scan
forward until you find one of these tokens at bracket-depth 0." This is why
`parser.mly` alone cannot be handed directly to a reader as "the grammar" —
it assumes its input has already had this resolution performed on it by
`token_filter`, and §4 onward states its EBNF on that basis (filtered-stream
input), never on raw lexer output.

## Conformance corpus

This chapter is backed by a runnable parse/reject corpus at
`specs/lang/grammar/`, mirroring the shape of `specs/lang/types/` (the
`core-march-types.md` corpus) with intentionally different directory names:

- **`parse/*.march`** — must parse (`march --check` exit **0**; kept
  well-typed so exit 0 isolates "this parsed", the same discipline
  `types/accept/` uses for "this typechecked").
- **`reject/*.march`** — must fail to **parse** (`march --check` exit **1**),
  with the compiler's actual output containing the exact substring named in
  the program's own first-line `-- EXPECT-ERROR: <substring>` annotation.
  Some of these substrings are menhir's generic fallback diagnostics (e.g.
  `I got stuck here`) rather than a bespoke message — that is expected and
  fine; the corpus pins whatever the live compiler actually prints, never a
  wished-for message.

Run it:

```
MARCH_BIN=$PWD/_build/default/bin/main.exe bash specs/lang/grammar/check_grammar.sh
```

See [`grammar/INDEX.md`](grammar/INDEX.md) for the full program-to-rule map.
This Task-1 pass seeds the corpus with four programs anchoring §2–§3 (the
preprocessing layers); Tasks 2–5 grow it alongside §4–§9.

---

## Coming in later tasks (not yet written)

- **§4 Expressions** — the stratified precedence ladder (Task 2).
- **§5 Blocks & statements** — `block_body`, `if`/`match`/`cond`, `let?`
  placement (Task 3).
- **§6 Patterns** — `simple_pattern`/`pattern`, reachability
  (`PatRecord`/`PatAs`) (Task 4).
- **§7 Types** — the type-expression grammar (Task 4).
- **§8 Declarations** — `mod`, `fn`/`pfn`, `type`/`ptype`, `use`/`import`,
  `interface`/`impl` (Task 5).
- **§9 DSL appendix** — actors, capabilities, protocols, transitions,
  supervision (lighter treatment) (Task 5).
