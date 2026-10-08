/* march_shell.c — the node's shell listener: signed EVAL of compiled
 * fragments (R6 of specs/plans/2026-09-28-observe-recon-shell-plan.md;
 * design §6.4 and §6.9 of specs/2026-09-24-observe-recon-shell-design.md).
 *
 * A Unix socket beside the reload socket, `<reload socket>.shell`, started by
 * march_reload_server_start.  One thread per connection, at most
 * SHELL_MAX_SESSIONS at once.  The reload socket is not touched: a shell
 * session never holds the one-client reload server, so it never blocks a
 * deploy.  Line protocol, one request line and one reply line:
 *
 *   HELLO
 *     -> OK epoch:<E> slots:<lo>-<hi> triple:<llvm triple> session:<hex>
 *        The session attaches at code epoch E and owns the march_repl_set
 *        slots lo..hi (released, values dropped, when the connection closes).
 *        The triple is what the client must compile fragments for: the
 *        operator's machine is often not the node's platform.
 *   EVAL <sig> name:<sym> [kind:value|init] epoch:<E> session:<hex> nonce:<hex> not_after_ms:<t>
 *        timeout_ms:<t> caps:<csv|-> src_b64:<b64> so_b64:<b64>
 *     -> OK <b64 result> out:<b64> | PANIC <b64 msg> out:<b64>
 *        | TIMEOUT out:<b64> | TIMEOUT uncancellable | ERR <code> [detail]
 *   IDENT
 *     -> OK <b64 table> | ERR no_ident
 *        The build's shell identity (lib/jit/shell_ident.ml): a hash per
 *        source declaration and each variant type's constructor tags, which
 *        the client compares with its own source before running an input.
 *   BYE
 *
 * <sig> is the deploy key's signature over the line without its signature
 * word ("EVAL name:… … so_b64:…"), so it covers the fragment's bytes as well
 * as every field.  Checks, in order: a key is compiled in, the fields parse,
 * the signature, the session (the random challenge this connection's HELLO
 * returned, so a captured line runs on no other connection, node or
 * restart: ERR bad_session), the nonce and expiry (march_sig_admit), the
 * session's epoch
 * is still current, every cap in `caps` is listed in $MARCH_SHELL_POLICY (one
 * cap path per line; no file denies all), and, once the fragment is loaded,
 * that its `__march_cap_manifest` (the caps its compiler derived from the
 * code it emitted) lists exactly the signed caps (ERR cap_tamper, or
 * ERR no_cap_manifest when it has none).  Every attempt is audited with
 * "type":"shell" and the decoded source; an input whose audit line cannot
 * be written does not run (ERR audit_unavailable).  The socket is 0600 from
 * before listen(), and a peer of another uid (root aside) is dropped. 
 *
 * The fragment's entry `name` is a zero-argument function returning the
 * rendered result String (the client generates it; capabilities are erased
 * to null pointers, as for `main`).  With `kind:init` it returns nothing: it
 * stores a `let`'s value in the session's slot, and the reply's result is
 * empty.  It runs as a task at the current epoch,
 * under a crash trap and a cancellation landing, with its print output
 * captured.  On timeout the task is cancelled the way a drain's hard deadline
 * cancels tasks.
 *
 * A deploy ends every session: an EVAL whose session epoch is no longer
 * current gets ERR epoch_changed, and an idle session is sent
 * `BYE epoch_changed <old> <new>` and closed.
 *
 * Fragments are never dlclose'd in this version: a `let` may have stored a
 * closure whose code lives in the fragment.  Reference-counted unloading is
 * R6.3. */
#if defined(__linux__) || defined(__APPLE__)
#define _GNU_SOURCE
#include "march_runtime.h"
#include "march_scheduler.h"
#include "march_dispatch.h"
#include "march_reclaim.h"
#include "march_sig.h"

#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <setjmp.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

#ifndef MSG_NOSIGNAL
#define MSG_NOSIGNAL 0
#endif

#define SHELL_MAX_SESSIONS   4
#define SHELL_SLOTS_PER      256
#define SHELL_SLOT_RANGES    (4096 / SHELL_SLOTS_PER)
#define SHELL_LINE_MAX       ((size_t)8 << 20)
#define SHELL_SO_MAX         ((size_t)4 << 20)
#define SHELL_TIMEOUT_MAX_MS 30000
#define SHELL_OUT_CAP        ((size_t)256 << 10)
#define SHELL_RESULT_CAP     ((size_t)1 << 20)

/* The node's target, from the driver's hot-reload identity flags. */
#ifdef MARCH_HCR_TRIPLE
#define SHELL_TRIPLE MARCH_HCR_TRIPLE
#else
#define SHELL_TRIPLE "unknown"
#endif

