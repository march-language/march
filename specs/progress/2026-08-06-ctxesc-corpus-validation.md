# Task 8 — corpus validation of `~H` contextual escaping

**Date:** 2026-08-06
**Corpora:** `bastion/lib`, `forgepm/lib` — 121 templates, 253 interpolations

Task 8 of `specs/plans/2026-08-05-contextual-autoescaping.md`. Two claims from
Tasks 3–5 rested on reading rather than rendering; this settles both with
evidence.

## Method

The plan assumed forgepm could be built against the compiler. It cannot — 68
pre-existing errors from bastion version drift, unrelated to this work. But
building it was never the goal; *rendering before and after* was.

`lib/ctxesc/scan_templates.ml --diff` does that directly. It already walks every
`~H` template through the automaton and knows each hole's escaper, so it renders
each hole **both ways** — as `~H` used to (HTML entity-encode everything,
regardless of context) and as it does now — against probe values chosen to be
**realistic for the position**, not adversarial. Attack cases are already covered
by `test/test_ctx_escape.c`; the question here is the opposite one: does the new
behaviour mangle anything legitimate?

## Result

40 of 253 holes get a different escaper. **Zero produce different rendered output
for values these applications can actually produce**, with one wire-format
exception.

### CSS — zero diffs

`var(--text-muted)`, `transparent`, `#22d3ee`, `inline-block`, and the full
declaration list `border:1px solid rgba(34,211,238,0.35);background:transparent`
all render identically before and after.

This is the claim that most needed checking: Task 3's original CSS escaper broke
two of these, and `2333523e` fixed it. Confirmed fixed by rendering, not by
reading the diff.

### URL component — zero diffs in practice

All 14 holes are path segments, and every value is validated by forgepm itself:

| hole | value | rule | RFC 3986 |
|---|---|---|---|
| `/packages/${pkg.name}` ×4 | package name | `^[a-z0-9][a-z0-9-]*[a-z0-9]$` | all unreserved |
| `/users/${author}` | username | `^[a-z0-9][a-z0-9_-]*[a-z0-9]$` | all unreserved |
| `/orgs/${o.handle}` ×2 | org handle | lowercase, digits, `-`, `_` | all unreserved |
| `?tab=${name}` | tab name | source literal | unreserved |
| `?after=${last.id}` | integer id | digits | unreserved |
| `${path}?${param_name}=` | source literal | — | unreserved |

Percent-encoding is a **no-op** on every one. The scanner does report diffs for
`a b` → `a%20b` and `x/y` → `x%2Fy`, which is the escaper working as designed —
but no validated value can contain a space or a slash.

**One near-miss worth recording.** Versions allow `+`
(`^[0-9]+\.[0-9]+\.[0-9]+[-+0-9A-Za-z.]*$`), which *would* encode:
`1.2.3+build` → `1.2.3%2Bbuild`. No version reaches a URL context in forgepm —
they appear in element content (`<span>${pkg.version}</span>`), which is
unchanged. If a future route interpolates a version into an `href`, that is the
case to check.

### Whole URL — zero diffs

`/packages/bastion`, `/admin/users`, `#frag`, `https://example.com/a?b=c`,
`/x?a=b&c=d` all render identically. The scheme allowlist does not disturb
legitimate URLs; it only changes output for a URL that would have been an
injection.

### Attribute — one wire-format difference

The backtick: `back` + backtick + `tick` → `back&#96;tick`. Deliberate — old IE
accepted a backtick as an attribute delimiter, so a value containing one could
break out of a double-quoted attribute. It entity-decodes to the same character
in a browser, so there is **no visible change**, only a different byte sequence
on the wire.

Worth knowing for anyone diffing raw HTTP responses across this change.

## What this does and does not establish

**Does:** for these two codebases, contextual escaping changes which escaper runs
without changing what a user sees — except where it is neutralising an
injection.

**Does not:** prove the escapers are right in general. It proves they do not
regress *this* corpus. A codebase that interpolates a value containing `/`, a
space, or `+` into a URL component, or a CSS function outside the allowlist,
would see real changes. The `--diff` mode is the tool to check that before
adopting.

The CSS function allowlist remains the judgement call flagged in #202: a function
not on it degrades to strict escaping — visibly broken styling, at runtime only.
Nothing in either corpus hits it.
