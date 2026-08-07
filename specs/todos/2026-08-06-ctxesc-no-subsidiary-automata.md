# `~H` has no subsidiary automata — nested languages are handled coarsely

**Filed:** 2026-08-06
**Priority:** P3 — a correctness/usability defect, not a known vulnerability

The contextual escaping in `specs/plans/2026-08-05-contextual-autoescaping.md`
matches the paper (Samuel et al., arXiv:2605.16561v1) on transition tables, the
context tuple, substitutions, terminal validity and diagnostics. It **diverges
on one element**: subsidiary automata.

## What the paper does

> "Subsidiary automata handle processing of nested content languages. Upon
> encountering `<a href=`, the HTML automaton spins up a URL parsing automaton
> and mediates its input via an HTML attribute codec."

The codec "decodes content as seen by the HTML automaton and re-encodes any
modifications made by the URL automaton", and the subsidiary relationship is
tracked alongside the context value.

## What we do instead

The nested language is flattened into the `attr` field of the 4-tuple
(`url` / `urlmid` / `style` / `stylevalue` / `script`), and the escaper does that
language's work in one shot. There is no separate automaton object and no codec.

Two positions instead of a real automaton: `url` → `urlmid` on the first literal
character, and `style` → `stylevalue` on a `:`. A real URL automaton would track
scheme / authority / path / query / fragment; a real CSS one would track far
more than declaration-vs-value.

## The cost, measured

The codec's absence turns out **not** to be exploitable, because the attribute
escaper escapes `&` after the URL check, so an entity cannot be decoded a second
time:

```
href="${'javascript&#58;alert(1)'}"  ->  href="javascript&amp;#58;alert(1)"
```

The coarseness does bite for a URL nested inside CSS:

```
style="background:url(${'/img/logo.png'})"
  -> url(\2F img\2F logo.png)          slashes escaped, legitimate URL BROKEN

<style>a{background:url(${'javascript:alert(1)'})}</style>
  -> url(javascript:alert\28 1\29 )    colon SURVIVES; only the parens escaped
```

The first is a plain usability defect: a legitimate relative URL in `url()` is
mangled.

The second is not exploitable as it stands — the escaped parens leave the JS
malformed, and current browsers do not execute `javascript:` in a CSS `url()` —
but the colon surviving is a smell, and it is there only because a `<style>`
body is treated as declaration position throughout, when inside `url(...)` it is
really a URL position.

**Not currently reachable.** Nothing in bastion or forgepm interpolates inside a
CSS `url()` — checked.

## Fix

Give `url(` a context of its own. Minimally: add `cssurl` to the `attr` field
with transitions `style|stylevalue --url(--> cssurl` and `cssurl --)--> back`,
and select the URL escaper there. That is a table change plus one escaper
mapping, and it uses machinery that already exists.

The full paper design — a real subsidiary automaton with a codec — is a larger
change and is only worth it if a nested language appears whose *position* matters
in ways the flat model cannot express. The `url(` case does not need it.

## Do not "fix" this by widening the CSS allowlist

Adding `/` to the CSS-safe character set would repair the broken-URL symptom and
reintroduce a hole: `/` is how a CSS comment (`/*`) starts. The escaper's
allowlist is deliberate — see `specs/security/README.md`.