int64_t march_repl_get(int64_t slot);
void    march_repl_set(int64_t slot, int64_t val);

/* ── base64 (standard alphabet, padded) ──────────────────────────────── */

static const char B64[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static char *b64_encode(const unsigned char *in, size_t n) {
    char *out = (char *)malloc(4 * ((n + 2) / 3) + 1);
    if (!out) return NULL;
    size_t o = 0;
    for (size_t i = 0; i < n; i += 3) {
        unsigned v = (unsigned)in[i] << 16;
        if (i + 1 < n) v |= (unsigned)in[i + 1] << 8;
        if (i + 2 < n) v |= in[i + 2];
        out[o++] = B64[(v >> 18) & 63];
        out[o++] = B64[(v >> 12) & 63];
        out[o++] = i + 1 < n ? B64[(v >> 6) & 63] : '=';
        out[o++] = i + 2 < n ? B64[v & 63] : '=';
    }
    out[o] = '\0';
    return out;
}

static int b64v(unsigned char c) {
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    if (c == '+' || c == '-') return 62;
    if (c == '/' || c == '_') return 63;
    return -1;
}

/* Decoded bytes (malloc'd) and their length, or NULL on bad input. */
static unsigned char *b64_decode(const char *in, size_t n, size_t *out_n) {
    unsigned char *out = (unsigned char *)malloc(n / 4 * 3 + 3);
    if (!out) return NULL;
    size_t o = 0;
    unsigned acc = 0;
    int bits = 0;
    for (size_t i = 0; i < n; i++) {
        if (in[i] == '=') break;
        int v = b64v((unsigned char)in[i]);
        if (v < 0) { free(out); return NULL; }
        acc = (acc << 6) | (unsigned)v;
        bits += 6;
        if (bits >= 8) { bits -= 8; out[o++] = (unsigned char)((acc >> bits) & 0xff); }
    }
    *out_n = o;
    return out;
}

/* ── sessions and slots ──────────────────────────────────────────────── */

static pthread_mutex_t g_slots_mu = PTHREAD_MUTEX_INITIALIZER;
static int             g_slot_used[SHELL_SLOT_RANGES];
static _Atomic int     g_sessions;
static _Atomic unsigned g_frag_seq;
static char            g_shell_path[sizeof(((struct sockaddr_un *)0)->sun_path)];

static int slot_range_take(void) {
    pthread_mutex_lock(&g_slots_mu);
    int r = -1;
    for (int i = 0; i < SHELL_SLOT_RANGES; i++)
        if (!g_slot_used[i]) { g_slot_used[i] = 1; r = i; break; }
    pthread_mutex_unlock(&g_slots_mu);
    return r;
}

/* Drop the values the session's `let`s stored, then free the range. */
static void slot_range_release(int r) {
    if (r < 0) return;
    for (int i = 0; i < SHELL_SLOTS_PER; i++) {
        int64_t slot = (int64_t)r * SHELL_SLOTS_PER + i;
        int64_t v = march_repl_get(slot);
        if (v && IS_HEAP_PTR((void *)(uintptr_t)v)) march_decrc((void *)(uintptr_t)v);
        march_repl_set(slot, 0);
    }
    pthread_mutex_lock(&g_slots_mu);
    g_slot_used[r] = 0;
    pthread_mutex_unlock(&g_slots_mu);
}

/* ── one fragment run ────────────────────────────────────────────────── */

enum { RUN_PENDING, RUN_OK, RUN_PANIC, RUN_CANCELLED };

typedef struct shell_run {
    pthread_mutex_t   mu;
    pthread_cond_t    cv;
    int               refs;          /* the listener's and the task's */
    int               state;
    _Atomic int64_t   pid;           /* the task, once it runs; -1 before */
    void           *(*entry)(void);
    int               init;          /* kind:init: entry returns nothing */
    char             *text;          /* result or panic message (malloc'd) */
    size_t            text_len;
    march_out_capture out;
} shell_run;

static void run_release(shell_run *r) {
    pthread_mutex_lock(&r->mu);
    int last = --r->refs == 0;
    pthread_mutex_unlock(&r->mu);
    if (!last) return;
    pthread_mutex_destroy(&r->mu);
    pthread_cond_destroy(&r->cv);
    free(r->text);
    free(r->out.buf);
    free(r);
}

static void run_finish(shell_run *r, int state, char *text, size_t len) {
    pthread_mutex_lock(&r->mu);
    r->state = state;
    r->text = text;
    r->text_len = len;
    pthread_cond_signal(&r->cv);
    pthread_mutex_unlock(&r->mu);
}

/* The task: on its own green thread, under a crash trap (a panic) and a
 * cancellation landing (the timeout). */
static void shell_task(void *arg) {
    shell_run *r = (shell_run *)arg;
    march_proc *self = march_sched_current();
    atomic_store(&r->pid, self ? self->pid : -1);
    jmp_buf jb;
    jmp_buf *saved_crash = self ? self->crash_jmp : NULL;
    jmp_buf *saved_task  = self ? self->task_jmp : NULL;
    if (self) {
        self->crash_jmp = &jb;
        self->task_jmp = &jb;
        self->out_capture = &r->out;
    }
    if (setjmp(jb) == 0) {
        char *t;
        size_t n = 0;
        if (r->init) {
            ((void (*)(void))r->entry)();
            t = (char *)calloc(1, 1);
        } else {
            void *s = r->entry();
            march_string *ms = (march_string *)s;
            n = IS_HEAP_PTR(s) ? (size_t)ms->len : 0;
            if (n > SHELL_RESULT_CAP) n = SHELL_RESULT_CAP;
            t = (char *)malloc(n + 1);
            if (t) { if (n) memcpy(t, ms->data, n); t[n] = '\0'; }
            march_decrc(s);
        }
        if (self) { self->crash_jmp = saved_crash; self->task_jmp = saved_task; self->out_capture = NULL; }
        run_finish(r, RUN_OK, t, t ? n : 0);
    } else if (self && atomic_load(&self->cancel_requested)) {
        self->crash_jmp = saved_crash; self->task_jmp = saved_task; self->out_capture = NULL;
        run_finish(r, RUN_CANCELLED, NULL, 0);
    } else {
        char *m = NULL;
        size_t n = 0;
        if (self && self->crash_message) {
            m = self->crash_message;
            n = self->crash_message_len;
            self->crash_message = NULL;
            self->crash_message_len = 0;
        }
        if (self) { self->crash_jmp = saved_crash; self->task_jmp = saved_task; self->out_capture = NULL; }
        run_finish(r, RUN_PANIC, m, n);
    }
    run_release(r);
}

static void cancel_task(int64_t pid) {
    if (pid < 0) return;
    march_reclaim_enter();
    march_proc *p = march_sched_find(pid);
    if (p) atomic_store_explicit(&p->cancel_requested, 1, memory_order_release);
    march_reclaim_exit();
    march_preempt_request = 1;
}

/* ── wire helpers ────────────────────────────────────────────────────── */

static void send_all(int fd, const char *p, size_t n) {
    while (n > 0) {
        ssize_t k = send(fd, p, n, MSG_NOSIGNAL);
        if (k < 0 && errno == EINTR) continue;
        if (k <= 0) return;
        p += k;
        n -= (size_t)k;
    }
}

static void send_line(int fd, const char *s) {
    send_all(fd, s, strlen(s));
    send_all(fd, "\n", 1);
}

/* Read one line into a growing buffer.  1 a line, 0 EOF or error,
 * -1 too long, 2 an idle second passed (no byte yet). */
static int read_line(int fd, char **buf, size_t *cap, size_t *len) {
    *len = 0;
    for (;;) {
        if (*len == 0) {
            struct pollfd pf = { fd, POLLIN, 0 };
            int pr = poll(&pf, 1, 1000);
            if (pr == 0) return 2;
            if (pr < 0) { if (errno == EINTR) continue; return 0; }
        }
        char c;
        ssize_t k = recv(fd, &c, 1, 0);
        if (k < 0 && errno == EINTR) continue;
        if (k <= 0) return 0;
        if (c == '\n') break;
        if (*len + 2 > *cap) {
            if (*cap >= SHELL_LINE_MAX) return -1;
            size_t nc = *cap ? *cap * 2 : 4096;
            if (nc > SHELL_LINE_MAX) nc = SHELL_LINE_MAX;
            char *nb = (char *)realloc(*buf, nc);
            if (!nb) return 0;
            *buf = nb;
            *cap = nc;
        }
        (*buf)[(*len)++] = c;
    }
    if (*len > 0 && (*buf)[*len - 1] == '\r') (*len)--;
    (*buf)[*len] = '\0';
    return 1;
}

static int64_t wall_ms(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (int64_t)tv.tv_sec * 1000 + tv.tv_usec / 1000;
}

/* ── policy and audit ────────────────────────────────────────────────── */

/* 1 iff the fragment's own manifest (`__march_cap_manifest`: its caps, sorted,
 * one per line, as its compiler derived them from the code it emitted) lists
 * exactly the caps of the signed `caps:` csv ("-" = none), in the same order.
 * The client sends the manifest's caps; a mismatch means the signed line does
 * not describe this fragment (a stale or broken client, or an edited line),
 * and the policy was checked against the wrong set. */
static int caps_match_manifest(const char *csv, const char *manifest) {
    if (!csv || strcmp(csv, "-") == 0) csv = "";
    const char *a = csv, *b = manifest;
    for (;;) {
        size_t na = strcspn(a, ","), nb = strcspn(b, "\n");
        if (na != nb || memcmp(a, b, na) != 0) return 0;
        if (!a[na] && !b[nb]) return 1;
        if (!a[na] || !b[nb]) return 0;
        a += na + 1;
        b += nb + 1;
    }
}

/* 1 iff every cap in [csv] ("-" = none) is a line of $MARCH_SHELL_POLICY;
 * else 0 with the first missing cap in [missing]. */
static int caps_allowed(const char *csv, char *missing, size_t mlen) {
    missing[0] = '\0';
    if (!csv || strcmp(csv, "-") == 0 || !*csv) return 1;
    const char *path = getenv("MARCH_SHELL_POLICY");
    char *pol = NULL;
    size_t pol_n = 0;
    if (path && *path) {
        FILE *f = fopen(path, "r");
        if (f) {
            fseek(f, 0, SEEK_END);
            long n = ftell(f);
            fseek(f, 0, SEEK_SET);
            if (n > 0 && n < (1 << 20)) {
                pol = (char *)malloc((size_t)n + 1);
                if (pol) { pol_n = fread(pol, 1, (size_t)n, f); pol[pol_n] = '\0'; }
            }
            fclose(f);
        }
    }
    int ok = 1;
    const char *p = csv;
    while (*p && ok) {
        const char *comma = strchr(p, ',');
        size_t n = comma ? (size_t)(comma - p) : strlen(p);
        int found = 0;
        for (const char *line = pol; line && *line && !found; ) {
            const char *eol = strchr(line, '\n');
            size_t ln = eol ? (size_t)(eol - line) : strlen(line);
            const char *s = line;
            size_t sn = ln;
            const char *hash = memchr(s, '#', sn);
            if (hash) sn = (size_t)(hash - s);
            while (sn && (s[0] == ' ' || s[0] == '\t')) { s++; sn--; }
            while (sn && (s[sn - 1] == ' ' || s[sn - 1] == '\t' || s[sn - 1] == '\r')) sn--;
            if (sn == n && memcmp(s, p, n) == 0) found = 1;
            line = eol ? eol + 1 : NULL;
        }
        if (!found) {
            ok = 0;
            snprintf(missing, mlen, "%.*s", (int)(n < 200 ? n : 200), p);
        }
        p = comma ? comma + 1 : p + n;
    }
    free(pol);
    return ok;
}

static void json_str(FILE *f, const char *s, size_t n) {
    fputc('"', f);
    for (size_t i = 0; i < n; i++) {
        unsigned char c = (unsigned char)s[i];
        if (c == '"' || c == '\\') { fputc('\\', f); fputc(c, f); }
        else if (c < 0x20) fprintf(f, "\\u%04x", c);
        else fputc(c, f);
    }
    fputc('"', f);
}

/* 1 when the line was written.  A refusal is audited best-effort; an input
 * about to run is not run unless its line was written (handle_eval). */
static int audit(const char *name, const char *caps, const char *nonce,
                 const char *src, size_t src_n, const char *result) {
    FILE *f = march_audit_open();
    if (!f) return 0;
    char signer[65];
    march_sig_pubkey_hex(signer);
    fprintf(f, "{\"ts\":%lld,\"type\":\"shell\",\"name\":", (long long)wall_ms());
    json_str(f, name ? name : "", name ? strlen(name) : 0);
    fputs(",\"caps\":", f);
    json_str(f, caps ? caps : "", caps ? strlen(caps) : 0);
    fputs(",\"nonce\":", f);
    json_str(f, nonce ? nonce : "", nonce ? strlen(nonce) : 0);
    fprintf(f, ",\"signer\":\"%s\",\"src\":", signer);
    json_str(f, src ? src : "", src ? src_n : 0);
    fprintf(f, ",\"result\":\"%s\"}\n", result);
    int ok = fflush(f) == 0 && !ferror(f);
    march_audit_close(f);
    return ok;
}

/* ── EVAL ────────────────────────────────────────────────────────────── */

typedef struct {
    const char *name, *kind, *nonce, *caps, *src_b64, *so_b64, *session;
    int64_t epoch, not_after_ms, timeout_ms;
} eval_req;

/* Field value after "key:" within [rest]'s space-separated words; the
 * words are NUL-terminated in place by parse_eval. */
static int parse_eval(char *rest, eval_req *q) {
    memset(q, 0, sizeof *q);
    q->epoch = q->not_after_ms = q->timeout_ms = -1;
    for (char *w = rest; w && *w; ) {
        char *sp = strchr(w, ' ');
        if (sp) *sp = '\0';
        char *colon = strchr(w, ':');
        if (!colon) return 0;
        *colon = '\0';
        const char *k = w, *v = colon + 1;
        if      (strcmp(k, "name") == 0)         q->name = v;
        else if (strcmp(k, "kind") == 0)         q->kind = v;
        else if (strcmp(k, "nonce") == 0)        q->nonce = v;
        else if (strcmp(k, "caps") == 0)         q->caps = v;
        else if (strcmp(k, "session") == 0)      q->session = v;
        else if (strcmp(k, "src_b64") == 0)      q->src_b64 = v;
        else if (strcmp(k, "so_b64") == 0)       q->so_b64 = v;
        else if (strcmp(k, "epoch") == 0)        q->epoch = strtoll(v, NULL, 10);
        else if (strcmp(k, "not_after_ms") == 0) q->not_after_ms = strtoll(v, NULL, 10);
        else if (strcmp(k, "timeout_ms") == 0)   q->timeout_ms = strtoll(v, NULL, 10);
        else return 0;
        w = sp ? sp + 1 : NULL;
    }
    return q->name && q->nonce && q->caps && q->src_b64 && q->so_b64
        && q->epoch >= 0 && q->not_after_ms >= 0 && q->timeout_ms >= 0;
}

/* A fresh private file for the fragment's bytes. */
static int write_fragment(const unsigned char *so, size_t n, char *path, size_t plen) {
    const char *tmp = getenv("TMPDIR");
    if (!tmp || !*tmp) tmp = "/tmp";
    char dir[600];
    snprintf(dir, sizeof dir, "%s/march-shell-%ld", tmp, (long)getpid());
    mkdir(dir, 0700);
    snprintf(path, plen, "%s/frag-%u.so", dir, atomic_fetch_add(&g_frag_seq, 1));
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC | O_EXCL, 0700);
    if (fd < 0) return 0;
    size_t off = 0;
    while (off < n) {
        ssize_t k = write(fd, so + off, n - off);
        if (k < 0 && errno == EINTR) continue;
        if (k <= 0) { close(fd); return 0; }
        off += (size_t)k;
    }
    close(fd);
    return 1;
}

