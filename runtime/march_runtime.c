#include "march_runtime.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ── Allocation ──────────────────────────────────────────────────────── */

void *march_alloc(int64_t sz) {
    void *p = calloc(1, (size_t)sz);
    if (!p) { fputs("march: out of memory\n", stderr); exit(1); }
    /* Initialize rc=1, tag=0, pad=0 */
    march_hdr *h = (march_hdr *)p;
    h->rc  = 1;
    h->tag = 0;
    h->pad = 0;
    return p;
}

/* ── Reference counting ──────────────────────────────────────────────── */

void march_incrc(void *p) {
    if (!p) return;
    ((march_hdr *)p)->rc++;
}

void march_decrc(void *p) {
    if (!p) return;
    march_hdr *h = (march_hdr *)p;
    if (--h->rc <= 0) free(p);
}

void march_free(void *p) {
    free(p);
}

/* ── Strings ─────────────────────────────────────────────────────────── */

/* march_string layout: [rc:i64][len:i64][data:char*] */
void *march_string_lit(const char *utf8, int64_t len) {
    march_string *s = malloc(sizeof(march_string) + (size_t)len + 1);
    if (!s) { fputs("march: out of memory\n", stderr); exit(1); }
    s->rc  = 1;
    s->len = len;
    memcpy(s->data, utf8, (size_t)len);
    s->data[len] = '\0';
    return s;
}

void *march_int_to_string(int64_t n) {
    char buf[32];
    int len = snprintf(buf, sizeof(buf), "%lld", (long long)n);
    return march_string_lit(buf, len);
}

void *march_float_to_string(double f) {
    char buf[64];
    int len = snprintf(buf, sizeof(buf), "%g", f);
    return march_string_lit(buf, len);
}

void *march_bool_to_string(int64_t b) {
    return b ? march_string_lit("true", 4) : march_string_lit("false", 5);
}

void *march_string_concat(void *a, void *b) {
    march_string *sa = (march_string *)a;
    march_string *sb = (march_string *)b;
    int64_t total = sa->len + sb->len;
    march_string *s = malloc(sizeof(march_string) + (size_t)total + 1);
    if (!s) { fputs("march: out of memory\n", stderr); exit(1); }
    s->rc  = 1;
    s->len = total;
    memcpy(s->data, sa->data, (size_t)sa->len);
    memcpy(s->data + sa->len, sb->data, (size_t)sb->len);
    s->data[total] = '\0';
    return s;
}

int64_t march_string_eq(void *a, void *b) {
    march_string *sa = (march_string *)a;
    march_string *sb = (march_string *)b;
    return sa->len == sb->len && memcmp(sa->data, sb->data, (size_t)sa->len) == 0 ? 1 : 0;
}

/* ── I/O ─────────────────────────────────────────────────────────────── */

void march_print(void *s) {
    march_string *ms = (march_string *)s;
    fwrite(ms->data, 1, (size_t)ms->len, stdout);
}

void march_println(void *s) {
    march_string *ms = (march_string *)s;
    fwrite(ms->data, 1, (size_t)ms->len, stdout);
    putchar('\n');
}
