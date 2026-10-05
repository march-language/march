/* march_observe_debug.c — the observe socket's signed debug verbs (R4 of
 * specs/plans/2026-09-28-observe-recon-shell-plan.md).
 *
 *   STATE        <sig> nonce:<hex> not_after_ms:<t> pid:<p> [timeout_ms:<t>]
 *   CRASHES_FULL <sig> nonce:<hex> not_after_ms:<t> [n:<n>]
 *
 * <sig> is the deploy key's ed25519 signature (base64) over the request line
 * with the signature word removed ("STATE nonce:... not_after_ms:... pid:7").
 * Every request is checked in this order, and every outcome is appended to
 * the audit log with "type":"debug":
 *
 *   signing_not_configured  the binary has no key (not a `--hot-reload
 *                           --signing-pubkey` build)
 *   bad_args                a missing, repeated or unknown key:value
 *   bad_signature
 *   expired / not_after_too_far / bad_nonce / replay / nonce_ring_full
 *                           (march_sig_admit)
 *   policy                  the verb is not listed in $MARCH_DEBUG_POLICY
 *
 * Signature before policy, so an unauthenticated client learns nothing about
 * what the policy allows.  The verbs are registered by
 * march_observe_debug_install, which march_observe_snapshot_install calls; a
 * C harness that links the snapshot verbs without this file gets the weak
 * no-op there instead. */
#include "march_observe.h"
#include "march_scheduler.h"
#include "march_sig.h"

#include <stdlib.h>
#include <string.h>
#include <sys/time.h>

#define STATE_TIMEOUT_DEFAULT_MS 1000
#define STATE_TIMEOUT_MAX_MS     10000
#define CRASHES_FULL_DEFAULT_N   20

static int64_t wall_ms(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (int64_t)tv.tv_sec * 1000 + tv.tv_usec / 1000;
}

/* The parsed request.  -1 marks an absent number. */
typedef struct {
    char    sig[160];
    char    nonce[MARCH_SIG_NONCE_MAX + 2];
    int64_t not_after_ms;
    int64_t pid;
    int64_t timeout_ms;
    int64_t n;
} dbg_req;

static void audit(const char *verb, const dbg_req *r, const char *result) {
    FILE *f = march_audit_open();
    if (!f) return;
    char signer[65];
    march_sig_pubkey_hex(signer);
    fprintf(f, "{\"ts\":%lld,\"type\":\"debug\",\"verb\":\"%s\",\"pid\":",
            (long long)wall_ms(), verb);
    if (r->pid >= 0) fprintf(f, "%lld", (long long)r->pid); else fputs("null", f);
    /* The nonce went through isxdigit when admitted; one that did not is
     * printed only as far as it is hex, so it can never break the line. */
    fputs(",\"nonce\":\"", f);
    for (const char *p = r->nonce; *p && strchr("0123456789abcdefABCDEF", *p); p++) fputc(*p, f);
    fprintf(f, "\",\"signer\":\"%s\",\"result\":\"%s\"}\n", signer, result);
    march_audit_close(f);
}

/* 1 iff [k] is one of the space-separated words of [list]. */
static int has_word(const char *list, const char *k) {
    size_t n = strlen(k);
    for (const char *p = list; *p; ) {
        const char *e = strchr(p, ' ');
        size_t m = e ? (size_t)(e - p) : strlen(p);
        if (m == n && strncmp(p, k, n) == 0) return 1;
        if (!e) break;
        p = e + 1;
    }
    return 0;
}

/* key:<decimal>; 1 on success. */
static int parse_num(const char *v, int64_t *out) {
    if (!*v) return 0;
    char *end;
    long long x = strtoll(v, &end, 10);
    if (*end) return 0;
    *out = x;
    return 1;
}

/* Parse "<sig> k:v k:v ..." for [verb], verify and admit it, check the
 * policy.  NULL when the request may run, else the error code.  [allowed]
 * lists the keys this verb takes besides nonce and not_after_ms. */
static const char *admit(const char *verb, const char *args, const char *allowed,
                         dbg_req *r) {
    memset(r, 0, sizeof *r);
    r->not_after_ms = r->pid = r->timeout_ms = r->n = -1;
    if (!march_sig_key_loaded()) return "signing_not_configured";

    while (*args == ' ') args++;
    const char *sp = strchr(args, ' ');
    size_t sl = sp ? (size_t)(sp - args) : strlen(args);
    if (sl == 0 || sl >= sizeof r->sig) return "bad_args";
    memcpy(r->sig, args, sl);
    const char *rest = sp ? sp + 1 : "";
    while (*rest == ' ') rest++;

    char buf[MARCH_OBSERVE_LINE_MAX + 1];
    snprintf(buf, sizeof buf, "%s", rest);
    for (char *tok = strtok(buf, " "); tok; tok = strtok(NULL, " ")) {
        char *colon = strchr(tok, ':');
        if (!colon) return "bad_args";
        *colon = '\0';
        const char *k = tok, *v = colon + 1;
        int64_t *slot = NULL;
        if (strcmp(k, "nonce") == 0) {
            if (r->nonce[0] || strlen(v) > MARCH_SIG_NONCE_MAX) return "bad_args";
            snprintf(r->nonce, sizeof r->nonce, "%s", v);
            continue;
        } else if (strcmp(k, "not_after_ms") == 0) {
            slot = &r->not_after_ms;
        } else if (!has_word(allowed, k)) {
            return "bad_args";
        } else if (strcmp(k, "pid") == 0) {
            slot = &r->pid;
        } else if (strcmp(k, "timeout_ms") == 0) {
            slot = &r->timeout_ms;
        } else if (strcmp(k, "n") == 0) {
            slot = &r->n;
        } else {
            return "bad_args";
        }
        if (*slot != -1 || !parse_num(v, slot) || *slot < 0) return "bad_args";
    }
    if (!r->nonce[0] || r->not_after_ms < 0) return "bad_args";

    /* The signed text: the line without its signature word. */
    size_t mlen = strlen(verb) + 1 + strlen(rest) + 1;
    char *msg = (char *)malloc(mlen);
    if (!msg) return "out_of_memory";
    snprintf(msg, mlen, "%s %s", verb, rest);
    int ok = march_sig_verify(msg, r->sig);
    free(msg);
    if (!ok) return "bad_signature";

    const char *why = march_sig_admit(r->nonce, r->not_after_ms, wall_ms());
    if (why) return why;
    if (!march_sig_debug_allowed(verb)) return "policy";
    return NULL;
}

