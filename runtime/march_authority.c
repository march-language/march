/* The run-time authority's policy in C, for native and JIT programs (ocap
 * phase 4, Task 4b: specs/plans/2026-11-15-ocap-p4-runtime-plan.md).
 *
 * stdlib/authority.march defines the policy: the scope parser (the `needs`
 * surface grammar), `admits`, `subset`, the layered check and the launch
 * validation.  The interpreter and the JS target run that March code.  A
 * native or JIT program instead calls the functions below: the compiler
 * retargets every direct call of those Authority functions to these builtins
 * (lib/tir/auth_native.ml), so a compiled program links no March matcher or
 * parser, only these few symbols in the precompiled runtime.
 *
 *   Authority.parse        march_cap_rt_parse
 *   Authority.admits       march_cap_rt_admits
 *   Authority.subset       march_cap_rt_subset
 *   Authority.frame_layer  march_cap_rt_frame_layer
 *   Authority.launch_init  march_cap_rt_launch_init
 *   Authority.check_layers march_cap_rt_check_layers
 *   Authority.check_slow   march_cap_rt_check_slow   (Authority.check's slow path)
 *
 * Every function here is a line-for-line port of its March original and
 * must give the same answer and the same text (decision 4: launch errors are
 * byte-identical in every runtime).  test/test_authority_differential.ml runs
 * the same rows through the March policy (interpreted), this one (compiled)
 * and lib/caps, and requires all three to agree.
 *
 * Values.  The layers in the authority slot keep the March shapes
 * (Authority.Layer / CapEntry / Arg, CapLimit): March code pattern-matches
 * `cap_layers()` (Authority.enter_fn), and march_cap_release /
 * march_cap_immortalize walk them by tag.  So the values this file builds are
 * ordinary March values, tags as declared:
 *   List(a)   Nil = 0 | Cons(a, List(a)) = 1          Result  Ok = 0 | Err = 1
 *   Authority.Layer  Layer(CapLimit, String, List(CapEntry))  = 0
 *   Authority.CapEntry  CapEntry(String, Arg)                = 0
 *   Authority.Arg    Any = 0 | Paths(List(String)) = 1 | Hosts(String) = 2
 *                    | Names(List(String), List(String)) = 3
 *                    | HostAt(String, String, Bool, Int) = 4 | PathsAt(List(String)) = 5
 *   CapLimit         ByLaunch = 0 | ByFnNeeds(String) = 1 | ...
 *   CapError         CapError(String, String, CapLimit, String) = 0
 * Bool and Int fields are raw 64-bit words.  The retargeting pass falls back
 * to the March policy when a program declares a type whose short name
 * collides with one of these (such a type takes global constructor tags).
 *
 * Arguments are borrowed (lib/tir/borrow.ml): a value stored into a result
 * is incref'd.  Results are owned. */

#include "march_runtime.h"
#include "march_authority_tables.h"
#include <stdatomic.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* Size over speed: this file is linked into every binary that does a
 * capability operation, its parser runs once per launch and once per framed
 * function, and a check walks a few short lists.  minsize keeps a printing
 * program small (test/test_authority_differential.ml, authority_size). */
#pragma clang attribute push (__attribute__((minsize)), apply_to = function)

/* march_runtime.c / march_scheduler.c */
extern _Atomic(void *) march_cap_launch;
void **march_sched_auth_slot(void);

/* ── Scratch memory: one arena per top-level call ─────────────────────── */

/* The first 2 KB live in the arena itself (on the caller's stack), so a
 * check allocates nothing on the heap; larger requests fall back to malloc. */
typedef struct ablk { struct ablk *next; } ablk;
typedef struct { ablk *head; size_t used; _Alignas(16) char buf[2048]; } arena;

static void ar_init(arena *a) { a->head = NULL; a->used = 0; }

static void *ar_alloc(arena *a, size_t n) {
    size_t need = (n + 15) & ~(size_t)15;
    if (need == 0) need = 16;
    if (a->used + need <= sizeof a->buf) {
        void *p = a->buf + a->used;
        a->used += need;
        return p;
    }
    ablk *b = (ablk *)malloc(sizeof(ablk) + 16 + need);
    if (b == NULL) abort();
    b->next = a->head;
    a->head = b;
    return (void *)((char *)b + 16);
}

static void ar_free(arena *a) {
    ablk *b = a->head;
    while (b) { ablk *n = b->next; free(b); b = n; }
    a->head = NULL;
    a->used = 0;
}

/* ── String views ─────────────────────────────────────────────────────── */

typedef struct { const char *p; int64_t n; } sv;

static sv sv_m(void *s) {
    march_string *m = (march_string *)s;
    sv r = { m->data, m->len };
    return r;
}
static sv sv_z(const char *z) { sv r = { z, (int64_t)strlen(z) }; return r; }
static int sv_eq(sv a, sv b) { return a.n == b.n && (a.n == 0 || memcmp(a.p, b.p, (size_t)a.n) == 0); }
static int sv_eqz(sv a, const char *z) { return sv_eq(a, sv_z(z)); }
static int sv_starts(sv a, sv b) { return a.n >= b.n && (b.n == 0 || memcmp(a.p, b.p, (size_t)b.n) == 0); }
static int sv_startsz(sv a, const char *z) { return sv_starts(a, sv_z(z)); }
static int sv_ends(sv a, sv b) {
    return a.n >= b.n && (b.n == 0 || memcmp(a.p + a.n - b.n, b.p, (size_t)b.n) == 0);
}
static int sv_abs(sv a) { return a.n > 0 && a.p[0] == '/'; }
/* string_slice: byte offsets, clamped. */
static sv sv_sub(sv a, int64_t i, int64_t n) {
    if (i < 0) i = 0;
    if (i > a.n) i = a.n;
    if (n < 0) n = 0;
    if (i + n > a.n) n = a.n - i;
    sv r = { a.p + i, n };
    return r;
}
static sv sv_from(sv a, int64_t i) { return sv_sub(a, i, a.n - i); }
static int64_t sv_find(sv a, char c) {
    for (int64_t i = 0; i < a.n; i++) if (a.p[i] == c) return i;
    return -1;
}
static int64_t sv_rfind(sv a, char c) {
    for (int64_t i = a.n - 1; i >= 0; i--) if (a.p[i] == c) return i;
    return -1;
}
static int sv_has(sv a, char c) { return sv_find(a, c) >= 0; }
static int sv_contains(sv a, sv b) {
    if (b.n == 0) return 1;
    for (int64_t i = 0; i + b.n <= a.n; i++)
        if (memcmp(a.p + i, b.p, (size_t)b.n) == 0) return 1;
    return 0;
}
/* all_chars: every byte of [a] is in [allowed] (true for ""). */
static int sv_all(sv a, const char *allowed) {
    for (int64_t i = 0; i < a.n; i++)
        if (a.p[i] == '\0' || strchr(allowed, a.p[i]) == NULL) return 0;
    return 1;
}
static char lower_c(char c) { return (c >= 'A' && c <= 'Z') ? (char)(c - 'A' + 'a') : c; }
static sv sv_lower(arena *ar, sv a) {
    char *d = (char *)ar_alloc(ar, (size_t)a.n);
    for (int64_t i = 0; i < a.n; i++) d[i] = lower_c(a.p[i]);
    sv r = { d, a.n };
    return r;
}

/* ── Growable buffers ─────────────────────────────────────────────────── */