static void reply_with_out(int fd, const char *head, const char *b64_text, const march_out_capture *out) {
    char *ob = b64_encode((const unsigned char *)(out->buf ? out->buf : ""), out->len);
    size_t n = strlen(head) + (b64_text ? strlen(b64_text) : 0) + (ob ? strlen(ob) : 0) + 64;
    char *line = (char *)malloc(n);
    if (line) {
        if (b64_text)
            snprintf(line, n, "%s %s out:%s", head, b64_text, ob ? ob : "");
        else
            snprintf(line, n, "%s out:%s", head, ob ? ob : "");
        send_line(fd, line);
        free(line);
    } else {
        send_line(fd, "ERR out_of_memory");
    }
    free(ob);
}

static void handle_eval(int fd, char *line, uint32_t session_epoch, const char *session) {
    /* line: "EVAL <sig> <rest>" */
    char *sig = line + 5;
    while (*sig == ' ') sig++;
    char *rest = strchr(sig, ' ');
    if (!march_sig_key_loaded()) {
        audit("", "", "", "", 0, "signing_not_configured");
        send_line(fd, "ERR signing_not_configured");
        return;
    }
    if (!rest) { audit("", "", "", "", 0, "bad_args"); send_line(fd, "ERR bad_args"); return; }
    *rest++ = '\0';
    /* The signed text, before parse_eval cuts [rest] into words. */
    size_t mlen = strlen(rest) + 6;
    char *msg = (char *)malloc(mlen);
    if (!msg) { send_line(fd, "ERR out_of_memory"); return; }
    snprintf(msg, mlen, "EVAL %s", rest);
    eval_req q;
    if (!parse_eval(rest, &q)) {
        free(msg);
        audit("", "", "", "", 0, "bad_args");
        send_line(fd, "ERR bad_args");
        return;
    }
    size_t src_n = 0;
    unsigned char *src = b64_decode(q.src_b64, strlen(q.src_b64), &src_n);
    const char *srcs = src ? (const char *)src : "";
    int ok = march_sig_verify(msg, sig);
    free(msg);
    const char *why = NULL;
    char detail[256] = "";
    if (!ok) why = "bad_signature";
    /* The line was signed for THIS session's HELLO challenge: a captured
     * line cannot be replayed on another connection, on another node with
     * the same key, or after a restart (whose nonce ring is empty). */
    if (!why && (!q.session || strcmp(q.session, session) != 0)) why = "bad_session";
    if (!why) why = march_sig_admit(q.nonce, q.not_after_ms, wall_ms());
    uint32_t cur = march_epoch_current();
    if (!why && ((uint32_t)q.epoch != session_epoch || cur != session_epoch)) {
        why = "epoch_changed";
        snprintf(detail, sizeof detail, " %u %u", session_epoch, cur);
    }
    if (!why && !caps_allowed(q.caps, detail + 1, sizeof detail - 1)) {
        why = "policy";
        detail[0] = ' ';
    }
    if (!why && q.timeout_ms > SHELL_TIMEOUT_MAX_MS) why = "bad_args";
    if (!why && q.kind && strcmp(q.kind, "value") != 0 && strcmp(q.kind, "init") != 0) why = "bad_args";
    if (why) {
        audit(q.name, q.caps, q.nonce, srcs, src_n, why);
        char buf[320];
        snprintf(buf, sizeof buf, "ERR %s%s", why, detail);
        send_line(fd, buf);
        free(src);
        return;
    }
    size_t so_n = 0;
    unsigned char *so = b64_decode(q.so_b64, strlen(q.so_b64), &so_n);
    char path[700];
    if (!so || so_n == 0 || so_n > SHELL_SO_MAX || !write_fragment(so, so_n, path, sizeof path)) {
        free(so);
        audit(q.name, q.caps, q.nonce, srcs, src_n, "err_write");
        send_line(fd, "ERR fragment_write");
        free(src);
        return;
    }
    free(so);
    void *h = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (!h) {
        const char *e = dlerror();
        char *eb = b64_encode((const unsigned char *)(e ? e : "dlopen"), strlen(e ? e : "dlopen"));
        char buf[2048];
        snprintf(buf, sizeof buf, "ERR dlopen %s", eb ? eb : "");
        free(eb);
        audit(q.name, q.caps, q.nonce, srcs, src_n, "err_dlopen");
        send_line(fd, buf);
        free(src);
        return;
    }
    void *(*entry)(void) = (void *(*)(void))dlsym(h, q.name);
    if (!entry) {
        audit(q.name, q.caps, q.nonce, srcs, src_n, "err_no_entry");
        send_line(fd, "ERR no_entry");
        free(src);
        return;
    }
    /* The policy above was checked against the signed caps; they must be the
     * fragment's own.  The handle stays open on refusal, like every other
     * fragment's: nothing in it has run. */
    const char *manifest = (const char *)dlsym(h, "__march_cap_manifest");
    if (!manifest || !caps_match_manifest(q.caps, manifest)) {
        const char *code = manifest ? "cap_tamper" : "no_cap_manifest";
        audit(q.name, q.caps, q.nonce, srcs, src_n, code);
        char buf[64];
        snprintf(buf, sizeof buf, "ERR %s", code);
        send_line(fd, buf);
        free(src);
        return;
    }
    /* Every input that runs is audited: one whose line cannot be written
     * does not run. */
    if (!audit(q.name, q.caps, q.nonce, srcs, src_n, "ok")) {
        free(src);
        send_line(fd, "ERR audit_unavailable");
        return;
    }
    free(src);

    shell_run *r = (shell_run *)calloc(1, sizeof *r);
    if (!r) { send_line(fd, "ERR out_of_memory"); return; }
    pthread_mutex_init(&r->mu, NULL);
    pthread_cond_init(&r->cv, NULL);
    r->refs = 2;
    r->state = RUN_PENDING;
    atomic_store(&r->pid, -1);
    r->entry = entry;
    r->init = q.kind && strcmp(q.kind, "init") == 0;
    r->out.buf = (char *)malloc(SHELL_OUT_CAP);
    r->out.cap = r->out.buf ? SHELL_OUT_CAP : 0;
    if (!march_sched_spawn(shell_task, r)) {
        r->refs = 1;
        run_release(r);
        send_line(fd, "ERR spawn");
        return;
    }
    struct timespec dl;
    clock_gettime(CLOCK_REALTIME, &dl);
    int64_t ns = (int64_t)dl.tv_nsec + (q.timeout_ms % 1000) * 1000000;
    dl.tv_sec += (time_t)(q.timeout_ms / 1000 + ns / 1000000000);
    dl.tv_nsec = (long)(ns % 1000000000);
    pthread_mutex_lock(&r->mu);
    while (r->state == RUN_PENDING)
        if (pthread_cond_timedwait(&r->cv, &r->mu, &dl) == ETIMEDOUT) break;
    int state = r->state;
    pthread_mutex_unlock(&r->mu);
    if (state == RUN_PENDING) {
        /* Cancel, then give the task a second to reach a cancellation point. */
        cancel_task(atomic_load(&r->pid));
        struct timespec dl2;
        clock_gettime(CLOCK_REALTIME, &dl2);
        dl2.tv_sec += 1;
        pthread_mutex_lock(&r->mu);
        while (r->state == RUN_PENDING)
            if (pthread_cond_timedwait(&r->cv, &r->mu, &dl2) == ETIMEDOUT) break;
        state = r->state;
        pthread_mutex_unlock(&r->mu);
    }
    if (state == RUN_PENDING) {
        send_line(fd, "TIMEOUT uncancellable");
    } else if (state == RUN_CANCELLED) {
        reply_with_out(fd, "TIMEOUT", NULL, &r->out);
    } else {
        char *tb = b64_encode((const unsigned char *)(r->text ? r->text : ""), r->text ? r->text_len : 0);
        reply_with_out(fd, state == RUN_OK ? "OK" : "PANIC", tb ? tb : "", &r->out);
        free(tb);
    }
    run_release(r);
}

