/* runtime/march_https_tls.c — the HTTPS builtins that need OpenSSL:
 * http_server_tls_configure and http_server_reload_tls. Linked only into a
 * program that reaches them (the runtime's optional archive); configuring
 * TLS installs the table through which the always-linked HTTP runtime
 * reaches the TLS code (march_tls_ops.h). */

#include "march_https.h"
#include "march_tls_ops.h"
#include "march_runtime.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Result(Int, String): Ok = tag 0, Err = tag 1; field 0 at offset 16. */
static void *ok_int(int64_t v) {
    void *r = march_alloc(16 + 8);
    *(int64_t *)((char *)r + 16) = v;
    return r;
}

static void *err_str(const char *msg) {
    void *s = march_string_lit(msg, (int64_t)strlen(msg));
    void *r = march_alloc(16 + 8);
    *(int32_t *)((char *)r + 8) = 1;
    *(void **)((char *)r + 16) = s;
    return r;
}

/* A NUL-terminated copy of a March String (paths); "" for NULL. */
static char *str_dup(void *ms) {
    march_string *s = (march_string *)ms;
    size_t n = s ? (size_t)s->len : 0;
    char *c = malloc(n + 1);
    if (!c) return NULL;
    if (n) memcpy(c, s->data, n);
    c[n] = '\0';
    return c;
}

static const char *str_data(void *ms, size_t *len) {
    march_string *s = (march_string *)ms;
    *len = s ? (size_t)s->len : 0;
    return s ? s->data : "";
}

static char *read_file(const char *path, size_t *len, char *err, size_t errlen) {
    FILE *f = fopen(path, "rb");
    if (!f) { snprintf(err, errlen, "cannot read %s: %s", path, strerror(errno)); return NULL; }
    size_t cap = 8192, n = 0;
    char *buf = malloc(cap);
    for (;;) {
        if (!buf) { fclose(f); snprintf(err, errlen, "out of memory reading %s", path); return NULL; }
        n += fread(buf + n, 1, cap - n, f);
        if (n < cap) break;
        if (cap >= (1u << 20)) { free(buf); fclose(f); snprintf(err, errlen, "%s is too large", path); return NULL; }
        cap *= 2;
        buf = realloc(buf, cap);
    }
    int bad = ferror(f);
    fclose(f);
    if (bad) { free(buf); snprintf(err, errlen, "cannot read %s", path); return NULL; }
    *len = n;
    return buf;
}

void *march_http_server_tls_configure(int64_t kind, void *a, void *b,
                                      int64_t poll_secs, int64_t wait_for_cert) {
    char err[600] = "";
    g_march_tls_ops = &mts_real_ops;
    g_march_https.poll_secs = poll_secs < 0 ? 0 : (int)poll_secs;
    g_march_https.wait_for_cert = wait_for_cert != 0;
    g_march_https.files = (kind == 0);
    if (kind == 0) {
        char *cp = str_dup(a), *kp = str_dup(b);
        if (!cp || !kp) { free(cp); free(kp); return err_str("out of memory"); }
        mts_poller_set_paths(cp, kp);
        mts_poll_rc rc = mts_poll_initial(err, sizeof err);
        free(cp); free(kp);
        switch (rc) {
        case MTS_POLL_INSTALLED:
        case MTS_POLL_UNCHANGED:
            break;
        case MTS_POLL_MISSING:
            if (!g_march_https.wait_for_cert) return err_str(err);
            break;
        case MTS_POLL_REFUSED:
            return err_str(err);
        }
    } else {
        size_t cl, kl;
        const char *c = str_data(a, &cl), *k = str_data(b, &kl);
        if (mts_slot_install_pem(c, cl, k, kl, 1, err, sizeof err) != 0)
            return err_str(err);
        g_march_https.poll_secs = 0;             /* nothing on disk to watch */
    }
    g_march_https.tls = 1;
    return ok_int(0);
}

void *march_http_server_reload_tls(int64_t kind, void *a, void *b) {
    if (!g_march_https.tls) return err_str("reload_tls: no TLS server is configured");
    char why[512] = "", msg[640];
    int rc;
    if (kind == 0) {
        char *cp = str_dup(a), *kp = str_dup(b);
        size_t cl = 0, kl = 0;
        char *c = cp ? read_file(cp, &cl, why, sizeof why) : NULL;
        char *k = (c && kp) ? read_file(kp, &kl, why, sizeof why) : NULL;
        rc = (c && k) ? mts_slot_install_pem(c, cl, k, kl, 0, why, sizeof why) : -1;
        free(c); free(k); free(cp); free(kp);
    } else {
        size_t cl, kl;
        const char *c = str_data(a, &cl), *k = str_data(b, &kl);
        rc = mts_slot_install_pem(c, cl, k, kl, 0, why, sizeof why);
    }
    if (rc != 0) {
        snprintf(msg, sizeof msg, "reload_tls: %s", why);
        return err_str(msg);
    }
    return ok_int(0);
}

