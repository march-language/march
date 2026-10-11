/* march_observe_debug.c — the observe socket's signed debug verbs (R4 of
 * specs/plans/2026-09-28-observe-recon-shell-plan.md).
 *
 *   STATE        <sig> nonce:<hex> not_after_ms:<t> pid:<p> [timeout_ms:<t>]
 *   CRASHES_FULL <sig> nonce:<hex> not_after_ms:<t> [n:<n>]
 *   TRACE_START  <sig> ... (count:<n> | rate:<n> per_s:<s>) fn:<a,b,..> [ring:<r>]
 *   TRACE_DRAIN  <sig> ... session:<id> [max:<n>]
 *   TRACE_STOP   <sig> ... session:<id>
 *
 * Every signed request also carries boot:<hex>, the node's HELLO answer: the
 * signature then names THIS process of THIS node, so a captured line cannot
 * be replayed after a restart or against another node holding the same key
 * (the F1/F2 findings of the shell review, specs/reviews/2026-10-07-shell-r5-
 * review-packet.md; the observe socket serves one request per connection, so
 * the challenge is per process, not per connection).
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
#include "march_dispatch.h"
#include "march_trace.h"

#include <ctype.h>

#include <stdlib.h>
#include <string.h>
#include <sys/time.h>

#define STATE_TIMEOUT_DEFAULT_MS 1000
#define STATE_TIMEOUT_MAX_MS     10000
#define CRASHES_FULL_DEFAULT_N   20
#define TRACE_DRAIN_DEFAULT      1024

static int64_t wall_ms(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (int64_t)tv.tv_sec * 1000 + tv.tv_usec / 1000;
}

/* The parsed request.  -1 marks an absent number. */
enum { K_PID, K_TIMEOUT, K_N, K_COUNT, K_RATE, K_PER_S, K_RING, K_SESSION, K_MAX, K_NUM };
static const char *const num_keys[K_NUM] = {
    "pid", "timeout_ms", "n", "count", "rate", "per_s", "ring", "session", "max"
};

typedef struct {
    char    sig[160];
    char    nonce[MARCH_SIG_NONCE_MAX + 2];
    char    boot[40];
    char    fn[1024];              /* TRACE_START's comma-separated names */
    int     local;                 /* in-process caller: the cap is the authority */
    int64_t not_after_ms;
    int64_t v[K_NUM];
} dbg_req;

