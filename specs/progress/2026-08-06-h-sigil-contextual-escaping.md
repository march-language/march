# `~H` contextual auto-escaping

**Landed:** 2026-08-06
**Branch:** `feat/ctxesc-tables` (off `main` @ `37d1e166`)

Tasks 1–5 of `specs/plans/2026-08-05-contextual-autoescaping.md`, following
Samuel, Palmer, Summa & Grayson, *Compile-time Security Analysis and
Optimization of Sensitive String Producers* (arXiv:2605.16561v1).

## What was wrong

`~H` applied one escaper to every interpolation regardless of parse context.
Correct in element content, wrong everywhere else:

- `~H"<a href=\"${url}\">"` accepted `javascript:alert(1)` — entity-encoding
  does not touch a scheme.
- `~H"<div class=${cls}>"` — an unquoted attribute ends at the first space, so
  a value could start a new attribute.
- `~H"<script>var x = \"${d}\";</script>"` — HTML entities are the wrong codec
  entirely inside a script.

## How it works

`specs/security/html-contexts.tbl` is the source of truth: a declarative
transition table a security engineer can read without knowing OCaml.
`lib/ctxesc/` parses it, walks it, and selects an escaper from the resulting
context.

**The whole walk is compile-time.** The paper's load-bearing property is that an
interpolation is a single transition whose successor depends only on the
predecessor context, never on the interpolated value. Combined with `~H` having
no in-template control flow — no `if`/`for`, so no join points and no fixed
point — the context trajectory is fully determined by the literal chunks, which
are constants in the desugarer. Nothing survives to runtime but a direct escaper
call, so there is no per-render cost.

The escaper is derived from the *successor* context rather than named in a table
row, so the table cannot drift out of sync with the escaper set.

## Measured impact

The dry-run scanner (`lib/ctxesc/scan_templates.ml`) walks every `~H` in a
source tree and reports what the desugar would do. Against bastion + forgepm —
**121 templates, 253 holes**:

| escaper | holes | change |
|---|---|---|
| html | 213 | none |
| attr | 17 | + backtick |
| url_component | 14 | percent-encoded |
| css_value / css_decl | 7 | allowlist-filtered |
| url_whole | 2 | **scheme allowlist** |

**Zero would fail to compile.** Nothing in either codebase interpolates into an
attribute name, element name, or comment.

## Design decisions the plan did not anticipate

Every one of these came from measurement or from an earlier task's consequences,
not from the plan:

- **`ilit:` (case-insensitive literals)** is load-bearing. Without it
  `</SCRIPT>` walks past the raw-text exit rule and every hole after it is
  escaped as the wrong language.
- **URL position.** A hole at the start of an `href` *is* the whole URL and
  needs a scheme allowlist; after literal text it is a component needing
  percent-encoding. Expressed as a table transition (`url` → `urlmid`) rather
  than a fifth context field.
- **CSS position and a function allowlist.** Task 3's CSS escaper rejected every
  `(`, which I described as "deliberately strict". Measured against forgepm that
  was simply wrong: it destroyed `var(--text-muted)` (pages.march:336) and a
  whole declaration list (pages.march:714), neither malicious. Now split by CSS
  syntax position (declaration vs value, discriminated by `:` and `;`, not by
  offset) with an allowlisted function set. See
  `specs/progress/…` history in the branch for the full reasoning.
- **Already-safe HTML.** A nested `~H` partial is an `IOList` of trusted markup
  and must be inserted verbatim — but only when the surrounding context is HTML.
  An `IOList` spliced into an `href` is a context mismatch, so it is flattened
  and escaped for wherever it landed. Type-indexed trust (`Html.Trusted`) makes
  this precise in a later task.
- **Table embedding.** The desugarer needs the table at compile time and an
  installed `march` has no `specs/` directory, so `lib/ctxesc/dune` `cat`s the
  `.tbl` into a generated module. Drift is structurally impossible — dune
  regenerates from the source of truth every build — so the OCaml side needs no
  freshness check. The March-side copy still does (later task).

## Verification

- 28 OCaml tests over the *shipped* table (parser, automaton, escaper selection,
  substitution, rejections, terminal validity), **mutation-tested**: breaking
  `ilit:` or removing the URL demotion row makes the right tests fail.
- 61 C escaper checks, including six `javascript:` bypass variants (case,
  leading space, embedded tab/newline/control byte) and the two forgepm CSS
  regressions pinned verbatim by file:line.
- `test/native/h_escape_ctx_builtin.march` — compiled/interpreted golden diff.
  Parity is the property that matters: the ADT misread in
  `2026-08-05-h-sigil-adt-misread.md` stayed hidden because only compiled output
  was wrong.
- The OCaml↔C escaper-id pairing is asserted explicitly; it is the one
  cross-language contract no generated-table check covers, and a mismatch would
  silently apply the wrong escaper.

Suites: compiler 739, eval 256, codegen 546, stdlib 830 — all green except
`adversarial-regressions 40 MARCH_SANITIZE`, an ASAN timeout that is
environmental (a trivial `clang -fsanitize=address` program also hangs on this
host; CI's `sanitize-gate` passes).

Exactly one existing test needed updating: `~H sigil codegen / int interp
coerces arg to ptr` pinned `march_html_auto_escape` in the emitted IR. Its
intent — an `Int` must reach the escaper as a tagged ptr, never a raw `i64` —
is unchanged and now asserted against the new call shape, plus the contextual
decision itself (escaper id 0 in element content).

## Open

- The CSS **function allowlist** is a judgement call, modelled on Go's
  `html/template`. A function not on it degrades to strict escaping: visibly
  broken styling, at runtime only. Worth review.
- The 14 `url_component` holes were reasoned safe by reading the templates
  (package names and internal paths are unreserved characters), not by
  rendering them.
- Tasks 6–8 remain: context-indexed `Html.Trusted`, the March-side table copy
  plus its drift guard, and the full-corpus validation sweep.
