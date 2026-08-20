# `~H` auto-escaping executed attacker JS in three contexts — FIXED

**Found:** 2026-08-20, during a pre-0.3.0 adversarial sweep.
**Fixed:** 2026-08-20, same day. Pre-release; no tagged version shipped it.

Reproduced first-hand on both backends before the fix; interpreted and
`--compile --opt 2` output was byte-identical, so this was a context-table /
automaton design gap, not a codegen bug.

`~H`'s promise is compile-time *contextual* auto-escaping: a `${hole}` is made
safe for the context it lands in. In the cases below it was not, and the result
was attacker-controlled script execution.

## What was wrong, and what it renders now

Probe values: `p = "alert(document.cookie)"`, `u = "javascript:alert(1)"`,
`h = "<img src=x onerror=alert(1)>"`, `j = "1 < 2 && 3 > 2"`.

| # | Template | Before | After |
|---|---|---|---|
| 1 | `<script>var x = ${p};</script>` | `var x = alert(document.cookie);` **XSS** | `var x = 'alert(document.cookie)';` |
| 2 | `<button onclick="n = ${p}">` | `onclick="n = alert(document.cookie)"` **XSS** | `onclick="n = 'alert(document.cookie)'"` |
| 3 | `<script>var x = "${s}";</script>` | `var x = "hello";` correct | unchanged |
| 4 | `<a href="${u}">` | `about:invalid#zSoyz` correct | unchanged |
| 5 | `<a xlink:href="${u}">` | `javascript:alert(1)` **XSS (SVG)** | `about:invalid#zSoyz` |
| 6 | `<object data="${u}">` | `javascript:alert(1)` **XSS** | `about:invalid#zSoyz` |
| 7 | `<a ping="${u}">` | `javascript:alert(1)` unvalidated fetch | `about:invalid#zSoyz` |
| 8 | `<iframe srcdoc="${h}">` | `&lt;img …&gt;` **XSS** (decoded, then parsed) | **compile error** |
| 9 | `<div>${h}</div>` | entity-encoded, correct | unchanged |
| 10 | `<script>var y = ${j};</script>` | `var y = 1 < 2 …` JS syntax error | `var y = '1 < 2 …';` valid JS |

Rows 3, 4 and 9 are the regression guard: they were already right, and the fix
had to leave them alone. It did.

## The three defects

### A. A hole in a bare-JS position got the JS *string* escaper

`escaper_for` in `lib/ctxesc/automaton.ml` mapped every script context to
`EscJsString`, and there was no JS sub-automaton distinguishing "inside a string
literal" from "expression position". The C comment even said "For a hole inside
a JS string literal" — nothing checked that it was.

`EscJsString` makes a value unable to END a string literal. At an expression
position the template opened no literal, so it was escaping delimiters that were
not delimiting anything: it escapes quotes and angle brackets, and does not
touch parens, dots, identifiers or `;`, so `alert(document.cookie)` passed
through intact. Row 10 is the same mismatch in the other direction — in
expression position the escaper corrupted legitimate arithmetic into a syntax
error. **The escaper was wrong for the position both ways, from one root cause.**

There was also no JS value escaper anywhere in the escaper set — the ability to
escape an expression-position hole correctly did not exist at all.

Row 2 is the same defect via `on*` handler attributes.

### B. The URL-attribute allowlist missed live vectors

`[attrs]` listed only `on* href src action formaction poster cite background
style`. `Tbl_parse.classify` is exact-match unless glob, so anything absent fell
to `*` → `normal` → `EscAttr`, which passes `javascript:` through untouched.
Confirmed live for `xlink:href` (executes in SVG), `object data` and `ping`.

### C. `srcdoc` was entity-escaped, which is not enough

`EscAttr` is correct *as an attribute*, but the browser HTML-decodes `srcdoc`
and then parses the result as a document, so `&lt;img …&gt;` decodes back to
live markup and fires.

## What shipped

### 1. A JS sub-automaton in the context table

`specs/security/html-contexts.tbl` now tracks JS position in both a `<script>`
body and an `on*` attribute, using the existing flat context tuple: `attr`
carries the position, and in a script body `delim` — free there, since no HTML
attribute surrounds it — carries the open string literal's quote.