/* ── connections ─────────────────────────────────────────────────────── */

/* A session's HELLO challenge: 16 random bytes as hex.  Every EVAL on the
 * connection must sign it (field `session:`). */
static int random_hex(char out[33]) {
    unsigned char b[16];
    int got = 0;
#if defined(__APPLE__)
    arc4random_buf(b, sizeof b);
    got = 1;
#else
    int rf = open("/dev/urandom", O_RDONLY | O_CLOEXEC);
    if (rf >= 0) {
        size_t n = 0;
        while (n < sizeof b) {
            ssize_t r = read(rf, b + n, sizeof b - n);
            if (r <= 0) { if (r < 0 && errno == EINTR) continue; break; }
            n += (size_t)r;
        }
        close(rf);
        got = n == sizeof b;
    }
#endif
    if (!got) return 0;
    for (int i = 0; i < 16; i++) snprintf(out + 2 * i, 3, "%02x", b[i]);
    return 1;
}

/* Belt and braces over the socket's mode, as for the reload socket: a peer
 * must run as this process's uid (or root).  1 when the platform cannot
 * say. */
static int peer_uid_ok(int fd) {
#if defined(__APPLE__)
    uid_t uid; gid_t gid;
    if (getpeereid(fd, &uid, &gid) != 0) return 1;
    return uid == geteuid() || uid == 0;
#elif defined(SO_PEERCRED)
    struct ucred cr;
    socklen_t len = sizeof(cr);
    if (getsockopt(fd, SOL_SOCKET, SO_PEERCRED, &cr, &len) != 0) return 1;
    return cr.uid == geteuid() || cr.uid == 0;
#else
    (void)fd;
    return 1;
#endif
}