static void audit(const char *verb, const dbg_req *r, const char *result,
                  const char *detail) {
    FILE *f = march_audit_open();
    if (!f) return;
    char signer[65];
    if (r->local) snprintf(signer, sizeof signer, "in-process");
    else march_sig_pubkey_hex(signer);
    fprintf(f, "{\"ts\":%lld,\"type\":\"debug\",\"verb\":\"%s\",\"pid\":",
            (long long)wall_ms(), verb);
    if (r->v[K_PID] >= 0) fprintf(f, "%lld", (long long)r->v[K_PID]); else fputs("null", f);
    /* The nonce went through isxdigit when admitted; one that did not is
     * printed only as far as it is hex, so it can never break the line. */
    fputs(",\"nonce\":\"", f);
    for (const char *p = r->nonce; *p && strchr("0123456789abcdefABCDEF", *p); p++) fputc(*p, f);
    fprintf(f, "\",\"signer\":\"%s\",\"result\":\"%s\"", signer, result);
    /* [detail] is built by the verb from numbers and names that passed
     * valid_fn_list, so it needs no escaping. */
    if (detail) fprintf(f, ",\"detail\":\"%s\"", detail);
    fputs("}\n", f);
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

/* A function-name list: [A-Za-z0-9_.$] names joined by single commas. */
static int valid_fn_list(const char *v) {
    if (!*v) return 0;
    int prev_comma = 1;
    for (const char *p = v; *p; p++) {
        if (*p == ',') { if (prev_comma) return 0; prev_comma = 1; continue; }
        if (!(isalnum((unsigned char)*p) || *p == '_' || *p == '.' || *p == '$')) return 0;
        prev_comma = 0;
    }
    return !prev_comma;
}

/* Parse "<sig> k:v k:v ..." for [verb], verify and admit it, check the
 * policy.  NULL when the request may run, else the error code.  [allowed]
 * lists the keys this verb takes besides nonce, boot and not_after_ms.
 *
 * An in-process caller (Trace.start from March code, through observe_query)
 * sends no signature, nonce, boot or expiry: holding Cap(Actor.Debug) is its
 * authority, as it is for Actor.inspect_state.  Its request is still parsed
 * the same way, audited with signer "in-process", and not checked against
 * the policy file. */
static const char *admit(const char *verb, const char *args, const char *allowed,
                         dbg_req *r) {
    memset(r, 0, sizeof *r);
    r->not_after_ms = -1;
    for (int i = 0; i < K_NUM; i++) r->v[i] = -1;
    r->local = march_observe_in_process();
    if (!r->local && !march_sig_key_loaded()) return "signing_not_configured";

    while (*args == ' ') args++;
    const char *rest = args;
    if (!r->local) {
        const char *sp = strchr(args, ' ');
        size_t sl = sp ? (size_t)(sp - args) : strlen(args);
        if (sl == 0 || sl >= sizeof r->sig) return "bad_args";
        memcpy(r->sig, args, sl);
        rest = sp ? sp + 1 : "";
        while (*rest == ' ') rest++;
    }

    /* strtok_r, not strtok: up to MARCH_OBSERVE_MAX_CONNS connection threads
     * parse requests at once. */
    char buf[MARCH_OBSERVE_LINE_MAX + 1];
    snprintf(buf, sizeof buf, "%s", rest);
    char *save = NULL;
    for (char *tok = strtok_r(buf, " ", &save); tok; tok = strtok_r(NULL, " ", &save)) {
        char *colon = strchr(tok, ':');
        if (!colon) return "bad_args";
        *colon = '\0';
        const char *k = tok, *v = colon + 1;
        if (strcmp(k, "nonce") == 0) {
            if (r->local || r->nonce[0] || strlen(v) > MARCH_SIG_NONCE_MAX) return "bad_args";
            snprintf(r->nonce, sizeof r->nonce, "%s", v);
            continue;
        }
        if (strcmp(k, "boot") == 0) {
            if (r->local || r->boot[0] || strlen(v) >= sizeof r->boot) return "bad_args";
            snprintf(r->boot, sizeof r->boot, "%s", v);
            continue;
        }
        if (strcmp(k, "not_after_ms") == 0) {
            if (r->local || r->not_after_ms != -1 || !parse_num(v, &r->not_after_ms)
                    || r->not_after_ms < 0) return "bad_args";
            continue;
        }
        if (!has_word(allowed, k)) return "bad_args";
        if (strcmp(k, "fn") == 0) {
            if (r->fn[0] || !valid_fn_list(v) || strlen(v) >= sizeof r->fn) return "bad_args";
            snprintf(r->fn, sizeof r->fn, "%s", v);
            continue;
        }
        int64_t *slot = NULL;
        for (int i = 0; i < K_NUM; i++)
            if (strcmp(k, num_keys[i]) == 0) slot = &r->v[i];
        if (!slot) return "bad_args";
        if (*slot != -1 || !parse_num(v, slot) || *slot < 0) return "bad_args";
    }
    if (r->local) return NULL;
    if (!r->nonce[0] || r->not_after_ms < 0 || !r->boot[0]) return "bad_args";

    /* The signed text: the line without its signature word. */
    size_t mlen = strlen(verb) + 1 + strlen(rest) + 1;
    char *msg = (char *)malloc(mlen);
    if (!msg) return "out_of_memory";
    snprintf(msg, mlen, "%s %s", verb, rest);
    int ok = march_sig_verify(msg, r->sig);
    free(msg);
    if (!ok) return "bad_signature";

    /* Signed for another process of this node, or another node: refused
     * before the nonce is spent. */
    if (strcmp(r->boot, march_sig_boot_id()) != 0) return "wrong_boot";
    const char *why = march_sig_admit(r->nonce, r->not_after_ms, wall_ms());
    if (why) return why;
    if (!march_sig_debug_allowed(verb)) return "policy";
    return NULL;
}

/* ── STATE ────────────────────────────────────────────────────────────── */

static const char *verb_state(march_jw *w, const char *args) {
    dbg_req r;
    const char *err = admit("STATE", args, "pid timeout_ms", &r);
    if (!err && r.v[K_PID] < 0) err = "bad_args";
    /* A green thread (observe_query) must not block its scheduler on the
     * reply: the actor it waits for may need that very scheduler. */
    if (!err && march_sched_current()) err = "not_from_a_green_thread";
    if (err) { audit("STATE", &r, err, NULL); return err; }

    int64_t timeout = r.v[K_TIMEOUT] < 0 ? STATE_TIMEOUT_DEFAULT_MS : r.v[K_TIMEOUT];
    if (timeout > STATE_TIMEOUT_MAX_MS) timeout = STATE_TIMEOUT_MAX_MS;
    char *text = NULL;
    int ok = march_actor_inspect_external(r.v[K_PID], timeout, &text);
    audit("STATE", &r, "ok", NULL);
    march_jw_obj_begin(w);
    march_jw_key(w, "pid");   march_jw_i64(w, r.v[K_PID]);
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
    if (!err && r.v[K_N] == 0) err = "bad_args";
    if (!err && r.v[K_N] > MARCH_CRASH_RING) err = "bad_args";
    if (err) { audit("CRASHES_FULL", &r, err, NULL); return err; }
    int64_t want = r.v[K_N] < 0 ? CRASHES_FULL_DEFAULT_N : r.v[K_N];
    march_obs_crash *ring = (march_obs_crash *)malloc(sizeof *ring * (size_t)want);
    if (!ring) { audit("CRASHES_FULL", &r, "out_of_memory", NULL); return "out_of_memory"; }
    uint64_t total = 0;
    int m = march_obs_crashes(ring, (int)want, &total);
    audit("CRASHES_FULL", &r, "ok", NULL);
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

/* ── HELLO, TRACE_* ───────────────────────────────────────────────────── */

/* Observe tier, unsigned: what a client needs before it signs a debug
 * request.  boot is this process's random id, which every signed request
 * must name (see the file comment); signing says whether the binary has a
 * deploy key at all. */
static const char *verb_hello(march_jw *w, const char *args) {
    (void)args;
    march_jw_obj_begin(w);
    march_jw_key(w, "boot");    march_jw_str(w, march_sig_boot_id());
    march_jw_key(w, "signing"); march_jw_bool(w, march_sig_key_loaded());
    march_jw_obj_end(w);
    return NULL;
}

static void write_limit(march_jw *w, int kind, int64_t n, int64_t per_s) {
    march_jw_obj_begin(w);
    march_jw_key(w, "kind"); march_jw_str(w, kind == MARCH_TRACE_COUNT ? "count" : "rate");
    march_jw_key(w, "n");    march_jw_i64(w, n);
    if (kind == MARCH_TRACE_RATE) { march_jw_key(w, "per_s"); march_jw_i64(w, per_s); }
    march_jw_obj_end(w);
}

static const char *verb_trace_start(march_jw *w, const char *args) {
    dbg_req r;
    const char *err = admit("TRACE_START", args, "count rate per_s ring fn", &r);
    int has_count = r.v[K_COUNT] >= 0, has_rate = r.v[K_RATE] >= 0, has_per = r.v[K_PER_S] >= 0;
    char detail[160] = "";
    if (!err) {
        /* No limit, no trace: there is no spelling of this verb without one. */
        if (!has_count && !has_rate && !has_per) err = "limit_required";
        else if (has_count && (has_rate || has_per)) err = "bad_args";
        else if (has_rate != has_per) err = "bad_args";
        else if (!r.fn[0]) err = "bad_args";
    }
    const char *names[MARCH_TRACE_MAX_FNS + 1];
    int nn = 0;
    int64_t id = 0;
    int kind = has_count ? MARCH_TRACE_COUNT : MARCH_TRACE_RATE;
    int64_t a = has_count ? r.v[K_COUNT] : r.v[K_RATE];
    int64_t b = has_count ? 0 : r.v[K_PER_S];
    if (!err) {
        char *save = NULL;
        for (char *t = strtok_r(r.fn, ",", &save); t; t = strtok_r(NULL, ",", &save)) {
            if (nn >= MARCH_TRACE_MAX_FNS) { err = "bad_args"; break; }
            if (strlen(t) >= MARCH_TRACE_NAME_MAX) { err = "bad_args"; break; }
            names[nn++] = t;
        }
    }
    if (!err)
        err = march_trace_start((march_trace_kind)kind, a, b,
                                r.v[K_RING] < 0 ? 0 : r.v[K_RING], names, nn, &id);
    if (err) {
        snprintf(detail, sizeof detail, "limit=%lld/%lld",
                 (long long)(has_count ? r.v[K_COUNT] : r.v[K_RATE]),
                 (long long)(has_per ? r.v[K_PER_S] : 0));
        audit("TRACE_START", &r, err, detail);
        return err;
    }
    snprintf(detail, sizeof detail, "session=%lld %s=%lld fns=%d",
             (long long)id, kind == MARCH_TRACE_COUNT ? "count" : "rate", (long long)a, nn);
    audit("TRACE_START", &r, "ok", detail);
    int64_t cap = kind == MARCH_TRACE_COUNT ? a
                : r.v[K_RING] > 0 ? r.v[K_RING] : MARCH_TRACE_RING_DEFAULT;
    march_jw_obj_begin(w);
    march_jw_key(w, "session"); march_jw_i64(w, id);
    march_jw_key(w, "limit");   write_limit(w, kind, a, b);
    march_jw_key(w, "ring");    march_jw_i64(w, cap);
    march_jw_key(w, "functions");
    march_jw_arr_begin(w);
    for (int i = 0; i < nn; i++) march_jw_str(w, names[i]);
    march_jw_arr_end(w);
    march_jw_key(w, "lifetime_s"); march_jw_i64(w, MARCH_TRACE_LIFETIME_S);
    march_jw_key(w, "idle_s");     march_jw_i64(w, MARCH_TRACE_IDLE_S);
    march_jw_obj_end(w);
    return NULL;
}

static void write_status(march_jw *w, const march_trace_status *st) {
    march_jw_key(w, "recorded");     march_jw_u64(w, st->recorded);
    march_jw_key(w, "dropped");      march_jw_u64(w, st->dropped);
    march_jw_key(w, "rate_dropped"); march_jw_u64(w, st->rate_dropped);
    march_jw_key(w, "pending");      march_jw_u64(w, st->pending);
    march_jw_key(w, "done");         march_jw_bool(w, st->done);
    march_jw_key(w, "why");
    if (st->why) march_jw_str(w, st->why); else march_jw_null(w);
    march_jw_key(w, "now_ns");       march_jw_u64(w, st->now_ns);
}

static const char *verb_trace_drain(march_jw *w, const char *args) {
    dbg_req r;
    const char *err = admit("TRACE_DRAIN", args, "session max", &r);
    if (!err && r.v[K_SESSION] < 0) err = "bad_args";
    if (!err && r.v[K_MAX] == 0) err = "bad_args";
    if (!err && r.v[K_MAX] > MARCH_TRACE_DRAIN_MAX) err = "bad_args";
    char detail[64] = "";
    if (err) { audit("TRACE_DRAIN", &r, err, NULL); return err; }
    snprintf(detail, sizeof detail, "session=%lld", (long long)r.v[K_SESSION]);
    int max = r.v[K_MAX] < 0 ? TRACE_DRAIN_DEFAULT : (int)r.v[K_MAX];
    march_trace_event *ev = (march_trace_event *)malloc(sizeof *ev * (size_t)max);
    if (!ev) { audit("TRACE_DRAIN", &r, "out_of_memory", detail); return "out_of_memory"; }
    march_trace_status st;
    int k = march_trace_drain(r.v[K_SESSION], max, ev, &st);
    if (k < 0) { free(ev); audit("TRACE_DRAIN", &r, "not_found", detail); return "not_found"; }
    audit("TRACE_DRAIN", &r, "ok", detail);
    march_jw_obj_begin(w);
    march_jw_key(w, "session"); march_jw_i64(w, r.v[K_SESSION]);
    march_jw_key(w, "events");
    march_jw_arr_begin(w);
    for (int i = 0; i < k; i++) {
        const char *nm = march_dispatch_id_to_name(ev[i].name_id);
        march_jw_obj_begin(w);
        march_jw_key(w, "pid");     march_jw_i64(w, ev[i].pid);
        march_jw_key(w, "fn");
        if (nm) march_jw_str(w, nm); else march_jw_null(w);
        march_jw_key(w, "name_id"); march_jw_u64(w, ev[i].name_id);
        march_jw_key(w, "epoch");   march_jw_u64(w, ev[i].epoch);
        march_jw_key(w, "at_ns");   march_jw_u64(w, ev[i].at_ns);
        march_jw_obj_end(w);
    }
    march_jw_arr_end(w);
    write_status(w, &st);
    march_jw_obj_end(w);
    free(ev);
    return NULL;
}

static const char *verb_trace_stop(march_jw *w, const char *args) {
    dbg_req r;
    const char *err = admit("TRACE_STOP", args, "session", &r);
    if (!err && r.v[K_SESSION] < 0) err = "bad_args";
    char detail[64] = "";
    if (err) { audit("TRACE_STOP", &r, err, NULL); return err; }
    snprintf(detail, sizeof detail, "session=%lld", (long long)r.v[K_SESSION]);
    march_trace_status st;
    if (march_trace_stop(r.v[K_SESSION], &st) < 0) {
        audit("TRACE_STOP", &r, "not_found", detail);
        return "not_found";
    }
    audit("TRACE_STOP", &r, "ok", detail);
    march_jw_obj_begin(w);
    march_jw_key(w, "session"); march_jw_i64(w, r.v[K_SESSION]);
    write_status(w, &st);
    march_jw_obj_end(w);
    return NULL;
}

#define SIGNED "<sig> nonce:<hex> boot:<hex> not_after_ms:<t>"
static const march_observe_verb debug_verbs[] = {
    { "HELLO", "observe", "",
      "this process's boot id (name it in every signed request) and whether signing is configured",
      verb_hello },
    { "TRACE_START", "debug", SIGNED " (count:<n> | rate:<n> per_s:<s>) fn:<a,b,..> [ring:<r>]",
      "start a bounded trace of boundary calls; a limit is mandatory (signed; $MARCH_DEBUG_POLICY)",
      verb_trace_start },
    { "TRACE_DRAIN", "debug", SIGNED " session:<id> [max:<n>]",
      "take the session's events so far: pid, function, epoch, time; never arguments (signed; $MARCH_DEBUG_POLICY)",
      verb_trace_drain },
    { "TRACE_STOP", "debug", SIGNED " session:<id>",
      "stop and free a trace session (signed; $MARCH_DEBUG_POLICY)",
      verb_trace_stop },
    { "STATE", "debug", SIGNED " pid:<p> [timeout_ms:<t>]",
      "an actor's state as Actor.inspect_state renders it (signed; $MARCH_DEBUG_POLICY)",
      verb_state },
    { "CRASHES_FULL", "debug", SIGNED " [n:<n>]",
      "CRASHES with each crash's message (signed; $MARCH_DEBUG_POLICY)",
      verb_crashes_full },
};

void march_observe_debug_install(void) {
    static int done;
    if (done) return;
    done = 1;
    (void)march_observe_add_verbs(debug_verbs, sizeof debug_verbs / sizeof debug_verbs[0]);
}