New `attr` classes: `jsstring`, `jscomment`, `jsregex`, `jstemplate` (plus
`srcset` and `htmldoc` for defect C).

The block is arranged around one invariant, stated in the table itself:

> the walk must never land at `jsstring` when the hole is really in expression
> position.

That is the dangerous direction — it is defect A, reached by a different route.
The reverse costs an over-strict escaper or a compile error, both loud and
harmless. So every construct that can hide a stray quote is tracked: a comment
(`// don't`), a template literal (`` `it's` ``), and a regex literal (`/'/`).
Each would otherwise leave the quote count off by one and hand the NEXT hole the
string escaper while it sat in open code.

`jsregex` is entered by ANY `/` in expression position, because the table cannot
tell a regex from division without a JS parser. Deliberately biased: misreading
division as a regex costs a compile error; misreading a regex as division costs
a quote desynchronisation, which is unsafe.

### 2. A new escaper: `EscJsExpr` / `MARCH_ESC_JS_EXPR` (id 9)

There is no encoding that makes an arbitrary string safe as bare JS *code*, so
this escaper does not try. It stops the value being code: it supplies the quotes
the template did not and renders the value as a JS **string literal**. A payload
lands as inert data; honest input survives as text, which is also how row 10 got
fixed. This is what go's `html/template` and Closure Templates do in the same
position.

Both quote characters are escaped numerically (`"` / `'`), so the only
raw quotes in the output are the escaper's own two delimiters — which is what
lets ONE escaper serve a `<script>` body and a double-quoted `on*` attribute.

**The same numeric escaping was applied to `EscJsString`.** It previously emitted
`\"`, which still contains a raw `"` byte, and HTML has never heard of the
backslash — so a JS string inside `onclick="f('${x}')"` could end the attribute.
That was not exploitable, because escaping `=` stopped the escapee writing
`onerror=`, but relying on the second line of defence for the first one's failure
is not a position to stay in. Now "an escaped hole never emits a raw quote" holds
for every escaper without exception, which the corpus asserts as one sweep.

### 3. Rejections where no escaper would be honest