typedef struct { char *p; int64_t n, cap; } sbuf;

static void sb_add(sbuf *b, sv s) {
    if (b->n + s.n + 1 > b->cap) {
        int64_t c = b->cap ? b->cap : 64;
        while (b->n + s.n + 1 > c) c *= 2;
        b->p = (char *)realloc(b->p, (size_t)c);
        if (b->p == NULL) abort();
        b->cap = c;
    }
    if (s.n) memcpy(b->p + b->n, s.p, (size_t)s.n);
    b->n += s.n;
    b->p[b->n] = '\0';
}
static void sb_addz(sbuf *b, const char *z) { sb_add(b, sv_z(z)); }
static void sb_addc(sbuf *b, char c) { sv s = { &c, 1 }; sb_add(b, s); }
static sv sb_sv(const sbuf *b) { sv r = { b->p ? b->p : "", b->n }; return r; }
static void sb_free(sbuf *b) { free(b->p); b->p = NULL; b->n = b->cap = 0; }
/* The buffer's text copied into [ar]. */
static sv sb_keep(arena *ar, sbuf *b) {
    char *d = (char *)ar_alloc(ar, (size_t)b->n);
    if (b->n) memcpy(d, b->p, (size_t)b->n);
    sv r = { d, b->n };
    sb_free(b);
    return r;
}

/* A list of string views, its storage in the arena. */
typedef struct { sv *v; int n, cap; } svl;

static void svl_push(arena *ar, svl *l, sv s) {
    if (l->n == l->cap) {
        int c = l->cap ? l->cap * 2 : 8;
        sv *nv = (sv *)ar_alloc(ar, sizeof(sv) * (size_t)c);
        if (l->n) memcpy(nv, l->v, sizeof(sv) * (size_t)l->n);
        l->v = nv;
        l->cap = c;
    }
    l->v[l->n++] = s;
}
/* string_split on a one-byte separator ("" splits to [""]). */
static svl sv_split(arena *ar, sv s, char sep) {
    svl l = { 0 };
    int64_t start = 0;
    for (int64_t i = 0; i < s.n; i++)
        if (s.p[i] == sep) { svl_push(ar, &l, sv_sub(s, start, i - start)); start = i + 1; }
    svl_push(ar, &l, sv_from(s, start));
    return l;
}
static int svl_mem(svl l, sv x) {
    for (int i = 0; i < l.n; i++) if (sv_eq(l.v[i], x)) return 1;
    return 0;
}
/* [pre] (may be "") then the elements of [l] joined by [sep], in [ar]. */
static sv svl_join_pre(arena *ar, const char *pre, svl l, const char *sep) {
    size_t pn = strlen(pre), sn = strlen(sep), total = pn;
    for (int i = 0; i < l.n; i++) total += (size_t)l.v[i].n + (i ? sn : 0);
    char *d = (char *)ar_alloc(ar, total);
    size_t k = 0;
    memcpy(d, pre, pn); k = pn;
    for (int i = 0; i < l.n; i++) {
        if (i) { memcpy(d + k, sep, sn); k += sn; }
        if (l.v[i].n) memcpy(d + k, l.v[i].p, (size_t)l.v[i].n);
        k += (size_t)l.v[i].n;
    }
    sv r = { d, (int64_t)total };
    return r;
}
static sv svl_join(arena *ar, svl l, const char *sep) { return svl_join_pre(ar, "", l, sep); }

/* ── The lattice and the kinds of scope (generated tables) ────────────── */

static sv lattice_parent(sv k) {
    for (int i = 0; i < MARCH_AUTH_N_PARENTS; i++)
        if (k.n == march_auth_parent_table[i].kind_len
            && memcmp(k.p, march_auth_parent_table[i].kind, (size_t)k.n) == 0) {
            sv r = { march_auth_parent_table[i].parent, march_auth_parent_table[i].parent_len };
            return r;
        }
    sv none = { "", 0 };
    return none;
}
#define in_table(t, k) in_table_((const void *)(t), sizeof((t)[0]), (k))
/* A kind table (a NULL-terminated array of {name, length}) contains [k]. */
static int in_table_(const void *table, size_t stride, sv k) {
    for (const char *row = (const char *)table;; row += stride) {
        const char *name = *(const char *const *)row;
        int len = *(const int *)(row + sizeof(const char *));
        if (name == NULL) return 0;
        if (k.n == len && memcmp(k.p, name, (size_t)len) == 0) return 1;
    }
}
static int path_kind(sv k) { return in_table(march_auth_path_kinds, k); }
static int host_kind(sv k) { return in_table(march_auth_host_kinds, k); }
static int name_kind(sv k) { return in_table(march_auth_name_kinds, k); }

/* kind_subsumes(parent, child): parent is child or a lattice ancestor. */
static int kind_subsumes(sv parent, sv child) {
    for (int depth = 0; depth < 64; depth++) {
        if (sv_eq(parent, child)) return 1;
        child = lattice_parent(child);
        if (child.n == 0) return 0;
    }
    return 0;
}

/* ── Paths ─────────────────────────────────────────────────────────────── */

/* segments: `.` and empty segments dropped, `..` folded (dropped at the root). */
static svl segments(arena *ar, sv p) {
    svl parts = sv_split(ar, p, '/');
    svl acc = { 0 };
    for (int i = 0; i < parts.n; i++) {
        sv s = parts.v[i];
        if (s.n == 0 || sv_eqz(s, ".")) continue;
        if (sv_eqz(s, "..")) { if (acc.n > 0) acc.n--; continue; }
        svl_push(ar, &acc, s);
    }
    return acc;
}
static sv normalize(arena *ar, sv p) {
    return svl_join_pre(ar, sv_abs(p) ? "/" : "", segments(ar, p), "/");
}
static sv resolve(arena *ar, sv cwd, sv p) {
    if (sv_abs(p)) return p;
    char *d = (char *)ar_alloc(ar, (size_t)(cwd.n + 1 + p.n));
    if (cwd.n) memcpy(d, cwd.p, (size_t)cwd.n);
    d[cwd.n] = '/';
    if (p.n) memcpy(d + cwd.n + 1, p.p, (size_t)p.n);
    sv r = { d, cwd.n + 1 + p.n };
    return r;
}
static int segs_prefix(svl pre, svl segs) {
    if (pre.n > segs.n) return 0;
    for (int i = 0; i < pre.n; i++) if (!sv_eq(pre.v[i], segs.v[i])) return 0;
    return 1;
}
/* [n] is within [p], both normalized: the same absoluteness, and [p] has no
 * segment (`/`, or "" for a relative path), or [n] is [p], or [p] followed
 * by `/`.  The answer segment-by-segment comparison gives, by comparing
 * strings. */
static int norm_within(sv p, sv n) {
    if (sv_abs(p) != sv_abs(n)) return 0;
    if (p.n == 0 || (p.n == 1 && p.p[0] == '/')) return 1;
    return sv_starts(n, p) && (n.n == p.n || n.p[p.n] == '/');
}
/* path_within(scope, p): segment-wise, whatever the two are written as. */
static int path_within(arena *ar, sv scope, sv p) {
    return norm_within(normalize(ar, scope), normalize(ar, p));
}

/* ── Hosts ─────────────────────────────────────────────────────────────── */

static sv normalize_host(arena *ar, sv h) {
    sv l = sv_lower(ar, h);
    if (l.n > 0 && l.p[l.n - 1] == '.') l.n--;
    return l;
}