static void *session_thread(void *arg) {
    int fd = (int)(intptr_t)arg;
    sigset_t all;
    sigfillset(&all);
    pthread_sigmask(SIG_BLOCK, &all, NULL);
    char *buf = NULL;
    size_t cap = 0, len = 0;
    int range = -1;
    uint32_t epoch = 0;
    int hello = 0;
    char session[33] = "";
    for (;;) {
        int rc = read_line(fd, &buf, &cap, &len);
        if (rc == 2) {
            /* Idle: a deploy ends the session. */
            uint32_t cur = march_epoch_current();
            if (hello && cur != epoch) {
                char b[96];
                snprintf(b, sizeof b, "BYE epoch_changed %u %u", epoch, cur);
                send_line(fd, b);
                break;
            }
            continue;
        }
        if (rc == -1) { send_line(fd, "ERR line_too_long"); break; }
        if (rc == 0) break;
        if (strcmp(buf, "HELLO") == 0) {
            if (!hello) {
                if (!random_hex(session)) { send_line(fd, "ERR no_random"); break; }
                range = slot_range_take();
                if (range < 0) { send_line(fd, "ERR slots_full"); break; }
                epoch = march_epoch_current();
                hello = 1;
            }
            char b[256];
            snprintf(b, sizeof b, "OK epoch:%u slots:%d-%d triple:%s session:%s", epoch,
                     range * SHELL_SLOTS_PER, range * SHELL_SLOTS_PER + SHELL_SLOTS_PER - 1,
                     SHELL_TRIPLE, session);
            send_line(fd, b);
        } else if (strcmp(buf, "IDENT") == 0) {
            /* The build's shell identity table (lib/jit/shell_ident.ml),
             * which the client compares with its own source.  Public: it
             * holds hashes of the source, not the source. */
            static void *self;
            if (!self) self = dlopen(NULL, RTLD_NOW);
            const char *ident = self ? (const char *)dlsym(self, "__march_shell_ident") : NULL;
            if (!ident) { send_line(fd, "ERR no_ident"); continue; }
            char *b64 = b64_encode((const unsigned char *)ident, strlen(ident));
            if (!b64) { send_line(fd, "ERR out_of_memory"); continue; }
            send_all(fd, "OK ", 3);
            send_line(fd, b64);
            free(b64);
        } else if (strncmp(buf, "EVAL ", 5) == 0) {
            if (!hello) { send_line(fd, "ERR no_hello"); continue; }
            handle_eval(fd, buf, epoch, session);
        } else if (strcmp(buf, "BYE") == 0) {
            break;
        } else {
            send_line(fd, "ERR unknown_verb");
        }
    }
    free(buf);
    slot_range_release(range);
    close(fd);
    atomic_fetch_sub(&g_sessions, 1);
    return NULL;
}

