/* Contextual escapers for the ~H sigil.
 *
 * Each escaper corresponds to one parse context in
 * specs/security/html-contexts.tbl. The context is chosen at COMPILE time by
 * lib/ctxesc/automaton.ml and inlined as a constant id at the call site, so
 * nothing here ever inspects a value to decide what it is.
 *
 * CSS has two escapers because a style attribute alternates between two
 * positions with different syntax: a DECLARATION list (`color:red;...`), where
 * `:` and `;` are structural, and a VALUE (`#fff`, `var(--x)`), where either
 * would let the value start a new declaration. Both permit calls to an
 * allowlisted set of functions -- rejecting `var()` outright broke real
 * templates, and a denylist of `expression(`/`url(` is not credible.
 *
 * THE IDS BELOW MUST MATCH Context.escaper_id IN lib/ctxesc/context.ml.
 * That pairing is not covered by the generated-table drift check, so
 * test/test_ctx_escape.c asserts it explicitly against a copy of the OCaml
 * ordering. A mismatch would silently apply the WRONG escaper -- the worst
 * failure this component can have.
 */
#ifndef MARCH_CTX_ESCAPE_H
#define MARCH_CTX_ESCAPE_H

#include <stddef.h>

#define MARCH_ESC_HTML          0
#define MARCH_ESC_ATTR          1
#define MARCH_ESC_URL_COMPONENT 2
#define MARCH_ESC_URL_WHOLE     3
#define MARCH_ESC_CSS_VALUE     4
#define MARCH_ESC_JS_STRING     5
#define MARCH_ESC_NONE          6
#define MARCH_ESC_CSS_DECL      7
#define MARCH_ESC__COUNT        8

/* What a URL that failed the scheme allowlist is replaced with. Chosen to be
 * inert in every context: it navigates nowhere and executes nothing. */
#define MARCH_URL_UNSAFE_REPLACEMENT "about:invalid#zSoyz"

/* Escape [src, src+len) under [escaper_id], writing to [out].
 *
 * Two-pass by design: pass out=NULL to MEASURE (returns the byte count the
 * caller must allocate), then call again with a buffer of at least that size.
 * No allocation happens here, which is what lets the unit test link this file
 * on its own without the rest of the runtime.
 *
 * Returns the number of bytes written (or needed). Does NOT NUL-terminate.
 * An unknown escaper_id aborts rather than passing the value through: a bad id
 * means the emitter and the runtime disagree, and emitting unescaped output
 * would be the wrong way to fail. */
size_t march_ctx_escape(int escaper_id, const char *src, size_t len, char *out);

#endif /* MARCH_CTX_ESCAPE_H */
