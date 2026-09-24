/* march_reload.c — HCR Phase 3/4/7 reload server (Linux + macOS, Unix-domain socket).
 *
 * Protocol (newline-terminated text):
 *   PING                                          → PONG
 *   ABI_QUERY                                     → SLOT <id> <name> <impl_hash> <sig_hash> …, END
 *   VERSIONS                                      → VERSION <name> baseline <h> [hot <h>] …, END
 *   VERSIONS_DETAIL                               → SLOT <id> <name> <impl_hash> <activated_at_ms> <signer_hex> …, END
 *   CAS_CHECK <compilation_hash>                  → PRESENT | MISSING
 *   CAS_PUT <compilation_hash> <size_bytes>\n     → READY\n
 *     <binary data, exactly size_bytes>           → OK <hash> | ERR <reason>
 *   ACTIVATE  <name> <impl_hash> <cas_hash> <sig64>  → OK <impl_hash> | ERR <reason>  (v1, legacy)
 *   ACTIVATE2 <name> <impl_hash> <cas_hash> <sig64> <migrate> epoch:<N> callers:<sorted-csv>
 *                                                   → OK <impl_hash> | ERR <reason>  (v2, signed epoch+callers)
 *   ACTIVATE3 <name> <impl_hash> <cas_hash> <sig64> <migrate> epoch:<N> callers:<sorted-csv>
 *                                                   → OK <impl_hash> | ERR <reason>  (v3, migrate_required signed)
 *   ACTIVATE4 <name> <impl_hash> <cas_hash> <sig64> <migrate> epoch:<N> cap_root:<hex>
 *             caps:<sorted-csv> callers:<sorted-csv>
 *                                                   → OK <impl_hash> | ERR <reason>  (v4, cap_root admission)
 *     ACTIVATE4 recomputes cap_root server-side from the (unsigned) `caps:` set
 *     — sort+uniq, march_cap_normalize, join with '\n', BLAKE3 — and rejects a
 *     mismatch with the signed `cap_root` (ERR cap_tamper). This tamper check
 *     is ALWAYS performed within ACTIVATE4, even when `caps:` is empty: a
 *     genuinely capless artifact's signed cap_root is blake3(""), a specific
 *     known value, so an empty received set still recomputes correctly and
 *     admits, while a stripped-caps forgery of a real (non-empty) artifact
 *     recomputes to blake3("") which will NOT match the signed (non-empty)
 *     cap_root and is rejected. (Legacy-shaped/no-cap-root artifacts arrive
 *     over ACTIVATE3, distinguished by the verb, not by empty caps here.) If
 *     $MARCH_DEPLOY_POLICY names a file of permitted cap paths, every received
 *     cap must be subsumed by some policy entry (ERR cap_policy <cap>); the
 *     policy gate is a no-op when the received cap set is empty (trivially
 *     satisfied — there is nothing to violate).
 *   ACTIVATE5 <name> <impl_hash> <cas_hash> <sig64> <migrate> epoch:<N> cap_root:<hex>
 *             caps:<sorted-csv> callers:<sorted-csv>
 *                                                   → OK | WAIT … | ERR <reason>  (v5)
 *     As ACTIVATE4, but <migrate> is a bitmask: 1 = the actor's state schema
 *     changed (run __migrate_<Actor>), 2 = its message type changed
 *     (D30/II.4.6: old-format messages take __migrate_msg_<Actor>, or are
 *     dropped).  A new verb because the signed message changes meaning
 *     (the ACTIVATE3/4 precedent): an older server rejects it outright
 *     instead of misreading "3" as "no migration".
 *   BEGIN_BATCH                                       → OK
 *   COMMIT_BATCH                                      → OK <n> | WAIT … | ERR <reason>
 *   ROLLBACK_BATCH                                    → OK
 *   PINS                                              → EPOCH <e> pins:<n> [current] [draining] …,
 *                                                       COUNTERS deferred:<n> converted:<n>
 *                                                       dropped:<n> killed:<n> stopped:<n>
 *                                                       advances:<n> early:<n> forced:<n>
 *                                                       markers_live:<n> markers_lost:<n>, END
 *   DRAIN epoch:<E> [soft_ms:<n>] [hard_ms:<n>]      → OK  (drain every epoch <= E)
 *
 * The epoch model (specs/plans/2026-09-21-distributed-authority-and-deploys-
 * plan.md, II.4): every activation (single, or a whole batch) is ONE deploy
 * with its own runtime epoch (march_hcr_activate).  When some slot has no
 * reclaimable version, or the epoch pin table is full, nothing changes and
 * the answer is
 *     WAIT epoch:<E> pins:<n> deadline_ms:<t>
 * (E: the oldest pinned epoch, n: its units, t: ms to its hard drain
 * deadline, -1 if none).  A batch stays staged on the connection; the client
 * sends COMMIT_BATCH (or the single ACTIVATE) again to retry.
 *
 * Artifact CAS layout (server side):
 *   ~/.march/cas/artifacts/<2>/<62>
 *   where <2> = first 2 chars of compilation_hash, <62> = remaining 62 chars.
 *
 * Audit log: every ACTIVATE appends a JSON line to $MARCH_AUDIT_LOG
 *   (default: ${XDG_DATA_HOME:-$HOME/.local/share}/march/audit.jsonl).
 *   Fields: ts, type, fn, impl_hash, signer, cas_hash, caps, cap_root, result
 *   (caps/cap_root: ACTIVATE4 only, null for older protocols; see
 *   write_audit_log).
 */
#if defined(__linux__) || defined(__APPLE__)

#include "march_reload.h"
#include "march_dispatch.h"
#include "march_runtime.h"
#include "march_cap_lattice.h"
#include "march_blake3.h"
#include "tweetnacl.h"
#include <stdatomic.h>
#include <pthread.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>
#include <errno.h>
#include <sys/time.h>

#ifndef MARCH_HCR_TRIPLE
#define MARCH_HCR_TRIPLE ""
#endif
#ifndef MARCH_HCR_TARGET
#define MARCH_HCR_TARGET ""
#endif
#ifndef MARCH_HCR_PREFIX
#define MARCH_HCR_PREFIX ""
#endif
#define MARCH_HCR_STRINGIFY1(x) #x
#define MARCH_HCR_STRINGIFY(x) MARCH_HCR_STRINGIFY1(x)
#define MARCH_HCR_ABI_ID "march-hcr-v2;triple=" MARCH_HCR_STRINGIFY(MARCH_HCR_TRIPLE) ";ptr=8"

/* ── Signing public key (embedded at build time) ──────────────────────── */
/* Generated by the compiler when --signing-pubkey is passed.
 * All-zeros → signing not configured → ACTIVATE always rejects. */
#ifdef MARCH_SIGNING_PUBKEY_HEX
static unsigned char g_pubkey[32];
static int           g_pubkey_loaded = 0;