/* A port 1-65535 written in at most 5 digits, else 0. */
static int64_t port_or_zero(sv s) {
    if (s.n == 0 || s.n > 5 || !sv_all(s, "0123456789")) return 0;
    int64_t n = 0;
    for (int64_t i = 0; i < s.n; i++) n = n * 10 + (s.p[i] - '0');
    return (n >= 1 && n <= 65535) ? n : 0;
}

static void split_target(sv t, sv *host, int64_t *port) {
    int64_t i = sv_rfind(t, ':');
    if (i < 0) { *host = t; *port = 0; return; }
    *host = sv_sub(t, 0, i);
    *port = port_or_zero(sv_from(t, i + 1));
}

static int host_matches(arena *ar, sv h, int wild, int64_t port, sv host, int64_t tport) {
    sv th = normalize_host(ar, host);
    if (port != 0 && port != tport) return 0;
    if (wild) {
        /* suffix = "." ++ h */
        return th.n > h.n + 1 && sv_ends(th, h) && th.p[th.n - h.n - 1] == '.';
    }
    return sv_eq(th, h);
}

/* A parse failure: its text, built in [err]. */
typedef struct { arena ar; sbuf err; } pctx;
static void pctx_init(pctx *c) { ar_init(&c->ar); c->err.p = NULL; c->err.n = c->err.cap = 0; }

static int fail1(pctx *c, const char *a) { sb_addz(&c->err, a); return -1; }
static int fail3(pctx *c, const char *a, sv b, const char *d) {
    sb_addz(&c->err, a); sb_add(&c->err, b); sb_addz(&c->err, d); return -1;
}
static int fail5(pctx *c, const char *a, sv b, const char *d, sv e, const char *f) {
    sb_addz(&c->err, a); sb_add(&c->err, b); sb_addz(&c->err, d);
    sb_add(&c->err, e); sb_addz(&c->err, f); return -1;
}

typedef struct { sv host; int wild; int64_t port; int has_path; svl path; } hpat;