/* ── STATE ────────────────────────────────────────────────────────────── */

static const char *verb_state(march_jw *w, const char *args) {
    dbg_req r;
    const char *err = admit("STATE", args, "pid timeout_ms", &r);
    if (!err && r.pid < 0) err = "bad_args";
    /* A green thread (observe_query) must not block its scheduler on the
     * reply: the actor it waits for may need that very scheduler. */
    if (!err && march_sched_current()) err = "not_from_a_green_thread";
    if (err) { audit("STATE", &r, err); return err; }

    int64_t timeout = r.timeout_ms < 0 ? STATE_TIMEOUT_DEFAULT_MS : r.timeout_ms;
    if (timeout > STATE_TIMEOUT_MAX_MS) timeout = STATE_TIMEOUT_MAX_MS;
    char *text = NULL;
    int ok = march_actor_inspect_external(r.pid, timeout, &text);
    audit("STATE", &r, "ok");
    march_jw_obj_begin(w);
    march_jw_key(w, "pid");   march_jw_i64(w, r.pid);
    march_jw_key(w, "state");
    if (ok) march_jw_str(w, text ? text : ""); else march_jw_null(w);
    march_jw_key(w, "error");
    if (ok) march_jw_null(w); else march_jw_str(w, text ? text : "out of memory");
    march_jw_obj_end(w);
    free(text);
    return NULL;
}

/* ── CRASHES_FULL ─────────────────────────────────────────────────────── */

static const char *crash_kind(int k) {
    switch (k) {
    case MARCH_CRASH_KIND_DRAINING: return "draining";
    case MARCH_CRASH_KIND_PANIC:    return "panic";
    default:                        return "crash";
    }
}

/* CRASHES, plus each crash's message (kept up to MARCH_CRASH_MSG_MAX bytes). */
static const char *verb_crashes_full(march_jw *w, const char *args) {
    dbg_req r;
    const char *err = admit("CRASHES_FULL", args, "n", &r);
    if (!err && r.n == 0) err = "bad_args";
    if (!err && r.n > MARCH_CRASH_RING) err = "bad_args";
    if (err) { audit("CRASHES_FULL", &r, err); return err; }
    int64_t want = r.n < 0 ? CRASHES_FULL_DEFAULT_N : r.n;
    march_obs_crash *ring = (march_obs_crash *)malloc(sizeof *ring * (size_t)want);
    if (!ring) { audit("CRASHES_FULL", &r, "out_of_memory"); return "out_of_memory"; }
    uint64_t total = 0;
    int m = march_obs_crashes(ring, (int)want, &total);
    audit("CRASHES_FULL", &r, "ok");
    march_jw_obj_begin(w);
    march_jw_key(w, "total"); march_jw_u64(w, total);
    march_jw_key(w, "crashes");
    march_jw_arr_begin(w);
    for (int i = 0; i < m; i++) {
        const march_obs_crash *c = &ring[i];
        march_jw_obj_begin(w);
        march_jw_key(w, "seq");  march_jw_u64(w, c->seq);
        march_jw_key(w, "kind"); march_jw_str(w, crash_kind(c->kind));
        march_jw_key(w, "pid");
        if (c->pid >= 0) march_jw_i64(w, c->pid); else march_jw_null(w);
        march_jw_key(w, "type");
        if (c->type[0]) march_jw_str(w, c->type); else march_jw_null(w);
        march_jw_key(w, "code_epoch"); march_jw_u64(w, c->code_epoch);
        march_jw_key(w, "supervisor");
        if (c->supervisor >= 0) march_jw_i64(w, c->supervisor); else march_jw_null(w);
        march_jw_key(w, "restart"); march_jw_i64(w, c->restart);
        march_jw_key(w, "at_ms");   march_jw_i64(w, c->at_ms);
        march_jw_key(w, "message"); march_jw_strn(w, c->message, c->message_len);
        march_jw_obj_end(w);
    }
    march_jw_arr_end(w);
    march_jw_obj_end(w);
    free(ring);
    return NULL;
}

static const march_observe_verb debug_verbs[] = {
    { "STATE", "debug", "<sig> nonce:<hex> not_after_ms:<t> pid:<p> [timeout_ms:<t>]",
      "an actor's state as Actor.inspect_state renders it (signed; $MARCH_DEBUG_POLICY)",
      verb_state },
    { "CRASHES_FULL", "debug", "<sig> nonce:<hex> not_after_ms:<t> [n:<n>]",
      "CRASHES with each crash's message (signed; $MARCH_DEBUG_POLICY)",
      verb_crashes_full },
};

void march_observe_debug_install(void) {
    static int done;
    if (done) return;
    done = 1;
    (void)march_observe_add_verbs(debug_verbs, sizeof debug_verbs / sizeof debug_verbs[0]);
}
