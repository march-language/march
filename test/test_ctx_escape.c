/* Unit tests for the contextual escapers (runtime/march_ctx_escape.c).
 *
 * Links march_ctx_escape.c ALONE -- no runtime, no allocator -- which is why
 * the escaper core works on plain buffers rather than march_strings.
 *
 * See specs/security/README.md for which escaper applies where, and
 * specs/plans/2026-08-05-contextual-autoescaping.md (Task 3) for the plan. */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "march_ctx_escape.h"

static int failures = 0;
static int checks = 0;

static char *esc(int id, const char *src) {
    size_t n = march_ctx_escape(id, src, strlen(src), NULL);
    char *out = (char *)malloc(n + 1);
    size_t m = march_ctx_escape(id, src, strlen(src), out);
    if (m != n) {
        printf("FAIL sizing pass disagreed with writing pass: %zu vs %zu\n", n, m);
        failures++;
    }
    out[m] = '\0';
    return out;
}

static void expect(int id, const char *src, const char *want, const char *what) {
    checks++;
    char *got = esc(id, src);
    if (strcmp(got, want) != 0) {
        printf("FAIL %s\n  input:    %s\n  expected: %s\n  actual:   %s\n",
               what, src, want, got);
        failures++;
    }
    free(got);
}

static void expect_absent(int id, const char *src, const char *needle,
                          const char *what) {
    checks++;
    char *got = esc(id, src);
    if (strstr(got, needle) != NULL) {
        printf("FAIL %s\n  input:  %s\n  output: %s\n  must not contain: %s\n",
               what, src, got, needle);
        failures++;
    }
    free(got);
}