/* Host_scope.parse_scope_path: `/v1/weather/` as its segments. */
static int parse_scope_path(pctx *c, sv p, svl *out) {
    svl all = sv_split(&c->ar, p, '/');
    svl parts = { 0 };
    for (int i = 1; i < all.n; i++) svl_push(&c->ar, &parts, all.v[i]);   /* drop_first */
    if (parts.n > 0 && parts.v[parts.n - 1].n == 0) parts.n--;           /* drop_last_empty */
    for (int i = 0; i < parts.n; i++) {
        sv s = parts.v[i];
        if (s.n == 0)
            return fail1(c, "a path scope cannot contain `//`");
        if (sv_eqz(s, ".") || sv_eqz(s, ".."))
            return fail3(c, "a path scope cannot contain a `", s, "` segment");
        if (!sv_all(s, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.~"))
            return fail3(c, "the path segment `", s,
                         "` may contain only letters, digits, `-`, `_`, `.` and `~` (no `%`, `?`, `#` or `\\`)");
    }
    *out = parts;
    return 0;
}

/* The host and port text of `host[:port]` / `[v6][:port]` ("" for none);
 * an empty port after `:` reads as ":", a bad port. */
static void split_host_port(sv s, sv *hp, sv *pt) {
    sv colon = sv_z(":");
    if (sv_startsz(s, "[")) {
        int64_t i = sv_find(s, ']');
        if (i < 0) { *hp = s; *pt = sv_z(""); return; }
        sv rest = sv_from(s, i + 1);
        if (rest.n == 0) { *hp = sv_sub(s, 0, i + 1); *pt = sv_z(""); return; }
        if (sv_startsz(rest, ":")) {
            sv p = sv_from(rest, 1);
            *hp = sv_sub(s, 0, i + 1);
            *pt = p.n == 0 ? colon : p;
            return;
        }
        *hp = s; *pt = sv_z("");
        return;
    }
    int64_t i = sv_rfind(s, ':');
    if (i < 0) { *hp = s; *pt = sv_z(""); return; }
    sv p = sv_from(s, i + 1);
    *hp = sv_sub(s, 0, i);
    *pt = p.n == 0 ? colon : p;
}

static int valid_host_name(arena *ar, sv h) {
    if (h.n == 0) return 0;
    svl ls = sv_split(ar, h, '.');
    for (int i = 0; i < ls.n; i++)
        if (ls.v[i].n == 0 || !sv_all(ls.v[i], "abcdefghijklmnopqrstuvwxyz0123456789-")) return 0;
    return 1;
}

static int host_part_pattern(pctx *c, sv s, hpat *out) {
    if (s.n == 0) return fail1(c, "a host scope needs a host before its path");
    if (sv_has(s, '@')) return fail1(c, "a host scope cannot carry userinfo (`user@`)");
    sv host_part, port_text;
    split_host_port(s, &host_part, &port_text);
    int64_t port = port_text.n == 0 ? 0 : port_or_zero(port_text);
    if (port_text.n != 0 && port == 0)
        return fail3(c, "`", port_text, "` is not a port (1-65535)");
    if (sv_startsz(host_part, "[")) {
        int64_t n = host_part.n;
        sv body = sv_sub(host_part, 1, n - 2);
        if (n >= 2 && sv_ends(host_part, sv_z("]")) && body.n != 0 && sv_all(body, "0123456789abcdef:.")) {
            out->host = host_part; out->wild = 0; out->port = port;
            return 0;
        }
        return fail3(c, "`", host_part, "` is not an IPv6 literal");
    }
    int wild = host_part.n >= 2 && sv_startsz(host_part, "*.");
    sv name = normalize_host(&c->ar, wild ? sv_sub(host_part, 2, host_part.n - 2) : host_part);
    if (sv_has(name, '*') || sv_eqz(host_part, "*"))
        return fail1(c, "a wildcard must be the whole leftmost label (`*.example.com`)");
    if (!valid_host_name(&c->ar, name))
        return fail3(c, "`", host_part,
                     "` is not a host name: labels are letters, digits and `-`, separated by single dots");
    out->host = name; out->wild = wild; out->port = port;
    return 0;
}

/* Host_scope.parse_pattern. */
static int parse_host_pattern(pctx *c, sv raw, hpat *out) {
    memset(out, 0, sizeof *out);
    if (raw.n == 0) return fail1(c, "a host scope cannot be empty");
    if (sv_contains(raw, sv_z("://")))
        return fail1(c, "a host scope names a host, not a URL: drop the scheme (`https://`)");
    int64_t i = sv_find(raw, '/');
    sv host_raw = raw;
    if (i >= 0) {
        host_raw = sv_sub(raw, 0, i);
        if (parse_scope_path(c, sv_from(raw, i), &out->path) < 0) return -1;
        out->has_path = 1;
    }
    return host_part_pattern(c, sv_lower(&c->ar, host_raw), out);
}

static const struct { const char *kind; int len; } http_methods[] = {
    { "get", 3 }, { "head", 4 }, { "post", 4 }, { "put", 3 }, { "patch", 5 },
    { "delete", 6 }, { "options", 7 }, { 0, 0 } };

typedef struct { sv pre; int nr, mg; svl ms; } hdecl;

/* Host_scope.parse_decl's options: `no_redirects`, `methods=m,m`. */
static int host_options(pctx *c, svl opts, int from, hdecl *d) {
    for (int i = from; i < opts.n; i++) {
        sv o = opts.v[i];
        if (sv_eqz(o, "no_redirects")) {
            if (d->nr) return fail1(c, "`no_redirects` is given twice");
            d->nr = 1;
        } else if (sv_startsz(o, "methods=")) {
            if (d->mg) return fail1(c, "`methods(...)` is given twice");
            sv v = sv_from(o, 8);
            svl ms = sv_split(&c->ar, v, ',');
            for (int j = 0; j < ms.n; j++)
                if (!in_table(http_methods, ms.v[j]))
                    return fail3(c, "`", ms.v[j],
                                 "` is not an HTTP method a scope can name; use `get`, `head`, `post`, `put`, `patch`, `delete`, `options`");
            if (v.n == 0) return fail1(c, "`methods(...)` needs at least one method");
            d->mg = 1;
            d->ms = ms;
        } else {
            return fail3(c, "unknown option `", o, "`: the options are `no_redirects` and `methods(...)`");
        }
    }
    return 0;
}

/* A host spec as (pattern text, no_redirects, methods given, methods). */
static int host_decl(pctx *c, sv spec, hdecl *d) {
    memset(d, 0, sizeof *d);
    svl parts = sv_split(&c->ar, spec, ';');
    sv p = parts.v[0];
    if (p.n == 0 && parts.n == 1) return fail1(c, "a host scope cannot be empty");
    if (p.n != 0) {
        hpat hp;
        if (parse_host_pattern(c, p, &hp) < 0) return -1;
    }
    d->pre = p;
    return host_options(c, parts, 1, d);
}

/* Whether host spec [o] permits everything spec [i] does.  A spec that does
 * not parse permits nothing (the March version: `_ -> false`). */
static int pattern_subsumes(arena *ar, sv o, sv i) {
    pctx c1; pctx_init(&c1);
    hpat op, ip;
    int ok = parse_host_pattern(&c1, o, &op) == 0 && parse_host_pattern(&c1, i, &ip) == 0;
    int r = 0;
    if (ok) {
        sbuf dot = { 0 };
        sb_addc(&dot, '.');
        sb_add(&dot, op.host);
        int host_ok = op.wild ? ((ip.wild && sv_eq(ip.host, op.host)) || sv_ends(ip.host, sb_sv(&dot)))
                              : (!ip.wild && sv_eq(ip.host, op.host));
        sb_free(&dot);
        int port_ok = op.port == 0 || op.port == ip.port;
        int path_ok = !op.has_path ? 1 : (!ip.has_path ? 0 : segs_prefix(op.path, ip.path));
        r = host_ok && port_ok && path_ok;
    }
    (void)ar;
    ar_free(&c1.ar);
    sb_free(&c1.err);
    return r;
}

static int host_subsumes(sv o, sv i) {
    pctx c1; pctx_init(&c1);
    hdecl od, id;
    int r = 0;
    if (host_decl(&c1, o, &od) == 0 && host_decl(&c1, i, &id) == 0) {
        int ms_ok = 1;
        if (od.mg) {
            if (!id.mg) ms_ok = 0;
            else for (int k = 0; k < id.ms.n; k++) if (!svl_mem(od.ms, id.ms.v[k])) { ms_ok = 0; break; }
        }
        r = (!od.nr || id.nr) && ms_ok
            && (od.pre.n == 0 || (id.pre.n != 0 && pattern_subsumes(&c1.ar, od.pre, id.pre)));
    }
    ar_free(&c1.ar);
    sb_free(&c1.err);
    return r;
}

/* Host_scope.permits for one declaration (a hand-built `Hosts` spec). */
static int host_permits(arena *ar, sv spec, sv target) {
    int64_t semi = sv_find(spec, ';');
    sv raw = semi < 0 ? spec : sv_sub(spec, 0, semi);
    if (raw.n == 0) return 1;
    pctx c1; pctx_init(&c1);
    hpat hp;
    int r = 0;
    if (parse_host_pattern(&c1, raw, &hp) == 0) {
        sv th; int64_t tp;
        split_target(target, &th, &tp);
        r = host_matches(ar, hp.host, hp.wild, hp.port, th, tp);
    }
    ar_free(&c1.ar);
    sb_free(&c1.err);
    return r;
}

/* ── March values ─────────────────────────────────────────────────────── */

#define V_TAG(p) (((march_hdr *)(p))->tag)
#define V_FLD(p, i) (((void **)((char *)(p) + 16))[i])

static void *cell(int32_t tag, int nfields, int32_t type_id) {
    void *p = march_alloc(16 + 8 * (int64_t)nfields);
    ((march_hdr *)p)->tag = tag;
    ((march_hdr *)p)->pad = type_id;
    return p;
}
static void *mk_str(sv s) { return march_string_lit(s.p, s.n); }
static void *mk_nil(void) { return cell(0, 0, MARCH_AUTH_TID_LIST); }
static void *mk_cons(void *h, void *t) {
    void *c = cell(1, 2, MARCH_AUTH_TID_LIST);
    V_FLD(c, 0) = h;
    V_FLD(c, 1) = t;
    return c;
}
static void *mk_strs(svl l) {
    void *r = mk_nil();
    for (int i = l.n - 1; i >= 0; i--) r = mk_cons(mk_str(l.v[i]), r);
    return r;
}
static void *mk_result(int32_t tag, void *payload) {
    void *c = cell(tag, 1, MARCH_AUTH_TID_RESULT);
    V_FLD(c, 0) = payload;
    return c;
}
/* Ok(()): unit is the tagged immediate 0. */
static void *mk_ok_unit(void) { return mk_result(0, (void *)(intptr_t)1); }

static int v_is_cons(void *l) { return IS_HEAP_PTR(l) && V_TAG(l) == 1; }

/* ── The scope parser (the `needs` surface grammar) ───────────────────── */

enum { T_LP, T_RP, T_COMMA, T_WORD, T_STR };
typedef struct { int t; sv s; } tok;
typedef struct { tok *v; int n, cap; } toks;

static void toks_push(arena *ar, toks *l, int t, sv s) {
    if (l->n == l->cap) {
        int c = l->cap ? l->cap * 2 : 16;
        tok *nv = (tok *)ar_alloc(ar, sizeof(tok) * (size_t)c);
        if (l->n) memcpy(nv, l->v, sizeof(tok) * (size_t)l->n);
        l->v = nv;
        l->cap = c;
    }
    l->v[l->n].t = t;
    l->v[l->n].s = s;
    l->n++;
}

static int is_word_char(char ch) {
    return ch != '\0' && strchr("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.", ch) != NULL;
}

static int tokenize(pctx *c, sv s, toks *out) {
    int64_t i = 0, n = s.n;
    while (i < n) {
        char ch = s.p[i];
        if (ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r') { i++; continue; }
        if (ch == '(' || ch == ')' || ch == ',') {
            toks_push(&c->ar, out, ch == '(' ? T_LP : ch == ')' ? T_RP : T_COMMA, sv_sub(s, i, 1));
            i++;
            continue;
        }
        if (ch == '"') {
            char *acc = (char *)ar_alloc(&c->ar, (size_t)n);
            int64_t an = 0, j = i + 1;
            for (;;) {
                if (j >= n) return fail1(c, "a string is not closed");
                char d = s.p[j];
                if (d == '"') { j++; break; }
                if (d == '\\') {
                    if (j + 1 >= n) return fail1(c, "a string is not closed");
                    char e = s.p[j + 1];
                    acc[an++] = e == 'n' ? '\n' : e == 't' ? '\t' : e == 'r' ? '\r' : e;
                    j += 2;
                } else {
                    acc[an++] = d;
                    j++;
                }
            }
            sv str = { acc, an };
            toks_push(&c->ar, out, T_STR, str);
            i = j;
            continue;
        }
        if (is_word_char(ch)) {
            int64_t j = i;
            while (j < n && is_word_char(s.p[j])) j++;
            toks_push(&c->ar, out, T_WORD, sv_sub(s, i, j - i));
            i = j;
            continue;
        }
        return fail3(c, "unexpected `", sv_sub(s, i, 1), "`");
    }
    return 0;
}

/* describe_tok: "a string", or the token in backticks. */
static void add_desc(sbuf *b, tok t) {
    if (t.t == T_STR) { sb_addz(b, "a string"); return; }
    sb_addc(b, '`');
    sb_add(b, t.s);
    sb_addc(b, '`');
}
static int fail_desc(pctx *c, const char *a, tok t) {
    sb_addz(&c->err, a);
    add_desc(&c->err, t);
    return -1;
}

/* Dot-separated names, each starting with an upper-case letter. */
static int is_kind(tok t) {
    if (t.t != T_WORD) return 0;
    int64_t start = 0;
    for (int64_t i = 0; i <= t.s.n; i++) {
        if (i == t.s.n || t.s.p[i] == '.') {
            if (i == start) return 0;
            char f = t.s.p[start];
            if (!(f >= 'A' && f <= 'Z')) return 0;
            start = i + 1;
        }
    }
    return 1;
}
static int is_option_name(tok t) {
    return t.t == T_WORD && t.s.n > 0 && sv_all(t.s, "abcdefghijklmnopqrstuvwxyz_");
}

/* A parsed scope, before it becomes a March value. */
typedef struct { sv kind; int tag; svl a, b; sv spec, host; int wild; int64_t port; } pscope;
typedef struct { pscope *v; int n, cap; } pscopes;

static void ps_push(arena *ar, pscopes *l, pscope s) {
    if (l->n == l->cap) {
        int c = l->cap ? l->cap * 2 : 8;
        pscope *nv = (pscope *)ar_alloc(ar, sizeof(pscope) * (size_t)c);
        if (l->n) memcpy(nv, l->v, sizeof(pscope) * (size_t)l->n);
        l->v = nv;
        l->cap = c;
    }
    l->v[l->n++] = s;
}

static sv cat2(arena *ar, const char *a, sv b) {
    size_t an = strlen(a);
    char *d = (char *)ar_alloc(ar, an + (size_t)b.n);
    memcpy(d, a, an);
    if (b.n) memcpy(d + an, b.p, (size_t)b.n);
    sv r = { d, (int64_t)an + b.n };
    return r;
}

/* `name`, `name("value")` as `name=value`, `methods(a, b)` as `methods=a,b`. */
static int parse_option(pctx *c, sv name, toks *t, int *ip, sv *out) {
    int i = *ip;
    if (i + 2 < t->n && t->v[i].t == T_LP && t->v[i + 2].t == T_RP) {
        tok v = t->v[i + 1];
        if (v.t == T_STR) {
            if (sv_eqz(name, "methods"))
                return fail1(c, "`methods(...)` takes HTTP method names, not a string");
            sbuf b = { 0 };
            sb_add(&b, name); sb_addc(&b, '='); sb_add(&b, v.s);
            *out = sb_keep(&c->ar, &b);
            *ip = i + 3;
            return 0;
        }
        if (sv_eqz(name, "methods") && is_option_name(v)) {
            *out = cat2(&c->ar, "methods=", v.s);
            *ip = i + 3;
            return 0;
        }
        return fail3(c, "`", name, "(...)` takes a quoted string");
    }
    if (i < t->n && t->v[i].t == T_LP) {
        if (!sv_eqz(name, "methods"))
            return fail3(c, "`", name, "(...)` takes one quoted string");
        i++;
        svl ms = { 0 };
        for (;;) {
            if (i + 1 < t->n) {
                tok m = t->v[i], sep = t->v[i + 1];
                if (sep.t == T_COMMA) {
                    if (!is_option_name(m)) return fail1(c, "`methods(...)` takes HTTP method names");
                    svl_push(&c->ar, &ms, m.s);
                    i += 2;
                    continue;
                }
                if (sep.t == T_RP) {
                    if (!is_option_name(m)) return fail1(c, "`methods(...)` takes HTTP method names");
                    svl_push(&c->ar, &ms, m.s);
                    i += 2;
                    break;
                }
            }
            return fail1(c, "`methods(...)` is not closed");
        }
        *out = cat2(&c->ar, "methods=", svl_join(&c->ar, ms, ","));
        *ip = i;
        return 0;
    }
    *out = name;
    return 0;
}

/* The items of a scope up to its `)`: strings and options. */
static int parse_items(pctx *c, toks *t, int *ip, svl *strs, svl *opts) {
    int i = *ip;
    for (;;) {
        if (i >= t->n) return fail1(c, "a scope is not closed: expected `)`");
        tok tk = t->v[i++];
        if (tk.t == T_STR) {
            if (opts->n != 0) return fail1(c, "a string cannot follow an option in a scope");
            svl_push(&c->ar, strs, tk.s);
        } else if (is_option_name(tk)) {
            sv o;
            if (parse_option(c, tk.s, t, &i, &o) < 0) return -1;
            svl_push(&c->ar, opts, o);
        } else {
            return fail_desc(c, "expected a string or an option in a scope, found ", tk);
        }
        if (i >= t->n) return fail1(c, "a scope is not closed: expected `)`");
        if (t->v[i].t == T_RP) { *ip = i + 1; return 0; }
        if (t->v[i].t == T_COMMA) { i++; continue; }
        return fail_desc(c, "expected `,` or `)` in a scope, found ", t->v[i]);
    }
}

/* Name_scope.check_text: not empty, and no `;`, `=` or `,`. */
static int bad_name_text(pctx *c, svl ns, const char *what) {
    for (int i = 0; i < ns.n; i++) {
        sv n = ns.v[i];
        if (n.n == 0) { sb_addz(&c->err, what); sb_addz(&c->err, " cannot be empty"); return -1; }
        if (sv_has(n, ';') || sv_has(n, '=') || sv_has(n, ',')) {
            sb_addz(&c->err, what); sb_addz(&c->err, " `"); sb_add(&c->err, n);
            sb_addz(&c->err, "` contains `;`, `=` or `,`");
            return -1;
        }
    }
    return 0;
}

static int scope_arg(pctx *c, sv k, svl strs, svl opts, pscope *s) {
    if (path_kind(k)) {
        if (opts.n != 0) return fail3(c, "a path scope on `", k, "` takes only paths");
        if (svl_mem(strs, sv_z(""))) return fail1(c, "a path scope cannot be empty");
        for (int i = 0; i < strs.n; i++)
            if (!sv_startsz(strs.v[i], "/"))
                return fail5(c, "the scope `", strs.v[i], "` on `", k,
                             "` is a relative path; give an absolute path, one starting with `/`");
        svl norm = { 0 };
        for (int i = 0; i < strs.n; i++) svl_push(&c->ar, &norm, normalize(&c->ar, strs.v[i]));
        s->tag = 5;
        s->a = norm;
        return 0;
    }
    if (host_kind(k)) {
        sbuf b = { 0 };
        if (strs.n == 0) {
            sb_addc(&b, ';');
            for (int i = 0; i < opts.n; i++) { if (i) sb_addc(&b, ';'); sb_add(&b, opts.v[i]); }
        } else {
            sb_add(&b, strs.v[0]);
            for (int i = 1; i < strs.n; i++) { sb_addz(&b, ";name="); sb_add(&b, strs.v[i]); }
            for (int i = 0; i < opts.n; i++) { sb_addc(&b, ';'); sb_add(&b, opts.v[i]); }
        }
        sv spec = sb_keep(&c->ar, &b);
        hdecl d;
        if (host_decl(c, spec, &d) < 0) return -1;
        s->tag = 4;
        s->spec = spec;
        if (d.pre.n == 0) { s->host = sv_z(""); s->wild = 0; s->port = 0; return 0; }
        hpat hp;
        if (parse_host_pattern(c, d.pre, &hp) < 0) return -1;
        s->host = hp.host; s->wild = hp.wild; s->port = hp.port;
        return 0;
    }
    if (name_kind(k)) {
        svl pre = { 0 };
        for (int i = 0; i < opts.n; i++) {
            if (!sv_startsz(opts.v[i], "prefix="))
                return fail3(c, "`", opts.v[i],
                             "` is not an option a name scope takes; it takes names and `prefix(\"...\")`");
            svl_push(&c->ar, &pre, sv_from(opts.v[i], 7));
        }
        if (bad_name_text(c, strs, "a name") < 0) return -1;
        if (bad_name_text(c, pre, "a prefix") < 0) return -1;
        s->tag = 3;
        s->a = strs;
        s->b = pre;
        return 0;
    }
    return fail3(c, "`", k, "` takes no scope");
}

static int parse_entry(pctx *c, toks *t, int *ip, pscope *s) {
    int i = *ip;
    memset(s, 0, sizeof *s);
    if (i >= t->n) return fail1(c, "expected a capability at the end");
    tok k = t->v[i++];
    if (!is_kind(k)) return fail_desc(c, "expected a capability such as `IO.Console`, found ", k);
    s->kind = k.s;
    if (i < t->n && t->v[i].t == T_LP) {
        i++;
        if (i < t->n && t->v[i].t == T_RP)
            return fail5(c, "`", k.s, "()` names no scope: write `", k.s, "` for any target");
        svl strs = { 0 }, opts = { 0 };
        if (parse_items(c, t, &i, &strs, &opts) < 0) return -1;
        if (scope_arg(c, k.s, strs, opts, s) < 0) return -1;
    } else {
        s->tag = 0;
    }
    *ip = i;
    return 0;
}

/* Authority.parse, into C scopes. */
static int parse_scopes(pctx *c, sv text, pscopes *out) {
    toks t = { 0 };
    if (tokenize(c, text, &t) < 0) return -1;
    if (t.n == 0) return 0;
    if (t.n == 2 && t.v[0].t == T_LP && t.v[1].t == T_RP) return 0;
    int i = 0;
    for (;;) {
        pscope s;
        if (parse_entry(c, &t, &i, &s) < 0) return -1;
        ps_push(&c->ar, out, s);
        if (i >= t.n) return 0;
        if (t.v[i].t == T_COMMA) { i++; continue; }
        return fail_desc(c, "expected `,` between capabilities, found ", t.v[i]);
    }
}

static void *mk_arg(pscope *s) {
    void *a;
    switch (s->tag) {
    case 3:
        a = cell(3, 2, MARCH_AUTH_TID_ARG);
        V_FLD(a, 0) = mk_strs(s->a);
        V_FLD(a, 1) = mk_strs(s->b);
        return a;
    case 4:
        a = cell(4, 4, MARCH_AUTH_TID_ARG);
        V_FLD(a, 0) = mk_str(s->spec);
        V_FLD(a, 1) = mk_str(s->host);
        V_FLD(a, 2) = (void *)(intptr_t)(s->wild ? 1 : 0);
        V_FLD(a, 3) = (void *)(intptr_t)s->port;
        return a;
    case 5:
        a = cell(5, 1, MARCH_AUTH_TID_ARG);
        V_FLD(a, 0) = mk_strs(s->a);
        return a;
    default:
        return cell(0, 0, MARCH_AUTH_TID_ARG);
    }
}

static void *mk_scopes(pscopes *ps) {
    void *r = mk_nil();
    for (int i = ps->n - 1; i >= 0; i--) {
        void *s = cell(0, 2, MARCH_AUTH_TID_SCOPE);
        V_FLD(s, 0) = mk_str(ps->v[i].kind);
        V_FLD(s, 1) = mk_arg(&ps->v[i]);
        r = mk_cons(s, r);
    }
    return r;
}

/* ── Matching (over March values) ─────────────────────────────────────── */

/* Any element of the string list [l] satisfying [pred]. */
/* Some path of [ps] (normalized when [normal], else any spelling) holds
 * the normalized path [n]. */
static int any_within(arena *ar, void *ps, sv n, int normal) {
    for (void *l = ps; v_is_cons(l); l = V_FLD(l, 1)) {
        sv p = sv_m(V_FLD(l, 0));
        if (norm_within(normal ? p : normalize(ar, p), n)) return 1;
    }
    return 0;
}

static int list_mem(void *l, sv x) {
    for (; v_is_cons(l); l = V_FLD(l, 1)) if (sv_eq(sv_m(V_FLD(l, 0)), x)) return 1;
    return 0;
}
static int starts_with_any(sv n, void *pre) {
    for (void *l = pre; v_is_cons(l); l = V_FLD(l, 1)) if (sv_starts(n, sv_m(V_FLD(l, 0)))) return 1;
    return 0;
}
static int name_admits(void *ns, void *pre, sv n) { return list_mem(ns, n) || starts_with_any(n, pre); }

static int arg_admits(arena *ar, void *arg, sv kind, sv target, sv cwd) {
    switch (V_TAG(arg)) {
    case 0:
        return 1;
    case 1: {   /* Paths */
        if (!path_kind(kind)) return 0;
        if (cwd.n == 0 && !sv_startsz(target, "/")) return 0;
        return any_within(ar, V_FLD(arg, 0), normalize(ar, resolve(ar, cwd, target)), 0);
    }
    case 2:     /* Hosts */
        return host_kind(kind) ? host_permits(ar, sv_m(V_FLD(arg, 0)), target) : target.n == 0;
    case 3:     /* Names */
        return name_kind(kind) && name_admits(V_FLD(arg, 0), V_FLD(arg, 1), target);
    case 4: {   /* HostAt */
        if (!host_kind(kind)) return target.n == 0;
        sv h = sv_m(V_FLD(arg, 1));
        if (h.n == 0) return 1;
        sv th; int64_t tp;
        split_target(target, &th, &tp);
        return host_matches(ar, h, (int64_t)V_FLD(arg, 2) != 0, (int64_t)V_FLD(arg, 3), th, tp);
    }
    case 5:     /* PathsAt */
        if (!path_kind(kind)) return 0;
        if (cwd.n == 0 && !sv_startsz(target, "/")) return 0;
        return any_within(ar, V_FLD(arg, 0), normalize(ar, resolve(ar, cwd, target)), 1);
    default:
        return 0;
    }
}

/* kind_chain(kind): kind and its lattice ancestors. */
typedef struct { sv v[64]; int n; } chain_t;
static void kind_chain(sv kind, chain_t *ch) {
    ch->n = 0;
    while (ch->n < 64) {
        ch->v[ch->n++] = kind;
        kind = lattice_parent(kind);
        if (kind.n == 0) break;
    }
}
static int chain_mem(const chain_t *ch, sv k) {
    for (int i = 0; i < ch->n; i++) if (sv_eq(ch->v[i], k)) return 1;
    return 0;
}

static int admits_in(arena *ar, void *scopes, const chain_t *ch, sv kind, sv target, sv cwd) {
    for (void *l = scopes; v_is_cons(l); l = V_FLD(l, 1)) {
        void *s = V_FLD(l, 0);
        if (chain_mem(ch, sv_m(V_FLD(s, 0))) && arg_admits(ar, V_FLD(s, 1), kind, target, cwd)) return 1;
    }
    return 0;
}

/* The paths of a path scope (Paths / PathsAt), else NULL. */
static void *path_list(void *a) { return (V_TAG(a) == 1 || V_TAG(a) == 5) ? V_FLD(a, 0) : NULL; }
/* The packed spec of a host scope (Hosts / HostAt), else NULL. */
static void *host_spec(void *a) { return (V_TAG(a) == 2 || V_TAG(a) == 4) ? V_FLD(a, 0) : NULL; }

static int arg_subsumes(arena *ar, void *outer, void *inner) {
    switch (V_TAG(outer)) {
    case 0:
        return 1;
    case 1:
    case 5: {
        void *ips = path_list(inner);
        if (ips == NULL) return 0;
        for (void *l = ips; v_is_cons(l); l = V_FLD(l, 1)) {
            sv p = sv_m(V_FLD(l, 0));
            int in_any = 0;
            for (void *o = V_FLD(outer, 0); v_is_cons(o); o = V_FLD(o, 1))
                if (path_within(ar, sv_m(V_FLD(o, 0)), p)) { in_any = 1; break; }
            if (!in_any) return 0;
        }
        return 1;
    }
    case 3: {
        if (V_TAG(inner) != 3) return 0;
        for (void *l = V_FLD(inner, 0); v_is_cons(l); l = V_FLD(l, 1))
            if (!name_admits(V_FLD(outer, 0), V_FLD(outer, 1), sv_m(V_FLD(l, 0)))) return 0;
        for (void *l = V_FLD(inner, 1); v_is_cons(l); l = V_FLD(l, 1))
            if (!starts_with_any(sv_m(V_FLD(l, 0)), V_FLD(outer, 1))) return 0;
        return 1;
    }
    case 2:
    case 4: {
        void *i = host_spec(inner);
        if (i == NULL) return 0;
        return host_subsumes(sv_m(V_FLD(outer, 0)), sv_m(i));
    }
    default:
        return 0;
    }
}

static int covered(arena *ar, void *s, void *b) {
    for (void *l = b; v_is_cons(l); l = V_FLD(l, 1)) {
        void *o = V_FLD(l, 0);
        if (kind_subsumes(sv_m(V_FLD(o, 0)), sv_m(V_FLD(s, 0)))
            && arg_subsumes(ar, V_FLD(o, 1), V_FLD(s, 1)))
            return 1;
    }
    return 0;
}

/* The first entry of [a] that no entry of [b] covers, else NULL. */
static void *first_outside(arena *ar, void *a, void *b) {
    for (void *l = a; v_is_cons(l); l = V_FLD(l, 1))
        if (!covered(ar, V_FLD(l, 0), b)) return V_FLD(l, 0);
    return NULL;
}

/* ── Writing a scope back as text (for launch errors) ─────────────────── */

static void add_quoted(sbuf *b, sv s) {
    sb_addc(b, '"');
    for (int64_t i = 0; i < s.n; i++) {
        if (s.p[i] == '\\') sb_addz(b, "\\\\");
        else if (s.p[i] == '"') sb_addz(b, "\\\"");
        else sb_addc(b, s.p[i]);
    }
    sb_addc(b, '"');
}

static void add_scope_text(arena *ar, sbuf *b, void *s) {
    sv k = sv_m(V_FLD(s, 0));
    void *arg = V_FLD(s, 1);
    sb_add(b, k);
    switch (V_TAG(arg)) {
    case 1:
    case 5: {
        sb_addc(b, '(');
        int first = 1;
        for (void *l = V_FLD(arg, 0); v_is_cons(l); l = V_FLD(l, 1)) {
            if (!first) sb_addz(b, ", ");
            first = 0;
            add_quoted(b, sv_m(V_FLD(l, 0)));
        }
        sb_addc(b, ')');
        return;
    }
    case 3: {
        sb_addc(b, '(');
        int first = 1;
        for (void *l = V_FLD(arg, 0); v_is_cons(l); l = V_FLD(l, 1)) {
            if (!first) sb_addz(b, ", ");
            first = 0;
            add_quoted(b, sv_m(V_FLD(l, 0)));
        }
        for (void *l = V_FLD(arg, 1); v_is_cons(l); l = V_FLD(l, 1)) {
            if (!first) sb_addz(b, ", ");
            first = 0;
            sb_addz(b, "prefix(");
            add_quoted(b, sv_m(V_FLD(l, 0)));
            sb_addc(b, ')');
        }
        sb_addc(b, ')');
        return;
    }
    case 2:
    case 4: {
        svl parts = sv_split(ar, sv_m(V_FLD(arg, 0)), ';');
        sb_addc(b, '(');
        int first = 1;
        if (parts.v[0].n != 0) { add_quoted(b, parts.v[0]); first = 0; }
        for (int i = 1; i < parts.n; i++) {
            sv o = parts.v[i];
            if (!first) sb_addz(b, ", ");
            first = 0;
            int64_t eq = sv_find(o, '=');
            if (eq < 0) { sb_add(b, o); continue; }
            sv name = sv_sub(o, 0, eq), v = sv_from(o, eq + 1);
            if (sv_eqz(name, "name")) add_quoted(b, v);
            else if (sv_eqz(name, "methods")) {
                sb_addz(b, "methods(");
                svl ms = sv_split(ar, v, ',');
                for (int j = 0; j < ms.n; j++) { if (j) sb_addz(b, ", "); sb_add(b, ms.v[j]); }
                sb_addc(b, ')');
            } else {
                sb_add(b, name);
                sb_addc(b, '(');
                add_quoted(b, v);
                sb_addc(b, ')');
            }
        }
        sb_addc(b, ')');
        return;
    }
    default:
        return;
    }
}

/* ── The builtins ─────────────────────────────────────────────────────── */

/* Authority.parse(text) : Result(List(CapEntry), String) */
void *march_cap_rt_parse(void *text) {
    pctx c; pctx_init(&c);
    pscopes ps = { 0 };
    void *r;
    if (parse_scopes(&c, sv_m(text), &ps) < 0) r = mk_result(1, mk_str(sb_sv(&c.err)));
    else r = mk_result(0, mk_scopes(&ps));
    ar_free(&c.ar);
    sb_free(&c.err);
    return r;
}

/* Authority.admits(scopes, kind, target, cwd) : Bool */
int64_t march_cap_rt_admits(void *scopes, void *kind, void *target, void *cwd) {
    arena ar; ar_init(&ar);
    chain_t ch;
    kind_chain(sv_m(kind), &ch);
    int r = admits_in(&ar, scopes, &ch, sv_m(kind), sv_m(target), sv_m(cwd));
    ar_free(&ar);
    return r;
}

/* Authority.subset(a, b) : Bool */
int64_t march_cap_rt_subset(void *a, void *b) {
    arena ar; ar_init(&ar);
    int r = first_outside(&ar, a, b) == NULL;
    ar_free(&ar);
    return r;
}

/* An internal error (a needs clause or main's request the compiler
 * accepted but that does not parse): the message on fd 2, exit status 2.
 * The March policy panics instead; the C one avoids linking march_panic
 * into every binary for a case that cannot occur. */
static void internal_fail(const char *a, sv b, const char *c, sv d) {
    sbuf m = { 0 };
    sb_addz(&m, "march: internal error: ");
    sb_addz(&m, a); sb_add(&m, b); sb_addz(&m, c); sb_add(&m, d);
    sb_addc(&m, '\n');
    void *s = mk_str(sb_sv(&m));
    sb_free(&m);
    march_cap_launch_fail(s);
}

static void set_launch(void *layers) {
    if (march_cap_set_launch_once(layers))
        internal_fail("the launch authority is set twice", sv_z(""), "", sv_z(""));
}

static void *mk_layer(void *limit, void *text, void *scopes) {
    void *l = cell(0, 3, MARCH_AUTH_TID_LAYER);
    V_FLD(l, 0) = limit;
    V_FLD(l, 1) = text;
    V_FLD(l, 2) = scopes;
    return l;
}
static void *mk_by_launch(void) { return cell(0, 0, MARCH_AUTH_TID_LIMIT); }

/* Authority.frame_layer(name, needs_text) : Layer */
void *march_cap_rt_frame_layer(void *name, void *text) {
    pctx c; pctx_init(&c);
    pscopes ps = { 0 };
    if (parse_scopes(&c, sv_m(text), &ps) < 0)
        internal_fail("the needs clause of ", sv_m(name), " is not a scope list: ", sb_sv(&c.err));
    void *limit = cell(1, 1, MARCH_AUTH_TID_LIMIT);
    march_incrc(name);
    V_FLD(limit, 0) = name;
    march_incrc(text);
    void *l = mk_layer(limit, text, mk_scopes(&ps));
    ar_free(&c.ar);
    sb_free(&c.err);
    return l;
}

static void launch_error(sbuf *m) {
    sb_addc(m, '\n');
    void *s = mk_str(sb_sv(m));
    sb_free(m);
    march_cap_launch_fail(s);
}

/* Authority.launch_init(request, scoped) : () */
/* MARCH_GRANT, trimmed of spaces, tabs, CR and LF (march_cap_grant_text). */
static int trim_c(char c) { return c == ' ' || c == '\t' || c == '\n' || c == '\r'; }
static sv grant_text(void) {
    sv g = { getenv("MARCH_GRANT"), 0 };
    if (g.p == NULL) g.p = "";
    while (*g.p && trim_c(*g.p)) g.p++;
    g.n = (int64_t)strlen(g.p);
    while (g.n > 0 && trim_c(g.p[g.n - 1])) g.n--;
    return g;
}

void march_cap_rt_launch_init(void *request, int64_t scoped) {
    sv g = grant_text();
    if (!scoped && g.n == 0) return;
    pctx c; pctx_init(&c);
    pscopes req = { 0 };
    if (parse_scopes(&c, sv_m(request), &req) < 0)
        internal_fail("main's request is not a scope list: ", sb_sv(&c.err), "", sv_z(""));
    if (g.n == 0) {
        march_incrc(request);
        set_launch(mk_cons(mk_layer(mk_by_launch(), request, mk_scopes(&req)), mk_nil()));
        ar_free(&c.ar);
        sb_free(&c.err);
        return;
    }
    pscopes gs = { 0 };
    if (parse_scopes(&c, g, &gs) < 0) {
        sbuf m = { 0 };
        sb_addz(&m, "march: MARCH_GRANT is not a scope list: ");
        sb_add(&m, sb_sv(&c.err));
        launch_error(&m);
        return;
    }
    void *req_v = mk_scopes(&req);
    void *g_v = mk_scopes(&gs);
    void *out = first_outside(&c.ar, g_v, req_v);
    if (out != NULL) {
        sbuf m = { 0 };
        sb_addz(&m, "march: MARCH_GRANT grants ");
        add_scope_text(&c.ar, &m, out);
        sb_addz(&m, ", which main does not request (main requests: ");
        sb_add(&m, sv_m(request));
        sb_addc(&m, ')');
        launch_error(&m);
        return;
    }
    /* req_v is no longer needed: release it as the body of a layer. */
    march_incrc(request);
    march_cap_release(mk_cons(mk_layer(mk_by_launch(), request, req_v), mk_nil()));
    set_launch(mk_cons(mk_layer(mk_by_launch(), mk_str(g), g_v), mk_nil()));
    ar_free(&c.ar);
    sb_free(&c.err);
}

static void *mk_refusal(void *kind, void *target, void *limit, void *text) {
    void *e = cell(0, 4, MARCH_AUTH_TID_CAPERR);
    march_incrc(kind);
    march_incrc(target);
    march_incrc(limit);
    march_incrc(text);
    V_FLD(e, 0) = kind;
    V_FLD(e, 1) = target;
    V_FLD(e, 2) = limit;
    V_FLD(e, 3) = text;
    return mk_result(1, e);
}

/* The current directory, "" when it cannot be read (cap_cwd). */
static sv cwd_of(arena *ar) {
    char buf[4096];
    if (getcwd(buf, sizeof(buf)) == NULL) return sv_z("");
    size_t n = strlen(buf);
    char *d = (char *)ar_alloc(ar, n);
    memcpy(d, buf, n);
    sv r = { d, (int64_t)n };
    return r;
}

/* Authority.check_layers(kind, target, layers) : Result((), CapError) */
void *march_cap_rt_check_layers(void *kind, void *target, void *layers) {
    arena ar; ar_init(&ar);
    sv k = sv_m(kind), t = sv_m(target);
    sv cwd = (path_kind(k) && !sv_startsz(t, "/")) ? cwd_of(&ar) : sv_z("/");
    chain_t ch;
    kind_chain(k, &ch);
    void *r = NULL;
    for (void *l = layers; v_is_cons(l); l = V_FLD(l, 1)) {
        void *layer = V_FLD(l, 0);
        if (!admits_in(&ar, V_FLD(layer, 2), &ch, k, t, cwd)) {
            r = mk_refusal(kind, target, V_FLD(layer, 0), V_FLD(layer, 1));
            break;
        }
    }
    ar_free(&ar);
    return r ? r : mk_ok_unit();
}

/* Authority.check's slow path, after cap_check_raw answered [r] != 0: the
 * current layers decide. */
void *march_cap_rt_check_slow(void *kind, void *target, int64_t r) {
    (void)r;
    /* The slot (or the launch layers) stays alive for the whole call: this
     * green thread holds it, and the launch layers are never freed. */
    void *cur = *march_sched_auth_slot();
    if (cur == NULL) cur = atomic_load_explicit(&march_cap_launch, memory_order_acquire);
    if (cur == NULL) return mk_ok_unit();
    return march_cap_rt_check_layers(kind, target, cur);
}

#pragma clang attribute pop
