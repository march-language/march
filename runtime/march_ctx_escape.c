/* Contextual escapers for the ~H sigil. See march_ctx_escape.h for the
 * two-pass calling convention and the id contract, and
 * specs/security/README.md for which escaper applies in which parse context.
 *
 * Deliberately free of runtime dependencies (no allocator, no march_string) so
 * test/test_ctx_escape.c can link it on its own. */

#include "march_ctx_escape.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Small append helper. [out] may be NULL, in which case we only count. */
typedef struct { char *out; size_t n; } sink;

static void put(sink *s, const char *bytes, size_t len) {
    if (s->out) memcpy(s->out + s->n, bytes, len);
    s->n += len;
}

static void put1(sink *s, char c) {
    if (s->out) s->out[s->n] = c;
    s->n += 1;
}

static void put_str(sink *s, const char *z) { put(s, z, strlen(z)); }

static void put_hex2(sink *s, unsigned char c) {
    static const char hexd[] = "0123456789ABCDEF";
    put1(s, hexd[(c >> 4) & 0xF]);
    put1(s, hexd[c & 0xF]);
}

static int is_unreserved(unsigned char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
        || (c >= '0' && c <= '9')
        || c == '-' || c == '_' || c == '.' || c == '~';
}

/* ── HTML / attribute ─────────────────────────────────────────────────────
 * The backtick is escaped in attribute values because old IE accepted it as an
 * attribute delimiter, so a value containing one could break out of a
 * double-quoted attribute. It is harmless to escape it in PCDATA too, but we
 * keep the two distinct so the PCDATA output stays minimal. */
static void esc_html_like(sink *s, const char *src, size_t len, int attr) {
    for (size_t i = 0; i < len; i++) {
        char c = src[i];
        switch (c) {
        case '&':  put_str(s, "&amp;"); break;
        case '<':  put_str(s, "&lt;"); break;
        case '>':  put_str(s, "&gt;"); break;
        case '"':  put_str(s, "&quot;"); break;
        case '\'': put_str(s, "&#39;"); break;
        case '`':
            if (attr) put_str(s, "&#96;"); else put1(s, c);
            break;
        default: put1(s, c);
        }
    }
}

/* ── URL component ─────────────────────────────────────────────────────── */
static void esc_url_component(sink *s, const char *src, size_t len) {
    for (size_t i = 0; i < len; i++) {
        unsigned char c = (unsigned char)src[i];
        if (is_unreserved(c)) put1(s, (char)c);
        else { put1(s, '%'); put_hex2(s, c); }
    }
}

/* ── Whole URL ─────────────────────────────────────────────────────────────
 * A hole at the start of a url attribute IS the whole URL, so the value can
 * choose its own scheme. Only an allowlist is safe here: `javascript:` and
 * `data:` both execute.
 *
 * Browsers strip leading whitespace and C0 control characters before parsing a
 * URL, and ignore them *within* a scheme. So `java\tscript:` and
 * `  javascript:` are both live vectors against a naive prefix check. We
 * therefore extract the candidate scheme by skipping those bytes entirely,
 * rather than comparing a prefix of the raw input.
 *
 * A colon only introduces a scheme if everything before it looks like one
 * (ALPHA *( ALPHA / DIGIT / "+" / "-" / "." )). `/a/b:c` has a slash first, so
 * it is a path, not a scheme -- which is why we stop at the first `/`, `?` or
 * `#`. */
static int url_scheme_is_allowed(const char *src, size_t len) {
    char scheme[16];
    size_t n = 0;
    for (size_t i = 0; i < len; i++) {
        unsigned char c = (unsigned char)src[i];
        /* skip bytes a browser would ignore while reading the scheme */
        if (c <= 0x20 || c == 0x7F) continue;
        if (c == ':') {
            if (n == 0) return 0;  /* ":" with no scheme -- not a URL we know */
            scheme[n] = '\0';
            return strcmp(scheme, "http") == 0
                || strcmp(scheme, "https") == 0
                || strcmp(scheme, "mailto") == 0
                || strcmp(scheme, "tel") == 0
                || strcmp(scheme, "ftp") == 0;
        }
        /* Anything that ends the scheme means there was none: the value is a
           relative reference (path, query or fragment), which is safe. */
        if (c == '/' || c == '?' || c == '#') return 1;
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
              || (c >= '0' && c <= '9')
              || c == '+' || c == '-' || c == '.')) {
            /* not scheme-shaped, so this cannot be a scheme -- relative */
            return 1;
        }
        if (n >= sizeof(scheme) - 1) return 0;  /* absurdly long: reject */
        scheme[n++] = (char)(c >= 'A' && c <= 'Z' ? c - 'A' + 'a' : c);
    }
    return 1;  /* no colon at all -- relative reference */
}