int main(void) {
    /* ── id agreement with lib/ctxesc/context.ml ──────────────────────────
       Mirrors Context.escaper_id's ordering. If someone reorders that variant
       without touching this list, the wrong escaper would be applied silently.
       This is the one cross-language pairing the table drift check does NOT
       cover. */
    struct { int id; const char *name; } ids[] = {
        { MARCH_ESC_HTML,          "html" },
        { MARCH_ESC_ATTR,          "attr" },
        { MARCH_ESC_URL_COMPONENT, "url_component" },
        { MARCH_ESC_URL_WHOLE,     "url_whole" },
        { MARCH_ESC_CSS,           "css" },
        { MARCH_ESC_JS_STRING,     "js_string" },
        { MARCH_ESC_NONE,          "none" },
    };
    for (int i = 0; i < MARCH_ESC__COUNT; i++) {
        checks++;
        if (ids[i].id != i) {
            printf("FAIL escaper id drift: %s is %d, OCaml says %d\n",
                   ids[i].name, ids[i].id, i);
            failures++;
        }
    }

    /* ── HTML (PCDATA) ──────────────────────────────────────────────────── */
    expect(MARCH_ESC_HTML, "plain", "plain", "html passes plain text");
    expect(MARCH_ESC_HTML, "<b>&\"'", "&lt;b&gt;&amp;&quot;&#39;",
           "html escapes the five");
    expect(MARCH_ESC_HTML, "", "", "html handles empty");

    /* ── Attribute values ────────────────────────────────────────────────
       The backtick matters: old IE treated `x` as an attribute delimiter, so a
       value containing one could break out of a double-quoted attribute. */
    expect(MARCH_ESC_ATTR, "a\" onload=\"x", "a&quot; onload=&quot;x",
           "attr neutralises a quote breakout");
    expect_absent(MARCH_ESC_ATTR, "a`b", "`", "attr escapes the backtick");

    /* ── Whole-URL: the scheme allowlist ─────────────────────────────────
       This is the live `href` hole. Every variant below is a real bypass seen
       against naive filters: case, leading whitespace, embedded control
       characters, and a NUL-ish tab that browsers strip before parsing. */
    expect(MARCH_ESC_URL_WHOLE, "javascript:alert(1)",
           MARCH_URL_UNSAFE_REPLACEMENT, "url rejects javascript:");
    expect(MARCH_ESC_URL_WHOLE, "JaVaScRiPt:alert(1)",
           MARCH_URL_UNSAFE_REPLACEMENT, "url rejects mixed-case javascript:");
    expect(MARCH_ESC_URL_WHOLE, "  javascript:alert(1)",
           MARCH_URL_UNSAFE_REPLACEMENT, "url rejects leading-space javascript:");
    expect(MARCH_ESC_URL_WHOLE, "java\tscript:alert(1)",
           MARCH_URL_UNSAFE_REPLACEMENT, "url rejects tab-split javascript:");
    expect(MARCH_ESC_URL_WHOLE, "java\nscript:alert(1)",
           MARCH_URL_UNSAFE_REPLACEMENT, "url rejects newline-split javascript:");
    expect(MARCH_ESC_URL_WHOLE, "\x01javascript:alert(1)",
           MARCH_URL_UNSAFE_REPLACEMENT, "url rejects control-prefixed javascript:");
    expect(MARCH_ESC_URL_WHOLE, "data:text/html,<script>alert(1)</script>",
           MARCH_URL_UNSAFE_REPLACEMENT, "url rejects data:");
    expect(MARCH_ESC_URL_WHOLE, "vbscript:msgbox(1)",
           MARCH_URL_UNSAFE_REPLACEMENT, "url rejects vbscript:");

    expect(MARCH_ESC_URL_WHOLE, "https://example.com/a?b=c",
           "https://example.com/a?b=c", "url allows https");
    expect(MARCH_ESC_URL_WHOLE, "http://example.com", "http://example.com",
           "url allows http");
    expect(MARCH_ESC_URL_WHOLE, "mailto:a@b.example", "mailto:a@b.example",
           "url allows mailto");
    expect(MARCH_ESC_URL_WHOLE, "/relative/path", "/relative/path",
           "url allows a root-relative path");
    expect(MARCH_ESC_URL_WHOLE, "../up", "../up", "url allows a relative path");
    expect(MARCH_ESC_URL_WHOLE, "//cdn.example/x", "//cdn.example/x",
           "url allows scheme-relative");
    expect(MARCH_ESC_URL_WHOLE, "#frag", "#frag", "url allows a bare fragment");
    /* A colon AFTER the first path segment is not a scheme. */
    expect(MARCH_ESC_URL_WHOLE, "/a/b:c", "/a/b:c",
           "url allows a colon later in the path");
    /* Even an allowed URL must not break out of the attribute it sits in. */
    expect_absent(MARCH_ESC_URL_WHOLE, "https://e.com/\"onload=\"x", "\"",
           "url escapes quotes in an allowed URL");

    /* ── URL component (percent-encoding) ────────────────────────────────── */
    expect(MARCH_ESC_URL_COMPONENT, "a b", "a%20b", "component encodes space");
    expect(MARCH_ESC_URL_COMPONENT, "a&b=c", "a%26b%3Dc",
           "component encodes separators");
    expect(MARCH_ESC_URL_COMPONENT, "a/b", "a%2Fb", "component encodes slash");
    expect(MARCH_ESC_URL_COMPONENT, "aZ0-_.~", "aZ0-_.~",
           "component leaves unreserved alone");

    /* ── JS string ───────────────────────────────────────────────────────
       `</script` ends a script element even inside a JS string literal, and
       U+2028/U+2029 are line terminators in JS but not in JSON. */
    expect_absent(MARCH_ESC_JS_STRING, "</script>", "</script",
                  "js escapes a script close");
    expect_absent(MARCH_ESC_JS_STRING, "<!--", "<!--", "js escapes a comment open");
    expect(MARCH_ESC_JS_STRING, "a\"b", "a\\\"b", "js escapes a quote");
    expect(MARCH_ESC_JS_STRING, "a\\b", "a\\\\b", "js escapes a backslash");
    expect(MARCH_ESC_JS_STRING, "a\nb", "a\\nb", "js escapes a newline");
    expect(MARCH_ESC_JS_STRING, "\xe2\x80\xa8", "\\u2028", "js escapes U+2028");
    expect(MARCH_ESC_JS_STRING, "\xe2\x80\xa9", "\\u2029", "js escapes U+2029");

    /* ── CSS ─────────────────────────────────────────────────────────────── */
    expect(MARCH_ESC_CSS, "red", "red", "css passes an identifier");
    expect(MARCH_ESC_CSS, "#fff", "#fff", "css passes a hex colour");
    expect_absent(MARCH_ESC_CSS, "expression(alert(1))", "(",
                  "css neutralises expression()");
    expect_absent(MARCH_ESC_CSS, "a;color:red", ";", "css escapes a semicolon");
    expect_absent(MARCH_ESC_CSS, "url(javascript:x)", "(", "css escapes url(");
    expect_absent(MARCH_ESC_CSS, "a\"b", "\"", "css escapes a quote");

    /* ── None ────────────────────────────────────────────────────────────── */
    expect(MARCH_ESC_NONE, "<b>&", "<b>&", "none passes through verbatim");

    printf("%d checks, %d failures\n", checks, failures);
    return failures == 0 ? 0 : 1;
}
