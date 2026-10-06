/* march_sig.c — see march_sig.h.
 *
 * Factored out of march_reload.c (its key parsing, verify_signed_line and the
 * audit log's path) so the observe socket's debug verbs check signatures and
 * write audit lines exactly as the reload server does. */
#include "march_sig.h"
#include "tweetnacl.h"

#include <ctype.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>

/* ── Key ──────────────────────────────────────────────────────────────── */

static unsigned char   g_key[32];
static int             g_key_ok;
static pthread_once_t  g_key_once = PTHREAD_ONCE_INIT;

static int hex_nibble(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

static void load_key_once(void) {
#ifdef MARCH_SIGNING_PUBKEY_HEX
    const char *hex = MARCH_SIGNING_PUBKEY_HEX;
    if (strlen(hex) != 64) return;
    unsigned char k[32];
    int nonzero = 0;
    for (int i = 0; i < 32; i++) {
        int hi = hex_nibble(hex[2 * i]), lo = hex_nibble(hex[2 * i + 1]);
        if (hi < 0 || lo < 0) return;
        k[i] = (unsigned char)((hi << 4) | lo);
        nonzero |= k[i];
    }
    /* An all-zero key means "signing not configured". */
    if (!nonzero) return;
    memcpy(g_key, k, 32);
    g_key_ok = 1;
#endif
}

void march_sig_load_key(void) { pthread_once(&g_key_once, load_key_once); }

int march_sig_key_loaded(void) { march_sig_load_key(); return g_key_ok; }

const unsigned char *march_sig_pubkey(void) { march_sig_load_key(); return g_key; }

void march_sig_pubkey_hex(char out[65]) {
    out[0] = '\0';
    if (!march_sig_key_loaded()) return;
    static const char hc[] = "0123456789abcdef";
    for (int i = 0; i < 32; i++) {
        out[2 * i]     = hc[(g_key[i] >> 4) & 0xf];
        out[2 * i + 1] = hc[g_key[i] & 0xf];
    }
    out[64] = '\0';
}

/* ── Verify ───────────────────────────────────────────────────────────── */

static int b64_val(unsigned char c) {
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    if (c == '+' || c == '-') return 62;
    if (c == '/' || c == '_') return 63;
    if (c == '=')             return 0;
    return -1;
}

/* Same decoder as march_reload.c's: decoded length, or -1. */
static int b64_decode(const char *in, size_t inlen, unsigned char *out, size_t outcap) {
    size_t olen = 0, i = 0;
    while (i < inlen) {
        unsigned char c0 = in[i++];
        unsigned char c1 = i < inlen ? (unsigned char)in[i++] : '=';
        unsigned char c2 = i < inlen ? (unsigned char)in[i++] : '=';
        unsigned char c3 = i < inlen ? (unsigned char)in[i++] : '=';
        int v0 = b64_val(c0), v1 = b64_val(c1), v2 = b64_val(c2), v3 = b64_val(c3);
        if (v0 < 0 || v1 < 0 || v2 < 0 || v3 < 0) return -1;
        if (olen + 3 > outcap) return -1;
        out[olen++] = (unsigned char)((v0 << 2) | (v1 >> 4));
        if (c2 != '=') out[olen++] = (unsigned char)(((v1 & 0xf) << 4) | (v2 >> 2));
        if (c3 != '=') out[olen++] = (unsigned char)(((v2 & 0x3) << 6) | v3);
    }
    return (int)olen;
}

int march_sig_verify(const char *msg, const char *sig_b64) {
    if (!march_sig_key_loaded() || !msg || !sig_b64) return 0;
    size_t sl = strlen(sig_b64);
    if (sl > 128) return 0;
    unsigned char sig[66];
    if (b64_decode(sig_b64, sl, sig, sizeof sig) != 64) return 0;
    size_t mlen = strlen(msg);
    unsigned char *sm = (unsigned char *)malloc(mlen + 64);
    unsigned char *mo = (unsigned char *)malloc(mlen + 64);
    if (!sm || !mo) { free(sm); free(mo); return 0; }
    memcpy(sm, sig, 64);
    memcpy(sm + 64, msg, mlen);
    unsigned long long olen = 0;
    int rc = crypto_sign_open(mo, &olen, sm, (unsigned long long)(mlen + 64), g_key);
    free(sm);
    free(mo);
    return rc == 0;
}

/* ── Freshness ────────────────────────────────────────────────────────── */

typedef struct { char nonce[MARCH_SIG_NONCE_MAX + 1]; int64_t not_after_ms; } seen_nonce;
static seen_nonce      g_seen[MARCH_SIG_NONCE_RING];
static pthread_mutex_t g_seen_mu = PTHREAD_MUTEX_INITIALIZER;

const char *march_sig_admit(const char *nonce, int64_t not_after_ms, int64_t now_ms) {
    size_t n = nonce ? strlen(nonce) : 0;
    if (n < 16 || n > MARCH_SIG_NONCE_MAX) return "bad_nonce";
    for (size_t i = 0; i < n; i++)
        if (!isxdigit((unsigned char)nonce[i])) return "bad_nonce";
    if (not_after_ms < now_ms) return "expired";
    if (not_after_ms - now_ms > MARCH_SIG_MAX_WINDOW_MS) return "not_after_too_far";
    pthread_mutex_lock(&g_seen_mu);
    int free_slot = -1;
    for (int i = 0; i < MARCH_SIG_NONCE_RING; i++) {
        seen_nonce *s = &g_seen[i];
        if (s->nonce[0] && strcasecmp(s->nonce, nonce) == 0) {
            pthread_mutex_unlock(&g_seen_mu);
            return "replay";
        }
        /* An expired entry can never be replayed: its request would be
         * refused as expired anyway, so the slot is reusable. */
        if (free_slot < 0 && (!s->nonce[0] || s->not_after_ms < now_ms)) free_slot = i;
    }
    if (free_slot < 0) {
        pthread_mutex_unlock(&g_seen_mu);
        return "nonce_ring_full";
    }
    memcpy(g_seen[free_slot].nonce, nonce, n + 1);
    g_seen[free_slot].not_after_ms = not_after_ms;
    pthread_mutex_unlock(&g_seen_mu);
    return NULL;
}

/* ── Policy ───────────────────────────────────────────────────────────── */

int march_sig_debug_allowed(const char *verb) {
    const char *path = getenv("MARCH_DEBUG_POLICY");
    if (!path || !*path || !verb) return 0;
    FILE *f = fopen(path, "r");
    if (!f) return 0;
    char line[256];
    int ok = 0;
    while (!ok && fgets(line, sizeof line, f)) {
        char *h = strchr(line, '#');
        if (h) *h = '\0';
        char *p = line;
        while (*p == ' ' || *p == '\t') p++;
        char *e = p + strlen(p);
        while (e > p && (e[-1] == '\n' || e[-1] == '\r' || e[-1] == ' ' || e[-1] == '\t')) *--e = '\0';
        if (strcmp(p, verb) == 0) ok = 1;
    }
    fclose(f);
    return ok;
}

/* ── Audit log ────────────────────────────────────────────────────────── */

static pthread_mutex_t g_audit_mu = PTHREAD_MUTEX_INITIALIZER;

static void mkdir_p(const char *path) {
    char tmp[512];
    snprintf(tmp, sizeof tmp, "%s", path);
    for (char *p = tmp + 1; *p; p++)
        if (*p == '/') { *p = '\0'; mkdir(tmp, 0755); *p = '/'; }
    mkdir(tmp, 0755);
}

FILE *march_audit_open(void) {
    const char *log_path = getenv("MARCH_AUDIT_LOG");
    char default_path[512];
    if (!log_path || !log_path[0]) {
        const char *xdg = getenv("XDG_DATA_HOME");
        if (xdg && xdg[0]) {
            snprintf(default_path, sizeof default_path, "%s/march/audit.jsonl", xdg);
        } else {
            const char *home = getenv("HOME");
            if (!home || !home[0]) return NULL;
            snprintf(default_path, sizeof default_path,
                     "%s/.local/share/march/audit.jsonl", home);
        }
        log_path = default_path;
    }
    char dir[512];
    snprintf(dir, sizeof dir, "%s", log_path);
    char *slash = strrchr(dir, '/');
    if (slash) { *slash = '\0'; mkdir_p(dir); }
    pthread_mutex_lock(&g_audit_mu);
    FILE *f = fopen(log_path, "a");
    if (!f) pthread_mutex_unlock(&g_audit_mu);
    return f;
}

void march_audit_close(FILE *f) {
    if (!f) return;
    fclose(f);
    pthread_mutex_unlock(&g_audit_mu);
}
