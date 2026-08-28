# March: Resolved Surface Grammar

> Part of the March Language Reference; see [specs/lang/index.md](index.md).

**v2 · 2026-07-06 · core grammar AND DSL declaration forms resolved.** The
three-layer parse pipeline (lexer → `token_filter` → menhir, §1–§3), the
expression precedence ladder (§4), blocks/statements/significant-newline
semantics (§5), patterns/types, including record patterns and as-patterns,
both reachable as of 2026-07-24; see §6.3 for the history (§6–§7), the core declaration forms, including
the multi-head-`fn`-merge mechanism and the one-`mod`-per-file rule (§8),
and the DSL-heavy declaration forms (actors and their message handlers,
`app`/`on_start`/`on_stop`, `supervise` trees, `protocol`/`choose` binary
session types, `transitions`, and the capability directives `needs`/
`proof cap`/the five `cap …` forms) in §9 are all fully resolved and backed
by a 35-program parse/reject conformance corpus wired into CI
(`grammar-check`, see "Conformance corpus" below). See "Known parser
findings" below for the issues this chapter's corpus work surfaced along
the way.

**Depends on:** `specs/plans/archive/2026-07-06-resolved-grammar-plan.md` (the
implementation plan this chapter was built task-by-task from).
**Companions:** [`core-march.md`](core-march.md) (operational semantics),
[`core-march-types.md`](core-march-types.md) (static semantics),
[`surface-syntax.md`](surface-syntax.md) (the friendly grammar
cheatsheet; this chapter is its normative, resolved counterpart; see the
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
- **The EBNF in §4 onward takes a TOKEN-FILTERED stream as input**, not the
  raw lexer output. Two preprocessing layers sit between source text and the
  context-free grammar: the lexer (§2) and `token_filter` (§3). Both are
  documented here as **normative rules**, because the productions in later
  sections are only correct once those transformations have already
  happened (most importantly: most `NL` tokens have already been deleted by
  the time menhir sees the stream). Read §2–§3 before treating any later
  EBNF as literal truth about what raw source text is accepted.
- **`parser.mly` is the ultimate authority.** This chapter states its
  *resolved* behavior, precedence/associativity made explicit, ambiguities
  named and explained, unreachable productions flagged, but the grammar the
  compiler actually implements is whatever `lib/parser/parser.mly` (plus
  `lib/lexer/lexer.mll` and `lib/parser/token_filter.ml`) states. Every claim
  in this chapter is cited to a specific, re-grepped line in one of those
  three files; if a citation and the live source at any point disagree, the source
  wins and this chapter has rotted.
- **"Resolved, not transcribed."** The value added here is stating what the
  three source files leave implicit: which of menhir's shift/reduce
  resolutions is actually taken, why a token exists but can never appear in
  a valid program (`THEN`, §4), which AST constructors had no surface
  syntax reaching them until 2026-07-24 (`PatRecord` and `PatAs`, see §6.3
  for the history of both), and,
  the hardest part, the exact algorithm `token_filter.ml` uses to decide
  where a block expression ends. A line-by-line copy of `parser.mly`'s
  productions would not be worth a separate chapter; this is not that.

## 1. The three-layer pipeline

March source text passes through three distinct stages before it becomes an
AST, and all three are normative parts of "the grammar" even though only the
last one is commonly called that:

1. **Lexer** (`lib/lexer/lexer.mll`), turns raw characters into a token
   stream. Almost entirely context-free/regular, with exactly one
   non-regular wrinkle: string-interpolation brace-depth tracking (§2.3).
2. **`token_filter`** (`lib/parser/token_filter.ml`), a stateful,
   stack-based automaton that consumes the lexer's token stream and produces
   a *filtered* token stream for the parser. It performs soft-keyword
   demotion, `choose…by` disambiguation, and, the hard part, determines,
   using unbounded lookahead, which `NL` tokens are significant block/arm
   separators and which are insignificant layout to be deleted (§3). This
   layer is truly **not context-free**: it is why a single resolved EBNF
   over raw tokens cannot describe March's surface syntax, and why every
   later section in this chapter (§4 onward) states its grammar *in terms
   of the filtered stream* `token_filter` produces, not the lexer's raw
   output.
3. **menhir** (`lib/parser/parser.mly`), the context-free grammar proper.
   Every parse entry point wires the same three-stage composition,
   `March_parser.Parser.module_ (March_parser.Token_filter.make
   March_lexer.Lexer.token) lexbuf`, visible verbatim at, e.g.,
   `bin/main.ml:123` (and repeated at each of the compiler's other parse
   call sites: `lib/repl/repl.ml`, `lib/format/format.ml`,
   `lib/resolver/resolver.ml`, `lib/modules/module_registry.ml`,
   `lib/tir/lower_decls.ml`, `lib/lint/lint.ml`, `lib/search/search.ml`,
   `lib/refactor/refactor.ml`). `parser.mly` is the **ultimate authority**
   for what parses; this chapter states menhir's *resolved* behavior,
   which of its shift/reduce conflicts resolve which way, given the
   `%left`/`%right`/`%nonassoc` declarations and `%prec` annotations,
   rather than leaving readers to infer it from the raw `.mly` file.

**On the "~59 conflicts" figure.** The project's 2026-07-05 grammar-consolidation
survey reported that menhir resolves approximately 59 shift/reduce conflicts
in `parser.mly` via its declared precedence/associativity table. This chapter
**inherits that figure rather than re-deriving it**: regenerating menhir's
`.conflicts` report requires `dune build --root . <target> 2>&1` (menhir's
`--dump`/conflict-report flags run as part of the dune build rule), and this
task is expressly forbidden from running `dune` (see the plan's Global
Constraints, concurrent compiler sessions saturate the shared dune daemon).
No rule or claim in this chapter *depends* on the exact count; instead, the
chapter validates the parser's resolved behavior **by experiment**, precedence
and associativity claims (Task 2) are witnessed by value-producing corpus
programs that only have one possible correct parse under the claimed rule,
run against the real pre-built compiler, rather than by auditing menhir's
conflict list conflict-by-conflict. Treat "~59" as provenance, not a number
this document rechecked.

**Relationship to `surface-syntax.md`.** [`surface-syntax.md`](surface-syntax.md)
is the terse, friendly cheatsheet over nearly the whole surface grammar; it
explicitly defers to `parser.mly` as authoritative and does not attempt to
resolve ambiguities or formalize the preprocessing layers. This chapter is
that resolution: normative, cited by line, and backed by a parse/reject
conformance corpus (`specs/lang/grammar/`, see §"Conformance corpus" below).
The two are complementary, not duplicates: read `surface-syntax.md` first
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
  ordinary `LOWER_IDENT`/`UPPER_IDENT` space entirely at the lexer level;
  some of these keywords are later **demoted back to ordinary identifiers**
  in specific contexts by `token_filter` (§3.1); the lexer itself does no
  such demotion.
- **Literals.**
  - `INT`, `digit+` (`lexer.mll:106–119`); parsed with `int_of_string_opt`
    and raises a positioned `ParseError` (not an uncaught exception) if the
    literal exceeds a 63-bit OCaml `int` (`lexer.mll:110–119`).
  - `FLOAT`, `digit+ '.' digit+` (`lexer.mll:105`); note this requires at
    least one digit on both sides of `.`, matched *before* the bare `INT`
    rule so `1.5` lexes as one `FLOAT` token, not `INT DOT INT`.
  - `STRING`, `'"' … '"'` (`lexer.mll:121`, sub-lexer `read_string` at
    `lexer.mll:204–227`) and triple-quoted `"""…"""` (`lexer.mll:120`,
    sub-lexer `read_triple_string` at `lexer.mll:231–241`), both supporting
    the escapes `\n \t \r \b \f \0 \\ \" \$` and `\xHH` (`lexer.mll:212–224`).
    Triple-quoted strings additionally preserve raw newlines
    (`lexer.mll:239`) rather than requiring `\n`.
  - `BOOL`, the keywords `true`/`false` map directly to `BOOL true`/`BOOL
    false` (`lexer.mll:40–41`), not a separate literal rule.
  - `ATOM`, `':' atom_name` where `atom_name = ['a'-'z'] (alpha | digit)*`
    (`lexer.mll:97, 122`), a colon immediately followed by a
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
  tokens, ocamllex's rule-order/longest-match semantics, not a special
  lookahead the grammar needs to reason about separately.
- **Sigils and capability annotations.** `~Upper`/`~lower_ident` lex as a
  single `SIGIL_PREFIX` token that stores the name (`lexer.mll:173–174`); the
  five `cap ...`/`proof cap` two-word forms (`cap no_panic`, `cap pure`,
  `cap no_extern`, `cap deterministic`, `cap no_alloc`, `proof cap`) are
  matched as fixed multi-word lexer patterns with the whitespace between
  the words baked into the rule (`lexer.mll:175–180`), so e.g. `cap  pure`
  (two spaces) still lexes as one `CAP_PURE` token but `cappure` (no space)
  would not match at all and instead lexes as the ordinary identifier
  `cappure`.

### 2.2 Significant vs. insignificant whitespace

- **Insignificant:** runs of plain spaces/tabs (`whitespace = [' ' '\t']+`,
  `lexer.mll:92, 101`) are consumed with no token emitted at all; they
  never reach the parser in any form.
- **Significant (at the lexer level):** newlines (`newline = '\r' | '\n' |
  "\r\n"`, `lexer.mll:93`) DO produce a token, `NL`, via
  `Lexing.new_line lexbuf; NL` (`lexer.mll:102`). The lexer itself does not
  decide whether a given newline matters to the grammar; it always emits
  `NL` and defers that decision entirely to `token_filter` (§3), which
  deletes most of them. This split is why "significant newlines" is a
  property of the *filtered* stream, not the raw lexer output; the lexer's
  contribution is only that newline position information is preserved at all
  for `token_filter` to act on.
- **Comments** are whitespace-equivalent and never produce a token:
  line comments `-- ...` run to end-of-line (sub-lexer `line_comment`,
  `lexer.mll:103, 192–195`, note the line-comment sub-lexer still emits
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
  through to the **ordinary `token` lexer**, i.e. the interpolated
  expression is lexed with the FULL token grammar (identifiers, operators,
  nested strings, everything), not a restricted sub-grammar.
- While `interp_depth > 0`, every `{` increments the counter and every `}`
  decrements it (`lexer.mll:125, 127–128`), both still emit ordinary
  `LBRACE`/`RBRACE` tokens to the parser (`lexer.mll:125, 136, 138`), so a
  nested record literal or block inside an interpolation parses completely
  normally.
- The interpolation actually **closes** only on the `}` that would bring
  `interp_depth` to `0` (`lexer.mll:129`): at that point the lexer does NOT
  emit `RBRACE` for that closing brace; instead it resumes the appropriate
  string sub-lexer (`read_triple_string_interp` or `read_string_interp`,
  chosen by `interp_triple`, `lexer.mll:130–134`), which reads the next
  span of literal string text and emits `INTERP_MID <text>` (another `${`
  follows, more interpolation segments) or `INTERP_END <text>` (the
  closing `"`/`"""` follows, no more segments, `lexer.mll:245, 249,
  257, 262`).
- Consequently a string with `N` interpolation segments lexes to
  `INTERP_START, expr-tokens…, INTERP_MID, expr-tokens…, …, INTERP_END`
  (parsed by `parser.mly`'s `interp_parts`, cited in §4's string-literal
  entry), and brace balance inside each interpolated expression is
  necessarily well-formed by construction; the parser never has to
  disambiguate an interpolation-closing `}` from a nested one; the lexer's
  counter has already resolved that before menhir even sees a token.

## 3. The `token_filter` pre-pass

Source: `lib/parser/token_filter.ml` (510 lines, one entry point `make`,
`token_filter.ml:42`). This is the layer that makes March's grammar
truly **not context-free**: it is a stateful automaton with unbounded
lookahead sitting between the lexer and menhir, and every later section's
EBNF (§4 onward) describes the grammar **as this layer's output**, not as
the lexer's raw token stream. Concretely: `token_filter.make base_lexer`
returns a replacement lexing function with the same type
(`Lexing.lexbuf -> Parser.token`) that menhir is fed instead of the raw
lexer (`token_filter.ml:38`), from menhir's point of view there is only one
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

**Rule.** Four lexer keywords, `TEST`, `DESCRIBE`, `SETUP`, `SETUP_ALL`,
are only real keywords when immediately followed by a specific next token;
everywhere else they demote back to `LOWER_IDENT` so they remain usable as
ordinary identifiers (function/parameter/variable names). This runs as a
wrapper around the base lexer, *before* the rest of the filter's stack
mechanism sees any token (`token_filter.ml:47–77`):

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

Before/after example, `test` used as a plain function name (no following
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
keyword; it opens directly on `BY`) and an ordinary expression like
`Chan.choose(ch1, ch2)` (an application, reached via `expr_field; DOT;
CHOOSE` in `parser.mly:1188`). The filter peeks exactly one token past
`CHOOSE` (`token_filter.ml:277–288`):

- If the next token is `BY`, this is the protocol-DSL form: the filter
  pushes a `Match` context and a fresh match-state (`ms_is_cond = false`)
  right here at `CHOOSE` (`token_filter.ml:282–283`), *not* at a `DO`,
  because this form has no `DO`, so that `NL` inside the `choose…by…end`
  body is governed by the same arm-boundary mechanism as a real `match`
  (§3.3), letting each `choose` branch use `NL`/`PIPE` as its separator
  exactly like a match arm. The peeked `BY` token is re-queued
  (`token_filter.ml:284`) so downstream dispatch sees it normally.
  Grammar-side, `parser.mly:626` (`CHOOSE; BY; chooser = upper_name; COLON;
  …; branches = separated_nonempty_list(arm_sep, choose_branch); END`)
  confirms `arm_sep` (`NL | PIPE`, `parser.mly:1383–1385`) is exactly what
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

### 3.3 The newline-glom / match-arm-boundary lookahead: the core mechanism

This is the central non-context-free behavior. **Baseline rule
(`token_filter.ml:334, 392–393`): `NL` is significant (kept) only while the
top of the context stack is `Match`; everywhere else (top-level module
body, inside a `Block` i.e. a `do…end` that is not a match, inside any
`Paren`, parens/brackets/braces) every `NL` the lexer emits is silently
swallowed** (recursing straight to the next token, `token_filter.ml:393`).
This is why `block_body` in `parser.mly` (`nonempty_list(block_expr)`,
`parser.mly:992–994`) has **no explicit separator token between successive
block expressions at all**; the grammar doesn't need one, because by the
time menhir sees the stream, the newlines that separated them have already
been deleted; block-expression sequencing is purely "keep reading
`block_expr`s until something that isn't one," not "expressions separated
by `NL`."

Example, a plain function body (`Block` context, no `Match` on the stack):

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

All four `NL`s vanish, `DO` pushes a plain `Block` context
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
   subsequon `NL` seen while that flag is set recurses past it
   (`token_filter.ml:337–339`) until a non-`NL` token arrives; this
   absorbs blank/comment-only lines between `->` and the arm body's first
   real token, then `check_arm_body_transition` (`token_filter.ml:244–253`)
   flips the state to `ms_in_arm_body := true` right before that first
   token is dispatched.
2. **`NL` immediately before `END`, at any point, is suppressed**
   (`token_filter.ml:350–354` from inside an arm body; `token_filter.ml:379,
   386–388` before the first arm): the filter peeks past a run of `NL`s
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
     0 → not a new arm: `false` (`token_filter.ml:209–213`); these tokens
     can only appear inside a body continuation (e.g. the body itself
     starts a nested `let`/`if`/`match`/lambda), so seeing one before any
     `ARROW` proves the `NL` did not start a new pattern;
   - one of the binary-operator tokens `PLUS STAR SLASH PERCENT PIPE_ARROW
     LEQ GEQ EQEQ NEQ AND OR PLUSPLUS` at depth 0 → not a new arm: `false`
     (`token_filter.ml:214–219`), UNLESS `suppress_operators` is true
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

Before/after, a multi-expression arm body followed by a real next arm
(the critical case; corpus witness:
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
when run (`_build/default/bin/main.exe`, non-`--check` mode), the specific
values (`(3*2)^2 = 36`, `4*4 = 16`) only come out right if the arm boundary
resolved exactly where this section states it does, so the program is a
value-witness of the rule, not just a parse-witness.

### 3.4 `⚠️ is_pattern_start`: a hand-maintained shadow of the pattern grammar

`is_pattern_start` (`token_filter.ml:130–143`) determines, during the
arm-boundary lookahead (§3.3), whether the token *after* a candidate `NL`
could possibly begin a new arm's pattern, a fast pre-filter before paying
for the full unbounded lookahead scan. Its own doc comment
(`token_filter.ml:122–129`) is explicit that this is meant to track
`parser.mly`'s `pattern`/`simple_pattern` productions:

> "Kept in sync with the grammar's `pattern` / `simple_pattern` rules
> (parser.mly): `pattern` accepts qualified_upper (UPPER_IDENT), ATOM, and
> simple_pattern; `simple_pattern` accepts UNDERSCORE, soft_lower_name
> (LOWER_IDENT plus the soft keywords below), INT, MINUS INT, FLOAT, MINUS
> FLOAT, STRING, BOOL, LPAREN, LBRACKET, and LBRACE (record pattern
> `{ x, y: p }`)."

This is a **hand-maintained duplicate**, not a derived table: no tooling
generates `is_pattern_start` from `parser.mly`'s grammar automatically, so
every time a production is added to `pattern`/`simple_pattern`/
`soft_lower_name`, a human has to remember to update this predicate too,
and a prior review of this exact predicate on an earlier checkout found it
**already fallen out of sync** (missing the `FLOAT` case and some
soft-keyword cases at that point in time). That is exactly the "resolved,
not transcribed" hazard this whole chapter exists to name: a second,
informal copy of part of the grammar living outside `parser.mly`, kept
correct only by discipline.

**Live cross-check performed for this chapter (re-grepped, not assumed):**

- `soft_lower_name` in the current `parser.mly` (`parser.mly:1461–1475`)
  accepts exactly: `LOWER_IDENT`, `STATE`, `INIT`, `LOOP`, `ON`,
  `PROTOCOL`, `APP`, `AS`, `WITH`, `WHEN`, `USE`, `IN`, `FOR`, `TAG`, 13
  keyword alternatives plus `LOWER_IDENT`.
- `simple_pattern` (`parser.mly:1430–1449`) accepts: a record pattern
  (`LBRACE … RBRACE`, `{ x, y: p }`), `UNDERSCORE`,
  `soft_lower_name`, `INT`, `MINUS INT`, `FLOAT`, `MINUS FLOAT`, `STRING`,
  `BOOL`, `LPAREN … RPAREN` (parenthesized/tuple), `LBRACKET … RBRACKET`
  (list-literal pattern), so the tokens that can START a `simple_pattern`
  are `UNDERSCORE`, `LOWER_IDENT`+the 13 soft keywords above, `INT`,
  `MINUS`, `FLOAT`, `STRING`, `BOOL`, `LPAREN`, `LBRACKET`, `LBRACE`.
- `pattern` (`parser.mly:1419–1428`) adds on top of `simple_pattern`:
  `qualified_upper` (i.e. `UPPER_IDENT`, possibly `UPPER_IDENT DOT
  UPPER_IDENT`, `parser.mly:1413–1417`) and `ATOM` (with or without a
  parenthesized argument list).
- `is_pattern_start` itself (`token_filter.ml:165–177`) currently lists:
  `UPPER_IDENT`, `LOWER_IDENT`, `UNDERSCORE`, `INT`, `FLOAT`, `STRING`,
  `BOOL`, `LPAREN`, `LBRACKET`, `LBRACE`, `MINUS`, `ATOM`, and the 13 soft
  keywords `STATE INIT LOOP ON PROTOCOL APP AS WITH WHEN USE IN FOR TAG`.

**Result of this cross-check: `is_pattern_start` is currently IN SYNC with
`parser.mly`'s `pattern`/`simple_pattern`/`soft_lower_name` first-token set.**
Every token class the grammar's pattern productions can start with is
present in the predicate, with the same 13-keyword soft set, and no
extra entry is listed. `LBRACE` is now correctly *present* (record patterns
gained a `simple_pattern` production 2026-07-24, see §6.1/§6.3; it was
correctly absent before that date, when no pattern production began with
it). This chapter documents that finding as of this pass rather than
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
decide where one arm ends and the next begins; this cannot be expressed as
a context-free production over the raw token stream, because the decision
depends on scanning forward past an arbitrary number of tokens (including,
in the cond/guard case, past an arbitrary boolean expression) to find the
first depth-0 `ARROW`/`NL`/`END`/bail-out token. A context-free grammar's
production for "what follows an arm body" cannot be conditioned on "scan
forward until you find one of these tokens at bracket-depth 0." This is why
`parser.mly` on its own cannot be given directly to a reader as "the grammar";
it assumes its input has already had this resolution performed on it by
`token_filter`, and §4 onward states its EBNF on that basis (filtered-stream
input), never on raw lexer output.

## 4. Expressions: the precedence ladder

Source: `lib/parser/parser.mly` (1511 lines; the expression rules run
`parser.mly:1052–1289`, the precedence declarations are at
`parser.mly:214–220`). Everything in this section takes the **filtered**
token stream (§2–§3) as input: in particular, `NL` has already been deleted
almost everywhere expressions live (it persists only as a match-arm
separator, §3.3), so no production below needs to mention it.

### 4.0 Precedence table (tightest-binding → loosest)

This is the reader's quick reference; §4.1–§4.9 give the resolved production
for each row and cite the exact rule (§4.10 then covers the `then` token,
which has no row here because it never parses at all).

| # | Stratum (`parser.mly` rule) | Operators / forms | Associativity | How it binds |
|---|---|---|---|---|
| 1 (tightest) | `expr_atom` | literals, identifiers, constructors, `(…)`, tuples, records, lists, list comprehensions, `if`/`match`/`cond`/`with` (via `expr`, see note below), lambdas, `do…end` | n/a | atomic, never itself recurses through a lower stratum except via explicit `(…)` |
| 2 | `expr_field` | `.` (field/module access, plus the contextual field names `send`/`choose`/`offer`) | left | `expr_field DOT lower_name/upper_name/SEND/CHOOSE/OFFER` |
| 3 | `expr_app` | function application `f(a, b, …)`, constructor application `Con(a, b, …)` | n/a (application is not itself a binary operator; chained direct calls like `f(1)(2)` do **not** parse at all, see §4.7) | `expr_field LPAREN … RPAREN`; falls through to `expr_field %prec prec_app` otherwise |
| 4 | `expr_unary` | unary `-` (`negate`), `!` (`not`) | right (prefix; self-recursive on the right) | `MINUS expr_unary` / `BANG expr_unary` |
| 5 | `expr_mul` | `* / % *. /.`  | left | `expr_mul OP expr_unary` |
| 6 | `expr_add` | `+ - ++ +. -.` | left | `expr_add OP expr_mul` |
| 7 | `expr_cmp` | `== != < > <= >=` | **non-assoc** (chained comparisons do not parse, §4.4 below) | `expr_add OP expr_add`, both operands one stratum down |
| 8 | `expr_and` | `&&` | left | `expr_and AND expr_cmp` |
| 9 | `expr_or` | `\|\|` | left | `expr_or OR expr_and` |
| 10 (loosest) | `expr_pipe` | `\|>` | left | `expr_pipe PIPE_ARROW expr_or` |

`expr` itself (`parser.mly:1052–1109`) sits *above* `expr_pipe`; it is not
another precedence level so much as the entry point that adds the
non-operator expression forms that don't participate in the operator ladder
at all (`ASSERT`, lambdas via bare `FN`, `IF`, `MATCH`/`ECond`, `WITH`) as
alternatives alongside `expr_pipe`; see §4.1.

### 4.1 `expr`: the top-level entry point

```ebnf
expr ::= expr_pipe
       | "assert" expr
       | "fn" "->" lambda_body
       | "fn" lambda_params "->" lambda_body
       | "if" expr "do" block_body "else" block_body "end"
       | "match" expr "do" arm_sep? branch (arm_sep branch)* "end"
       | "match" "do" arm_sep? cond_branch (arm_sep cond_branch)* "end"
       | "with" with_binding ("," with_binding)* "do" block_body "end"
       | "with" with_binding ("," with_binding)* "do" block_body
             "else" arm_sep? branch (arm_sep branch)* "end"
```

(`parser.mly:1052–1109`.) These alternatives are **not** part of the
operator precedence ladder, they're keyword-led forms distinguishable by
their leading token (`ASSERT`/`FN`/`IF`/`MATCH`/`WITH`), so there is no
shift/reduce ambiguity between them and `expr_pipe`; menhir picks the
alternative with the first token that matches. Two of note:

- **`match do … end` (no scrutinee) is `ECond`** (`parser.mly:1091`), i.e.
  March's `cond`-equivalent: each `cond_branch` (`parser.mly:1400–1404`) is
  a boolean `expr ARROW block_body`, with a bare `_` arm desugaring to
  `true ARROW block_body` (`parser.mly:1403–1404`). This is why the plan
  and other chapters refer to "`cond` (scrutinee-less `match do`)"; there
  is no separate `COND` keyword; it's the same `MATCH` token disambiguated
  by the presence/absence of the scrutinee `expr` before `DO`.
- **`with … do … else … end`** (`parser.mly:1103–1109`) desugars in-parser
  (`build_with`, `parser.mly:161–167`) into nested `EMatch` on each binding
  in turn, so `with Ok(a) <- e1, Ok(b) <- e2 do body else h end` becomes
  `match e1 do Ok(a) -> match e2 do Ok(b) -> body | <else arms> end | <else
  arms> end`, a different desugaring from `let?` (§5.4), which is a
  **block-level** (not `expr`-level) construct: `let? p = e` only appears
  as a `block_expr`/`lambda_stmts` production (`parser.mly:1003–1004,
  1119–1120`), never as a standalone `expr`, and is right-folded into
  nested `ELetQ` continuations by `fold_letq` (`parser.mly:147–156`) rather
  than parsed as a ladder-level operator. Full detail on `let?`'s placement
  constraints (it cannot be the last expression in a block) is §5.4,
  not this section; it is noted here only to distinguish it from
  `with`, which *is* an `expr`-level production.

### 4.2 `expr_pipe`: pipe, loosest-binding, left-associative

```ebnf
expr_pipe ::= expr_pipe "|>" expr_or
            | expr_or
```

(`parser.mly:1122–1125`.) Left-recursive on the left operand, so `a |> f |>
g` parses as `(a |> f) |> g`, i.e. `g(f(a))` once `EPipe` is later lowered,
confirmed as a value-witness by
[`parse/p05_pipe_left_to_right_chain.march`](grammar/parse/p05_pipe_left_to_right_chain.march):
`3 |> double |> inc` prints `7` (`inc(double(3))`), not `8`
(`double(inc(3))`), which is what right-associativity would have produced.
`|>` is the loosest-binding operator in the ladder; its RHS is `expr_or`,
one full stratum down, so `|>` never has to compete with `||`/`&&`/etc. for
which side "wins" a shared operand.

### 4.3 `expr_or` / `expr_and`: boolean connectives, left-associative

```ebnf
expr_or  ::= expr_or "||" expr_and
           | expr_and
expr_and ::= expr_and "&&" expr_cmp
           | expr_cmp
```

(`parser.mly:1127–1133`.) Both left-recursive/left-associative, both
desugared immediately into ordinary calls (`EApp (EVar "||"/"&&", …)`,
**not** special AST nodes), so short-circuit evaluation, if any, is a
property of how `eval`/codegen treat the `||`/`&&` builtins, not of the
parse tree shape. `&&` binds tighter than `||` (it sits one level below in
the stratification, mirroring the conventional arithmetic-like precedence
of the two connectives), and both bind looser than comparisons: confirmed
live by
[`parse/p08_comparison_binds_tighter_than_bool.march`](grammar/parse/p08_comparison_binds_tighter_than_bool.march),
`1 < 2 && 3 > 2` parses as `(1 < 2) && (3 > 2)` (prints `true`), which
would be a type error (`&&` on non-bool `Int` operands) under any parse
that let `&&` bind tighter than `<`/`>`.

### 4.4 `expr_cmp`: comparisons, non-associative

```ebnf
expr_cmp ::= expr_add "==" expr_add
           | expr_add "!=" expr_add
           | expr_add "<"  expr_add
           | expr_add ">"  expr_add
           | expr_add "<=" expr_add
           | expr_add ">=" expr_add
           | expr_add                    (* %prec EQEQ *)
```

(`parser.mly:1135–1142`.) This is the one stratum that is **not**
left-recursive on comparison itself; both operands are `expr_add`, one
level down, not `expr_cmp` again. That means **chained comparisons do not
parse**: `1 < 2 < 3` has no valid derivation (there is no rule reducing
`expr_cmp OP expr_add` back into something an outer `<` could consume) and
menhir rejects it flat out, confirmed live by
[`reject/r03_chained_comparison_nonassoc.march`](grammar/reject/r03_chained_comparison_nonassoc.march)
(`1 < 2 < 3`, rejected with menhir's generic `I got stuck here`). The
`%nonassoc EQEQ NEQ LT GT LEQ GEQ` declaration at `parser.mly:217` exists to
resolve the **residual** shift/reduce ambiguity menhir would otherwise flag
for the trailing `e = expr_add %prec EQEQ { e }` fallthrough alternative
(`parser.mly:1142`), without an explicit precedence, menhir cannot tell
whether that bare-`expr_add` alternative should reduce before or after a
following comparison operator is examined; `%nonassoc` tells it neither
direction is allowed, matching the grammar's structural non-associativity.
The `MINUS` declaration (`%left MINUS`, `parser.mly:218`) plays a similar
disambiguation role one level down, for unary-vs-binary `-` (§4.6), and is
unrelated to comparisons despite sitting adjacent in the declaration list.

### 4.5 `expr_add` / `expr_mul`: arithmetic, left-associative, standard binding

```ebnf
expr_add ::= expr_add "+"  expr_mul
           | expr_add "-"  expr_mul
           | expr_add "++" expr_mul
           | expr_add "+." expr_mul
           | expr_add "-." expr_mul
           | expr_mul

expr_mul ::= expr_mul "*"  expr_unary
           | expr_mul "/"  expr_unary
           | expr_mul "%"  expr_unary
           | expr_mul "*." expr_unary
           | expr_mul "/." expr_unary
           | expr_unary
```

(`parser.mly:1144–1158`.) Both strata are left-recursive → left-associative,
and `*`/`/`/`%` (and their `.`-suffixed float forms) bind **tighter** than
`+`/`-`/`++` purely because `expr_add`'s alternatives recurse through
`expr_mul` (not `expr_add`) for both operands' *inner* structure; the
stratification itself is the precedence mechanism here, no `%prec`
annotation is needed or present. Confirmed live:
[`parse/p04_mul_binds_tighter_than_add.march`](grammar/parse/p04_mul_binds_tighter_than_add.march),
`1 + 2 * 3` prints `7`, not `9` (which is what equal-precedence
left-to-right evaluation would give). Left-associativity of `-` is
confirmed by
[`parse/p03_additive_left_assoc.march`](grammar/parse/p03_additive_left_assoc.march),
`10 - 3 - 2` prints `5` (`(10 - 3) - 2`), not `9` (`10 - (3 - 2)`, what
right-associativity would give). Note `++` (list/string append) and the
float-suffixed operators share `expr_add`'s precedence level exactly;
there is no separate stratum for them. All six operators desugar to
ordinary `EApp (EVar "<op>", [a; b], …)` calls, same as §4.3's boolean
connectives.

### 4.6 `expr_unary`: prefix `-`/`!`, right-recursive (prefix), tightest operator level

```ebnf
expr_unary ::= "-" expr_unary
             | "!" expr_unary
             | expr_app
```

(`parser.mly:1161–1166`.) `MINUS expr_unary` self-recurses so that repeated
prefixing works (`- - x`), and desugars to a call to the builtin `negate`;
`BANG expr_unary` similarly desugars to `not`. This is the tightest
*operator* stratum, tighter than `*`/`/`, which is what makes `1 - -2`
parse as `1 - (negate 2)` rather than failing or misparsing: confirmed live
by running `println(1 - -2)`, which prints `3`. The `%left MINUS`
declaration at `parser.mly:218` resolves the shift/reduce conflict between
treating a `MINUS` as *this* rule's unary prefix vs. as `expr_add`'s binary
infix operator when a `MINUS` token is seen after an existing `expr_add` on
the stack; menhir needs the explicit declaration because `expr_unary`'s
prefix `MINUS` and `expr_add`'s infix `MINUS` are distinguishable
in structure only via lookahead menhir's LALR core would otherwise
report as a conflict; declaring `MINUS` `%left` (matching `expr_add`'s
associativity) resolves it in favor of the intended shift/reduce outcome
without changing the grammar's actual shape.

### 4.7 `expr_app`: application, left-binding via chained atoms

```ebnf
expr_app ::= expr_field "(" separated_list(",", expr) ")"
           | UPPER_IDENT "(" ")"
           | UPPER_IDENT "(" separated_nonempty_list(",", expr) ")"
           | expr_field                    (* %prec prec_app *)
```

(`parser.mly:1168–1175`.) Function application `f(a, b, …)` and constructor
application `Con(a, b, …)`/`Con()` are siblings at this stratum; a bare
`UPPER_IDENT` immediately followed by `(` is always constructor application
(`ECon`), never a curried call, because `expr_field`'s own atom production
for a bare `UPPER_IDENT` (§4.9) is `%prec prec_atom`, which sits *below*
`LPAREN` in the precedence table (`parser.mly:219–220`) specifically so
that `Foo()` shifts the `(` into this rule rather than reducing `Foo` to an
atom first.

**Chained direct calls like `f(1)(2)` do not parse, and are now rejected
with a dedicated diagnostic in every position.** `expr_app`'s
function/callee position is `expr_field`, and its only base case is
`expr_atom` (§4.8–4.9), `expr_atom` has no alternative that accepts a bare
`expr_app`. So once `f(1)` has reduced to an `expr_app`, there is no
production that re-admits that whole application as the callee of a
further `(...)`; the grammar has no rule shaped like `expr_app "(" … ")"`.
Historically menhir rejected the *operand-position* case (`println(adder(1)(2))`)
with a generic `I got stuck here`, while the *statement-position* case
(`let r = adder(1)(2)` as a bare block statement) silently mis-split into
two statements with no error at all (§7.3). As of 2026-07-06 a
newline-sensitive guard in `token_filter.ml` catches the `)(` juxtaposition
**before** menhir in *both* positions: a `LPAREN` that immediately follows a
call's closing `RPAREN`, with no intervening newline, now raises
`` `f(...)(...)` is not a chained call — March functions are not curried. ``
(see §7.3 for the resolution and the IIFE/two-line cases the guard
intentionally preserves). March expresses "call the result of a call" via an
explicit intermediate binding (`let f = adder(1)` then `f(2)`) rather than
curried juxtaposition. The `prec_app` virtual token (declared at
`parser.mly:219`, doc comment at `parser.mly:213`) exists purely to make
`f()` shift `(` instead of reducing `f` to a bare atom first; the same
*shape* of disambiguation `prec_atom` performs for bare `UPPER_IDENT`/`ATOM`
(§4.9).

### 4.8 `expr_field`: field/module access, left-associative chains

```ebnf
expr_field ::= expr_field "." lower_name
             | expr_field "." upper_name
             | expr_field "." "send"
             | expr_field "." "choose"
             | expr_field "." "offer"
             | expr_atom
```

(`parser.mly:1179–1194`.) Left-recursive → left-associative, so `a.b.c`
parses as `(a.b).c`, and a qualified module path like `A.B.c` is *also*
just repeated `expr_field` application (there is no separate "module path"
production at the expression level, `upper_name` after a `DOT` covers
`A.B`-shaped sub-module chains the same way `lower_name` covers a terminal
field/function name). `send`/`choose`/`offer` are ordinary keywords
elsewhere in the grammar (actor-DSL primitives, `expr_atom` in the
`SPAWN`/`SEND` case and top-level `CHOOSE`/`OFFER` productions) but are
explicitly re-admitted as field names here so that `Chan.send(…)`,
`Chan.choose(…)`, `Chan.offer(…)` parse as ordinary method-call-shaped
field access rather than colliding with those keywords (§3.2 documents the
token_filter-level part of the `CHOOSE` disambiguation specifically).
Confirmed live by
[`parse/p06_field_access_vs_application.march`](grammar/parse/p06_field_access_vs_application.march):
`get(b.get)` prints `105`; the field access `b.get` (an `Int`) is fully
resolved as `expr_field`'s base case before being passed as the sole
argument to the outer `get(...)` application, proving `expr_field`
reduces before `expr_app`'s argument list closes around it (which is also
just the ordinary top-down parse of `expr_app`'s first alternative, since
`expr_field` is what appears before the argument-list `LPAREN`).

### 4.9 `expr_atom`: atoms: the base of the ladder

```ebnf
expr_atom ::= INT | FLOAT | STRING | BOOL
            | INTERP_START interp_parts              (* string interpolation *)
            | SIGIL_PREFIX STRING
            | SIGIL_PREFIX INTERP_START interp_parts  (* sigil + interpolation *)
            | ATOM "(" separated_list(",", expr) ")"
            | ATOM                                    (* %prec prec_atom *)
            | LOWER_IDENT
            | "_"
            | "tag"
            | UPPER_IDENT                              (* %prec prec_atom *)
            | "?" LOWER_IDENT
            | "?"                                      (* %prec prec_hole *)
            | "(" expr ")"
            | "(" expr "," separated_nonempty_list(",", expr) ")"   (* tuple *)
            | "(" ")"                                   (* unit / empty tuple *)
            | "do" block_body "end"
            | "[" expr "for" pattern "in" expr "]"                   (* list comprehension *)
            | "[" expr "for" pattern "in" expr "," expr "]"          (* … with guard *)
            | "[" "]"
            | "[" separated_nonempty_list(",", expr) "]"             (* list literal *)
            | "{" separated_nonempty_list(",", record_field_expr) "}"        (* record literal *)
            | "{" expr "with" separated_nonempty_list(",", record_field_expr) "}"  (* record update *)
            | "spawn" "(" expr ")"
            | "send" "(" expr "," expr ")"
            | "dbg" "(" ")"  |  "dbg" "(" expr ")"
            | "state"
```

(`parser.mly:1196–1266`.) This is the bottom of the ladder: every
alternative is either a literal/name terminal or delimited by an explicit
bracket pair (`( )`, `[ ]`, `{ }`, `do…end`), so no alternative here needs a
precedence declaration to disambiguate against the operator strata above it:
parenthesization is exactly how a lower-precedence expression re-enters
as an operand at any higher stratum. Three points worth calling out
explicitly:

- **`prec_atom` and `prec_hole`** (`parser.mly:211–212, 214, 216`) are
  virtual tokens, never emitted by the lexer, that exist solely so
  menhir can resolve, without ambiguity, that a bare `UPPER_IDENT`/`ATOM`/
  `QUESTION` should be treated as *lower precedence than* `LOWER_IDENT`/
  `LPAREN` when one of those immediately follows: `prec_atom` sits below
  `LPAREN` in the table (`parser.mly:216, 220`) exactly so `Foo(...)`/
  `:atom(...)` shift into the argument-list form (`expr_app`/`ATOM
  LPAREN…RPAREN`, §4.7/here) instead of reducing the bare name to an atom
  first; `prec_hole` (`QUESTION %prec prec_hole`, `parser.mly:1225`) sits
  below `LOWER_IDENT` (`parser.mly:215`) so that a bare `?` followed by an
  identifier shifts into the named-hole form (`?foo` → `EHole (Some
  "foo")`, `parser.mly:1223–1224`) rather than reducing to an anonymous
  hole (`EHole None`) too early.
- **`if`/`match`/`with` are NOT `expr_atom` alternatives**; they are
  alternatives of `expr` itself (§4.1), one level *above* the whole
  ladder, not atoms. (An earlier draft of this survey area conflated the
  two; the live grammar's `IF`/`MATCH`/`WITH` productions all live at
  `parser.mly:1051–1093`, inside `expr:`, never inside `expr_atom:`.) This
  matters for precedence reasoning: since they're `expr` alternatives
  chosen by leading keyword (not reachable through `expr_pipe`'s ladder at
  all when written bare), an `if …` used as an *operand* of a binary
  operator (e.g. `1 + if c do 2 else 3 end`) is **not directly
  expressible**, the operand strata (`expr_add` etc.) only accept
  `expr_mul`/`expr_unary`/etc., never bare `expr`, so `if`/`match`/`with`
  must be parenthesized to appear as an operand: `1 + (if c do 2 else 3
  end)`. `do…end` (a bare block used as an expression, `parser.mly:1231`)
  **is** an `expr_atom` alternative, so a `do…end` block *can* appear
  unparenthesized as an operand.
- **List comprehensions** (`parser.mly:1232–1238`) are `expr_atom`-level
  bracket-delimited forms:
  ```ebnf
  list_comp ::= "[" expr "for" pattern "in" expr "]"
              | "[" expr "for" pattern "in" expr "," expr "]"
  ```
  binding a full `pattern` (§6, not just `simple_pattern`, so
  constructor/tuple/list patterns are legal comprehension binders too) and
  desugaring **in-parser** (`desugar_list_comp`, `parser.mly:131–140`,
  called from the two comprehension actions at `parser.mly:1233–1238`);
  there is no `EListComp` AST node; by the time the parser returns, a
  comprehension is already `EApp(List.map, [src, mk_comp_lambda pat body])`
  (no guard) or `EApp(List.map, [EApp(List.filter, [src, mk_comp_lambda pat
  pred]), mk_comp_lambda pat body])` (with a guard), filter-then-map, in
  that order. `mk_comp_lambda` (`parser.mly:117–127`) builds a plain
  one-param lambda when the pattern is a bare `PatVar`, or a one-param
  lambda wrapping an `EMatch` for any richer pattern (tuple/constructor/
  list-literal destructuring in the binder position). Confirmed live by
  [`parse/p07_list_comprehension_with_guard.march`](grammar/parse/p07_list_comprehension_with_guard.march):
  `[x * 2 for x in [1, 2, 3, 4, 5], x > 2]` prints `[6, 8, 10]`, filtering
  to `{3, 4, 5}` before doubling, matching the filter-then-map desugaring
  order exactly. The malformed form `[x * 2 for x]` (missing `in <expr>`)
  is rejected live by
  [`reject/r04_malformed_comprehension_missing_in.march`](grammar/reject/r04_malformed_comprehension_missing_in.march)
  with menhir's generic `I got stuck here`; there is no bespoke
  comprehension-specific diagnostic.

### 4.10 `then`: a token with no accepting production

`THEN` (`lexer.mll` keyword table; `parser.mly:177` token declaration) is
declared as a token but **appears in exactly one place in the entire
grammar**: the dedicated error-recovery alternative
`IF; _c = expr; THEN; _t = expr; error` (`parser.mly:1063–1067`), which
unconditionally calls `error_raise` with the message `` I don't recognize
`then` here — March uses do/end blocks instead. ``; there is no path from
a successfully-shifted `THEN` token to a value; every derivation containing
`THEN` terminates in this one diagnostic-raising action. `then` therefore
**can never parse**, by construction, in any position, not just after
`if`. Confirmed live by
[`reject/r01_then_keyword_rejected.march`](grammar/reject/r01_then_keyword_rejected.march)
(`if true then 1 else 2 end`, captured message matches exactly).

## 5. Blocks & statements

Source: `lib/parser/parser.mly` (`block_body`/`block_expr` at
`parser.mly:992–1033`; `expr`'s `IF`/`MATCH`/`WITH` alternatives at
`parser.mly:1051–1093`; `branch`/`cond_branch`/`arm_sep` at
`parser.mly:1275–1296`). Like §4, everything here takes the **filtered**
token stream (§2–§3) as input; this section is in fact where the filter's
newline-glom (§3.3) does the most critical work, since `block_body` and
match-arm bodies are exactly the two places a raw `NL` could plausibly mean
either "end this expression" or "just formatting."

### 5.1 `block_body` / `block_expr`: sequencing, no separator token

```ebnf
block_body ::= block_expr+                          (* nonempty_list *)

block_expr ::= "let" simple_pattern type_annot? "=" expr
             | "linear" "let" simple_pattern type_annot? "=" expr
             | "let" "?" simple_pattern "=" expr
             | "fn" lower_name "(" fn_param,* ")" ret_annot? "do" block_body "end"
             | expr
```

(`parser.mly:992–1033`.) Two things worth stating explicitly because
`parser.mly` leaves them implicit:

- **There is no separator token between successive `block_expr`s at all**,
  `block_body` is `nonempty_list(block_expr)` (`parser.mly:992–994`), i.e.
  "keep parsing another `block_expr` until the next token can't start one."
  This is only well-defined because, by the time menhir sees the stream,
  §3.3's baseline rule has already deleted every `NL` that separated one
  `block_expr` from the next inside an ordinary `do…end` (`Block` context);
  the grammar doesn't encode "expressions separated by newlines" as a
  production, because no material is left in the filtered stream *to*
  encode; sequencing is achieved purely by each `block_expr` alternative's
  own leading-token shape (`LET`, `LINEAR LET`, `FN`, or "falls through to
  `expr`") being enough for menhir to tell where one ends and the next
  begins with no lookahead past that. §3.3's own example (a three-`let`
  function body) is the direct witness of this rule as filtered token
  output; [`parse/p09_block_let_sequencing.march`](grammar/parse/p09_block_let_sequencing.march)
  is this chapter's value-witness: three chained `let`s (`a = 2`,
  `b = a * 3`, `c = b + 4`) followed by the bare final expression `c`,
  printing `10`, the only possible result if all three `let`s bound in
  sequence into one flat block rather than, say, the parser mis-parsing
  a `let` as continuing a previous expression.
- **A `block_expr`'s `let`/`let?`/`fn` alternatives are only reachable at
  block-statement position, never as a general `expr`.** `ELet`, `ELetQ`,
  and `ELetFn` (the local-function-definition form) are productions of
  `block_expr`, not of `expr` (§4.1), so `let x = 1` cannot appear, say, as
  the then-branch of an `if` written on one line, or as a pipe operand;
  it only parses in a position `block_body` (or `lambda_body`/
  `lambda_stmts`, `parser.mly:1101–1120`, the arrow-lambda equivalent
  described in §4.1's cross-reference) governs. `fn name(...) do … end`
  as a `block_expr` (`parser.mly:1015–1027`) is March's local/nested named
  function definition, distinct from the anonymous `fn ... -> expr`
  lambda form, which is an `expr`-level production (§4.1) reachable
  anywhere an expression is.

### 5.2 `if` / `else`: mandatory `else`, no `then`, and how "`else if`" actually works

```ebnf
if_expr ::= "if" expr "do" block_body "else" block_body "end"
```

(`parser.mly:1051–1052`, action `EIf (cond, t, f, sp)`.) This is the
**only** accepting production for `if` in the entire grammar; there is no
bare `if cond do … end` with no `else` at all. Four dedicated menhir `error`
alternatives exist purely to turn common malformed attempts into specific
diagnostics rather than menhir's generic fallback (all still terminate in
`error_raise`, i.e. none of them accept; every one is a rejection with a
better message, not a second way to parse `if`):

- `IF; _c=expr; DO; _t=block_body; ELSE; _f=block_body; error`
  (`parser.mly:1053–1057`), missing the closing `end`:
  `` I was expecting `end` to close the if expression here: ``.
- `IF; _c=expr; DO; _t=block_body; error` (`parser.mly:1058–1062`), no
  `else` branch at all: `` March `if` expressions always need an `else`
  branch: ``. Confirmed live by
  [`reject/r06_if_missing_else.march`](grammar/reject/r06_if_missing_else.march)
  (`if x > 0 do 1 end`, no `else`), captured message matches exactly, and
  this is a real **parse**-stage rejection (the `error` token fires
  inside the `expr` production itself, before typechecking is even
  reached), unlike §5.4's `let?`-last case below.
- `IF; _c=expr; THEN; _t=expr; error` (`parser.mly:1063–1067`), `then` used
  after the condition: `` I don't recognize `then` here — March uses
  do/end blocks instead. `` This is §4.10's `THEN`-has-no-production fact
  repeated at the point it's actually reached; `then` is unreachable from
  *any* position, not just this one, but this is the alternative that
  produces the diagnostic when a user writes `if cond then …`. Already
  witnessed by [`reject/r01_then_keyword_rejected.march`](grammar/reject/r01_then_keyword_rejected.march)
  (§4.10; not re-added here).
- `IF; _c=expr; error` (`parser.mly:1068–1072`); no `do` at all after the
  condition: `` I was expecting `do` after the condition here: ``.

**"`else if`" is not a grammar production; it is just `else` followed by a
nested `if…end` as that block's sole `block_expr`, and every nesting level
needs its own `end`.** There is no `ELSIF`/`ELSE IF` token
(`grep -n "ELSIF\|ELSE IF" lib/parser/parser.mly` and
`lib/parser/token_filter.ml` both come back empty) and no alternative
production shaped like `"else" "if" expr "do" …`, `f` in the `EIf`
production above is an ordinary `block_body`, and `block_body`'s `expr`
fallthrough (`block_expr ::= expr`) happily accepts another `if…end` as that
`block_body`'s one expression. Consequently, a chain that *looks* flat in
source:

```march
if n < 0 do
  "negative"
else if n == 0 do
  "zero"
else
  "large"
end
end
```

is really `if n < 0 do "negative" else (if n == 0 do "zero" else "large"
end) end`: two independent `EIf` nodes, the outer's `else`-branch
`block_body` consisting of exactly one `block_expr`, which is the inner
`if`. Each `if` token opened must be closed by its own `end`; there is no
elision of `end`s for chained `else if`s the way some languages allow.
Value-witnessed by
[`parse/p11_if_else_if_chain.march`](grammar/parse/p11_if_else_if_chain.march):
a 4-way classification (`"negative"`/`"zero"`/`"small"`/`"large"`) written
as three visually-chained `if … do … else if … do … else if … do … else …
end end end` (note the **three** trailing `end`s, one per nested `if`),
printing all four branches correctly for `-5`, `0`, `3`, `100`. Omitting any
of the stacked `end`s (writing only one, as if `else if` were a single
construct) produces the same `` I was expecting `end` to close the if
expression here: `` / generic-fallback family of errors as an ordinarily
unclosed `if`, since the parser truly sees an unterminated nested `if`,
not a special "else-if" form missing its terminator.

### 5.3 `match` (with scrutinee) and `cond` (scrutinee-less `match do`)

```ebnf
match_expr ::= "match" expr "do" arm_sep? branch (arm_sep branch)* "end"
cond_expr  ::= "match" "do" arm_sep? cond_branch (arm_sep cond_branch)* "end"

arm_sep    ::= NL | "|"                              (* %inline, parser.mly:1275–1277 *)

branch      ::= pattern when_guard? "->" block_body
cond_branch ::= expr "->" block_body
              | "_" "->" block_body                  (* sugar for `true -> block_body` *)
```

(`parser.mly:1073–1076` for the two `expr` alternatives; `branch` at
`parser.mly:1279–1281`; `cond_branch` at `parser.mly:1292–1296`.) There is
no separate `COND` keyword, both forms share the `MATCH` token, disambiguated
purely by whether an `expr` scrutinee appears before `DO` (§4.1 already
makes this point for the precedence table; this section is where the arm
grammar itself is stated). A bare `_ -> body` cond-arm desugars in-parser to
`ELit (LitBool true) -> body` (`parser.mly:1295–1296`), i.e. `_` in a
`cond` arm is sugar for an always-true guard, not a distinct AST shape.

**Arm separator (`arm_sep`) is `NL` or `PIPE`, and by the time menhir sees
either, it has already passed through §3.3's suppression mechanism**, every
`arm_sep` NL that reaches this production is one `token_filter`'s
`lookahead_is_new_arm` (§3.3) has already positively identified as a real
arm boundary; menhir's grammar itself just sees "some separator, then
another arm," with no burden of distinguishing "the multi-expression arm
body just ended" from "there's more of this arm's body to come"; that
distinction has already been resolved one layer down. This is why `branch`
and `cond_branch` can both use the same simple `X -> block_body` shape
regardless of how many `block_expr`s the body has: `block_body` is already
`block_expr+` (§5.1), so a multi-statement arm body ("`let`, `let`, final
expr") is just an ordinary `block_body`, no special multi-line-arm
production needed; **the entire "does this arm have one expression or
five?" question is invisible to `parser.mly`**; it is only visible to
`token_filter`, and its job is exactly to have already turned "however many
lines this arm's body spans" into "one contiguous run of `block_expr`s with
no interior `NL`, followed by exactly one `arm_sep` `NL`/`PIPE` that
`branch`/`cond_branch` can trivially consume."

**Fixed gap (found auditing this chapter, 2026-07-22; fixed same day): a
`PIPE` arm separator on its own line used to fail**: `token_filter.ml`'s
`NL`-then-`PIPE` handling (the `Parser.PIPE ->` arm of the `NL` case, next to
the `is_pattern_start` branch described above) emitted the `NL` itself as the
arm boundary but then `push_buf`'d the `PIPE` token back onto the queue
instead of discarding it, so the literal `PIPE` was re-delivered to the
parser as a second, unconsumed token right after the `NL` already served as
`arm_sep`, `branch` has no production for a leading `PIPE`, so this was a
parse error ("I got stuck here" at the `|`). This hit both the leading arm
(before the first `branch`/`cond_branch`, a separate code path in
`token_filter.ml` with the identical bug) and every subsequent arm. Fixed by
having both sites consume the `PIPE` and deliver it directly as the single
`arm_sep` token, rather than re-queuing it after an already-emitted `NL`.
Witnessed by
[`parse/p27_leading_pipe_arm_separator.march`](grammar/parse/p27_leading_pipe_arm_separator.march)
(leading `|` on every arm, including the first, for both the scrutinee'd and
cond forms).

Value-witnessed end-to-end (parse-and-run, not just parse) by
[`parse/p10_match_multi_expr_arms_three_way.march`](grammar/parse/p10_match_multi_expr_arms_three_way.march),
a three-constructor `match` (`Circle(r)`/`Square(side)`/`Triangle(base,
height)`), where the **first two** arms are multi-expression bodies (two
`let`s then a final expr) and the **third** is a single-expression body,
intentionally mixing both shapes to prove the arm-boundary lookahead handles
the transition *into* a multi-expression arm, *between* two multi-expression
arms, and *out of* a multi-expression arm into a single-expression one, all
in the same program. Printed output `36`, `16`, `30` (`(3*2)²`, `4²`,
`5*6`) is only obtainable if every arm boundary in the whole match landed
exactly where §3.3 states it does; this strictly extends §3.3's own
[`p02_match_multi_expr_arms.march`](grammar/parse/p02_match_multi_expr_arms.march)
witness (two arms, both multi-expression) to a three-arm, mixed-shape case.

### 5.4 `let?` position constraint: cannot be the last expression in a block

`let? p = e` is **not** an `expr`-level production (contrast with `with…do…
end`, §4.1); it is one specific alternative of `block_expr`
(`parser.mly:1003–1004`) and of `lambda_stmts` (`parser.mly:1119–1120`),
never reachable as a standalone expression, a pipe operand, or an `if`
branch written inline. Both call sites fold a flat list of `block_expr`s
into right-nested `ELetQ` continuations via `fold_letq`
(`parser.mly:147–156`, doc comment `142–146`): `[let? p = e; rest…]`
becomes `ELetQ(p, e, fold_letq rest sp, sp)`, i.e. everything *after* a
`let?` in the same block becomes that `ELetQ`'s continuation, recursively.

**The grammar happily parses `let?` as the last `block_expr`; this
restriction is enforced by the *typechecker*, not the parser.** When
`fold_letq` reaches a `let?` with no expression following it (the `[e]`/`[]` base
cases never apply to a trailing `ELetQ` the way they do to an ordinary
expression), it produces `ELetQ (p, e, EBlock ([], sp), sp)`
(`parser.mly:1004`, and identically at `parser.mly:1120` for the
lambda-body call site); an empty `EBlock` as the continuation. This parses
completely successfully; menhir never rejects it. The rejection happens
later, in `Typecheck.infer_expr`'s `ELetQ` case
(`lib/typecheck/typecheck.ml:4651–4665`; re-grep `ELetQ`): it pattern-matches the
continuation, and specifically when it sees `Ast.EBlock ([], _)`, the
empty-continuation shape `fold_letq` produces exactly when `let?` was last;
it raises `` `let?` cannot be the last expression in a block. `` (full
message includes a suggested fix, `typecheck.ml:4658–4663`) and returns
`TError` rather than unifying a result type. So `march --check` still exits
1 for this program (typecheck failure, not codegen/eval failure), but the
diagnostic is a **type** error, not a **parse** error, worth stating
explicitly since every other `reject/` program in this corpus so far pins a
parse-stage diagnostic. Confirmed live by
[`reject/r05_letq_last_in_block.march`](grammar/reject/r05_letq_last_in_block.march)
(`fn f() do let? x = Ok(1) end`), `march --check` exits 1 with exactly the
message above; the same source parses fine standalone (verified by removing
the outer `fn`/checking the token stream is well-formed, the failure
surfaces only once type inference visits the `ELetQ` node). This is a
intentional, documented design choice (the `fold_letq` doc comment states so
in as many words: "the typechecker flags the empty continuation with a clear
error"), not a parser gap to file. The positive companion, a well-formed multi-`let?` block that DOES parse and run, is [`parse/p25_letq_block_fold.march`](grammar/parse/p25_letq_block_fold.march) (a two-step chain printing `70`, witnessing that `fold_letq` nests the continuations right-associatively).

## 6. Patterns

Source: `lib/parser/parser.mly` (`pattern` at `parser.mly:1311–1320`,
`simple_pattern` at `parser.mly:1322–1341`, `qualified_upper` at
`parser.mly:1305–1309`, `soft_lower_name` at `parser.mly:1353–1367`). Like
§4–§5, this section describes the grammar over the **filtered** token stream
(§2–§3); §3.4 already cross-checked `token_filter`'s `is_pattern_start`
shadow predicate against these exact same productions, so this section
states the productions themselves as the primary reference.

### 6.1 `simple_pattern`: the narrower pattern grammar

```ebnf
simple_pattern ::= "{" separated_nonempty_list(",", record_field_pat) "}"      (* record *)
                  | "_"
                  | soft_lower_name
                  | INT
                  | "-" INT
                  | FLOAT
                  | "-" FLOAT
                  | STRING
                  | BOOL
                  | "(" pattern ")"
                  | "(" pattern "," separated_nonempty_list(",", pattern) ")"   (* tuple *)
                  | "[" "]"                                                     (* Nil sugar *)
                  | "[" separated_nonempty_list(",", pattern) "]"               (* Cons-chain sugar *)

record_field_pat ::= lower_name ":" pattern                                    (* name: p *)
                    | lower_name                                                (* punned: name  ==  name: name *)
```

(`parser.mly:1322–1341`, `record_field_pat` immediately above
`record_field_expr`.) Thirteen alternatives, in source order (the EBNF
above groups the two literal-negation pairs and the two list-literal cases
onto shared lines for readability, so it shows 11 bullet-level shapes
over the same thirteen grammar alternatives):

- `"{" record_field_pat,* "}"` → `PatRecord`, a record-destructuring
  pattern. Each field is either `name: p` (a full sub-pattern) or a bare
  punned `name`, sugar for `name: name` (binds a variable with the same
  name as the field, mirroring the record-literal punning convention). As
  of this pass (2026-07-24) the field list must **exactly** match the
  scrutinee record's own field set, a partial list (`{ x }` against a
  two-field record) is a typechecker gap tracked separately, not a grammar
  restriction; the production itself places no limit on which fields, or
  how many, may appear. This was unreachable from surface syntax until this
  pass; see §6.3.
- `UNDERSCORE` → `PatWild`, the wildcard, matches anything, binds no name.
- `soft_lower_name` → `PatVar`, a variable binding. `soft_lower_name`
  (`parser.mly:1353–1367`) is not just `LOWER_IDENT`: it additionally accepts
  13 keyword alternatives that would otherwise be reserved words,
  `STATE`, `INIT`, `LOOP`, `ON`, `PROTOCOL`, `APP`, `AS`, `WITH`, `WHEN`,
  `USE`, `IN`, `FOR`, `TAG`, each mapped back to its literal lowercase
  spelling (e.g. `STATE` → `PatVar "state"`). This is what makes `fn (state,
  event, payload) -> …`-shaped actor-DSL code parse: without this widening,
  `state` used as an ordinary parameter/binding name would collide with the
  `STATE` keyword. Note `AS` is in this list; a bare `as` is still a legal
  variable name in binding position (`let as = 5` parses via
  `simple_pattern`'s `soft_lower_name`). As of 2026-07-24 there IS a
  dedicated as-pattern production, but it lives one level up, on `pattern`
  (`pattern_no_as AS lower_name`, §6.2), and intentionally uses `lower_name`
  rather than `soft_lower_name` for the name after `AS`, so the two never
  compete for the same token position; see §6.3.
- `INT` / `MINUS INT` → `PatLit (LitInt …)`, plain and negative integer
  literals. The negative form is its own two-token alternative (`MINUS`
  immediately followed by `INT`), not a unary-minus *expression* embedded in
  a pattern, patterns have no operator ladder of their own.
- `FLOAT` / `MINUS FLOAT` → `PatLit (LitFloat …)`, same shape, for floats.
- `STRING` → `PatLit (LitString …)`, `BOOL` → `PatLit (LitBool …)`, literal
  patterns for the two remaining scalar kinds.
- `LPAREN pattern RPAREN` → parenthesization (returns the inner pattern
  unchanged, no new AST node), lets a full `pattern` (e.g. a bare
  constructor pattern, only otherwise reachable via `pattern`, not
  `simple_pattern`) appear anywhere a `simple_pattern` is required, by
  wrapping it in parens. This is the escape hatch that makes `let Some(x) =
  opt` fail (§6.2) but `let (Some(x)) = opt`... **also** fail, parenthesizing
  doesn't help here because the parenthesized form still reduces to a bare
  `pattern`, and `simple_pattern`'s `LPAREN pattern RPAREN` alternative
  accepts any `pattern` including a `PatCon`, so in fact `let (Some(x)) = opt`
  **does** parse (confirmed live, exit 0): the parens are exactly the
  mechanism that lets a constructor pattern reach `let`-position, since
  `let` only accepts `simple_pattern` (§6.2) and this is `simple_pattern`'s
  own rule for admitting an arbitrary `pattern` inside explicit parens.
- `LPAREN pattern COMMA … RPAREN` → `PatTuple`, tuple-destructuring
  pattern, two or more comma-separated sub-patterns.
- `LBRACKET RBRACKET` → sugar for `PatCon (Nil, [])`; `LBRACKET
  separated_nonempty_list(",", pattern) RBRACKET` → sugar for a right-folded
  `Cons`-chain, `[a, b]` becoming `PatCon(Cons, [a; PatCon(Cons, [b;
  PatCon(Nil, [])])])`, list-literal patterns desugar in-parser to ordinary
  constructor patterns over March's built-in `List` representation; there is
  no dedicated `PatList` AST node.

### 6.2 `pattern`: adds constructors, atoms, and or-patterns on top of `simple_pattern`

```ebnf
pattern         ::= pattern_no_as "as" lower_name
                   | pattern_no_as

pattern_no_as   ::= pattern_alt "|" separated_nonempty_list("|", pattern_alt)   (* or-pattern *)
                   | pattern_alt

pattern_alt     ::= qualified_upper "(" separated_nonempty_list(",", pattern) ")"
                   | qualified_upper
                   | ATOM "(" separated_nonempty_list(",", pattern) ")"
                   | ATOM
                   | simple_pattern

qualified_upper ::= UPPER_IDENT
                   | UPPER_IDENT "." UPPER_IDENT
```

(`parser.mly:1451–1454` for `pattern`; `pattern_no_as` at `parser.mly:1461–1464`;
`pattern_alt` at `parser.mly:1466–1474`; `qualified_upper` at
`parser.mly:1439–1443`.) The full hierarchy is now three layers deep,
`pattern` adds the `as`-alias (§6.3), `pattern_no_as` adds or-patterns (below),
and `pattern_alt` is `simple_pattern` **plus** two more alternatives, both
leading with a token `simple_pattern` never starts with (`UPPER_IDENT` or
`ATOM`):

- **Constructor patterns**, `C(...)`/bare `C` → `PatCon`. The callee is
  `qualified_upper`, not a bare `UPPER_IDENT`; it also accepts the
  two-segment `TypeName.CtorName` form (e.g. `Http.Get`) for disambiguating
  same-named constructors across modules; the doc comment right above
  `qualified_upper` (`parser.mly:1300–1304`) notes this dotted lookahead is
  conflict-free because `DOT` never appears in `qualified_upper`'s own
  follow set. A bare `C` with no argument list is `PatCon (C, [])`, nullary
  constructor patterns need no parens (`None`, `Nil`, an enum-like variant).
- **Atom patterns**, `:tag(...)`/bare `:tag` → `PatAtom`. The same
  shape, in structure, as constructor patterns (parenthesized-args or bare), just
  keyed by the `ATOM` token instead of `qualified_upper`; both were
  value-witnessed together by
  [`parse/p14_list_and_atom_payload_patterns.march`](grammar/parse/p14_list_and_atom_payload_patterns.march)
  (below).
- Everything else falls through to `simple_pattern` (6.1).

One level up, `pattern_no_as` adds **or-patterns**: `p1 | p2 | p3` →
`PatOr [p1; p2; p3]`, any two or more `pattern_alt`s separated by `PIPE`.
`PIPE` is also `arm_sep` (§3.3/§5.3, `NL | PIPE` between match arms), but the
two uses never conflict: an arm separator only follows a COMPLETE
branch, one that has already consumed its `ARROW` and body, so by the time
menhir sees a `PIPE` inside a pattern (before any `ARROW`), the only live
derivation is the or-pattern one; LR(1) distinguishes them without needing a
precedence declaration. Confirmed by experiment before writing this production
and reconfirmed after: menhir's shift/reduce conflict count is unchanged at
9. See §6.3 for the reachability history and the binding restriction
`typecheck.ml` enforces on `PatOr`'s alternatives.

**Where `simple_pattern` is used more narrowly than the full `pattern`.**
Three call sites in `parser.mly` bind only `simple_pattern`, never `pattern`
directly:

- `block_expr`'s `let`/`linear let` alternative, `LET; p = simple_pattern;
  ty = option(type_annot); EQUALS; e = expr` (`parser.mly:997, 1000`, also
  the module-level `let` at `parser.mly:390` and `let`-error-recovery sites
  at `parser.mly:393, 975, 1010`).
- `block_expr`'s `let?` alternative, `LET; QUESTION; p = simple_pattern;
  EQUALS; e = expr` (`parser.mly:968, 970`) and its `lambda_stmts` mirror
  (`parser.mly:1086`) and the REPL's `repl_input`/`repl_sequence` mirrors
  (`parser.mly:1344, 1368`).
- Function **parameters**, `param` binds `soft_lower_name` directly
  (`parser.mly:980–988`), a strict subset of `simple_pattern` (no literals,
  no tuples, no lists), so a March function parameter can never be a
  full pattern of any kind, only a plain name (or `_`); tuple/constructor
  destructuring of a parameter requires an extra `let` in the function body.

Consequently **a bare constructor pattern is not directly usable in a `let`
binding**: `let Some(x) = opt` fails to parse (confirmed live against the
pre-built compiler while writing this section, `` I got stuck here `` at
`Some`; not committed as a separate corpus program since
[`parse/p31_record_pattern_in_let.march`](grammar/parse/p31_record_pattern_in_let.march)
already covers the `let`-position `simple_pattern`-only restriction this
fact is adjacent to), because `Some(x)` is a `pattern` alternative
(`qualified_upper LPAREN … RPAREN`), not one of `simple_pattern`'s thirteen
alternatives, and `let` only accepts `simple_pattern`. The only way to bind a
constructor pattern in a `let` is via `simple_pattern`'s own
parenthesization escape hatch (6.1): `let (Some(x)) = opt` **does** parse,
because the parens make it `simple_pattern`'s `LPAREN pattern RPAREN`
alternative, and a `PatCon` is a perfectly good `pattern`. **`match` arms use
the full `pattern`, not `simple_pattern`** (`branch`'s `p = pattern`,
`parser.mly:1280`), so constructor/atom patterns need no such parenthesizing
in `match`; this imbalance (parens needed at `let`, not needed in `match`)
is exactly the practical consequence of the `simple_pattern`/`pattern`
split, and the reason idiomatic March destructures constructors via `match`
rather than `let` whenever the scrutinee isn't already known-exhaustive.

### 6.3 Historical note: `PatRecord` and `PatAs` were both unreachable until 2026-07-24

The AST (`lib/ast/ast.ml:47–48`) defines two pattern constructors,
`PatRecord` and `PatAs`. Both were implemented end-to-end, interpreter,
typechecker, desugarer, LSP, from the start, but `parser.mly` had no
production at all that constructed either one from surface syntax, so both
were dead code reachable only by hand-constructing an AST directly. Both
gaps are now closed and each has its own live production:

- `PatAs` (`p as name`) gained an as-pattern layer wrapping the ordinary
  pattern forms, which were renamed `pattern_no_as`:

  ```
  pattern:
    | p = pattern_no_as; AS; n = lower_name
      { PatAs (p, n, mk_span ($loc)) }
    | p = pattern_no_as { p }
  ```

  Written as `pattern_no_as AS lower_name` rather than left-recursively on
  `pattern` itself so `p as a as b` is a parse error instead of silently
  nesting, and so no menhir precedence declaration is needed for `AS`. See
  §6.2.

- `PatRecord` (`{ x, y: p }`) gained a `simple_pattern` production; see
  §6.1 for the grammar and the punning rule.

Neither production introduced any new shift/reduce conflicts (still 9, the
pre-existing baseline, confirmed with `menhir --explain` after each).
Their former reachability witnesses, `reject/r08_as_pattern_unreachable.march`
and `reject/r02_record_pattern_in_arm_unreachable.march` /
`reject/r07_record_pattern_in_let_unreachable.march`, are retired; the
replacement parse-corpus witnesses are
[`parse/p29_as_pattern.march`](grammar/parse/p29_as_pattern.march),
[`parse/p30_record_pattern_in_arm.march`](grammar/parse/p30_record_pattern_in_arm.march),
and
[`parse/p31_record_pattern_in_let.march`](grammar/parse/p31_record_pattern_in_let.march).
`core-march-types.md`'s reachability notes are updated in step (its own
`(P-As)` and `(P-Record)` rules). `core-march.md`'s §4.3/§4.3.1 still
describe both as dead code as of this pass, out of this task's scope;
that file needs its own pass to catch up.

### 6.4 Or-patterns (`PatOr`): a truly new AST constructor, added 2026-07-24

Unlike `PatAs`/`PatRecord` above (§6.3, both pre-existing AST constructors
that only lacked a grammar production), `PatOr` did not exist anywhere in
the AST before this pass. `p1 | p2 | p3` builds `PatOr [p1; p2; p3]` via the
`pattern_no_as`/`pattern_alt` layering shown in §6.2; the or layer sits
**beneath** the `as`-alias layer, so `1 | 2 as n` parses as `(1 | 2) as n`,
not `1 | (2 as n)`.

Every alternative must independently typecheck to the same type, but **no
alternative may bind a variable**; `A(x) | B(x) -> x` is a parse success
and a type-checking rejection (`` Or-pattern alternatives cannot bind
variables (`x`). ``, code `or_pattern_binding`), not a grammar restriction.
See `core-march-types.md`'s `(P-Or)` rule for the full typing judgment and
the operational reason for the restriction (a shared arm body has no place
to put a per-alternative binding), and `pattern-matching.md`'s "Or
Patterns" section for the user-facing explanation and workarounds.

Reachability witness: [`parse/p32_or_pattern.march`](grammar/parse/p32_or_pattern.march)
(this corpus, a parse-stage witness since `1 | 2` parses regardless of
typing). The binding-rejection counterpart is a **type** error, not a parse
error, so its witness lives in the types corpus instead:
`specs/lang/types/reject/t82_or_pattern_binding.march`.

## 7. Types

Source: `lib/parser/parser.mly` (`ty`/`ty_nat_add`/`ty_nat_mul`/`ty_app`/
`ty_atom` at `parser.mly:910–955`; `ty_record_field` at `parser.mly:957–958`;
`type_annot`/`ret_annot`/`type_params` at `parser.mly:901–908`). Type
expressions are parsed by an entirely separate stratified ladder from
`expr`'s (§4), `ty` does not share any nonterminal with the expression
grammar except where `TyRefine` intentionally embeds a full `expr` as a
refinement predicate (below), so no precedence declaration in `parser.mly`
(`214–220`) does double duty between the two; the type ladder resolves its
one ambiguity (arrow associativity) purely by recursive structure, the same
technique §4.5/§4.6 already showed for `expr_add`/`expr_unary`.

### 7.1 The type-expression ladder

```ebnf
ty         ::= ty_nat_add "->" ty
             | ty_nat_add

ty_nat_add ::= ty_nat_add "+" ty_nat_mul
             | ty_nat_mul

ty_nat_mul ::= ty_nat_mul "*" ty_app
             | ty_app

ty_app     ::= upper_name "(" separated_nonempty_list(",", ty) ")"
             | upper_name "." dotted_upper_tail "(" separated_nonempty_list(",", ty) ")"
             | ty_atom

ty_atom    ::= INT
             | LOWER_IDENT
             | upper_name "." dotted_upper_tail
             | upper_name
             | "linear" ty_atom
             | "affine" ty_atom
             | "(" ")"
             | "(" ty ")"
             | "(" ty "," separated_nonempty_list(",", ty) ")"
             | "{" ty_app "|" expr "}"                          (* refinement, no binder *)
             | "{" lower_name ":" ty "|" expr "}"                (* refinement, with binder *)
             | "{" separated_nonempty_list(",", ty_record_field) "}"

ty_record_field ::= lower_name ":" ty
```

(`parser.mly:910–958`.) Four strata, tightest-to-loosest read bottom-up
exactly as printed (`ty_atom` binds tightest, `ty`'s bare arrow is loosest):

- **`ty_atom`** (`parser.mly:930–955`), the base case. `INT` here builds a
  **type-level natural-number literal** (`TyNat`, e.g. a vector-length index
  type), not an ordinary value type, March's type language includes a small
  arithmetic sublanguage for these (`TyNatOp`, see `ty_nat_add`/`ty_nat_mul`
  below) that only participates when the surrounding type actually uses
  `TyNat`s; ordinary code never encounters it. `LOWER_IDENT` here is a
  **type variable** (`TyVar`); this is how generics/polymorphism are
  written: a lowercase name in type-annotation position is universally
  quantified (HM-style), with **no explicit binder syntax at the `fn`
  level**, contrast `type`/`ptype`/`opaque type` declarations, which *do*
  have an explicit `type_params` binder (`LPAREN separated_nonempty_list(",",
  lower_name) RPAREN`, `parser.mly:907–908`, used at each of the eight
  `type`/`ptype`/`opaque type`/`alwayslinear type` declaration sites (each of
  the four forms has a variant-body and a record-body alternative),
  `parser.mly:436–465`); a function signature's type variables are always
  implicit and inferred, never declared. A bare `upper_name` (or dotted
  `upper_name "." dotted_upper_tail`, e.g. `IO.Network`, joined into one
  `TyCon` name with the dots kept as literal text,
  `parser.mly:933–936`) with no argument list is `TyCon (name, [])`, a
  nullary type constructor (`Int`, `Bool`, a zero-parameter user type).
  `LINEAR ty_atom` / `AFFINE ty_atom` wrap a type in a linearity annotation
  (`TyLinear`), March's linear-types facility, orthogonal to the rest of
  the type grammar. `LPAREN RPAREN` is the unit/empty-tuple type
  (`TyTuple []`); `LPAREN ty RPAREN` is plain parenthesization (no new node,
  same escape-hatch role parens play in `expr`/`pattern`); `LPAREN ty COMMA
  … RPAREN` is a **tuple type** (`TyTuple`, two or more comma-separated
  members, e.g. `(Int, String)`). The three `LBRACE …` alternatives are
  **refinement types** (`TyRefine`, `{ Int | v >= 0 }` binderless or `{ v :
  Int | v >= 0 }` with an explicit binder, note the doc comment at
  `parser.mly:949–951` on how menhir resolves the shared `lower_name COLON
  ty` prefix against a **record type**'s own `lower_name COLON ty` field
  syntax by looking ahead to whether `PIPE` or `COMMA`/`RBRACE` follows) and
  **record types** (`TyRecord`, `{ l₁: t₁, l₂: t₂, … }`, note the field
  separator is `:`, not `=`, the same convention `ty_record_field`
  (`parser.mly:957–958`) and record *literal*/*pattern* syntax share
  elsewhere in the grammar).
- **`ty_app`** (`parser.mly:922–928`), type-constructor application with
  arguments, `Foo(a, b, …)` → `TyCon (Foo, [a; b; …])` (plus the
  dotted-module-path variant, `parser.mly:925–927`, joined the same way
  `ty_atom`'s dotted case is). This is how every generic user type is
  written: `List(Int)`, `Option(a)`, `Pair(a, b)`; there is no dedicated
  sugar production for `Option`/`Result` specifically. Both are compiler
  **builtins** registered directly in the typechecker's arity table
  (`Option` arity 1, `Result` arity 2, `lib/typecheck/typecheck.ml:1816,
  1818`), not `type`/`ptype` declarations anywhere in `stdlib/`
  (`stdlib/option.march`'s own doc comment states in as many words: "The type
  `Option(a)` is a builtin with constructors `Some` and `None`"), but from
  the **type-expression grammar's** point of view they are ordinary
  `TyCon`-with-args applications through `ty_app`, exactly like any
  user-defined generic type, `Option(Int)`/`Result(a, String)` parse via
  the same production as `Pair(a, b)` in this chapter's own corpus witness
  (below); there is no special-cased "option-type"/"result-type" grammar
  rule to document separately.
- **`ty_nat_mul`/`ty_nat_add`** (`parser.mly:914–920`), left-associative
  `+`/`*` over types, but **only meaningful over `TyNat`/`TyNatOp`
  operands** (type-level arithmetic on natural-number index types, e.g. a
  fixed-size-vector length expression); reusing the same `PLUS`/`STAR`
  tokens the value-level grammar uses for `expr_add`/`expr_mul` (§4.5)
  causes no ambiguity because `ty` and `expr` are parsed from disjoint
  contexts (a `ty` only appears after a `COLON`/inside a `type_annot`/
  `ret_annot`/`ty_atom`'s own parens, never interchangeably with `expr`).
  Ordinary generic types (`List(Int)`, records, tuples) never reach this
  stratum's operator alternatives at all, they fall straight through
  `ty_nat_mul`/`ty_nat_add` to `ty_app`/`ty_atom`, so in practice almost
  all type annotations are "atoms and applications," and the nat-arithmetic
  strata are a dormant mechanism for a narrow feature.
- **`ty` itself** (`parser.mly:910–912`), `TyArrow`, function types. **The
  production is right-recursive on the right operand (`ty`, the full
  nonterminal again) and left-bounded by one stratum down
  (`ty_nat_add`)**, the identical shape §4.6's prefix `expr_unary` used for
  right-associativity, just with the roles of "self" and "one-down"
  swapped to the arrow's right and left sides respectively. This makes
  `->` **right-associative**: `A -> B -> C` parses as `A -> (B -> C)`, a
  curried one-argument-at-a-time function type, not `(A -> B) -> C`. There
  is no `%prec`/precedence declaration involved, as with `expr_add`/
  `expr_mul`'s left-associativity (§4.5), the associativity is a pure
  consequence of which side of the production recurses into `ty` again vs.
  drops to `ty_nat_add`, with no menhir conflict to resolve at all (unlike
  `expr_unary`'s prefix-`MINUS` case, which did need `%left MINUS` to
  disambiguate against `expr_add`'s infix use of the same token, `ty` has
  no competing use of `ARROW` to disambiguate against).

### 7.2 Value-witnessing arrow-associativity, generics, tuple and record types

[`parse/p13_rich_type_annotation.march`](grammar/parse/p13_rich_type_annotation.march)
exercises every claim above in one program:

- `fn build(mk: Int -> (Int, Int) -> { x: Int, y: Int }, scale: Int, pair:
  (Int, Int))`: `mk`'s annotation, read right-associatively per 7.1, is `Int
  -> ((Int, Int) -> { x: Int, y: Int })`: a function taking an `Int` and
  returning a function from a **tuple type** `(Int, Int)` to a **record
  type** `{ x: Int, y: Int }` (`:`-separated fields, §7.1). The body calls
  `mk(scale)` (one argument, consuming the outer arrow) and then applies the
  result to `pair` as a *separate* statement (`step(pair)`, not the chained
  `mk(scale)(pair)` shape, see the finding below on why this matters), so
  the program only typechecks at all if `mk`'s type really did parse as a
  2-step curried arrow rather than, say, a 2-argument function type (which
  the grammar has no production for anyway, `ty` has no `(A, B) -> C`
  multi-arg-arrow alternative; multi-argument functions are always
  `A -> (B -> C)` curried arrows or a single tuple-typed argument, never
  both at once as one production).
- `type Pair(a, b) = MkPair(a, b)` and `fn swap(p: Pair(a, b))`, a
  **generic user type** (`type_params (a, b)` at the declaration,
  `parser.mly:907–908`) referenced in a function signature via `ty_app`
  (`Pair(a, b)`, with `a`/`b` as `TyVar`s, resolved by inference to
  `Pair(Int, String)` at the call site `swap(MkPair(1, "one"))`), proves
  `ty_app`'s constructor-application production accepts type variables as
  arguments, not just concrete `TyCon`s.
- Running the program (not just `--check`) prints `10`, `20`, `one`; the
  `10`/`20` are only obtainable if `build`'s curried-arrow parameter really
  invoked as `mk(scale)` then `step(pair)` (each producing the expected
  scaled record field), and `one` is only obtainable if `swap`'s generic
  `Pair(a, b)` annotation let `MkPair(1, "one"))` unify as `Pair(Int,
  String)` and the match-arm destructure/reconstruct round-tripped the
  first element back out correctly.

### 7.3 Finding (RESOLVED 2026-07-06): `f(1)(2)` is now a newline-sensitive parse error

While building this section's corpus, a gap in §4.7's existing claim
surfaced. §4.7 states "chained direct calls like `f(1)(2)` do not parse,"
witnessed there by `adder(1)(2)` as a `println(...)` **argument**, correct
in that position: `println(adder(1)(2))` does fail with `` I got stuck
here `` at the second `(`, because `expr_app` has no production admitting a
further `LPAREN … RPAREN` after it has already reduced. **But the same
`adder(1)(2)` text, written as (or ending) a bare `block_expr` rather than
as an operand nested inside another expression, does not raise any parse
error at all**, confirmed live: `let r = adder(1)(2)` inside a function
body typechecks and runs with no diagnostic, but `r` is bound to
`adder(1)` by itself (a closure value, prints `<fn>`), and the trailing `(2)`
silently becomes a **second, independent `block_expr`**; a
parenthesized-expression statement with a value that is simply discarded unless
it happens to be the block's last expression (confirmed further: a
side-effecting `adder(1)(side(99))` prints `99`, `side` really does run,
proving `(side(99))` is parsed and evaluated as its own statement, not
folded into the preceding call). This falls directly out of §5.1's own
rule (`block_body` is `nonempty_list(block_expr)`, no separator needed,
`parser.mly:992–994`): once `adder(1)` reduces to a complete `expr`/
`block_expr`, a following `(`-led token is perfectly capable of starting a
brand-new `block_expr` (the `LPAREN expr RPAREN` alternative of
`expr_atom`, §4.9), and no rule in `block_body`'s grammar requires the two
to be related. **This is a documentation-precision gap, not a parser bug**;
the behavior is exactly what the stated grammar predicts once §4.7 and
§5.1 are read together, but §4.7's blanket phrasing ("does not parse")
reads as though the rejection is universal, when it is actually
position-dependent (argument/operand position: hard parse error; bare
block-statement position: silently reparses as two statements with no
error at all, which is arguably the more surprising outcome for a reader to
miss).

**Resolution (2026-07-06).** Rather than leave the statement-position case
as a silent split, the decision was to make `f(1)(2)` a **parse error** with
a helpful message. The fix lives in `lib/parser/token_filter.ml` (not
`parser.mly`), because the newline-sensitivity it requires is only available
before the token filter deletes the newline: `f(1)(2)` and `f(1)⏎(g(2))`
are token-identical by the time menhir sees them, so the distinction *must*
be drawn while the `NL` token still exists. The filter now threads three
pieces of state through its emit boundary, a paren-kind stack (each emitted
`LPAREN` is classified `Call` if the preceding significant token is
value-ending, else `Group`/`Tuple`/lambda-paren), the previous significant
token, and a "newline seen since the previous significant token" flag, and,
when it is about to emit a `LPAREN` that immediately follows a **call's**
closing `RPAREN` with no intervening newline, raises
`` `f(...)(...)` is not a chained call — March functions are not curried. ``
(hint: `` Write `f(a, b)` for a multi-argument call, or put the second call
on its own line if you meant two separate statements. ``). The guard is
narrow by construction, exactly three behaviours, all pinned by corpus
witnesses:

- **Reject** `f(1)(2)` / `Con(1)(2)` / `f(g(1))(2)` (errors on the outer),
  the `RPAREN` closed a *call*, no newline follows
  ([`reject/r14_curried_call_not_chained.march`](grammar/reject/r14_curried_call_not_chained.march)).
- **Accept** an IIFE `(fn x -> x + 1)(5)`; the `RPAREN` closes a
  parenthesized **expression** (a `Group`, not a call's arg list), so the
  guard does not fire
  ([`parse/p23_iife_lambda_call.march`](grammar/parse/p23_iife_lambda_call.march)).
- **Accept** a two-line `f(1)⏎(g(2))`; the newline is the user's signal of
  two separate statements
  ([`parse/p24_two_line_call_juxtaposition.march`](grammar/parse/p24_two_line_call_juxtaposition.march)).

This is the sole compiler behaviour change from this finding; `parser.mly`
is untouched. Multi-argument calls (`f(a, b)`) and every other legitimate
`)(`-free program parse exactly as before.

## 8. Declarations (core)

Source: `lib/parser/parser.mly` (`module_` at `parser.mly:231–255`;
`decl_list_r` at `parser.mly:262–267`; `decl` at `parser.mly:275–334`, plus
each named `*_decl` rule it dispatches to). Unlike §4–§7, declarations are
parsed directly off the **filtered** token stream at the outermost level,
`module_`/`decl_list_r` never sit inside a `Match`/`Paren` context, so none
of §3's newline-glom mechanism is in play here; a `decl` boundary is decided
purely by which fixed keyword (`FN`, `LET`, `TYPE`, `MOD`, `USE`, …) starts
the next token, exactly the same "leading-keyword dispatch, no lookahead
needed" shape §4.1 already used for `expr`'s `IF`/`MATCH`/`WITH`
alternatives.

### 8.1 `mod … do … end`: the module wrapper, and the one-`mod`-per-file rule

```ebnf
module_   ::= "mod" upper_dot_path "do" decl_list_r "end" EOF

decl_list_r ::= decl*
```

(`parser.mly:231–234`, `262–264`.) A March **file** is exactly one top-level
`mod NAME do … end` followed immediately by `EOF`, `upper_dot_path`
(`parser.mly:717–719`) additionally allows a dotted path (`mod A.B.C do …
end`), joined into one name by `join_mod_path` (`parser.mly:46–54`).
**`mod` nested inside a `mod` body is a completely different, ordinary
`decl` alternative**, `mod_decl` (`parser.mly:632–640`), reachable through
`decl`'s `d = mod_decl { d }` line (`parser.mly:315`), so `mod Outer do mod
Inner do … end end` (a nested submodule) parses fine; what's disallowed is
a **second `mod` at the top level of the file**, after the first one's
closing `end`.

`module_` has three additional alternatives, all of which unconditionally
raise a diagnostic rather than accept (`error_raise`/`raise
(ParseError …)`, never returning a value), exactly the same "every
extra alternative is a rejection with a better message" pattern §5.2's `if`
error-recovery alternatives already established:

- **A complete `mod … end` followed by more tokens before `EOF`**
  (`parser.mly:240–245`) is the one-`mod`-per-file rule's own diagnostic:
  `MOD; _path = upper_dot_path; DO; _decls = decl_list_r; END; error` raises
  `` A file may have only one top-level `mod`; everything else must live
  inside it. `` with a suggested fix showing the nested-`fn` shape. This is
  the alternative a second top-level `mod A2 do … end` hits: the first
  `mod` closes cleanly at its `END`, then the second `MOD` token is exactly
  what `error` matches here. Confirmed live by
  [`reject/r10_second_top_level_mod_rejected.march`](grammar/reject/r10_second_top_level_mod_rejected.march),
  two top-level `mod … end` blocks in one file, `march --check` exits 1
  with the message above, verbatim.
- `MOD; _n = upper_dot_path; error` (`parser.mly:246–250`); a `mod Name`
  with no `do` at all: `` I was expecting `do` to start the module body
  here: ``.
- A bare `error` with no recognizable token at all (`parser.mly:251–255`);
  the file doesn't even start with `MOD`: `` March programs must start
  with a module declaration: ``.

### 8.2 `fn` / `pfn`: function declarations, and how multi-head clauses merge

```ebnf
fn_decl ::= "fn"  lower_name "(" fn_param,* ")" ret_annot? when_guard? "do" block_body "end"
          | "fn"  lower_name "[" fn_bound_param,+ "]" "(" fn_param,* ")" ret_annot? when_guard? "do" block_body "end"
          | "pfn" lower_name "(" fn_param,* ")" ret_annot? when_guard? "do" block_body "end"
          | "pfn" lower_name "[" fn_bound_param,+ "]" "(" fn_param,* ")" ret_annot? when_guard? "do" block_body "end"
```

(`parser.mly:341–397`; the bracketed `fn_bound_param,+` form,
`parser.mly:339, 355–369, 383–397`, is a bounded-generic parameter list,
e.g. `fn max[a: Ord](x: a, y: a) do … end`, orthogonal to the multi-head
mechanism below.) **Each of these four alternatives builds exactly one
`DFn`, holding exactly one clause** (`fn_clauses = [{ fc_params = params;
fc_guard = guard; fc_body = body; … }]`, `parser.mly:349–352` etc.); the
grammar itself has **no production for a multi-clause function
declaration**; `fn foo(0) do … end` and a following `fn foo(n) do … end`
are, to `decl`/`fn_decl`, two entirely unrelated, complete `DFn` values,
the same in shape as two functions with different names.

**Multi-head merging happens entirely outside the grammar, in one
post-parse pass over the declaration list: `group_fn_clauses`
(`parser.mly:67–112`, doc comment `56–66`), invoked once on the `decl_list_r`
each of `module_` (`parser.mly:234`) and nested `mod_decl` (`parser.mly:635`)
produces.** It is a linear left-to-right fold over the flat `decl list`
that:

1. Walks the list; on each `DFn` it finds, scans strictly **forward**
   through `collect_same` (`parser.mly:75–80`) absorbing every
   **immediately-following** `DFn` with the **same `fn_name.txt`**,
   concatenating their `fn_clauses` lists in source order
   (`clauses_acc @ d.fn_clauses`) and taking the **first** non-`None`
   return-type annotation seen among the group (`parser.mly:77`), so only
   one clause in a multi-head group needs (or may state) a `ret_annot`, and
   the parser does not require them to agree syntactically (typechecking is
   a separate, later pass).
2. Anything that isn't part of that adjacent run, a different name, or a
   non-`DFn` declaration, ends the group and the fold continues from
   there (`parser.mly:83`, `d :: rest -> go (d :: acc) rest`).
3. **Adjacency is required, and non-adjacency is a hard error, not silent
   shadowing.** After grouping, a second validation pass
   (`parser.mly:88–111`) walks the *grouped* output and raises if any `DFn`
   name appears **twice** in it, which can only happen if the same
   function name occurred in two non-adjacent positions in the original
   source (e.g. another declaration, or an unrelated function, sitting
   between two `fn foo` groups), with the message `` clauses of `%s` must
   be adjacent; earlier clauses at line %d would be silently unreachable ``
   (`parser.mly:100–103`), naming the earlier group's line and suggesting
   moving the clauses together. Confirmed live (not committed as a separate
   corpus program, since the plan's Task 5 scope calls for the merge itself
   plus the two named reject programs, not every error path): a three-`fn`
   program with `fn f(0) do … end`, an unrelated `fn g() do … end` in
   between, then a second `fn f(n) do … end` is rejected with exactly this
   message, naming the first `fn f`'s line.

**Net effect: consecutive same-name `fn`/`pfn` clauses become one
`DFn`/multi-clause function**, later compiled as ordinary pattern-matching
dispatch over the clauses in source order (each clause's `fc_params`
becoming one match arm); this is what makes `fn fib(0) do 0 end` / `fn
fib(1) do 1 end` / `fn fib(n) do fib(n-1)+fib(n-2) end`, written as three
textually separate `fn` declarations, behave as a single three-armed
function. Value-witnessed by
[`parse/p15_multi_head_fn_merge.march`](grammar/parse/p15_multi_head_fn_merge.march):
running it (not just `--check`) prints `55`, `fib(10)` is only obtainable
if all three heads merged into one dispatching function (a lone `fn fib(n)
do fib(n-1)+fib(n-2) end`, with no base cases, would never terminate; a lone
`fn fib(0)`/`fn fib(1)` would never be reached for `n = 10` if the three
were somehow kept as three independent, non-merged single-clause
functions, the only way `println(fib(10))` produces `55` and returns is if
`group_fn_clauses` really did fold all three into one 3-clause `DFn`
compiled as a 3-arm match).

There are also two grammar-level error-recovery alternatives specific to
`fn_decl` (`parser.mly:398–407`), both firing when the parameter list closes
but no `do` follows: `` I was expecting `do` to start the function body
here: `` for both `fn` and `pfn`.

### 8.3 `let` declarations

```ebnf
let_decl ::= "let" simple_pattern type_annot? "=" expr
```

(`parser.mly:424–427`, `DLet (Public, …)`, module/top-level `let`, reachable
through `decl`'s `d = let_decl { d }` line, `parser.mly:307`.) This is the
**module-level** `let`, a different production from `block_expr`'s `let`
(§5.1, `parser.mly:997`), though both share the identical
`simple_pattern type_annot? "=" expr` shape and both are restricted to
`simple_pattern`, not full `pattern` (§6.2's restriction applies
identically here: a bare constructor pattern needs `simple_pattern`'s own
parenthesization escape hatch, `let (Some(x)) = expr`, to bind at module
level too). A missing `=` after the pattern/annotation is caught by a
dedicated error alternative (`parser.mly:428–432`): `` I was expecting `=`
in the let binding here: ``. Module-level `let` is always public
(`DLet (Public, …, _)`; the constructor argument is hardcoded, not derived
from a keyword choice); there is no `plet`/private module-level `let`
production in the grammar.

### 8.4 `type` / `ptype`: variant, record, and generic declarations

```ebnf
type_decl ::= "opaque"? "type" upper_name type_params? "=" variant ("|" variant)*
            | "opaque"? "type" upper_name type_params? "=" "{" ty_record_field,* "}"
            | "ptype" upper_name type_params? "=" variant ("|" variant)*
            | "ptype" upper_name type_params? "=" "{" ty_record_field,* "}"
            | "alwayslinear" "type" upper_name type_params? "=" variant ("|" variant)*
            | "alwayslinear" "type" upper_name type_params? "=" "{" ty_record_field,* "}"
            | "tag" upper_name                                (* sugar: type Foo = Foo *)

type_params ::= "(" lower_name,+ ")"

variant ::= upper_name ("(" ty,+ ")")?
          | ATOM ("(" ty,+ ")")?
```

(`parser.mly:434–478`; `type_params` at `parser.mly:907–908`; `variant` at
`parser.mly:964–972`.) Eight declaration-site alternatives (four
visibility/linearity prefixes × {variant body, record body}), plus the
`tag` sugar and two error-recovery alternatives, all funneled through one
`type_decl` rule:

- **`type`**/**`opaque type`** are both `DType (Public, …)`, visible,
  public type declarations. The *only* difference `opaque` makes at the
  grammar level is that its variant-body alternative maps every variant's
  visibility to `Private` before constructing the `DType`
  (`parser.mly:439`, `List.map (fun v -> { v with var_vis = Private }) …`,
  contrast the plain `type` variant-body alternative, `parser.mly:445–448`,
  which keeps each `variant`'s own visibility, always `Public` per the
  `variant` production above since `var_vis = Public` is hardcoded there
  too), i.e. "the type name is public but its constructors are private to
  the module," a visibility split at the constructor level the grammar
  encodes by post-processing the parsed variant list, not by a different
  production shape. `opaque`'s record-body alternative
  (`parser.mly:441–444`) does not perform this remapping (records have no
  per-field visibility concept at this level).
- **`ptype`** is `DType (Private, …)`; the type name itself is private to
  the module (§8.6 states the general public/private convention this
  mirrors).
- **`alwayslinear type`** builds a distinct AST node, `DAlwaysLinearType`
  (`parser.mly:461–468`), not `DType`, March's linear-types facility for a
  type with values that must always be used exactly once; grammar-wise it is
  the same variant/record body shapes, just tagged into a different
  top-level constructor.
- **`tag Foo`** (`parser.mly:469–473`) is pure sugar: it builds
  `DType (Public, Foo, [], TDVariant [{ var_name = Foo; var_args = []; … }],
  …)` directly in the parser action, exactly equivalent to writing `type
  Foo = Foo` by hand, a zero-argument phantom-label type used for
  compile-time tagging.
- **Generic parameters** (`type_params`, `parser.mly:907–908`) are an
  explicit, parenthesized list of **lowercase** names right after the type
  name, `type Pair(a, b) = MkPair(a, b)`, the one place in the grammar a
  generic's type variables **are** explicitly bound at the declaration
  (contrast §7.1's note that a `fn` signature's type variables are always
  implicit/inferred, never declared this way).
- **Variant bodies** (`separated_nonempty_list(PIPE, variant)`) are
  pipe-separated `variant`s, each either a bare name/atom (nullary
  constructor, `var_args = []`) or a name/atom applied to a parenthesized,
  comma-separated list of **types** as its argument shapes (`var_args = […]`);
  the `ATOM`-headed alternatives (`parser.mly:969–972`) mean an atom like
  `:ok`/`:error` can be used as a variant constructor name interchangeably
  with an `UPPER_IDENT` one, e.g. `type Status = :ok | :error(String)`.
- **Record bodies** (`LBRACE ty_record_field,* RBRACE`) are the same
  `{ label: Type, … }` shape §7.1 already introduced for record *types*;
  here it's a fresh type declaration's sole body rather than an inline
  type expression.
- A `TYPE; upper_name; error` alternative (`parser.mly:474–478`) fires when
  no `=` follows the name: `` I was expecting `=` after the type name
  here: ``.

Value-witnessed (generics + record body together) by
[`parse/p17_generic_type_record_variant.march`](grammar/parse/p17_generic_type_record_variant.march):
`type Box(a) = { value: a, label: String }` (a one-type-parameter record
type) and `type Tree(a) = Leaf | Node(Tree(a), a, Tree(a))` (a
self-referential generic variant type, `Tree(a)` used as one of `Node`'s
own argument types) in the same program, run (not just `--check`) to print
`42`, `answer`, `2`, the record field accesses and the recursive `depth`
match over `Leaf`/`Node` only produce these values if both declarations
parsed with their generic parameter correctly threaded through.

### 8.5 `use` / `import` / `alias`: import forms and selectors

```ebnf
use_decl    ::= "use" upper_name use_path_tail
use_path_tail ::= ε                                            (* UseSingle *)
                | "." "*"                                       (* UseAll *)
                | "." "{" lower_name,* "}"                      (* UseNames *)
                | "." lower_name                                (* UseNames [one] *)
                | "." upper_name use_path_tail                  (* recurse deeper *)

import_decl ::= "import" upper_name import_path_tail
import_path_tail ::= ε                                          (* UseAll *)
                    | "," "only" ":" "[" lower_name,* "]"        (* UseNames *)
                    | "," "except" ":" "[" lower_name,* "]"      (* UseExcept *)
                    | "." "{" any_name,* "}"                     (* UseNames *)
                    | "." upper_name import_path_tail            (* recurse deeper *)

alias_decl ::= "alias" upper_dot_path "," "as" ":" upper_name
             | "alias" upper_dot_path "as" upper_name
             | "alias" upper_dot_path                            (* alias to its own last segment *)
```

(`use_decl` at `parser.mly:647–650`, `use_path_tail`/`use_selector` at
`parser.mly:659–672`; `import_decl` at `parser.mly:679–682`,
`import_path_tail` at `parser.mly:691–700`; `alias_decl_rule` at
`parser.mly:703–710`.) Both `use` and `import` build the same `DUse` AST
node; they are two alternative surface **spellings** for the same import
facility, not two different features: `use A.B.*`/`use A.B.{f, g}`/`use
A.B.foo`/`use A` (Elm/OCaml-flavored dotted-path style, right-recursive tail
so the lookahead after each `.`, `UPPER_IDENT` vs `LOWER_IDENT` vs `*` vs
`{`, unambiguously selects the next alternative, per the doc comment at
`parser.mly:642–646, 652–658`) vs. `import Mod`/`import Mod.Sub, only:
[f,g]`/`import Mod.Sub, except: [f,g]`/`import Mod.Sub.{A, B}`
(Elixir-flavored comma-clause style, doc comment `parser.mly:674–678,
684–690`). `alias` is a separate declaration (`DAlias`, not `DUse`) that
introduces a short name for a long dotted path, in either `alias Long.Name,
as: Short` (Elixir-style keyword-clause) or `alias Long.Name as Short`
(bare `as`) spelling, or with no rename at all (`alias Long.Name` aliases
to the path's own last segment).

### 8.6 `interface` / `impl`: typeclass-style method signatures and implementations

```ebnf
interface_decl ::= "interface" upper_name "(" lower_name ")"
                       ("requires" constraint_expr,+)?
                       "do" method_sig* "end"

method_sig ::= "fn" lower_name ":" ty ("do" expr "end")?

impl_decl ::= "impl" upper_dot_path "(" ty ")"
                 ("when" constraint_expr,+)?
                 "do" fn_decl* "end"

constraint_expr ::= upper_dot_path "(" ty ")"
```

(`interface_decl` at `parser.mly:771–781`; `method_sig` at
`parser.mly:788–794`; `impl_decl` at `parser.mly:799–814`; `constraint_expr`
at `parser.mly:821–825`.) `interface` declares a typeclass-shaped bundle of
method signatures parameterized over one type variable (the single
`lower_name` in parens, March interfaces are single-parameter, unlike
`type_params`' arbitrary arity), each `method_sig` being a bare `fn name: ty`
signature with an **optional default implementation**
(`preceded_by_do_end(expr)`, `parser.mly:790, 793–794`; a `do expr end`
body supplying a default method body inline in the interface itself,
usable when an `impl` doesn't override it). An optional `requires` clause
(`parser.mly:773`) names superclass interface constraints, e.g. `interface
Ord(a) requires Eq(a) do … end`. `impl` implements an interface for one
concrete type (`upper_dot_path` so `impl Conduit.Storage(T) do … end`
reaches an interface through a dotted module path, per the doc comment
`parser.mly:796–798`), with an optional `when` clause of further
constraints (`parser.mly:801`), and a body of ordinary `fn_decl`s
(`list(fn_decl)`, `parser.mly:802`), so each method body inside an `impl`
is parsed by the exact same `fn_decl` production §8.2 already describes,
including its own multi-head-clause eligibility (an `impl` method can, in
principle, be written as multiple same-name `fn` heads too, since
`impl_methods` just filters the parsed `fn_decl` list down to `DFn`s,
`parser.mly:810–813`, though `group_fn_clauses` is never re-invoked at this
level, only `module_`/`mod_decl` group_fn_clauses their own top `decl`
list, so multi-head merging inside an `impl` body is not exercised by this
pass's corpus and left as a documented, untested-here gap). Both
`interface`/`impl` have their own error-recovery alternatives for a missing
parenthesized parameter (`parser.mly:782–786, 815–819`).

Value-witnessed together (an interface with one method, an `impl` for a
two-constructor `type`, dispatched through the interface's method name) by
[`parse/p16_interface_impl_pair.march`](grammar/parse/p16_interface_impl_pair.march):
running it (not just `--check`) prints `circle:5` then `square:3`, only
obtainable if `describe`'s `impl`-provided body actually dispatched on the
`Shape` variant's two constructors correctly, proving both the `interface`
signature and the `impl` body parsed and wired together as one method.

### 8.7 `derive` / `satisfy`

```ebnf
derive_decl  ::= "derive" upper_name,+ "for" upper_name
satisfy_decl ::= "satisfy" upper_name,+ "for" upper_name,+
```

(`derive_decl` at `parser.mly:480–483`; `satisfy_decl` at
`parser.mly:485–488`.) `derive Eq, Show for Shape` (`DDeriving`) requests
compiler-synthesized instances of one or more interfaces for a single named
type. `satisfy Eq for Int, String` (`DSatisfy`) is the converse shape, one
or more interfaces claimed to already be satisfied by one or more named
types (used to assert conformance for types the compiler cannot
auto-derive, e.g. builtins), note `satisfy`'s **second** list is also
plural (`upper_name,+` for the type side too), unlike `derive`'s single
target type.

### 8.8 Visibility: `fn`/`type` public, `pfn`/`ptype` private, no `pub` keyword

March spells declaration visibility as **a different leading keyword**,
never as a modifier on a shared one:

| Public | Private | Grammar evidence |
|---|---|---|
| `fn` | `pfn` | `fn_decl`'s four alternatives (§8.2) hardcode `fn_vis = Public` for the `FN`-led ones (`parser.mly:345, 360`) and `fn_vis = Private` for the `PFN`-led ones (`parser.mly:373, 388`), visibility is baked into which keyword token started the declaration, not a separate field parsed from the source. |
| `type`/`opaque type` | `ptype` | `type_decl`'s alternatives construct `DType (Public, …)` for `TYPE`/`OPAQUE TYPE` (`parser.mly:440, 444, 448, 452`) and `DType (Private, …)` for `PTYPE` (`parser.mly:456, 460`), same pattern, §8.4. |
| module-level `let` | *(none)* | `let_decl` only builds `DLet (Public, …)` (`parser.mly:426`); there is no `plet`/private-`let` keyword or production in the grammar at all. |

**There is no `pub` keyword anywhere in the lexer or parser.** `grep -n
"PUB\b" lib/lexer/lexer.mll lib/parser/parser.mly` (re-run live for this
pass) returns zero matches, no token, no keyword-table entry, no production.
Writing `pub fn foo() do … end` therefore does not fail because `pub` is a
recognized-but-rejected modifier; it fails because `pub` lexes as an
ordinary `LOWER_IDENT` (it's just not in the keyword table), and
`decl_list_r`'s only alternative for an unrecognized declaration-starting
token sequence is its own catch-all `error` production
(`parser.mly:265–267`): `ds = decl_list_r; error` raises the generic ``
Parse error in declaration ``; there is no bespoke "`pub` is obsolete, did
you mean `fn`?" diagnostic; `pub` is not special-cased at all, it is simply
not a keyword, so `pub fn foo() …` parses exactly as far as an ordinary
`LOWER_IDENT` `fn_attr`/`decl` alternative could take it (none can, since
`pub` is followed by `fn`, not one of `fn_attr`'s own `AT`-led shapes) and
then hits the generic declaration-error fallback. Confirmed live by
[`reject/r09_pub_fn_keyword_rejected.march`](grammar/reject/r09_pub_fn_keyword_rejected.march)
(`pub fn add(a, b) do … end`), `march --check` exits 1 with exactly ``
Parse error in declaration ``, pointing at the `pub` token, matching the
plan's own prediction that this would be a generic rather than bespoke
message.

## 9. DSL declarations (actors, applications, supervision, protocols, transitions, capabilities)

The declaration forms in this section are all **domain-specific
sub-languages** layered on top of the same `decl`/token_filter mechanism
§1–§8 already describe in full, actors, applications, supervision trees,
session-type protocols, capability manifests, and state-machine
transitions. Each of §9.1–§9.6 below is resolved to the same depth §4–§8
use for the expression/pattern/type/core-declaration grammar: every
production, every soft-keyword/lookahead subtlety worth calling out, and a
live `parser.mly` citation, backed by the parse/reject corpus programs
listed under each subsection (see "Conformance corpus" below for the full
index). **`parser.mly` remains the ultimate authority**, as with every
earlier section, if a citation and the live source at any point disagree, the
source wins, but no construct below is left as a shape-only sketch.

### 9.1 `actor`: actor declarations and message handlers

```ebnf
actor_decl ::= "actor" upper_name "do"
                 "state" "{" field ("," field)* "}"
                 "init" expr
                 supervise_block?
                 actor_handler*
               "end"

actor_handler ::= "on" upper_name "(" param,* ")" "do" block_body "end"
```

(`actor_decl` at `parser.mly:490–505`; `actor_handler` at
`parser.mly:601–604`; `field`, shared with record-type bodies, at
`parser.mly:974–978`; `param` at `parser.mly:980–989`.) An actor bundles a
`state { field: Type, … }` shape and an `init` expression producing the
initial state; **both are mandatory, not optional**: neither `STATE` nor
`INIT` is wrapped in `option(...)` in `actor_decl`'s single success
alternative, so an actor body that opens straight on an `on` handler with
no `state`/`init` at all is a real parse-stage rejection (the `on`
handler's leading `ON` token, itself only a keyword when not demoted,
`ON` is one of the 13 soft keywords in `soft_lower_name`,
`parser.mly:1353–1367`, §3.4, cannot be shifted where `STATE` is
expected, so menhir's generic fallback fires). Following the mandatory
`state`/`init` pair comes an *optional* nested `supervise do … end` block
(§9.3, `option(supervise_block)`) and zero or more `on Msg(params) do …
end` message handlers, each pattern-matching on one message constructor
via `param,*`'s reuse of `soft_lower_name` for parameter names, so a
handler parameter may legally be named `state`, `on`, `loop`, etc. (the
same soft-keyword set patterns/`let`-bindings elsewhere in the grammar
already draw from). `actor_decl` also has its own missing-`do` error
alternative (`parser.mly:491–495`): `` I was expecting `do` after the
actor name here: ``.

**Decorators are layered on at the `decl` level, not inside `actor_decl`
itself.** `actor_decl`'s own rule has no production for `@compat:...`
attributes or an `@invariant(...)` clause; those are separate `decl`
alternatives that each parse a prefix (`nonempty_list(fn_attr)` and/or `AT;
INVARIANT; LPAREN; expr; RPAREN`) before delegating to `d = actor_decl` and
then post-processing the resulting `DActor` to fold the attribute/invariant
in (`parser.mly:284–305`), mirroring how `fn_attr`-prefixed `fn_decl`s work
(`parser.mly:280–283`). This is a case where the grammar's own structure,
decoration as a wrapper *around* a plain declaration, not a parameter *of*
it, is only visible by reading `decl` itself, not `actor_decl` in
isolation.

Value-witnessed by
[`parse/p18_actor_handler_supervise.march`](grammar/parse/p18_actor_handler_supervise.march):
a `Worker` actor with one handler, supervised by a `Supervisor` actor's
nested `supervise do … end` (§9.3). Running it (`spawn(Supervisor)` +
`run_until_idle()` + `println(mailbox_size(sup))`) prints `0`, the
supervisor's mailbox only drains if the nested child-spec grammar wired the
`Worker worker` child through correctly. The missing-`state`/`init`
rejection is confirmed live (not committed as a separate corpus program,
since this pass's corpus adds one dedicated reject witness per DSL family
rather than every error-recovery alternative): `actor NoState do on
Ping() do 1 end end` is rejected with menhir's generic `I got stuck here`
at the `on` token.

### 9.2 `app` / `on_start` / `on_stop`: application entry points

```ebnf
app_decl ::= "app" upper_name "do" on_start_block? on_stop_block? block_body "end"

on_start_block ::= "on_start" "do" block_body "end"
on_stop_block  ::= "on_stop"  "do" block_body "end"
```

(`app_decl` at `parser.mly:515–528`; `on_start_block`/`on_stop_block` at
`parser.mly:530–536`.) `app` is the OTP-style application root: an optional
`on_start`/`on_stop` lifecycle-hook block, each independently guarded by
its own `option(...)` (so `on_start` by itself, `on_stop` by itself, both, or
neither are all valid; there is no requirement that one imply the other),
followed by an ordinary `block_body` (typically a `Supervisor.spec(...)`
call wiring up the supervision tree, §9.3). `ON_START`/`ON_STOP` are each
their own fixed lexer keyword (`lexer.mll:75–76`), unlike the DSL
keywords covered by `soft_lower_name` (§3.4), neither demotes back to an
ordinary identifier in any context, so `on_start`/`on_stop` cannot be used
as variable or parameter names anywhere in a March program. `app_decl`'s
own missing-`do` error alternative is at `parser.mly:514–518`: `` I was
expecting `do` after the app name here: ``.

**An `app` and a top-level `main()` cannot coexist in one module.** This is
not a grammar-level restriction, both `app_decl` and `fn_decl` parse fine
standalone and `decl` accepts either, but a dedicated post-parse check
(surfaced live as `` A module cannot define both `main()` and an `app`
declaration. ``, naming both declarations' source lines) rejects a module
declaring both, confirmed live while building this section's corpus
program. This is a **typecheck-stage** rejection, not a parse-stage one
(`march --check` still exits 1, but for the same reason `let?`-last-in-block
is typecheck-stage per §5.4's `r05`, the grammar accepts the token
sequence, a later pass rejects the combination), which is why it is noted
here in prose rather than pinned as a `reject/` corpus program (this
corpus isolates the *parser*, per the harness model in "Conformance
corpus" below; a typecheck-stage rejection belongs to `specs/lang/types/`'s
corpus instead, not this one).

Value-witnessed by
[`parse/p19_app_on_start_supervisor_spec.march`](grammar/parse/p19_app_on_start_supervisor_spec.march):
an `on_start do 42 end` hook followed by a `Supervisor.spec(:one_for_one,
[worker(Counter)])` body, with no `main()` in the same module. `--check`
exits 0, and running it (non-`--check`) drains and exits cleanly rather
than hanging, confirming the optional-hook-then-`block_body` shape both
parses and evaluates as an application root.

### 9.3 `supervise`: supervision trees

```ebnf
supervise_block ::= "supervise" "do"
                       "strategy" restart_strategy
                       "max_restarts" INT "within" INT
                       supervise_child*
                     "end"

restart_strategy ::= "one_for_one" | "one_for_all" | "rest_for_one"
supervise_child  ::= upper_name lower_name
```

(`supervise_block` at `parser.mly:579–592`; `restart_strategy_tok` at
`parser.mly:598–601`; `supervise_child` at `parser.mly:594–596`.) Reachable
in the grammar from exactly one place, `actor_decl`'s optional
`supervise_block?` (§9.1); this names a fixed restart strategy, a
restart-budget window (`max_restarts N within SECONDS`), and a list of
`ChildActorType field_name` children supervised in that declared order
(`sc_order`, `parser.mly:585, 592`). **`strategy`/`STRATEGY` and
`max_restarts`/`within` are mandatory, not optional**: none of `STRATEGY`,
`MAX_RESTARTS`, or `WITHIN` is wrapped in `option(...)` in
`supervise_block`'s single production, so a `supervise do … end` that
opens straight on `max_restarts` (skipping `strategy`) has no valid
derivation, `MAX_RESTARTS` cannot be shifted where `STRATEGY` is
expected, and is a real parse-stage rejection. `restart_strategy_tok`
is a closed enumeration of three fixed lexer keywords
(`ONE_FOR_ONE`/`ONE_FOR_ALL`/`REST_FOR_ONE`, `lexer.mll:57–59`); there is
no fourth strategy and no way to spell a custom one. `supervise_child` is
just `upper_name lower_name` juxtaposition, no comma, no `:`, so
`Worker worker` (child actor type, then the state-field name it is stored
under) is the entire per-child syntax, with as many repeated as needed
(`list(supervise_child)`, zero or more).

Value-witnessed (jointly with §9.1) by
[`parse/p18_actor_handler_supervise.march`](grammar/parse/p18_actor_handler_supervise.march).
The missing-`strategy` rejection is the corpus's own dedicated witness:
[`reject/r11_supervise_missing_strategy.march`](grammar/reject/r11_supervise_missing_strategy.march),
a `supervise do max_restarts 3 within 5 \n Worker worker end` with no
leading `strategy one_for_one`. Captured live: `I got stuck here`, menhir's
generic fallback (no bespoke "you forgot `strategy`" diagnostic exists).

### 9.4 `protocol` / `choose`: binary session types

```ebnf
protocol_decl ::= "protocol" upper_name "do" protocol_step* "end"

protocol_step ::= upper_name "->" upper_name ":" ty
                 | "loop" "do" protocol_step* "end"
                 | "choose" "by" upper_name ":" arm_sep? choose_branch (arm_sep choose_branch)* "end"

choose_branch ::= "|"? lower_name "->" protocol_step*
```

(`protocol_decl` at `parser.mly:615–617`; `protocol_step` at
`parser.mly:619–625`; `choose_branch` at `parser.mly:627–629`; `arm_sep`,
shared verbatim with `match`'s arm separator, §5.3, at
`parser.mly:1275–1277`.) A `protocol` declares a binary session type as a
sequence of directed message steps (`Sender -> Receiver : PayloadType`, the
`: ty` payload annotation is **mandatory**, `protocol_step`'s first
alternative has no `option(...)` around `COLON; t = ty`, so `Client ->
Server` with no type after it cannot complete the step and the following
`END` is unexpected), an optional `loop do … end` repeating sub-sequence
(itself recursing through zero or more `protocol_step`s, so a `loop` may
be empty, `list(...)` permits zero, though the typechecker separately
errors on an empty loop body per `test_compiler.ml`'s
`test_protocol_empty_loop_error` case, a typecheck-stage concern outside
this section's scope), and a `choose by Chooser: label -> steps… | label ->
steps… end` branch point. `LOOP`, like `STATE`/`INIT`/`ON`/`PROTOCOL`/`APP`,
is one of the 13 soft keywords in `soft_lower_name` (§3.4,
`parser.mly:1353–1367`): outside a position where `protocol_step` is
expected, `loop` demotes back to an ordinary identifier and may be used as
a variable/parameter/field name, exactly as `state`/`init`/etc. can.



**`choose`'s `CHOOSE`/`BY` tokens and its `arm_sep`-governed branch
separator are exactly the grammar-level part of the disambiguation §3.2
already documents at the `token_filter` level.** §3.2 explains how
`token_filter` determines, one token of lookahead past `CHOOSE`, whether to
push a `Match` context (the protocol-DSL `choose by …` form, no `DO`) or
leave `CHOOSE` to flow through as an ordinary `expr_field`-chained
application (`Chan.choose(...)`); this section's `protocol_step`'s third
alternative and `choose_branch` are the menhir productions that consume
the token stream §3.2 sets up: the `Match` context pushed at `CHOOSE`
(not at a `DO`; this form has none) is exactly what makes `arm_sep` (`NL`
`|` `PIPE`, §3.3/§5.3) a legal separator between `choose_branch`es despite
there being no enclosing `match`/`DO` pair. Each `choose_branch` optionally
leads with a `PIPE` (`option(PIPE)`), so the first branch may write
either `label -> steps…` or `| label -> steps…`, both accepted identically
(the same convention `match`'s own arm list already uses via
`option(arm_sep)` before the first arm, §4.1).

Value-witnessed by
[`parse/p20_protocol_choose_session_type.march`](grammar/parse/p20_protocol_choose_session_type.march):
a `Client -> Server : Int` step followed by a `choose by Server: ok -> …
| err -> … end` branch point. `--check` exits 0 and the program still runs
to completion. The missing-payload-type rejection is its own dedicated
witness:
[`reject/r13_protocol_step_missing_payload_type.march`](grammar/reject/r13_protocol_step_missing_payload_type.march),
`Client -> Server` with no `: PayloadType`. Captured live: `I got stuck
here`.

### 9.5 `transitions`: compiler-enforced state-machine transitions

```ebnf
transitions_decl ::= "transitions" upper_name "do" transition_arm* "end"

transition_arm ::= upper_name ":" upper_name "->" upper_name "via" lower_name
```

(`transitions_decl` at `parser.mly:760–762`; `transition_arm` at
`parser.mly:764–767`.) Each arm names a resource/handle type, a `From ->
To` state-tag pair, and the function (`via fn_name`) that performs that
transition, grammar-wise a flat five-token sequence
(`upper_name COLON upper_name ARROW upper_name VIA lower_name`) with no
internal optionality or nesting at all; every one of `transitions_decl`'s
and `transition_arm`'s tokens (`TRANSITIONS`, `VIA`) is a fixed hard
keyword (`lexer.mll:87–88`), neither participating in `soft_lower_name`
(§3.4) the way `STATE`/`INIT`/`ON`/`PROTOCOL`/`APP` do, so `via` and
`transitions` are reserved everywhere in a March program, unlike those five
DSL leaders. `transition_arm*` (`list(...)`) permits zero arms, same as
`protocol_step*`'s `loop`; the typechecker (not this grammar) separately
warns when a `transitions Handle do end` names a handle type that has
`via`-eligible functions in scope but no declared arm covering them
(`test_transitions_warn_undeclared` in `test_compiler.ml`), again a
typecheck-stage concern.

Value-witnessed by
[`parse/p21_transitions_state_machine.march`](grammar/parse/p21_transitions_state_machine.march):
a linear `Handle(s)` type with `tag Open`/`tag Closed` phantom states, a
`via` function `open_conn : Handle(Closed) -> Handle(Open)`, and a
`transitions Handle do ConnTag: Closed -> Open via open_conn end`
declaration. Running it prints `1`, `open_conn`'s body only produces that
value if the arm's `From`/`To`/`via` triple parsed in the order this
section's production states (`resource : from -> to via fn`), matching
`tr_resource`/`tr_from`/`tr_to`/`tr_via` field order in the constructed
`transition` record.

### 9.6 Capability directives: `needs`, `proof cap`, and the five `cap …` forms

```ebnf
needs_decl     ::= "needs" cap_path ("," cap_path)*
proof_cap_decl ::= "proof cap" upper_name
cap_no_panic_decl      ::= "cap no_panic"
cap_pure_decl          ::= "cap pure"
cap_no_extern_decl     ::= "cap no_extern"
cap_deterministic_decl ::= "cap deterministic"
cap_no_alloc_decl      ::= "cap no_alloc"

cap_path ::= upper_name ("." upper_name)*
```

(`needs_decl` at `parser.mly:723–725`, `cap_path` at `parser.mly:727–729`;
`proof_cap_decl` at `parser.mly:731–733`; the five `cap_*_decl` rules at
`parser.mly:735–753`.) `needs IO.Network, IO.Clock` declares a module's
required capability manifest as a comma-separated list of dotted
capability paths (`cap_path`, itself right-recursive on `DOT`, mirroring
`upper_dot_path`'s shape used elsewhere for module paths, §8.1). `needs`,
`proof`, and `cap` are each their own grammar-level declaration
alternatives inside `decl` (`parser.mly:320–326`); a module may combine
any number of `needs`/`proof cap`/`cap …` directives with ordinary
declarations, in any order, since each is just one more `decl`.

**The five `cap …` forms and `proof cap` are each a single fixed
multi-word *lexer* token, not a `cap`/`proof` keyword followed by an
ordinary argument identifier; the entire disambiguation happens before
menhir even sees a token.** §2.1 already notes
`CAP_NO_PANIC`/`CAP_PURE`/`CAP_NO_EXTERN`/`CAP_DETERMINISTIC`/
`CAP_NO_ALLOC`/`PROOFCAP` are matched as one fixed-string lexer pattern
each, with the inter-word whitespace baked directly into the `.mll` rule
(`lexer.mll:175–180`: `"cap" [' ' '\t']+ "no_panic"`, etc., and `"proof"
[' ' '\t']+ "cap"`). The grammar-level consequence is that **`cap` is not
itself a reserved word**: `cap` followed by anything other than one of
those five exact trailing words does not match any of these lexer rules at
all, so the ocamllex fallthrough (`lexer.mll:181–188`) classifies bare
`cap` as an ordinary `LOWER_IDENT "cap"`, meaning `cap` remains usable as
a variable/function/parameter name everywhere except immediately before
one of the five fixed trailing words with only spaces/tabs between them. A
module-level line reading `cap no_such_thing` therefore lexes as two
unrelated `LOWER_IDENT`s (`cap`, `no_such_thing`), matches no `decl`
alternative, and falls through to `decl_list_r`'s generic error-recovery
rule (`parser.mly:265–267`), a **parse-stage** rejection, not a "you
misspelled the capability name" diagnostic, because as far as the grammar
is concerned no capability-directive production was entered at all.

At the grammar level, once lexed, each of the five `cap …` tokens and
`proof cap NAME` is a trivial zero-argument (or single-`upper_name`-argument,
for `proof cap`) declaration (`DOpts (["no_panic"], …)` etc., or `DProofCap
(name, …)` for `proof cap SomeName`) that exists purely to record a
module-level compiler-enforced option or a proof obligation; there is no
further internal structure for menhir to resolve.

Value-witnessed by
[`parse/p22_capability_directives.march`](grammar/parse/p22_capability_directives.march):
`needs IO.Network, IO.Clock` (a two-segment `cap_path` list), `proof cap
Trusted`, and `cap no_panic` combined in one module guarding a
division-free `add` function. `--check` exits 0 and the program prints
`5`. The "`cap` is not a reserved word, so an unrecognized trailing word
falls through to the generic declaration-error path" claim is its own
dedicated witness:
[`reject/r12_cap_unknown_directive.march`](grammar/reject/r12_cap_unknown_directive.march),
`cap no_such_thing`. Captured live: `` Parse error in declaration ``.

## Conformance corpus

This chapter is backed by a runnable parse/reject corpus at
`specs/lang/grammar/`, mirroring the shape of `specs/lang/types/` (the
`core-march-types.md` corpus) with intentionally different directory names:

- **`parse/*.march`**: must parse (`march --check` exit **0**; kept
  well-typed so exit 0 isolates "this parsed", the same discipline
  `types/accept/` uses for "this typechecked").
- **`reject/*.march`**: must fail to **parse** (`march --check` exit **1**),
  with the compiler's actual output containing the exact substring named in
  the program's own first-line `-- EXPECT-ERROR: <substring>` annotation.
  Some of these substrings are menhir's generic fallback diagnostics (e.g.
  `I got stuck here`) rather than a bespoke message; that is expected and
  fine; the corpus pins whatever the live compiler actually prints, never a
  wished-for message.

Run it:

```
MARCH_BIN=$PWD/_build/default/bin/main.exe bash specs/lang/grammar/check_grammar.sh
```

See [`grammar/INDEX.md`](grammar/INDEX.md) for the full program-to-rule map.
Task 1 seeded the corpus with four programs anchoring §2–§3 (the
preprocessing layers); Task 2 added six more (`p03`–`p08`, `r03`–`r04`)
anchoring §4's precedence/associativity claims and the list-comprehension
grammar; Task 3 added five more (`p09`–`p11`, `r05`–`r06`) anchoring §5's
block-sequencing, `if`/`else if`, `match`/`cond` arm-boundary, and `let?`
placement rules; Task 4 added five more (`p12`–`p14`, `r07`–`r08`) anchoring
§6's nested-pattern/generic-type/atom-and-list-pattern claims and the
`PatRecord`/`PatAs` reachability findings; Task 5 added five more
(`p15`–`p17`, `r09`–`r10`) anchoring §8's multi-head-`fn`-merge,
`interface`/`impl`, and generic-type/record-variant claims, plus the
obsolete-`pub`-keyword and one-`mod`-per-file reachability/rejection
findings. A later pass (fully resolving §9's DSL declaration forms) added
eight more (`p18`–`p22`, `r11`–`r13`) anchoring `actor`/`supervise`,
`app`/`on_start`/`Supervisor.spec`, `protocol`/`choose`, `transitions`, and
the capability-directive forms. Two later passes added the §7.3 curried-call
juxtaposition witnesses (`p23`–`p24`, `r14`) and a slice-8 companion
(`p25`, the positive `let?`-block-fold parse witness for §5.4). Further
passes added the item-110 ECond witness (`p26`), the leading-`|`/single-line
`cond` fixes (`p27`–`p28`), and the item-700 `let?`-annotation error
(`r15`); as-patterns became reachable and retired `r08`, adding `p29`; and
record patterns became reachable and retired `r02`/`r07`, adding `p30`–`p31`,
**43 programs total (31 `parse/`, 12 `reject/`)** as of this pass.

**CI-wired** as a separate slow lane, `grammar-check` (`test/dune`), mirroring
the `types-check` alias `specs/lang/types/` already uses, not part of
`runtest`/`oracle`, run directly with `dune build @grammar-check`. The corpus
count is now guarded against drift by `scripts/check-docs.sh` Check C (which
covers this INDEX alongside the golden and types corpora), so the three
authoritative count sites in `grammar/INDEX.md` (title ranges, the
`currently N/N` run line, the `N programs total` footer) cannot silently
diverge from the on-disk file count again.

## Known parser findings

Building this chapter's conformance corpus surfaced two categories of fact
about the live parser that are worth collecting in one place rather than
leaving scattered across the sections that happened to surface them:

- **RESOLVED (2026-07-06): `f(1)(2)` is now a newline-sensitive parse
  error.** Previously, `f(1)(2)`-shaped chained calls were rejected only in
  operand/argument position (menhir's generic `I got stuck here`); in bare
  block-statement position (`let r = adder(1)(2)`) they silently mis-split
  into two unrelated statements with no diagnostic at all; the more
  surprising outcome. This has been fixed: a newline-sensitive guard in
  `lib/parser/token_filter.ml` rejects a `LPAREN` that immediately follows a
  **call's** closing `RPAREN` (no intervening newline) in *every* position,
  with `` `f(...)(...)` is not a chained call — March functions are not
  curried. `` The guard intentionally preserves the two legitimate `)(`
  shapes: an IIFE `(fn x -> x)(5)` (the `)` closes a group/lambda, not a
  call) and a two-line `f(1)⏎(g(2))` (the newline signals two statements).
  Full detail, including the three-piece filter state and the corpus
  witnesses (`reject/r14`, `parse/p23`, `parse/p24`), is in §7.3. This is
  the one compiler behaviour change from this finding; `parser.mly` is
  untouched.
- **`token_filter.ml`'s `is_pattern_start` predicate (§3.4) is a
  hand-maintained shadow of `parser.mly`'s `pattern`/`simple_pattern`/
  `soft_lower_name` first-token set, not a derived table**: a prior review
  on an earlier checkout found it already fallen out of sync (missing the
  `FLOAT` case and some soft-keyword cases). The live three-way cross-check
  performed while writing §3.4 found the predicate back **in sync** as of
  this pass, but the mechanism for keeping it that way is entirely manual
  discipline (grep `is_pattern_start` whenever `pattern`/`simple_pattern`/
  `soft_lower_name` changes); there is no test or generator tying the two
  together, so this is a standing hazard, not a one-time fact. This is the
  chapter's own namesake finding: "resolved, not transcribed" applies to
  `token_filter.ml` itself having an informal, driftable copy of part of
  the grammar living outside `parser.mly`.

`then`'s no-accepting-production status (§4.10) is a reachability *claim
this chapter makes and witnesses live*, not an open finding requiring
follow-up; it is listed here only for completeness of cross-reference,
not because it is unresolved. (`PatRecord` and `PatAs` were the same kind
of claim through 2026-07-23; both became reachable 2026-07-24 and are no
longer in this category, see §6.3.) The `f(1)(2)` entry in
`specs/todos/`'s "Grammar / lint contradictions (2026-07-03)" section is
now closed (moved to Done, 2026-07-06), see §7.3 for the fix.