static void *accept_thread(void *arg) {
    int ls = (int)(intptr_t)arg;
    sigset_t all;
    sigfillset(&all);
    pthread_sigmask(SIG_BLOCK, &all, NULL);
    for (;;) {
        int fd = accept(ls, NULL, NULL);
        if (fd < 0) {
            if (errno == EINTR || errno == ECONNABORTED) continue;
            struct timespec pause = { 0, 50 * 1000 * 1000 };
            nanosleep(&pause, NULL);
            continue;
        }
#ifdef SO_NOSIGPIPE
        { int one = 1; setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one); }
#endif
        if (!peer_uid_ok(fd)) { close(fd); continue; }
        if (atomic_fetch_add(&g_sessions, 1) >= SHELL_MAX_SESSIONS) {
            send_line(fd, "ERR busy");
            close(fd);
            atomic_fetch_sub(&g_sessions, 1);
            continue;
        }
        pthread_attr_t at;
        pthread_attr_init(&at);
        pthread_attr_setdetachstate(&at, PTHREAD_CREATE_DETACHED);
        pthread_attr_setstacksize(&at, (size_t)1 << 20);
        pthread_t t;
        if (pthread_create(&t, &at, session_thread, (void *)(intptr_t)fd) != 0) {
            send_line(fd, "ERR busy");
            close(fd);
            atomic_fetch_sub(&g_sessions, 1);
        }
        pthread_attr_destroy(&at);
    }
    return NULL;
}