static int hex_nibble(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

static void load_pubkey_from_hex(void) {
    const char *hex = MARCH_SIGNING_PUBKEY_HEX;
    int ok = (strlen(hex) == 64);
    for (int i = 0; i < 32 && ok; i++) {
        int hi = hex_nibble(hex[2*i]);
        int lo = hex_nibble(hex[2*i+1]);
        if (hi < 0 || lo < 0) { ok = 0; break; }
        g_pubkey[i] = (unsigned char)((hi << 4) | lo);
    }
    g_pubkey_loaded = ok;
}
#define HAVE_SIGNING_KEY 1
#else
static const unsigned char g_pubkey[32] = {0};
static const int           g_pubkey_loaded = 0;
#define HAVE_SIGNING_KEY 0
#endif

/* ── Base64 decode (URL-safe, no-padding) ─────────────────────────────── */

static int b64_val(unsigned char c) {
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    if (c == '+' || c == '-') return 62;
    if (c == '/' || c == '_') return 63;
    if (c == '=')             return 0;
    return -1;
}

/* Decode URL-safe base64 (no padding) → raw bytes.
 * Returns decoded length, or -1 on invalid input.
 * out must hold at least ceil(inlen * 3 / 4) bytes. */
static int b64_decode(const char *in, size_t inlen, unsigned char *out) {
    int olen = 0;
    size_t i = 0;
    while (i < inlen) {
        unsigned char c0 = (i < inlen) ? (unsigned char)in[i++] : '=';
        unsigned char c1 = (i < inlen) ? (unsigned char)in[i++] : '=';
        unsigned char c2 = (i < inlen) ? (unsigned char)in[i++] : '=';
        unsigned char c3 = (i < inlen) ? (unsigned char)in[i++] : '=';
        int v0 = b64_val(c0), v1 = b64_val(c1), v2 = b64_val(c2), v3 = b64_val(c3);
        if (v0 < 0 || v1 < 0 || v2 < 0 || v3 < 0) return -1;
        out[olen++] = (unsigned char)((v0 << 2) | (v1 >> 4));
        if (c2 != '=') out[olen++] = (unsigned char)(((v1 & 0xf) << 4) | (v2 >> 2));
        if (c3 != '=') out[olen++] = (unsigned char)(((v2 & 0x3) << 6) | v3);
    }
    return olen;
}

#define RELOAD_BACKLOG  4
#define RELOAD_LINE_MAX 4096
#define CAS_HASH_LEN    64      /* compilation_hash: 64 hex chars */
#define CAS_MAX_ARTIFACT (64 * 1024 * 1024)  /* 64 MB sanity limit */

static char g_socket_path[256];
static char g_cas_root[512];    /* ~/.march/cas */

static void write_safe(int fd, const char *buf, int snprintf_ret, size_t bufsz);
static void pubkey_to_hex(char out[65]);

static void hcr_info_response(int fd) {
    char key[65]; pubkey_to_hex(key);
    char resp[512];
    int n = snprintf(resp, sizeof(resp),
        "HCR_INFO target:%s abi:%s prefix:%s key:%s\n",
        MARCH_HCR_TARGET, MARCH_HCR_ABI_ID, MARCH_HCR_PREFIX, key);
    write_safe(fd, resp, n, sizeof(resp));
}

int march_hcr_patch_identity_ok(void *handle, char *reason, size_t reason_len) {
    const char *a = (const char *)dlsym(handle, "__march_hcr_abi");
    const char *t = (const char *)dlsym(handle, "__march_hcr_target");
    const char *pr = (const char *)dlsym(handle, "__march_hcr_prefix");
    if (!a || !t || !pr) { snprintf(reason, reason_len, "missing marker"); return 0; }
    if (strcmp(a, MARCH_HCR_ABI_ID) != 0) { snprintf(reason, reason_len, "abi mismatch"); return 0; }
    if (strcmp(t, MARCH_HCR_TARGET) != 0) { snprintf(reason, reason_len, "target mismatch"); return 0; }
    if (strcmp(pr, MARCH_HCR_PREFIX) != 0) { snprintf(reason, reason_len, "prefix mismatch"); return 0; }
    return 1;
}

/* Phase 9: monotonic deploy epoch counter, persisted across server restarts. */
static _Atomic(uint32_t) g_next_epoch;  /* initialised in reload_server_thread */

static void persist_next_epoch(uint32_t next) {
    char path[640], tmp[660];
    snprintf(path, sizeof(path), "%s/next_epoch", g_cas_root);
    snprintf(tmp,  sizeof(tmp),  "%s.tmp",        path);
    FILE *f = fopen(tmp, "w");
    if (!f) return;
    fprintf(f, "%u\n", next);
    fclose(f);
    rename(tmp, path);  /* atomic on POSIX */
}

static uint32_t load_next_epoch(void) {
    char path[640];
    snprintf(path, sizeof(path), "%s/next_epoch", g_cas_root);
    FILE *f = fopen(path, "r");
    if (!f) return 1;  /* first run: start at epoch 1 */
    uint32_t v = 1;
    fscanf(f, "%u", &v);
    fclose(f);
    return v > 0 ? v : 1;
}

/* ── CAS path helpers ────────────────────────────────────────────────── */

/* Validate that s is exactly 64 lowercase-hex characters (CAS hash format). */
static int is_hex64(const char *s) {
    if (!s || s[CAS_HASH_LEN] != '\0') return 0;
    for (int i = 0; i < CAS_HASH_LEN; i++) {
        char c = s[i];
        if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')))
            return 0;
    }
    return 1;
}

static void cas_artifact_path(char *out, size_t outsz, const char *hash) {
    snprintf(out, outsz, "%s/artifacts/%.2s/%.62s", g_cas_root, hash, hash + 2);
}

static void mkdir_p(const char *path) {
    char tmp[512]; snprintf(tmp, sizeof(tmp), "%s", path);
    for (char *p = tmp + 1; *p; p++) {
        if (*p == '/') { *p = '\0'; mkdir(tmp, 0755); *p = '/'; }
    }
    mkdir(tmp, 0755);
}

/* Read a newline-terminated line into buf (NUL-terminated, newline stripped).
 * Returns bytes read (>=0), -1 on EOF/error, or -(max-1) if the line was
 * truncated (too long).  On truncation the stream is drained to the next '\n'
 * so subsequent commands are not desynced. */
static int read_line(int fd, char *buf, int max) {
    int n = 0;
    while (1) {
        char c;
        int r = (int)read(fd, &c, 1);
        if (r <= 0) return r ? r : -1;
        if (c == '\n') break;
        if (c == '\r') continue;
        if (n < max - 1) buf[n++] = c;
        /* else: buffer full — keep draining until '\n' to avoid desync */
    }
    buf[n] = '\0';
    return (n < max - 1) ? n : -(max - 1);
}

/* Read exactly nbytes from fd into buf. Returns 0 on success, -1 on error/EOF. */
static int read_exact(int fd, unsigned char *buf, size_t nbytes) {
    size_t got = 0;
    while (got < nbytes) {
        ssize_t r = read(fd, buf + got, nbytes - got);
        if (r <= 0) return -1;
        got += (size_t)r;
    }
    return 0;
}

static void wresp(int fd, const char *s) { write(fd, s, strlen(s)); }

/* Write the result of snprintf safely: clamp to bufsz-1 to guard against
 * the snprintf+write overread (snprintf returns would-have-written, not
 * actually-written; writing that many bytes reads off the end of the buffer
 * when the format string's inputs exceed bufsz). */
static void write_safe(int fd, const char *buf, int snprintf_ret, size_t bufsz) {
    int n = snprintf_ret < (int)bufsz ? snprintf_ret : (int)bufsz - 1;
    if (n > 0) write(fd, buf, (size_t)n);
}

/* ── Audit log ───────────────────────────────────────────────────────────── */

static void pubkey_to_hex(char out[65]) {
    out[0] = '\0';
#if HAVE_SIGNING_KEY
    if (!g_pubkey_loaded) return;
    static const char hc[] = "0123456789abcdef";
    for (int i = 0; i < 32; i++) {
        out[2*i]   = hc[(g_pubkey[i] >> 4) & 0xf];
        out[2*i+1] = hc[g_pubkey[i] & 0xf];
    }
    out[64] = '\0';
#endif
}

/* Capability data for one audit line.  Only ACTIVATE4 carries any; every
 * older protocol passes NULL, which the log records as "caps":null,
 * "cap_root":null, distinct from an ACTIVATE4 with an empty cap set ([]).
 * Borrowed pointers: the log copies nothing past the call. */
typedef struct {
    const char *caps;       /* comma-separated, as received on the wire */
    const char *cap_root;   /* signed 64-hex root */
} audit_caps_t;

/* Write s as a JSON string literal (quotes included). */
static void json_write_str(FILE *f, const char *s, size_t n) {
    fputc('"', f);
    for (size_t i = 0; i < n; i++) {
        unsigned char c = (unsigned char)s[i];
        if (c == '"' || c == '\\') { fputc('\\', f); fputc(c, f); }
        else if (c < 0x20)          fprintf(f, "\\u%04x", c);
        else                        fputc(c, f);
    }
    fputc('"', f);
}

/* Append one JSON line to the audit log. Path is $MARCH_AUDIT_LOG, or
 * ${XDG_DATA_HOME:-$HOME/.local/share}/march/audit.jsonl by default.
 *
 * "caps"/"cap_root" record the capability set the deploy carried, so an
 * operator can answer "when did this system gain capability X" from the log
 * alone (a --grant-cap widening is part of that signed set).  They are the
 * values AS RECEIVED: verified against the signed cap_root only when result
 * is "ok", "err_cap_policy", or a post-admission error (err_cas_miss,
 * err_dlopen, ...); on "err_sig"/"err_cap_tamper" they are exactly what the
 * rejected request claimed. */
static void write_audit_log(const char *fn, const char *impl_hash,
                             const char *cas_hash, const audit_caps_t *ac,
                             const char *result) {
    const char *log_path = getenv("MARCH_AUDIT_LOG");
    char default_path[512];
    if (!log_path || !log_path[0]) {
        const char *xdg = getenv("XDG_DATA_HOME");
        if (xdg && xdg[0])
            snprintf(default_path, sizeof(default_path), "%s/march/audit.jsonl", xdg);
        else {
            const char *home = getenv("HOME");
            if (!home || !home[0]) return;
            snprintf(default_path, sizeof(default_path),
                     "%s/.local/share/march/audit.jsonl", home);
        }
        log_path = default_path;
    }
    /* Ensure parent directory exists */
    char dir[512];
    snprintf(dir, sizeof(dir), "%s", log_path);
    char *slash = strrchr(dir, '/');
    if (slash) { *slash = '\0'; mkdir_p(dir); }

    struct timeval tv;
    gettimeofday(&tv, NULL);
    long long ts_ms = (long long)tv.tv_sec * 1000LL + (long long)tv.tv_usec / 1000;

    char signer[65]; pubkey_to_hex(signer);

    FILE *f = fopen(log_path, "a");
    if (!f) return;
    fprintf(f,
        "{\"ts\":%lld,\"type\":\"activate\",\"fn\":\"%s\","
        "\"impl_hash\":\"%s\",\"signer\":\"%s\","
        "\"cas_hash\":\"%s\",",
        ts_ms, fn ? fn : "", impl_hash ? impl_hash : "",
        signer, cas_hash ? cas_hash : "");
    if (ac && ac->caps) {
        fputs("\"caps\":[", f);
        const char *p = ac->caps;
        int first = 1;
        while (*p) {
            const char *comma = strchr(p, ',');
            size_t n = comma ? (size_t)(comma - p) : strlen(p);
            if (n > 0) {
                if (!first) fputc(',', f);
                json_write_str(f, p, n);
                first = 0;
            }
            if (!comma) break;
            p = comma + 1;
        }
        fputs("],\"cap_root\":", f);
        json_write_str(f, ac->cap_root ? ac->cap_root : "",
                       ac->cap_root ? strlen(ac->cap_root) : 0);
        fputc(',', f);
    } else {
        fputs("\"caps\":null,\"cap_root\":null,", f);
    }
    fprintf(f, "\"result\":\"%s\"}\n", result);
    fclose(f);
}

/* RTLD_DEEPBIND: prefer this .so's own symbols over the main executable's.
 * Without it, a hot-patched function resolves PLT calls to the compiled-in v1
 * instead of the v2 copies in the patch .so.  GNU extension; guard it. */
#ifndef RTLD_DEEPBIND
#define RTLD_DEEPBIND 0
#endif

/* Actor migration symbol: __migrate_<Actor>, from the ACTIVATE name
 * "<Actor>_dispatch" (dots in a module-qualified name become '_'). NULL if
 * the .so exports none (e.g. @compat(any) with schema changes and no
 * migrate_state fn): the actors still switch at their markers, unmigrated. */
typedef void *(*migrate_fn_t)(void *);
static migrate_fn_t resolve_migrate_fn(void *handle, const char *name,
                                       uint32_t slot_id) {
    char migrate_sym[320];
    const char *dispatch_sfx = "_dispatch";
    size_t name_len = strlen(name);
    size_t dsfx_len = strlen(dispatch_sfx);
    char actor_short[256];
    if (name_len > dsfx_len &&
        strcmp(name + name_len - dsfx_len, dispatch_sfx) == 0) {
        size_t alen = name_len - dsfx_len;
        if (alen >= sizeof(actor_short)) alen = sizeof(actor_short) - 1;
        strncpy(actor_short, name, alen);
        actor_short[alen] = '\0';
    } else {
        strncpy(actor_short, name, sizeof(actor_short) - 1);
        actor_short[sizeof(actor_short) - 1] = '\0';
    }
    snprintf(migrate_sym, sizeof(migrate_sym), "__migrate_%s", actor_short);
    for (char *p = migrate_sym + 10; *p; p++) {
        if (*p == '.') *p = '_';
    }
    void *raw_sym = dlsym(handle, migrate_sym);
    migrate_fn_t migrate_fn = NULL;
    if (raw_sym) {
        memcpy(&migrate_fn, &raw_sym, sizeof(migrate_fn));
        fprintf(stderr, "[hcr] migrate: found %s, migrating slot %u\n",
                migrate_sym, slot_id);
    } else {
        /* Log to stderr only — writing WARN before OK would desync the
         * client's response parser. */
        fprintf(stderr, "[hcr] migrate: symbol not found: %s (proceeding without migration)\n",
                migrate_sym);
    }
    return migrate_fn;
}

/* __migrate_msg_<Actor>: the compiler-generated wrapper around
 * <actor>_migrate_msg, called as fn(old_msg, none) -> new_msg or none. */
typedef void *(*migrate_msg_fn_t)(void *, void *);
static migrate_msg_fn_t resolve_migrate_msg_fn(void *handle, const char *name,
                                               uint32_t slot_id) {
    char sym[320];
    size_t name_len = strlen(name), dlen = strlen("_dispatch");
    size_t alen = (name_len > dlen && strcmp(name + name_len - dlen, "_dispatch") == 0)
                  ? name_len - dlen : name_len;
    if (alen > 255) alen = 255;
    snprintf(sym, sizeof(sym), "__migrate_msg_%.*s", (int)alen, name);
    for (char *p = sym + 14; *p; p++) if (*p == '.') *p = '_';
    void *raw = dlsym(handle, sym);
    migrate_msg_fn_t fn = NULL;
    if (raw) {
        memcpy(&fn, &raw, sizeof(fn));
        fprintf(stderr, "[hcr] migrate_msg: found %s for slot %u\n", sym, slot_id);
    } else {
        fprintf(stderr, "[hcr] migrate_msg: symbol not found: %s (old-format "
                "messages to slot %u will be dropped and counted)\n", sym, slot_id);
    }
    return fn;
}

#define MIGRATE_STATE 1
#define MIGRATE_MSGS  2

typedef struct {
    const char         *name, *impl_hash, *cas_hash, *callers;
    uint32_t            epoch;
    int                 migrate;   /* MIGRATE_STATE | MIGRATE_MSGS */
    const audit_caps_t *ac;
} act_item;

/* Activate [n] functions as one deploy.  Returns 0 (OK), 1 (WAIT: nothing
 * changed, [resp] holds the WAIT line) or -1 (error: nothing changed, [resp]
 * holds the ERR line). */
static int activate_items(const act_item *it, int n, char *resp, size_t rsz) {
    march_hcr_unit *u = (march_hcr_unit *)calloc((size_t)n, sizeof(*u));
    if (!u) { snprintf(resp, rsz, "ERR oom\n"); return -1; }
    int opened = 0, rc = -1;
    uint32_t req = 0;
    for (int i = 0; i < n; i++, opened++) {
        uint32_t slot_id;
        if (!march_dispatch_name_to_id(it[i].name, &slot_id)) {
            write_audit_log(it[i].name, it[i].impl_hash, it[i].cas_hash, it[i].ac, "err_abi");
            snprintf(resp, rsz, "ERR unknown_name %.200s\n", it[i].name);
            goto fail;
        }
        char path[640]; cas_artifact_path(path, sizeof(path), it[i].cas_hash);
        if (access(path, F_OK) != 0) {
            write_audit_log(it[i].name, it[i].impl_hash, it[i].cas_hash, it[i].ac, "err_cas_miss");
            snprintf(resp, rsz, "ERR missing_artifact\n");
            goto fail;
        }
        void *handle = dlopen(path, RTLD_NOW | RTLD_GLOBAL | RTLD_DEEPBIND);
        if (!handle) {
            write_audit_log(it[i].name, it[i].impl_hash, it[i].cas_hash, it[i].ac, "err_dlopen");
            snprintf(resp, rsz, "ERR dlopen_failed %.300s\n", dlerror());
            goto fail;
        }
        char identity_reason[128];
        if (!march_hcr_patch_identity_ok(handle, identity_reason, sizeof(identity_reason))) {
            write_audit_log(it[i].name, it[i].impl_hash, it[i].cas_hash, it[i].ac, "err_identity");
            snprintf(resp, rsz, "ERR identity %.200s\n", identity_reason);
            dlclose(handle);
            goto fail;
        }
        void *fn_ptr = dlsym(handle, it[i].name);
        if (!fn_ptr) {
            write_audit_log(it[i].name, it[i].impl_hash, it[i].cas_hash, it[i].ac, "err_dlsym");
            snprintf(resp, rsz, "ERR dlsym_failed %.200s\n", it[i].name);
            dlclose(handle);
            goto fail;
        }
        u[i].slot           = slot_id;
        u[i].fn             = fn_ptr;
        u[i].impl_hash      = it[i].impl_hash;
        u[i].sig_hash       = NULL;
        u[i].kind           = (uint8_t)MARCH_NATIVE;
        u[i].state_changed  = (it[i].migrate & MIGRATE_STATE) != 0;
        u[i].msgs_changed   = (it[i].migrate & MIGRATE_MSGS) != 0;
        u[i].migrate_fn     = u[i].state_changed
                              ? resolve_migrate_fn(handle, it[i].name, slot_id) : NULL;
        u[i].migrate_msg_fn = u[i].msgs_changed
                              ? resolve_migrate_msg_fn(handle, it[i].name, slot_id) : NULL;
        u[i].handle         = handle;
        u[i].ring_idx       = -1;
        if (it[i].epoch > req) req = it[i].epoch;
    }
    {
        /* __march_init still stamps the per-.so epoch cell (retired: nothing
         * reads it, D33), with the epoch this deploy will get. */
        uint32_t predicted = march_epoch_next(req);
        for (int i = 0; i < n; i++) {
            void (*init_fn)(uint32_t) = NULL;
            void *raw_init = dlsym(u[i].handle, "__march_init");
            if (raw_init) memcpy(&init_fn, &raw_init, sizeof(init_fn));
            if (init_fn) init_fn(predicted);
        }
    }
    march_hcr_wait w;
    int e = march_hcr_activate(u, n, req, -1, -1, &w);
    if (e == MARCH_HCR_WAIT) {
        snprintf(resp, rsz, "WAIT epoch:%u pins:%lld deadline_ms:%lld%s\n",
                 w.epoch, (long long)w.pins, (long long)w.deadline_ms,
                 w.table_full ? " table_full" : "");
        rc = 1;
        goto fail;
    }
    if (e <= 0) {
        for (int i = 0; i < n; i++)
            write_audit_log(it[i].name, it[i].impl_hash, it[i].cas_hash, it[i].ac, "err_publish");
        snprintf(resp, rsz, "ERR publish_failed\n");
        goto fail;
    }
    /* The dispatch table owns every handle now (dlclosed when its ring slot
     * is reclaimed). */
    {
        struct timeval atv; gettimeofday(&atv, NULL);
        long long ats = (long long)atv.tv_sec * 1000LL + (long long)atv.tv_usec / 1000;
        char asigner[65]; pubkey_to_hex(asigner);
        for (int i = 0; i < n; i++) {
            march_dispatch_set_activation(u[i].slot, ats, asigner);
            march_dispatch_set_callers(u[i].slot,
                it[i].callers && it[i].callers[0] ? it[i].callers : NULL);
            write_audit_log(it[i].name, it[i].impl_hash, it[i].cas_hash, it[i].ac, "ok");
        }
    }
    free(u);
    return 0;
fail:
    for (int i = 0; i < opened; i++) if (u[i].handle) dlclose(u[i].handle);
    free(u);
    return rc;
}

/* A single (unbatched) activation: answers OK <impl_hash>, WAIT …, or ERR. */
static void do_activate(int fd, const char *name, const char *impl_hash,
                        const char *cas_hash, int migrate,
                        uint32_t activate_epoch, const char *callers_csv,
                        const audit_caps_t *ac) {
    act_item it = { name, impl_hash, cas_hash, callers_csv, activate_epoch,
                    migrate, ac };
    char resp[512];
    int r = activate_items(&it, 1, resp, sizeof(resp));
    if (r == 0) {
        int n = snprintf(resp, sizeof(resp), "OK %s\n", impl_hash);
        write_safe(fd, resp, n, sizeof(resp));
    } else {
        wresp(fd, resp);
    }
}

/* ── ACTIVATE4: cap_root admission (Phase5C-C.3) ───────────────────────── */

#define MARCH_CAP_MAX_TOKENS   256   /* mirrors the callers-CSV token cap */
#define MARCH_CAP_TOKEN_MAX    128   /* max length of one cap path, incl NUL */
#define MARCH_POLICY_MAX_CAPS  256
#define MARCH_POLICY_LINE_MAX  128

/* Loaded lazily from $MARCH_DEPLOY_POLICY (newline-delimited cap-path file).
 * Absent env var or unreadable file => g_policy_loaded stays 0 => permissive
 * (skip the policy check entirely). Loaded at most once per process. */
static char g_policy_caps[MARCH_POLICY_MAX_CAPS][MARCH_POLICY_LINE_MAX];
static int  g_policy_n_caps   = 0;
static int  g_policy_loaded   = 0;   /* 1 once load_deploy_policy() has run */
static int  g_policy_present  = 0;   /* 1 iff a policy file was successfully read */

static void load_deploy_policy(void) {
    if (g_policy_loaded) return;
    g_policy_loaded = 1;
    const char *path = getenv("MARCH_DEPLOY_POLICY");
    if (!path || !path[0]) return;
    FILE *f = fopen(path, "r");
    if (!f) return;
    char line[MARCH_POLICY_LINE_MAX + 32];
    while (g_policy_n_caps < MARCH_POLICY_MAX_CAPS && fgets(line, sizeof(line), f)) {
        size_t len = strlen(line);
        while (len > 0 && (line[len-1] == '\n' || line[len-1] == '\r')) line[--len] = '\0';
        if (len == 0) continue;  /* skip blank lines */
        if (len >= MARCH_POLICY_LINE_MAX) len = MARCH_POLICY_LINE_MAX - 1;  /* bound, truncate */
        memcpy(g_policy_caps[g_policy_n_caps], line, len);
        g_policy_caps[g_policy_n_caps][len] = '\0';
        g_policy_n_caps++;
    }
    fclose(f);
    g_policy_present = 1;
}

/* Parse a bounded CSV of cap tokens from `csv` (already NUL-terminated and
 * length-bounded by the caller) into `tokens`/`out_n`. Mutates a private
 * copy `buf` (caller-supplied scratch, must outlive `tokens`, since tokens
 * are pointers into it) — never mutates the wire buffer directly. Returns 1
 * on success, 0 if the token count would exceed MARCH_CAP_MAX_TOKENS or a
 * single token would exceed MARCH_CAP_TOKEN_MAX-1 bytes. */
static int split_cap_csv(char *buf, char *tokens[], int *out_n) {
    int ntok = 0;
    if (buf[0] == '\0') { *out_n = 0; return 1; }
    char *p = buf;
    while (*p) {
        if (ntok >= MARCH_CAP_MAX_TOKENS) return 0;
        char *start = p;
        char *c = strchr(p, ',');
        size_t tok_len = c ? (size_t)(c - start) : strlen(start);
        if (tok_len == 0 || tok_len >= MARCH_CAP_TOKEN_MAX) return 0;
        tokens[ntok++] = start;
        if (c) { *c = '\0'; p = c + 1; } else { break; }
    }
    *out_n = ntok;
    return 1;
}

/* strcmp-based comparator for qsort over `char *` tokens (byte-lexicographic,
 * matching OCaml String.compare / List.sort_uniq). */
static int cap_token_cmp(const void *a, const void *b) {
    const char *sa = *(const char * const *)a;
    const char *sb = *(const char * const *)b;
    return strcmp(sa, sb);
}

/* Sort tokens[0..n) byte-lexicographically and drop exact-duplicate strings
 * in place, returning the deduped count. Mirrors OCaml List.sort_uniq
 * String.compare. */
static int sort_uniq_tokens(char *tokens[], int n) {
    if (n <= 1) return n;
    qsort(tokens, (size_t)n, sizeof(char *), cap_token_cmp);
    int w = 1;
    for (int i = 1; i < n; i++) {
        if (strcmp(tokens[i], tokens[w-1]) != 0) tokens[w++] = tokens[i];
    }
    return w;
}

/* Recompute cap_root over the received (unsigned) caps set, reproducing
 * Part A's OCaml recipe exactly:
 *   all_caps_sorted = List.sort_uniq String.compare caps
 *   artifact_caps   = Cap_lattice.normalize all_caps_sorted
 *   cap_root        = Blake3.hash_string (String.concat "\n" artifact_caps)
 * `caps_csv` must already be NUL-terminated and length-bounded (drawn from
 * the same tmp[]-style bounded scan used elsewhere in this file). Writes the
 * 64-char lowercase hex digest into out_hex[65]. Returns 1 on success, 0 on
 * a malformed/oversized caps CSV (caller should respond ERR bad_format). */
static int compute_cap_root(char *caps_csv, char out_hex[65]) {
    char *tokens[MARCH_CAP_MAX_TOKENS];
    int ntok = 0;
    if (!split_cap_csv(caps_csv, tokens, &ntok)) return 0;

    int nsorted = sort_uniq_tokens(tokens, ntok);

    const char *normalized[MARCH_CAP_MAX_TOKENS];
    int nnorm = march_cap_normalize((const char **)tokens, nsorted, normalized);

    /* Join survivors with '\n', no trailing newline. */
    char joined[MARCH_CAP_MAX_TOKENS * MARCH_CAP_TOKEN_MAX];
    size_t jlen = 0;
    for (int i = 0; i < nnorm; i++) {
        if (i > 0) {
            if (jlen + 1 >= sizeof(joined)) return 0;
            joined[jlen++] = '\n';
        }
        size_t sl = strlen(normalized[i]);
        if (jlen + sl >= sizeof(joined)) return 0;
        memcpy(joined + jlen, normalized[i], sl);
        jlen += sl;
    }

    march_blake3_hex((const unsigned char *)joined, jlen, out_hex);
    return 1;
}

/* Policy check: every cap in tokens[0..n) must be march_cap_subsumes'd by
 * some policy entry. Returns NULL if all pass, or the (borrowed) offending
 * cap string on the first violation. No-op (always passes) if no policy is
 * loaded. */
static const char *check_cap_policy(char *tokens[], int n) {
    load_deploy_policy();
    if (!g_policy_present) return NULL;  /* no policy => permissive */
    for (int i = 0; i < n; i++) {
        int allowed = 0;
        for (int j = 0; j < g_policy_n_caps; j++) {
            if (march_cap_subsumes(g_policy_caps[j], tokens[i])) { allowed = 1; break; }
        }
        if (!allowed) return tokens[i];
    }
    return NULL;
}

static void handle_client(int fd) {
    char line[RELOAD_LINE_MAX];

    /* Per-session batch state (BEGIN_BATCH / COMMIT_BATCH / ROLLBACK_BATCH) */
#define MARCH_MAX_BATCH 256
    struct march_staged {
        char     name[256];
        char     impl_hash[128];
        char     cas_hash[128];
        char     callers[1024];
        uint32_t epoch;
        int      migrate_required;
        char    *caps;       /* ACTIVATE4 only (heap, may be ""); NULL otherwise */
        char    *cap_root;   /* ACTIVATE4 only (heap); NULL otherwise */
    } staged[MARCH_MAX_BATCH];
    int n_staged  = 0;
    int in_batch  = 0;

    while (1) {
        int r = read_line(fd, line, RELOAD_LINE_MAX);
        if (r <= 0) break;

        /* ── PING ─────────────────────────────────────────────────────── */
        if (strcmp(line, "PING") == 0) {
            wresp(fd, "PONG\n");

        /* ── HCR_INFO ─────────────────────────────────────────────────── */
        } else if (strcmp(line, "HCR_INFO") == 0) {
            hcr_info_response(fd);

        /* ── ABI_QUERY ────────────────────────────────────────────────── */
        } else if (strcmp(line, "ABI_QUERY") == 0) {
            for (uint32_t i = 1; i < 65536; i++) {  /* 1-based; slot 0 = sentinel */
                uint32_t cur = march_dispatch_current(i);
                const char *h = march_dispatch_impl_hash(i, cur);
                if (!h) break;
                const char *name    = march_dispatch_id_to_name(i);
                const char *sig     = march_dispatch_sig_hash(i, cur);
                const char *callers = march_dispatch_callers(i);
                char resp[1024];
                int n;
                if (callers && callers[0]) {
                    n = snprintf(resp, sizeof(resp), "SLOT %u %s %s %s callers:%s\n",
                                 i,
                                 name ? name : "(none)",
                                 h[0] ? h : "(none)",
                                 sig && sig[0] ? sig : "(none)",
                                 callers);
                } else {
                    n = snprintf(resp, sizeof(resp), "SLOT %u %s %s %s\n",
                                 i,
                                 name ? name : "(none)",
                                 h[0] ? h : "(none)",
                                 sig && sig[0] ? sig : "(none)");
                }
                write_safe(fd, resp, n, sizeof(resp));
            }
            wresp(fd, "END\n");

        /* ── VERSIONS ─────────────────────────────────────────────────── */
        } else if (strcmp(line, "VERSIONS") == 0) {
            for (uint32_t i = 1; i < 65536; i++) {  /* 1-based; slot 0 = sentinel */
                const char *name = march_dispatch_id_to_name(i);
                if (!name) break;
                const char *base = march_dispatch_baseline_hash(i);
                uint32_t cur = march_dispatch_current(i);
                const char *hot  = march_dispatch_impl_hash(i, cur);
                char resp[512];
                int n = snprintf(resp, sizeof(resp), "VERSION %s baseline %s\n",
                                 name, base && base[0] ? base : "(none)");
                write_safe(fd, resp, n, sizeof(resp));
                /* Emit "hot" line only when impl_hash differs from baseline */
                if (hot && hot[0] && base && base[0] && strcmp(hot, base) != 0) {
                    n = snprintf(resp, sizeof(resp), "VERSION %s hot %s\n", name, hot);
                    write_safe(fd, resp, n, sizeof(resp));
                }
            }
            wresp(fd, "END\n");

        /* ── VERSIONS_DETAIL ──────────────────────────────────────────── */
        } else if (strcmp(line, "VERSIONS_DETAIL") == 0) {
            for (uint32_t i = 1; i < 65536; i++) {  /* 1-based; slot 0 = sentinel */
                const char *name = march_dispatch_id_to_name(i);
                if (!name) break;
                uint32_t cur = march_dispatch_current(i);
                const char *h   = march_dispatch_impl_hash(i, cur);
                long long   ts  = march_dispatch_activated_at(i);
                const char *sig = march_dispatch_signer_hex(i);
                uint32_t    ep  = march_dispatch_epoch(i, cur);
                char resp[512];
                int n = snprintf(resp, sizeof(resp),
                                 "SLOT %u %s %s %lld %s %u\n",
                                 i,
                                 name,
                                 h && h[0] ? h : "(none)",
                                 ts,
                                 sig && sig[0] ? sig : "(none)",
                                 ep);
                write_safe(fd, resp, n, sizeof(resp));
            }
            {
                /* Delivery-failure counters (II.4.7); parsers skip non-SLOT
                 * lines. */
                march_hcr_counters c; march_hcr_counters_get(&c);
                char resp[256];
                int n = snprintf(resp, sizeof(resp),
                                 "COUNTERS deferred:%lld converted:%lld dropped:%lld killed:%lld\n",
                                 (long long)c.deferred, (long long)c.converted,
                                 (long long)c.dropped, (long long)c.killed);
                write_safe(fd, resp, n, sizeof(resp));
            }
            wresp(fd, "END\n");

        /* ── CAS_CHECK ────────────────────────────────────────────────── */
        } else if (strncmp(line, "CAS_CHECK ", 10) == 0) {
            const char *hash = line + 10;
            if (!is_hex64(hash)) {
                wresp(fd, "ERR bad_hash\n"); continue;
            }
            char path[640]; cas_artifact_path(path, sizeof(path), hash);
            wresp(fd, (access(path, F_OK) == 0) ? "PRESENT\n" : "MISSING\n");

        /* ── CAS_PUT ──────────────────────────────────────────────────── */
        } else if (strncmp(line, "CAS_PUT ", 8) == 0) {
            char hash[65]; long long size_ll;
            if (sscanf(line + 8, "%64s %lld", hash, &size_ll) != 2
                || !is_hex64(hash)
                || size_ll <= 0 || size_ll > CAS_MAX_ARTIFACT) {
                wresp(fd, "ERR bad_format\n"); continue;
            }
            size_t sz = (size_t)size_ll;
            unsigned char *buf = (unsigned char *)malloc(sz);
            if (!buf) { wresp(fd, "ERR oom\n"); continue; }
            wresp(fd, "READY\n");
            if (read_exact(fd, buf, sz) != 0) {
                /* Stream is desynced — close rather than trying to recover. */
                free(buf); close(fd); return;
            }
            /* Write to CAS */
            char path[640]; cas_artifact_path(path, sizeof(path), hash);
            /* Ensure parent directory exists */
            char dir[640]; snprintf(dir, sizeof(dir), "%s/artifacts/%.2s", g_cas_root, hash);
            mkdir_p(dir);
            /* Write atomically via tmp file */
            char tmp[660]; snprintf(tmp, sizeof(tmp), "%s.tmp", path);
            FILE *f = fopen(tmp, "wb");
            if (!f) { free(buf); wresp(fd, "ERR open_failed\n"); continue; }
            size_t written = fwrite(buf, 1, sz, f);
            fclose(f); free(buf);
            if (written != sz) { unlink(tmp); wresp(fd, "ERR write_failed\n"); continue; }
            if (rename(tmp, path) != 0) { unlink(tmp); wresp(fd, "ERR rename_failed\n"); continue; }
            char resp[128];
            int n = snprintf(resp, sizeof(resp), "OK %s\n", hash);
            write_safe(fd, resp, n, sizeof(resp));

        /* ── ACTIVATE ─────────────────────────────────────────────────── */
        } else if (strncmp(line, "ACTIVATE ", 9) == 0) {
            char name[256], impl_hash[128], cas_hash[128], sig_b64[256];
            char migrate_required_str[8] = {0};
            int parsed = sscanf(line + 9, "%255s %127s %127s %255s %7s",
                                name, impl_hash, cas_hash, sig_b64,
                                migrate_required_str);
            if (parsed < 4) {
                wresp(fd, "ERR bad_format\n"); continue;
            }
            if (!is_hex64(cas_hash)) {
                wresp(fd, "ERR bad_cas_hash\n"); continue;
            }
            int migrate_required = (parsed >= 5 && migrate_required_str[0] == '1') ? 1 : 0;

#if HAVE_SIGNING_KEY
            /* Verify ed25519 signature before doing anything else. */
            if (!g_pubkey_loaded) {
                wresp(fd, "ERR signing_not_configured\n"); continue;
            }
            /* Check for all-zero pubkey (signing not configured) */
            int all_zero = 1;
            for (int i = 0; i < 32; i++) if (g_pubkey[i]) { all_zero = 0; break; }
            if (all_zero) { wresp(fd, "ERR signing_not_configured\n"); continue; }

            /* Signed message is "<name> <impl_hash> <cas_hash>" */
            char signed_msg[640];
            int smlen = snprintf(signed_msg, sizeof(signed_msg), "%s %s %s",
                                 name, impl_hash, cas_hash);

            /* Decode base64 signature */
            unsigned char sigbytes[64];
            int siglen = b64_decode(sig_b64, strlen(sig_b64), sigbytes);
            if (siglen != 64) { wresp(fd, "ERR bad_signature\n"); continue; }

            /* Build the signed message in tweetnacl format: sig || message */
            unsigned char *sm = (unsigned char *)malloc((size_t)(smlen + 64));
            if (!sm) { wresp(fd, "ERR oom\n"); continue; }
            memcpy(sm, sigbytes, 64);
            memcpy(sm + 64, signed_msg, (size_t)smlen);

            unsigned char *m_out = (unsigned char *)malloc((size_t)(smlen + 64));
            unsigned long long m_out_len = 0;
            int vrc = crypto_sign_open(m_out, &m_out_len, sm, (unsigned long long)(smlen + 64), g_pubkey);
            free(sm); free(m_out);
            if (vrc != 0) {
                write_audit_log(name, impl_hash, cas_hash, NULL, "err_sig");
                wresp(fd, "ERR bad_signature\n"); continue;
            }
#else
            (void)sig_b64;
            write_audit_log(name, impl_hash, cas_hash, NULL, "err_sig");
            wresp(fd, "ERR signing_not_configured\n"); continue;
#endif
            {
                uint32_t activate_epoch = 0;
                const char *ep_ptr = strstr(line, " epoch:");
                if (ep_ptr) activate_epoch = (uint32_t)atoi(ep_ptr + 7);
                const char *callers_ptr = strstr(line, " callers:");
                do_activate(fd, name, impl_hash, cas_hash, migrate_required,
                            activate_epoch, callers_ptr ? callers_ptr + 9 : NULL, NULL);
            }

        /* ── ACTIVATE2 ─────────────────────────────────────────────────── */
        /* Protocol v2: epoch and callers are included in the signed payload,
         * preventing replay attacks that forge the epoch or caller list.
         * Signed message: "ACTIVATE2 <name> <impl_hash> <cas_hash> epoch:<N> callers:<sorted-csv>" */
        } else if (strncmp(line, "ACTIVATE2 ", 10) == 0) {
            char name[256], impl_hash[128], cas_hash[128], sig_b64[256];
            char migrate_str[8] = {0};
            if (sscanf(line + 10, "%255s %127s %127s %255s %7s",
                       name, impl_hash, cas_hash, sig_b64, migrate_str) < 5) {
                wresp(fd, "ERR bad_format\n"); continue;
            }
            if (!is_hex64(cas_hash)) {
                wresp(fd, "ERR bad_cas_hash\n"); continue;
            }
            int migrate_required = (migrate_str[0] == '1') ? 1 : 0;

            /* Parse mandatory epoch:<N>. */
            uint32_t activate_epoch = 0;
            {
                const char *ep = strstr(line, " epoch:");
                if (!ep) { wresp(fd, "ERR bad_format missing_epoch\n"); continue; }
                activate_epoch = (uint32_t)atoi(ep + 7);
            }

            /* Parse mandatory callers:<csv>, then sort for canonical form. */
            char callers_sorted[1024] = {0};
            {
                const char *cp = strstr(line, " callers:");
                if (!cp) { wresp(fd, "ERR bad_format missing_callers\n"); continue; }
                const char *csv = cp + 9;
                char tmp[1024]; size_t tlen = 0;
                while (csv[tlen] && csv[tlen] != '\n' && csv[tlen] != '\r'
                       && tlen < sizeof(tmp) - 1)
                    tlen++;
                memcpy(tmp, csv, tlen); tmp[tlen] = '\0';

                if (tmp[0] != '\0') {
                    char *tokens[256]; int ntok = 0;
                    char *p = tmp;
                    while (*p && ntok < 255) {
                        tokens[ntok++] = p;
                        char *c = strchr(p, ',');
                        if (!c) break;
                        *c = '\0'; p = c + 1;
                    }
                    for (int i = 1; i < ntok; i++) {
                        char *key = tokens[i]; int j = i - 1;
                        while (j >= 0 && strcmp(tokens[j], key) > 0)
                            { tokens[j+1] = tokens[j]; j--; }
                        tokens[j+1] = key;
                    }
                    char *out = callers_sorted; size_t rem = sizeof(callers_sorted);
                    for (int i = 0; i < ntok && rem > 1; i++) {
                        if (i > 0) { *out++ = ','; rem--; }
                        size_t sl = strlen(tokens[i]);
                        if (sl >= rem) sl = rem - 1;
                        memcpy(out, tokens[i], sl); out += sl; rem -= sl;
                    }
                    *out = '\0';
                }
            }

#if HAVE_SIGNING_KEY
            if (!g_pubkey_loaded) {
                wresp(fd, "ERR signing_not_configured\n"); continue;
            }
            int all_zero = 1;
            for (int i = 0; i < 32; i++) if (g_pubkey[i]) { all_zero = 0; break; }
            if (all_zero) { wresp(fd, "ERR signing_not_configured\n"); continue; }

            /* Reconstruct the canonical signed message from parsed values. */
            char signed_msg[1024];
            int smlen = snprintf(signed_msg, sizeof(signed_msg),
                                 "ACTIVATE2 %s %s %s epoch:%u callers:%s",
                                 name, impl_hash, cas_hash, activate_epoch, callers_sorted);

            unsigned char sigbytes[64];
            int siglen = b64_decode(sig_b64, strlen(sig_b64), sigbytes);
            if (siglen != 64) { wresp(fd, "ERR bad_signature\n"); continue; }

            unsigned char *sm = (unsigned char *)malloc((size_t)(smlen + 64));
            if (!sm) { wresp(fd, "ERR oom\n"); continue; }
            memcpy(sm, sigbytes, 64);
            memcpy(sm + 64, signed_msg, (size_t)smlen);
            unsigned char *m_out = (unsigned char *)malloc((size_t)(smlen + 64));
            unsigned long long m_out_len = 0;
            int vrc = crypto_sign_open(m_out, &m_out_len, sm,
                                       (unsigned long long)(smlen + 64), g_pubkey);
            free(sm); free(m_out);
            if (vrc != 0) {
                write_audit_log(name, impl_hash, cas_hash, NULL, "err_sig");
                wresp(fd, "ERR bad_signature\n"); continue;
            }
#else
            (void)sig_b64;
            write_audit_log(name, impl_hash, cas_hash, NULL, "err_sig");
            wresp(fd, "ERR signing_not_configured\n"); continue;
#endif
            do_activate(fd, name, impl_hash, cas_hash, migrate_required,
                        activate_epoch, callers_sorted, NULL);

        /* ── ACTIVATE3 ─────────────────────────────────────────────────── */
        /* Protocol v3: migrate_required is now included in the signed payload,
         * preventing unsigned modification of the migration flag.
         * Signed message: "ACTIVATE3 <name> <impl_hash> <cas_hash> <migrate> epoch:<N> callers:<sorted-csv>" */
        } else if (strncmp(line, "ACTIVATE3 ", 10) == 0) {
            char name[256], impl_hash[128], cas_hash[128], sig_b64[256];
            char migrate_str[8] = {0};
            if (sscanf(line + 10, "%255s %127s %127s %255s %7s",
                       name, impl_hash, cas_hash, sig_b64, migrate_str) < 5) {
                wresp(fd, "ERR bad_format\n"); continue;
            }
            if (!is_hex64(cas_hash)) {
                wresp(fd, "ERR bad_cas_hash\n"); continue;
            }
            int migrate_required = (migrate_str[0] == '1') ? 1 : 0;

            /* Parse mandatory epoch:<N>. */
            uint32_t activate_epoch = 0;
            {
                const char *ep = strstr(line, " epoch:");
                if (!ep) { wresp(fd, "ERR bad_format missing_epoch\n"); continue; }
                activate_epoch = (uint32_t)atoi(ep + 7);
            }

            /* Parse mandatory callers:<csv>, then sort for canonical form. */
            char callers_sorted[1024] = {0};
            {
                const char *cp = strstr(line, " callers:");
                if (!cp) { wresp(fd, "ERR bad_format missing_callers\n"); continue; }
                const char *csv = cp + 9;
                char tmp[1024]; size_t tlen = 0;
                while (csv[tlen] && csv[tlen] != '\n' && csv[tlen] != '\r'
                       && tlen < sizeof(tmp) - 1)
                    tlen++;
                memcpy(tmp, csv, tlen); tmp[tlen] = '\0';

                if (tmp[0] != '\0') {
                    char *tokens[256]; int ntok = 0;
                    char *p = tmp;
                    while (*p && ntok < 255) {
                        tokens[ntok++] = p;
                        char *c = strchr(p, ',');
                        if (!c) break;
                        *c = '\0'; p = c + 1;
                    }
                    for (int i = 1; i < ntok; i++) {
                        char *key = tokens[i]; int j = i - 1;
                        while (j >= 0 && strcmp(tokens[j], key) > 0)
                            { tokens[j+1] = tokens[j]; j--; }
                        tokens[j+1] = key;
                    }
                    char *out = callers_sorted; size_t rem = sizeof(callers_sorted);
                    for (int i = 0; i < ntok && rem > 1; i++) {
                        if (i > 0) { *out++ = ','; rem--; }
                        size_t sl = strlen(tokens[i]);
                        if (sl >= rem) sl = rem - 1;
                        memcpy(out, tokens[i], sl); out += sl; rem -= sl;
                    }
                    *out = '\0';
                }
            }

#if HAVE_SIGNING_KEY
            if (!g_pubkey_loaded) {
                wresp(fd, "ERR signing_not_configured\n"); continue;
            }
            int all_zero = 1;
            for (int i = 0; i < 32; i++) if (g_pubkey[i]) { all_zero = 0; break; }
            if (all_zero) { wresp(fd, "ERR signing_not_configured\n"); continue; }

            /* Reconstruct the canonical signed message — now includes migrate_required. */
            char signed_msg[2048];
            int smlen = snprintf(signed_msg, sizeof(signed_msg),
                                 "ACTIVATE3 %s %s %s %d epoch:%u callers:%s",
                                 name, impl_hash, cas_hash, migrate_required,
                                 activate_epoch, callers_sorted);
            if (smlen < 0 || smlen >= (int)sizeof(signed_msg)) {
                wresp(fd, "ERR signed_msg_truncated\n"); continue;
            }

            unsigned char sigbytes[64];
            int siglen = b64_decode(sig_b64, strlen(sig_b64), sigbytes);
            if (siglen != 64) { wresp(fd, "ERR bad_signature\n"); continue; }

            unsigned char *sm = (unsigned char *)malloc((size_t)(smlen + 64));
            if (!sm) { wresp(fd, "ERR oom\n"); continue; }
            memcpy(sm, sigbytes, 64);
            memcpy(sm + 64, signed_msg, (size_t)smlen);
            unsigned char *m_out = (unsigned char *)malloc((size_t)(smlen + 64));
            unsigned long long m_out_len = 0;
            int vrc = crypto_sign_open(m_out, &m_out_len, sm,
                                       (unsigned long long)(smlen + 64), g_pubkey);
            free(sm); free(m_out);
            if (vrc != 0) {
                write_audit_log(name, impl_hash, cas_hash, NULL, "err_sig");
                wresp(fd, "ERR bad_signature\n"); continue;
            }
#else
            (void)sig_b64;
            write_audit_log(name, impl_hash, cas_hash, NULL, "err_sig");
            wresp(fd, "ERR signing_not_configured\n"); continue;
#endif
            if (in_batch) {
                /* Stage: verify sig and record for COMMIT_BATCH */
                if (n_staged >= MARCH_MAX_BATCH) {
                    wresp(fd, "ERR batch_full\n"); continue;
                }
                strncpy(staged[n_staged].name,      name,            255);
                strncpy(staged[n_staged].impl_hash, impl_hash,       127);
                strncpy(staged[n_staged].cas_hash,  cas_hash,        127);
                strncpy(staged[n_staged].callers,   callers_sorted, 1023);
                staged[n_staged].epoch           = activate_epoch;
                staged[n_staged].migrate_required = migrate_required;
                staged[n_staged].name[255]      = '\0';
                staged[n_staged].impl_hash[127] = '\0';
                staged[n_staged].cas_hash[127]  = '\0';
                staged[n_staged].callers[1023]  = '\0';
                staged[n_staged].caps     = NULL;   /* no cap data pre-ACTIVATE4 */
                staged[n_staged].cap_root = NULL;
                n_staged++;
                char resp[256];
                int n = snprintf(resp, sizeof(resp), "OK %s\n", impl_hash);
                write_safe(fd, resp, n, sizeof(resp));
            } else {
                do_activate(fd, name, impl_hash, cas_hash, migrate_required,
                            activate_epoch, callers_sorted, NULL);
            }

        /* ── ACTIVATE4 ─────────────────────────────────────────────────── */
        /* Protocol v4: adds cap_root/caps admission. cap_root is signed
         * (tamper-evident); caps is NOT signed — its integrity comes solely
         * from the server recomputing cap_root over it and matching the
         * signed value (see compute_cap_root / THE CRUX in the task brief).
         * Signed message: "ACTIVATE4 <name> <impl_hash> <cas_hash> <migrate>
         *                  epoch:<N> cap_root:<hex> callers:<sorted-csv>" */
        } else if (strncmp(line, "ACTIVATE4 ", 10) == 0
                   || strncmp(line, "ACTIVATE5 ", 10) == 0) {
            /* ACTIVATE5 differs only in <migrate> being a bitmask (see the
             * file header) and in the verb inside the signed message. */
            const int v5 = line[8] == '5';
            const char *verb = v5 ? "ACTIVATE5" : "ACTIVATE4";
            char name[256], impl_hash[128], cas_hash[128], sig_b64[256];
            char migrate_str[8] = {0};
            if (sscanf(line + 10, "%255s %127s %127s %255s %7s",
                       name, impl_hash, cas_hash, sig_b64, migrate_str) < 5) {
                wresp(fd, "ERR bad_format\n"); continue;
            }
            if (!is_hex64(cas_hash)) {
                wresp(fd, "ERR bad_cas_hash\n"); continue;
            }
            int migrate_required;
            if (v5) {
                if (migrate_str[0] < '0' || migrate_str[0] > '3' || migrate_str[1]) {
                    wresp(fd, "ERR bad_format bad_migrate\n"); continue;
                }
                migrate_required = migrate_str[0] - '0';
            } else {
                migrate_required = (migrate_str[0] == '1') ? MIGRATE_STATE : 0;
            }

            /* Parse mandatory epoch:<N>. */
            uint32_t activate_epoch = 0;
            {
                const char *ep = strstr(line, " epoch:");
                if (!ep) { wresp(fd, "ERR bad_format missing_epoch\n"); continue; }
                activate_epoch = (uint32_t)atoi(ep + 7);
            }

            /* Parse mandatory cap_root:<hex64>. */
            char cap_root[65] = {0};
            {
                const char *cr = strstr(line, " cap_root:");
                if (!cr) { wresp(fd, "ERR bad_format missing_cap_root\n"); continue; }
                const char *hex = cr + 10;
                size_t hlen = 0;
                while (hex[hlen] && hex[hlen] != ' ' && hlen < sizeof(cap_root) - 1) hlen++;
                memcpy(cap_root, hex, hlen); cap_root[hlen] = '\0';
                if (!is_hex64(cap_root)) { wresp(fd, "ERR bad_format bad_cap_root\n"); continue; }
            }

            /* Parse optional caps:<csv> — bounded scan to the NEXT " <key>:"
             * boundary (i.e. up to " callers:"), NOT to end-of-line, since
             * callers follows caps on the wire. An empty/absent caps:<csv>
             * is a genuinely capless artifact (real cap_root = blake3("")) —
             * the tamper check below always runs, empty or not. */
            char caps_buf[1024] = {0};
            {
                const char *cp = strstr(line, " caps:");
                if (cp) {
                    const char *csv = cp + 6;
                    const char *end = strstr(csv, " callers:");
                    size_t clen = end ? (size_t)(end - csv) : strlen(csv);
                    /* Also stop at CR/LF in case callers: is absent (shouldn't
                     * happen given the protocol, but bound defensively). */
                    size_t bound = 0;
                    while (bound < clen && csv[bound] != '\n' && csv[bound] != '\r') bound++;
                    if (bound > clen) bound = clen;
                    if (bound >= sizeof(caps_buf)) {
                        /* Over-long caps field: distinct honest error, not a
                         * silently-truncated value that would misleadingly
                         * recompute to the wrong root and read as tampering. */
                        wresp(fd, "ERR bad_format caps_too_long\n"); continue;
                    }
                    memcpy(caps_buf, csv, bound);
                    caps_buf[bound] = '\0';
                }
            }

            /* Audit context for every log line from here on (see
             * write_audit_log for when these values are verified). */
            audit_caps_t ac4 = { caps_buf, cap_root };

            /* Parse mandatory callers:<csv>, then sort for canonical form. */
            char callers_sorted[1024] = {0};
            {
                const char *cp = strstr(line, " callers:");
                if (!cp) { wresp(fd, "ERR bad_format missing_callers\n"); continue; }
                const char *csv = cp + 9;
                char tmp[1024]; size_t tlen = 0;
                while (csv[tlen] && csv[tlen] != '\n' && csv[tlen] != '\r'
                       && tlen < sizeof(tmp) - 1)
                    tlen++;
                memcpy(tmp, csv, tlen); tmp[tlen] = '\0';

                if (tmp[0] != '\0') {
                    char *tokens[256]; int ntok = 0;
                    char *p = tmp;
                    while (*p && ntok < 255) {
                        tokens[ntok++] = p;
                        char *c = strchr(p, ',');
                        if (!c) break;
                        *c = '\0'; p = c + 1;
                    }
                    for (int i = 1; i < ntok; i++) {
                        char *key = tokens[i]; int j = i - 1;
                        while (j >= 0 && strcmp(tokens[j], key) > 0)
                            { tokens[j+1] = tokens[j]; j--; }
                        tokens[j+1] = key;
                    }
                    char *out = callers_sorted; size_t rem = sizeof(callers_sorted);
                    for (int i = 0; i < ntok && rem > 1; i++) {
                        if (i > 0) { *out++ = ','; rem--; }
                        size_t sl = strlen(tokens[i]);
                        if (sl >= rem) sl = rem - 1;
                        memcpy(out, tokens[i], sl); out += sl; rem -= sl;
                    }
                    *out = '\0';
                }
            }

#if HAVE_SIGNING_KEY
            if (!g_pubkey_loaded) {
                wresp(fd, "ERR signing_not_configured\n"); continue;
            }
            int all_zero = 1;
            for (int i = 0; i < 32; i++) if (g_pubkey[i]) { all_zero = 0; break; }
            if (all_zero) { wresp(fd, "ERR signing_not_configured\n"); continue; }

            /* Reconstruct the canonical signed message — cap_root is signed,
             * caps is NOT (see file-header note above). */
            char signed_msg[2048];
            int smlen = snprintf(signed_msg, sizeof(signed_msg),
                                 "%s %s %s %s %d epoch:%u cap_root:%s callers:%s",
                                 verb, name, impl_hash, cas_hash, migrate_required,
                                 activate_epoch, cap_root, callers_sorted);
            if (smlen < 0 || smlen >= (int)sizeof(signed_msg)) {
                wresp(fd, "ERR signed_msg_truncated\n"); continue;
            }

            unsigned char sigbytes[64];
            int siglen = b64_decode(sig_b64, strlen(sig_b64), sigbytes);
            if (siglen != 64) { wresp(fd, "ERR bad_signature\n"); continue; }

            unsigned char *sm = (unsigned char *)malloc((size_t)(smlen + 64));
            if (!sm) { wresp(fd, "ERR oom\n"); continue; }
            memcpy(sm, sigbytes, 64);
            memcpy(sm + 64, signed_msg, (size_t)smlen);
            unsigned char *m_out = (unsigned char *)malloc((size_t)(smlen + 64));
            unsigned long long m_out_len = 0;
            int vrc = crypto_sign_open(m_out, &m_out_len, sm,
                                       (unsigned long long)(smlen + 64), g_pubkey);
            free(sm); free(m_out);
            if (vrc != 0) {
                write_audit_log(name, impl_hash, cas_hash, &ac4, "err_sig");
                wresp(fd, "ERR bad_signature\n"); continue;
            }
#else
            (void)sig_b64;
            write_audit_log(name, impl_hash, cas_hash, &ac4, "err_sig");
            wresp(fd, "ERR signing_not_configured\n"); continue;
#endif

            /* Cap admission gates — run AFTER sig-verify, BEFORE staging/
             * do_activate, so both batched and immediate activations are
             * gated identically.
             *
             * TAMPER CHECK IS UNCONDITIONAL — always recompute cap_root over
             * the received (possibly-empty) caps set and compare against the
             * signed cap_root, even when caps:<csv> is empty. A genuinely
             * capless artifact's signed cap_root is blake3(""), a specific
             * known value that an empty received set recomputes correctly,
             * so it still admits. Skipping this check on empty caps would let
             * a MITM strip the caps: field off a legitimately-signed ACTIVATE4
             * for a real (non-empty-cap) artifact — the signature only covers
             * cap_root/cas_hash, not caps — and have the server treat it as
             * capless, bypassing policy entirely. */
            {
                char tamper_scratch[1024];
                snprintf(tamper_scratch, sizeof(tamper_scratch), "%s", caps_buf);
                char recomputed_root[65];
                if (!compute_cap_root(tamper_scratch, recomputed_root)) {
                    wresp(fd, "ERR bad_format bad_caps\n"); continue;
                }
                if (strcmp(recomputed_root, cap_root) != 0) {
                    write_audit_log(name, impl_hash, cas_hash, &ac4, "err_cap_tamper");
                    wresp(fd, "ERR cap_tamper\n"); continue;
                }
            }

            /* Policy check may remain gated on a non-empty received cap set:
             * an empty set trivially satisfies any policy (nothing to
             * violate), and the tamper check above already guarantees an
             * empty caps_buf here really does correspond to a signed empty
             * cap_root (blake3("")), not a stripped non-empty set. */
            if (caps_buf[0] != '\0') {
                char policy_scratch[1024];
                snprintf(policy_scratch, sizeof(policy_scratch), "%s", caps_buf);
                char *ptokens[MARCH_CAP_MAX_TOKENS]; int pntok = 0;
                if (!split_cap_csv(policy_scratch, ptokens, &pntok)) {
                    wresp(fd, "ERR bad_format bad_caps\n"); continue;
                }
                const char *violation = check_cap_policy(ptokens, pntok);
                if (violation) {
                    write_audit_log(name, impl_hash, cas_hash, &ac4, "err_cap_policy");
                    char resp[256];
                    int n = snprintf(resp, sizeof(resp), "ERR cap_policy %s\n", violation);
                    write_safe(fd, resp, n, sizeof(resp));
                    continue;
                }
            }

            if (in_batch) {
                if (n_staged >= MARCH_MAX_BATCH) {
                    wresp(fd, "ERR batch_full\n"); continue;
                }
                strncpy(staged[n_staged].name,      name,            255);
                strncpy(staged[n_staged].impl_hash, impl_hash,       127);
                strncpy(staged[n_staged].cas_hash,  cas_hash,        127);
                strncpy(staged[n_staged].callers,   callers_sorted, 1023);
                staged[n_staged].epoch           = activate_epoch;
                staged[n_staged].migrate_required = migrate_required;
                staged[n_staged].name[255]      = '\0';
                staged[n_staged].impl_hash[127] = '\0';
                staged[n_staged].cas_hash[127]  = '\0';
                staged[n_staged].callers[1023]  = '\0';
                /* Heap-owned: the staged array lives on this thread's stack
                 * (256 entries); inline 1 KB caps buffers would overflow a
                 * 512 KB macOS secondary-thread stack.  Freed on commit,
                 * rollback and disconnect. */
                staged[n_staged].caps     = strdup(caps_buf);
                staged[n_staged].cap_root = strdup(cap_root);
                n_staged++;
                char resp[256];
                int n = snprintf(resp, sizeof(resp), "OK %s\n", impl_hash);
                write_safe(fd, resp, n, sizeof(resp));
            } else {
                do_activate(fd, name, impl_hash, cas_hash, migrate_required,
                            activate_epoch, callers_sorted, &ac4);
            }

        /* ── GET_EPOCH ────────────────────────────────────────────────── */
        } else if (strcmp(line, "GET_EPOCH") == 0) {
            uint32_t e = atomic_fetch_add_explicit(&g_next_epoch, 1,
                                                    memory_order_acq_rel);
            persist_next_epoch(e + 1);
            char resp[64];
            int n = snprintf(resp, sizeof(resp), "EPOCH %u\n", e);
            write_safe(fd, resp, n, sizeof(resp));

        /* ── BEGIN_BATCH ──────────────────────────────────────────────── */
        } else if (strcmp(line, "BEGIN_BATCH") == 0) {
            if (in_batch) { wresp(fd, "ERR already_in_batch\n"); continue; }
            n_staged = 0; in_batch = 1;
            wresp(fd, "OK\n");

        /* ── COMMIT_BATCH ─────────────────────────────────────────────── */
        } else if (strcmp(line, "COMMIT_BATCH") == 0) {
            if (!in_batch) { wresp(fd, "ERR not_in_batch\n"); continue; }
            /* The whole batch is ONE deploy (one epoch, one marker per
             * actor).  WAIT keeps it staged: send COMMIT_BATCH again. */
            act_item *items = (act_item *)calloc((size_t)(n_staged ? n_staged : 1),
                                                 sizeof(*items));
            audit_caps_t *acs = (audit_caps_t *)calloc((size_t)(n_staged ? n_staged : 1),
                                                       sizeof(*acs));
            if (!items || !acs) { free(items); free(acs); wresp(fd, "ERR oom\n"); continue; }
            for (int i = 0; i < n_staged; i++) {
                acs[i].caps = staged[i].caps;
                acs[i].cap_root = staged[i].cap_root;
                items[i].name      = staged[i].name;
                items[i].impl_hash = staged[i].impl_hash;
                items[i].cas_hash  = staged[i].cas_hash;
                items[i].callers   = staged[i].callers[0] ? staged[i].callers : NULL;
                items[i].epoch     = staged[i].epoch;
                items[i].migrate   = staged[i].migrate_required;
                items[i].ac        = staged[i].caps ? &acs[i] : NULL;
            }
            char resp[512];
            int r = n_staged ? activate_items(items, n_staged, resp, sizeof(resp)) : 0;
            free(items); free(acs);
            if (r == 1) {           /* WAIT: the batch stays staged */
                wresp(fd, resp);
                continue;
            }
            int committed = r == 0 ? n_staged : 0;
            for (int k = 0; k < n_staged; k++) {
                free(staged[k].caps); free(staged[k].cap_root);
            }
            in_batch = 0; n_staged = 0;
            if (r == 0) {
                int n = snprintf(resp, sizeof(resp), "OK %d\n", committed);
                write_safe(fd, resp, n, sizeof(resp));
            } else {
                wresp(fd, "ERR commit_partial_failure\n");
            }

        /* ── PINS ─────────────────────────────────────────────────────── */
        } else if (strcmp(line, "PINS") == 0) {
            uint32_t eps[MARCH_EPOCH_PIN_SLOTS]; int64_t cnt[MARCH_EPOCH_PIN_SLOTS];
            int k = march_epoch_pin_table(eps, cnt, MARCH_EPOCH_PIN_SLOTS);
            uint32_t cur = march_epoch_current();
            for (int i = 0; i < k; i++) {
                char resp[160];
                /* The current epoch's count includes its one role pin. */
                int n = snprintf(resp, sizeof(resp), "EPOCH %u pins:%lld%s%s\n",
                                 eps[i],
                                 (long long)(eps[i] == cur ? cnt[i] - 1 : cnt[i]),
                                 eps[i] == cur ? " current" : "",
                                 march_hcr_epoch_draining(eps[i]) ? " draining" : "");
                write_safe(fd, resp, n, sizeof(resp));
            }
            march_hcr_counters c; march_hcr_counters_get(&c);
            char resp[512];
            int n = snprintf(resp, sizeof(resp),
                             "COUNTERS deferred:%lld converted:%lld dropped:%lld "
                             "killed:%lld stopped:%lld advances:%lld early:%lld "
                             "forced:%lld markers_live:%lld markers_lost:%lld\n",
                             (long long)c.deferred, (long long)c.converted,
                             (long long)c.dropped, (long long)c.killed,
                             (long long)c.stopped, (long long)c.advances,
                             (long long)c.early, (long long)c.forced,
                             (long long)march_hcr_markers_live(),
                             (long long)c.markers_lost);
            write_safe(fd, resp, n, sizeof(resp));
            wresp(fd, "END\n");

        /* ── DRAIN ────────────────────────────────────────────────────── */
        } else if (strncmp(line, "DRAIN ", 6) == 0) {
            const char *ep = strstr(line, "epoch:");
            if (!ep) { wresp(fd, "ERR bad_format missing_epoch\n"); continue; }
            long long e = atoll(ep + 6), soft = 0, hard = 0;
            const char *sp = strstr(line, "soft_ms:");
            const char *hp = strstr(line, "hard_ms:");
            if (sp) soft = atoll(sp + 8);
            if (hp) hard = atoll(hp + 8);
            if (e <= 0 || soft < 0 || hard < 0) {
                wresp(fd, "ERR bad_format\n"); continue;
            }
            march_hcr_drain((uint32_t)e, (int64_t)soft, (int64_t)hard);
            wresp(fd, "OK\n");

        /* ── ROLLBACK_BATCH ───────────────────────────────────────────── */
        } else if (strcmp(line, "ROLLBACK_BATCH") == 0) {
            for (int k = 0; k < n_staged; k++) {
                free(staged[k].caps); free(staged[k].cap_root);
            }
            in_batch = 0; n_staged = 0;
            wresp(fd, "OK\n");

        } else {
            wresp(fd, "ERR unknown_command\n");
        }
    }
    /* Discard any uncommitted staged activations (connection dropped mid-batch) */
    for (int k = 0; k < n_staged; k++) {
        free(staged[k].caps); free(staged[k].cap_root);
    }
    close(fd);
}

static void *reload_server_thread(void *arg) {
    (void)arg;

#if HAVE_SIGNING_KEY
    load_pubkey_from_hex();
#endif
    /* Phase 9: restore epoch counter from disk (g_cas_root already set). */
    atomic_store_explicit(&g_next_epoch, load_next_epoch(), memory_order_relaxed);

    int srv = socket(AF_UNIX, SOCK_STREAM, 0);
    if (srv < 0) { perror("march_reload: socket"); return NULL; }

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, g_socket_path, sizeof(addr.sun_path) - 1);

    unlink(g_socket_path);
    if (bind(srv, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        perror("march_reload: bind"); close(srv); return NULL;
    }
    listen(srv, RELOAD_BACKLOG);
    fprintf(stderr, "[hcr] reload server listening on %s\n", g_socket_path);

    while (1) {
        int cli = accept(srv, NULL, NULL);
        if (cli < 0) {
            if (errno == EINTR) continue;
            perror("march_reload: accept");
            break;
        }
        handle_client(cli);
    }
    unlink(g_socket_path);
    close(srv);
    return NULL;
}

void march_reload_server_start(const char *socket_path) {
    if (!socket_path || socket_path[0] == '\0') return;
    strncpy(g_socket_path, socket_path, sizeof(g_socket_path) - 1);
    g_socket_path[sizeof(g_socket_path) - 1] = '\0';

    /* Build CAS root path: ~/.march/cas */
    const char *home = getenv("HOME");
    if (home)
        snprintf(g_cas_root, sizeof(g_cas_root), "%s/.march/cas", home);
    else
        snprintf(g_cas_root, sizeof(g_cas_root), "/tmp/.march_cas");

    pthread_t tid;
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    pthread_create(&tid, &attr, reload_server_thread, NULL);
    pthread_attr_destroy(&attr);
}

#else  /* non-POSIX stub */

#include "march_reload.h"

void march_reload_server_start(const char *socket_path) {
    (void)socket_path;
}

#endif /* __linux__ || __APPLE__ */