Compile errors, each carrying its reason: a hole inside a JS comment, regex
literal or template literal; a JS expression hole in a **single-quoted** `on*`
attribute (where `EscJsExpr`'s own `'` delimiters would end the attribute — use
a double-quoted attribute); `srcdoc`; and `srcset`.

### 4. Table contents

`xlink:href`, `data`, `ping`, `manifest`, `longdesc` → `url`. `data` is matched
EXACTLY, so the whole `data-*` family keeps the ordinary attribute escaper; the
conformance test pins that. `stdlib/html.march` carries a hand-written second
copy of these classifications for the deprecated `Html.tag`, and it was updated
in step, including a runtime refusal for `srcset` / `srcdoc`.

## Why NOT a compile-time rejection for expression position

The original write-up recommended rejecting a bare-JS hole outright. That was
the right instinct and it is not what shipped, for a reason found only by
reading the code:

**`Html.trust_js` exists, and its only meaningful position is exactly the one
that would be rejected.** `test/native/h_trusted_context.march:39` is
`~H"<script>${j}</script>"` with a `TrustedJs` value, and context-indexed trust
is resolved AFTER typechecking — in `lib/tir/llvm_emit.ml` for the compiled
backend and in `lib/eval/eval.ml` for the interpreter, both by matching the
value's type against the folded escaper id. The desugar, where a `.tbl`
diagnostic fires, has no types. It cannot tell a trusted value from an untrusted
one, so rejecting there would have deleted a shipped, golden-tested feature
inside a security patch.

Giving expression position its own escaper id solves it: `TrustedJs` now maps to
`[5; 9]`, so trusted JS still inserts verbatim (the golden is unchanged), while
an untrusted value is quoted into inertness.

The cost is honest and worth writing down: **a hole at a JS expression position
is now rendered as a string, not as the value's own JS type.**
`<script>var n = ${count}</script>` yields `'42'`, not `42`. That is a silent
change of meaning rather than a loud one. Making it loud needs the typechecker to
learn the `Trusted*` types so it can reject an untrusted value here and point at
`Html.trust_js` — recorded in
`specs/todos/2026-08-06-ctxesc-no-subsidiary-automata.md`.

## Why the existing tests did not catch it — and what was added

This is the part worth keeping.

The leaf escapers **were** adversarially tested: `test/test_ctx_escape.c` had
~90 checks with real payloads (`JaVaScRiPt:`, `java\tscript:`,
`\x01javascript:`, `data:text/html,<script>`, `expression()`, `</script>`,
U+2028, quote breakouts). `test/test_ctxesc.ml` asserted which escaper each
context SELECTS.

Both layers were green while row 1 executed. The escaper *was* the one the table
named, and it *did* escape exactly what it promised to. **The defect was the
pairing, and nothing anywhere put an attack string through a template and looked
at what came out.** `test/test_ctxesc.ml:229` went further and asserted the
buggy mapping — the bug written down as an expectation.

So the missing coverage class was added: a **rendered-output attack corpus** in
`test/test_ctxesc.ml`, 17 payloads × 21 accepting contexts, driven by a `render`
helper that is the desugar's own loop reduced to one hole. Four properties:

1. no escaped value emits a raw `<`, `>` or `"` (nor a `'`, except the JS
   expression escaper's own delimiters);
2. the paper's soundness property checked on real output — re-walking the
   escaped value must leave the parser's state, element and delimiter unchanged;
3. the rendered document still re-parses and still ends in a valid terminal
   state;
4. a JS expression hole is exactly one string literal.

Plus exact-output assertions for every row of the table above, and a reject
corpus that grew from three strings to nine.

**Non-vacuity was verified, and it changed the design of the tests.** Against a
control with `html-contexts.tbl` and `automaton.ml` reverted to their pre-fix
versions, 9 cases go red — including property 4 and every exact-output row.
Properties 1–3 stay GREEN against the pre-fix tree, which is worth knowing: the
original bug is *semantic*, not structural. The payload never moved the HTML
parser and never emitted a structural byte; it was simply admitted as code. A
structural invariant, however carefully stated, could not have caught this.
Property 4 and the exact-output rows are what carry the weight.

## Whose gap was this — the paper's, or ours? Ours.

`specs/todos/2026-08-06-ctxesc-no-subsidiary-automata.md` recorded that this
implementation matches the paper "on transition tables, the context tuple,
substitutions, terminal validity and diagnostics" and **diverges on exactly one
element: subsidiary automata** — *"Subsidiary automata handle processing of
nested content languages."* A JS sub-automaton is precisely what distinguishes
inside-a-string-literal from expression position.

Each nested language had been flattened into the `attr` field with hand-rolled
positions, and the refinement was very uneven: URL had two positions and two
escapers, CSS had three and three, **JS had one and one.**

The flattening was a deliberate, documented trade-off. **The miss was the risk
assessment.** That todo was rated `P3 — "a correctness/usability defect, not a
known vulnerability"`, and its "cost, measured" section reasoned through URL and
CSS only, concluding "not currently reachable" / "not exploitable as it stands".
It never analysed JS — the one nested language where the same divergence WAS
exploitable. A divergence from a security design is only as safe as its worst
instance, and the instance nobody examined is not evidence of safety. That file
has been re-rated and now carries this argument.

The attribute-allowlist gap (defect B) was not a model question at all — it was
table CONTENTS. `srcdoc` (defect C) is arguably a third instance of the
subsidiary-automata divergence, since HTML nested inside an HTML attribute is
exactly the codec case the paper describes; rejecting is the honest answer until
that exists.

## Files

- `specs/security/html-contexts.tbl` — JS sub-automaton, new URL attributes,
  rejections
- `specs/security/README.md` — JS positions, "What is rejected", known
  limitations; also corrected a stale pointer to an `emit_tables.exe` that was
  planned and never built
- `lib/ctxesc/context.ml` — 6 new `attr` classes, `EscJsExpr` (id 9), `describe`
- `lib/ctxesc/automaton.ml` — `escaper_for` splits the two JS positions
- `lib/ctxesc/escape.ml`, `runtime/march_ctx_escape.{c,h}` — the new escaper,
  and numeric quote escaping in the old one
- `lib/tir/llvm_emit.ml`, `lib/eval/eval.ml` — `TrustedJs` covers both JS ids
- `stdlib/html.march` — the second copy of `[attrs]`, and `Html.tag` refusals
- `test/test_ctxesc.ml`, `test/test_ctx_escape.c` — the corpus