static void unlink_at_exit(void) {
    struct stat st;
    if (g_shell_path[0] && lstat(g_shell_path, &st) == 0 && S_ISSOCK(st.st_mode))
        unlink(g_shell_path);
}

void march_shell_server_start(const char *reload_socket_path) {
    if (!reload_socket_path || !*reload_socket_path) return;
    struct sockaddr_un a;
    char path[sizeof a.sun_path + 16];
    snprintf(path, sizeof path, "%s.shell", reload_socket_path);
    if (strlen(path) >= sizeof a.sun_path) {
        fprintf(stderr, "march: shell socket path too long: %s\n", path);
        return;
    }
    struct stat st;
    if (lstat(path, &st) == 0) {
        if (!S_ISSOCK(st.st_mode)) {
            fprintf(stderr, "march: shell socket path exists and is not a socket: %s\n", path);
            return;
        }
        unlink(path);
    }
    int ls = socket(AF_UNIX, SOCK_STREAM, 0);
    if (ls < 0) return;
    memset(&a, 0, sizeof a);
    a.sun_family = AF_UNIX;
    memcpy(a.sun_path, path, strlen(path) + 1);
    /* Owner-only, like the reload socket, and set between bind and listen:
     * connecting needs write permission on the socket inode, and nothing
     * can connect before listen(), so no connection is ever accepted under
     * the inherited umask's mode. */
    if (bind(ls, (struct sockaddr *)&a, sizeof a) < 0 || chmod(path, 0600) != 0
        || listen(ls, 8) < 0) {
        fprintf(stderr, "march: shell socket %s: %s\n", path, strerror(errno));
        close(ls);
        unlink(path);
        return;
    }
    snprintf(g_shell_path, sizeof g_shell_path, "%s", path);
    atexit(unlink_at_exit);
    pthread_attr_t at;
    pthread_attr_init(&at);
    pthread_attr_setdetachstate(&at, PTHREAD_CREATE_DETACHED);
    pthread_attr_setstacksize(&at, (size_t)256 << 10);
    pthread_t t;
    if (pthread_create(&t, &at, accept_thread, (void *)(intptr_t)ls) != 0) {
        fprintf(stderr, "march: shell socket thread failed\n");
        close(ls);
        unlink(path);
    }
    pthread_attr_destroy(&at);
}

#else  /* non-POSIX stub */
void march_shell_server_start(const char *reload_socket_path) { (void)reload_socket_path; }
#endif