static void esc_url_whole(sink *s, const char *src, size_t len) {
    if (!url_scheme_is_allowed(src, len)) {
        put_str(s, MARCH_URL_UNSAFE_REPLACEMENT);
        return;
    }
    /* An allowed URL still sits inside an attribute, so it must not be able to
       close it. Escape the HTML-significant bytes and leave the rest -- we
       must NOT percent-encode here, or every legitimate `?a=b&c=d` would
       break. */
    esc_html_like(s, src, len, 1);
}

/* ── JS string ─────────────────────────────────────────────────────────────
 * For a hole inside a JS string literal. Beyond the usual escapes:
 *  - `</script` ends the element even inside a string literal, and `<!--`
 *    starts an HTML comment that some parsers honour inside <script>; both are
 *    neutralised by escaping `<` and `>`.
 *  - U+2028 and U+2029 are line terminators in JS but legal inside a JSON
 *    string, so a JSON-safe encoder is not JS-safe. */
static void esc_js_string(sink *s, const char *src, size_t len) {
    for (size_t i = 0; i < len; i++) {
        unsigned char c = (unsigned char)src[i];
        /* U+2028 / U+2029 arrive as UTF-8 E2 80 A8 / E2 80 A9 */
        if (c == 0xE2 && i + 2 < len
            && (unsigned char)src[i + 1] == 0x80
            && ((unsigned char)src[i + 2] == 0xA8
                || (unsigned char)src[i + 2] == 0xA9)) {
            put_str(s, (unsigned char)src[i + 2] == 0xA8 ? "\\u2028" : "\\u2029");
            i += 2;
            continue;
        }
        switch (c) {
        case '"':  put_str(s, "\\\""); break;
        case '\'': put_str(s, "\\'"); break;
        case '\\': put_str(s, "\\\\"); break;
        case '\n': put_str(s, "\\n"); break;
        case '\r': put_str(s, "\\r"); break;
        case '\t': put_str(s, "\\t"); break;
        case '<':  put_str(s, "\\u003c"); break;
        case '>':  put_str(s, "\\u003e"); break;
        case '&':  put_str(s, "\\u0026"); break;
        case '=':  put_str(s, "\\u003d"); break;
        default:
            if (c < 0x20) { put_str(s, "\\u00"); put_hex2(s, c); }
            else put1(s, (char)c);
        }
    }
}

/* ── CSS ───────────────────────────────────────────────────────────────────
 * Allowlist rather than denylist: CSS has too many ways to reach a URL or an
 * expression for a blocklist to be credible. Anything outside a small safe set
 * becomes a `\XX ` hex escape, which CSS reads as a literal character and
 * which can never re-open a construct. */
static void esc_css(sink *s, const char *src, size_t len) {
    for (size_t i = 0; i < len; i++) {
        unsigned char c = (unsigned char)src[i];
        if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
            || (c >= '0' && c <= '9')
            || c == '-' || c == '_' || c == '#' || c == '%' || c == '.'
            || c == ',' || c == ' ') {
            put1(s, (char)c);
        } else {
            put1(s, '\\');
            put_hex2(s, c);
            put1(s, ' ');  /* terminate the escape so the next char is literal */
        }
    }
}

size_t march_ctx_escape(int escaper_id, const char *src, size_t len, char *out) {
    sink s = { out, 0 };
    switch (escaper_id) {
    case MARCH_ESC_HTML:          esc_html_like(&s, src, len, 0); break;
    case MARCH_ESC_ATTR:          esc_html_like(&s, src, len, 1); break;
    case MARCH_ESC_URL_COMPONENT: esc_url_component(&s, src, len); break;
    case MARCH_ESC_URL_WHOLE:     esc_url_whole(&s, src, len); break;
    case MARCH_ESC_CSS:           esc_css(&s, src, len); break;
    case MARCH_ESC_JS_STRING:     esc_js_string(&s, src, len); break;
    case MARCH_ESC_NONE:          put(&s, src, len); break;
    default:
        /* An id the runtime does not know means the emitter and the runtime
           disagree. Passing the value through unescaped would be the wrong way
           to fail. */
        fprintf(stderr,
                "march_ctx_escape: unknown escaper id %d (valid 0..%d). The "
                "emitter in lib/tir and runtime/march_ctx_escape.h have "
                "diverged.\n",
                escaper_id, MARCH_ESC__COUNT - 1);
        abort();
    }
    return s.n;
}
