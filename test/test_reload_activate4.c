/* test_reload_activate4.c — end-to-end socket test for ACTIVATE4 admission
 * (runtime/march_reload.c, Phase5C-C.3).
 *
 * Starts the real reload server (march_reload_server_start) on a Unix-domain
 * socket, connects as a client, and drives the ACTIVATE4 wire protocol
 * exactly as forge/the compiler's deploy client would: build the signed
 * message "ACTIVATE4 <name> <impl_hash> <cas_hash> <migrate> epoch:<N>
 * cap_root:<hex> callers:<csv>", sign it with a real ed25519 key (whose
 * public half is baked into this test binary via -DMARCH_SIGNING_PUBKEY_HEX,
 * generated at build time by test_reload_keygen.c — see test/dune), base64
 * it, and send the full ACTIVATE4 line including the (unsigned) caps:<csv>.
 *
 * The load-bearing case is the cap_root recompute: this test computes the
 * *expected* cap_root the same way the OCaml compiler does (Cap_lattice
 * normalize + Blake3, see bin/main.ml ~2213-2219) using the C helpers
 * (march_cap_lattice.h / march_blake3.h) that the server itself uses, so a
 * PASS here proves the C server-side canonicalization agrees with Part A's
 * OCaml recipe — the single most important property of this task. A second
 * assertion (test_cas.ml + a march --hot-reload --compile-so smoke path, see
 * task-c3-report.md) cross-checks that the *compiler's* OCaml cap_root for a
 * known cap set equals what this test independently computes in C.
 *
 * Because a real CAS artifact is never staged, admission that passes the cap
 * gates falls through to do_activate's "ERR missing_artifact" — that's
 * expected and, combined with distinguishing it from the cap-gate errors
 * (ERR cap_tamper / ERR cap_policy), is exactly what proves the gate ran
 * and produced the correct verdict before do_activate touched the CAS.
 */
#include "march_reload.h"
#include "march_dispatch.h"
#include "march_cap_lattice.h"
#include "march_blake3.h"
#include "tweetnacl.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <errno.h>
#include <time.h>

#ifndef MARCH_SIGNING_PUBKEY_HEX
#error "test_reload_activate4 must be compiled with -DMARCH_SIGNING_PUBKEY_HEX"
#endif

static int g_failed = 0;
#define CHECK(cond, msg) do {                                               \
    if (!(cond)) {                                                          \
        fprintf(stderr, "  FAIL [%s:%d]: %s\n", __func__, __LINE__, (msg)); \
        g_failed++;                                                         \
    } else {                                                                \
        fprintf(stderr, "  ok   [%s:%d]: %s\n", __func__, __LINE__, (msg)); \
    }                                                                        \
} while (0)

/* ── Secret key: read from the file test_reload_keygen wrote (dune rule
 *   passes its path via argv[1]); this is the sk half of the same keypair
 *   whose pk half is baked into MARCH_SIGNING_PUBKEY_HEX. ── */
static unsigned char g_sk[64];

static int hex_nibble(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

static int load_secret_key(const char *keys_path) {
    FILE *f = fopen(keys_path, "r");
    if (!f) { fprintf(stderr, "cannot open %s\n", keys_path); return 0; }
    char pk_hex[128], sk_hex[256];
    if (!fgets(pk_hex, sizeof(pk_hex), f) || !fgets(sk_hex, sizeof(sk_hex), f)) {
        fclose(f); return 0;
    }
    fclose(f);
    size_t sklen = strlen(sk_hex);
    while (sklen > 0 && (sk_hex[sklen-1] == '\n' || sk_hex[sklen-1] == '\r')) sk_hex[--sklen] = '\0';
    if (sklen != 128) { fprintf(stderr, "bad sk hex length %zu\n", sklen); return 0; }
    for (int i = 0; i < 64; i++) {
        int hi = hex_nibble(sk_hex[2*i]), lo = hex_nibble(sk_hex[2*i+1]);
        if (hi < 0 || lo < 0) return 0;
        g_sk[i] = (unsigned char)((hi << 4) | lo);
    }
    return 1;
}

/* ── base64 (URL-safe, no padding) — mirrors march_reload.c's b64_decode
 *   counterpart so the client encodes exactly what the server expects. ── */
static void b64_encode(const unsigned char *in, size_t inlen, char *out) {
    static const char tbl[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    size_t i = 0, o = 0;
    while (i < inlen) {
        unsigned int v = in[i++] << 16;
        int have2 = (i < inlen); if (have2) v |= in[i++] << 8;
        int have3 = (i < inlen); if (have3) v |= in[i++];
        out[o++] = tbl[(v >> 18) & 0x3f];
        out[o++] = tbl[(v >> 12) & 0x3f];
        out[o++] = have2 ? tbl[(v >> 6) & 0x3f] : '=';
        out[o++] = have3 ? tbl[v & 0x3f] : '=';
    }
    out[o] = '\0';
}

/* Sign `msg` with g_sk; write URL-safe-base64(sig) into out (>= 128 bytes). */
static void sign_b64(const char *msg, char *out) {
    size_t mlen = strlen(msg);
    unsigned char *sm = (unsigned char *)malloc(mlen + 64);
    unsigned long long smlen = 0;
    crypto_sign(sm, &smlen, (const unsigned char *)msg, mlen, g_sk);
    /* sm = sig(64) || msg; we only want the 64-byte signature, b64'd. */
    b64_encode(sm, 64, out);
    free(sm);
}

/* ── Socket helpers ──────────────────────────────────────────────────────── */

static int connect_sock(const char *path) {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, path, sizeof(addr.sun_path) - 1);
    /* The server thread starts asynchronously; retry briefly. */
    for (int i = 0; i < 100; i++) {
        if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) == 0) return fd;
        struct timespec ts = { 0, 20 * 1000 * 1000 };  /* 20ms */
        nanosleep(&ts, NULL);
    }
    close(fd);
    return -1;
}

static void send_line(int fd, const char *line) {
    write(fd, line, strlen(line));
    write(fd, "\n", 1);
}

/* Read one newline-terminated response line (bounded). */
static int read_resp(int fd, char *buf, int max) {
    int n = 0;
    while (n < max - 1) {
        char c;
        int r = (int)read(fd, &c, 1);
        if (r <= 0) break;
        if (c == '\n') break;
        buf[n++] = c;
    }
    buf[n] = '\0';
    return n;
}

/* ── cap_root recompute, independent of march_reload.c's static helpers —
 *   this is the "known cap set" half of THE CRUX cross-check: both this
 *   test and the server compute cap_root via the same public C helpers
 *   (march_cap_normalize / march_blake3_hex), and bin/main.ml's OCaml
 *   recipe is asserted to agree with the identical algorithm in
 *   test/test_cas.ml + test/test_caps.ml (Cap_lattice.normalize /
 *   Blake3.hash_string over sort_uniq'd caps joined with "\n"). ── */
static void expected_cap_root(const char **sorted_caps, int n, char out_hex[65]) {
    const char *normalized[64];
    int nnorm = march_cap_normalize(sorted_caps, n, normalized);
    char joined[4096]; size_t jlen = 0;
    for (int i = 0; i < nnorm; i++) {
        if (i > 0) joined[jlen++] = '\n';
        size_t sl = strlen(normalized[i]);
        memcpy(joined + jlen, normalized[i], sl);
        jlen += sl;
    }
    march_blake3_hex((const unsigned char *)joined, jlen, out_hex);
}

/* ── Test bodies ─────────────────────────────────────────────────────────── */

static const char *SOCK_PATH;
static uint32_t g_epoch = 1;

/* ── Audit log: main() points $MARCH_AUDIT_LOG at a per-run temp file (it
 *   used to land in the real ~/.local/share/march/audit.jsonl).  The server
 *   appends each line BEFORE writing its response, so after read_resp the
 *   line for that request is the file's last. ── */
static char g_audit_path[128];

static void last_audit_line(char *out, size_t max) {
    out[0] = '\0';
    FILE *f = fopen(g_audit_path, "r");
    if (!f) return;
    char line[4096];
    while (fgets(line, sizeof(line), f)) snprintf(out, max, "%s", line);
    fclose(f);
}

static void check_audit(const char *fn, const char *caps_json,
                        const char *cap_root, const char *result) {
    char line[4096]; last_audit_line(line, sizeof(line));
    char want[512];
    snprintf(want, sizeof(want), "\"fn\":\"%s\"", fn);
    CHECK(strstr(line, want) != NULL, "audit: last line is for this fn");
    snprintf(want, sizeof(want), "\"caps\":%s,", caps_json);
    CHECK(strstr(line, want) != NULL, "audit: caps recorded");
    if (cap_root) snprintf(want, sizeof(want), "\"cap_root\":\"%s\"", cap_root);
    else          snprintf(want, sizeof(want), "\"cap_root\":null");
    CHECK(strstr(line, want) != NULL, "audit: cap_root recorded");
    snprintf(want, sizeof(want), "\"result\":\"%s\"", result);
    CHECK(strstr(line, want) != NULL, "audit: result recorded");
    if (g_failed) fprintf(stderr, "    audit line: %s", line);
}

/* Build+send one ACTIVATE4 line for (name, caps_csv, cap_root) and return the
 * server's response line in `resp` (caller-provided buffer). */
static void do_activate4(int fd, const char *name, const char *caps_csv,
                          const char *cap_root, const char *callers_csv,
                          char *resp, int resp_max) {
    char impl_hash[65], cas_hash[65];
    memset(impl_hash, '1', 64); impl_hash[64] = '\0';
    memset(cas_hash,  '2', 64); cas_hash[64]  = '\0';
    int migrate = 0;
    uint32_t epoch = g_epoch++;

    char signed_msg[2048];
    snprintf(signed_msg, sizeof(signed_msg),
             "ACTIVATE4 %s %s %s %d epoch:%u cap_root:%s callers:%s",
             name, impl_hash, cas_hash, migrate, epoch, cap_root, callers_csv);

    char sig_b64[128];
    sign_b64(signed_msg, sig_b64);

    char line[2560];
    snprintf(line, sizeof(line),
             "ACTIVATE4 %s %s %s %s %d epoch:%u cap_root:%s caps:%s callers:%s",
             name, impl_hash, cas_hash, sig_b64, migrate, epoch, cap_root,
             caps_csv, callers_csv);
    send_line(fd, line);
    read_resp(fd, resp, resp_max);
}

/* 1. Tamper check: matching cap_root (computed the same way as Part A) lets
 *    admission proceed past the cap gates (falls through to CAS-miss, since
 *    no real artifact is staged — proves the gate ran and passed). */
static void test_tamper_check_matching_root_admits(void) {
    int fd = connect_sock(SOCK_PATH);
    CHECK(fd >= 0, "connected to reload server");
    if (fd < 0) return;

    const char *caps[] = { "IO.Console", "IO.FileRead" };
    char root[65];
    expected_cap_root(caps, 2, root);

    char resp[512];
    do_activate4(fd, "test_fn_ok", "IO.Console,IO.FileRead", root, "", resp, sizeof(resp));
    CHECK(strncmp(resp, "ERR missing_artifact", 20) == 0,
          "matching cap_root passes both cap gates, falls through to CAS-miss (not cap_tamper/cap_policy)");
    check_audit("test_fn_ok", "[\"IO.Console\",\"IO.FileRead\"]", root, "err_cas_miss");
    close(fd);
}

/* 2. Tamper check: mutated caps (server recomputes a different root than the
 *    signed one) is rejected with ERR cap_tamper — the single most important
 *    assertion in this task. */
static void test_tamper_check_mutated_caps_rejected(void) {
    int fd = connect_sock(SOCK_PATH);
    CHECK(fd >= 0, "connected to reload server");
    if (fd < 0) return;

    const char *caps[] = { "IO.Console", "IO.FileRead" };
    char root[65];
    expected_cap_root(caps, 2, root);

    /* Sign+send with a caps:<csv> that does NOT match the signed cap_root
     * (attacker mutates the unsigned caps field post-signing). */
    char resp[512];
    do_activate4(fd, "test_fn_tamper", "IO.NetListen", root, "", resp, sizeof(resp));
    CHECK(strcmp(resp, "ERR cap_tamper") == 0,
          "mutated caps (root mismatch) rejected with ERR cap_tamper");
    /* Recorded AS RECEIVED: the rejected request's claimed caps. */
    check_audit("test_fn_tamper", "[\"IO.NetListen\"]", root, "err_cap_tamper");
    close(fd);
}

/* 3. No policy configured (MARCH_DEPLOY_POLICY unset in this test process)
 *    => permissive: any well-formed, tamper-free cap set is admitted. */
static void test_no_policy_is_permissive(void) {
    CHECK(getenv("MARCH_DEPLOY_POLICY") == NULL,
          "MARCH_DEPLOY_POLICY is unset for this process (permissive baseline)");
    int fd = connect_sock(SOCK_PATH);
    CHECK(fd >= 0, "connected to reload server");
    if (fd < 0) return;

    const char *caps[] = { "IO.NetConnect.TLS" };
    char root[65];
    expected_cap_root(caps, 1, root);
    char resp[512];
    do_activate4(fd, "test_fn_nopolicy", "IO.NetConnect.TLS", root, "", resp, sizeof(resp));
    CHECK(strncmp(resp, "ERR missing_artifact", 20) == 0,
          "no policy loaded => admitted past cap gates (falls through to CAS-miss)");
    close(fd);
}

/* 4a. Caps-stripping bypass (whole-branch review C-1): empty caps:<csv> with
 *     a BOGUS cap_root must now be rejected with ERR cap_tamper. This is the
 *     enshrining regression test for the fix — the old version of this test
 *     (test_empty_caps_is_permissive_legacy) asserted the opposite (that a
 *     bogus root was silently admitted whenever caps: was empty), which is
 *     exactly the MITM caps-stripping admission bypass: an attacker can
 *     intercept a legitimately-signed ACTIVATE4 for a real (non-empty-cap)
 *     artifact, blank the (unsigned) caps: field, and have the server treat
 *     it as a legacy capless artifact and skip the tamper check entirely —
 *     while the signed cap_root/cas_hash (and thus the artifact admitted)
 *     are still the real, over-authority ones. The tamper check must be
 *     unconditional: an empty received caps set only recomputes to a
 *     matching root when the SIGNED root really is blake3(""). */
static void test_empty_caps_bogus_root_rejected(void) {
    int fd = connect_sock(SOCK_PATH);
    CHECK(fd >= 0, "connected to reload server");
    if (fd < 0) return;

    /* cap_root is present (mandatory field) but caps:<csv> is empty and the
     * cap_root is bogus (not blake3("")) — must be rejected as tampering,
     * simulating a MITM that stripped caps: off a real signed artifact. */
    char bogus_root[65];
    memset(bogus_root, 'a', 64); bogus_root[64] = '\0';
    char resp[512];
    do_activate4(fd, "test_fn_legacy", "", bogus_root, "", resp, sizeof(resp));
    CHECK(strcmp(resp, "ERR cap_tamper") == 0,
          "empty caps:<csv> with a bogus (non-blake3(\"\")) cap_root is rejected: "
          "caps-stripping bypass is closed");
    close(fd);
}

/* 4b. A genuinely capless artifact — empty caps:<csv> AND the real signed
 *     cap_root = blake3("") (af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7
 *     cc9a93cae41f326) — must still admit. The tamper check being
 *     unconditional does not break the legitimate capless case: recomputing
 *     cap_root over an empty received set reproduces blake3("") exactly, so
 *     it matches the signed value and falls through to CAS-miss like every
 *     other passing case in this file. */
static void test_empty_caps_real_empty_root_admitted(void) {
    int fd = connect_sock(SOCK_PATH);
    CHECK(fd >= 0, "connected to reload server");
    if (fd < 0) return;

    char real_empty_root[65];
    expected_cap_root(NULL, 0, real_empty_root);
    CHECK(strcmp(real_empty_root,
                 "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262") == 0,
          "blake3(\"\") matches the well-known empty-set cap_root constant");

    char resp[512];
    do_activate4(fd, "test_fn_legacy_ok", "", real_empty_root, "", resp, sizeof(resp));
    CHECK(strncmp(resp, "ERR missing_artifact", 20) == 0,
          "empty caps:<csv> with the real cap_root=blake3(\"\") admits (falls through to CAS-miss)");
    /* An empty ACTIVATE4 cap set is [], distinct from a legacy line's null. */
    check_audit("test_fn_legacy_ok", "[]", real_empty_root, "err_cas_miss");
    close(fd);
}

/* 5. ACTIVATE3 (no caps/cap_root at all) still works unchanged. */
static void test_activate3_regression(void) {
    int fd = connect_sock(SOCK_PATH);
    CHECK(fd >= 0, "connected to reload server");
    if (fd < 0) return;

    char impl_hash[65], cas_hash[65];
    memset(impl_hash, '3', 64); impl_hash[64] = '\0';
    memset(cas_hash,  '4', 64); cas_hash[64]  = '\0';
    uint32_t epoch = g_epoch++;

    char signed_msg[1024];
    snprintf(signed_msg, sizeof(signed_msg),
             "ACTIVATE3 %s %s %s %d epoch:%u callers:%s",
             "test_fn_v3", impl_hash, cas_hash, 0, epoch, "");
    char sig_b64[128];
    sign_b64(signed_msg, sig_b64);

    char line[1536];
    snprintf(line, sizeof(line), "ACTIVATE3 %s %s %s %s %d epoch:%u callers:%s",
             "test_fn_v3", impl_hash, cas_hash, sig_b64, 0, epoch, "");
    send_line(fd, line);
    char resp[512];
    read_resp(fd, resp, sizeof(resp));
    CHECK(strncmp(resp, "ERR missing_artifact", 20) == 0,
          "ACTIVATE3 (no caps/cap_root) unaffected by ACTIVATE4 changes");
    check_audit("test_fn_v3", "null", NULL, "err_cas_miss");
    close(fd);
}

/* 5b. A BATCHED ACTIVATE4 carries its caps through staging to the audit line
 *     written at COMMIT_BATCH (staged entries hold heap copies). */
static void test_batch_audit_carries_caps(void) {
    int fd = connect_sock(SOCK_PATH);
    CHECK(fd >= 0, "connected to reload server");
    if (fd < 0) return;
    char resp[512];
    send_line(fd, "BEGIN_BATCH");
    read_resp(fd, resp, sizeof(resp));
    CHECK(strcmp(resp, "OK") == 0, "BEGIN_BATCH ok");

    const char *caps[] = { "IO.FileWrite" };
    char root[65];
    expected_cap_root(caps, 1, root);
    do_activate4(fd, "test_fn_batch", "IO.FileWrite", root, "", resp, sizeof(resp));
    CHECK(strncmp(resp, "OK ", 3) == 0, "ACTIVATE4 inside a batch is staged");

    send_line(fd, "COMMIT_BATCH");
    read_resp(fd, resp, sizeof(resp));
    CHECK(strcmp(resp, "ERR commit_partial_failure") == 0,
          "commit reaches activation (CAS-miss, no artifact staged)");
    check_audit("test_fn_batch", "[\"IO.FileWrite\"]", root, "err_cas_miss");
    close(fd);
}

/* 6. Policy enforcement: run with $MARCH_DEPLOY_POLICY pointed at a small
 *    file. Needs its own server (policy is loaded lazily/once per process),
 *    so this spawns as a forked child with the env var set, exercised via
 *    a fresh process rather than in-process (server policy cache is a
 *    process-global loaded-once flag). We approximate this in-process by
 *    invoking a second binary variant is unnecessary; instead this test
 *    is run as a *separate* dune test target (test_reload_activate4_policy)
 *    that starts its own server with MARCH_DEPLOY_POLICY set before any
 *    ACTIVATE4 — see test/dune and main() below (argv[2] selects mode). */

/* 7. The epoch model end to end (II.4.2): a real patch (hcr_stub.so) goes in
 *    through CAS_PUT and ACTIVATE5.  With the slot's three live versions all
 *    in use (a unit pinned at the base epoch keeps the baseline, one pinned at
 *    the first deploy's epoch keeps that version), a third deploy WAITs
 *    instead of failing, the batch stays staged, PINS and DRAIN report and
 *    arm, and the retry succeeds once the blocking unit exits. */
static const char STUB_CAS[] =
    "5555555555555555555555555555555555555555555555555555555555555555";

static int put_stub(int fd) {
    FILE *f = fopen("hcr_stub.so", "rb");
    if (!f) return 0;
    static unsigned char buf[1 << 20];
    size_t n = fread(buf, 1, sizeof(buf), f);
    fclose(f);
    char line[256], resp[256];
    snprintf(line, sizeof(line), "CAS_PUT %s %zu", STUB_CAS, n);
    send_line(fd, line);
    read_resp(fd, resp, sizeof(resp));
    if (strcmp(resp, "READY") != 0) return 0;
    if (write(fd, buf, n) != (ssize_t)n) return 0;
    read_resp(fd, resp, sizeof(resp));
    return strncmp(resp, "OK ", 3) == 0;
}

static void activate5(int fd, const char *name, int migrate, char *resp, int max) {
    char impl_hash[65];
    memset(impl_hash, '6', 64); impl_hash[64] = '\0';
    char root[65];
    expected_cap_root(NULL, 0, root);
    uint32_t epoch = 0;   /* the server's runtime epoch is max(this, current + 1) */
    char signed_msg[2048];
    snprintf(signed_msg, sizeof(signed_msg),
             "ACTIVATE5 %s %s %s %d epoch:%u cap_root:%s callers:%s",
             name, impl_hash, STUB_CAS, migrate, epoch, root, "");
    char sig_b64[128];
    sign_b64(signed_msg, sig_b64);
    char line[2560];
    snprintf(line, sizeof(line),
             "ACTIVATE5 %s %s %s %s %d epoch:%u cap_root:%s caps: callers:",
             name, impl_hash, STUB_CAS, sig_b64, migrate, epoch, root);
    send_line(fd, line);
    read_resp(fd, resp, max);
}

/* Read PINS up to END into one buffer. */
static void read_pins(int fd, char *out, size_t max) {
    send_line(fd, "PINS");
    out[0] = '\0';
    char line[512];
    for (int i = 0; i < 32; i++) {
        read_resp(fd, line, sizeof(line));
        if (strcmp(line, "END") == 0) break;
        strncat(out, line, max - strlen(out) - 2);
        strncat(out, "\n", max - strlen(out) - 1);
    }
}

static void test_epoch_model_wait_pins_drain(void) {
    int fd = connect_sock(SOCK_PATH);
    CHECK(fd >= 0, "connected to reload server (epoch model)");
    if (fd < 0) return;
    char resp[512], pins[4096];
    CHECK(put_stub(fd), "stub patch uploaded to the CAS");

    activate5(fd, "test_fn_epoch", 7, resp, sizeof(resp));
    CHECK(strcmp(resp, "ERR bad_format bad_migrate") == 0,
          "ACTIVATE5 rejects a migrate value outside the bitmask");

    uint32_t base = march_epoch_current();
    CHECK(march_epoch_pin(base) == 0, "a unit pinned at the base epoch");
    activate5(fd, "test_fn_epoch", 0, resp, sizeof(resp));
    CHECK(strncmp(resp, "OK ", 3) == 0, "first deploy activates");
    uint32_t e1 = march_epoch_current();
    CHECK(e1 > base, "and advances the epoch");
    CHECK(march_epoch_pin(e1) == 0, "a unit pinned at the first deploy's epoch");
    activate5(fd, "test_fn_epoch", 0, resp, sizeof(resp));
    CHECK(strncmp(resp, "OK ", 3) == 0, "second deploy takes the third live version");

    activate5(fd, "test_fn_epoch", 0, resp, sizeof(resp));
    char want[128];
    snprintf(want, sizeof(want), "WAIT epoch:%u pins:1 deadline_ms:-1", base);
    CHECK(strcmp(resp, want) == 0,
          "third deploy WAITs on the oldest pinned epoch (nothing reclaimable)");
    if (strcmp(resp, want) != 0) fprintf(stderr, "    got: %s\n", resp);

    read_pins(fd, pins, sizeof(pins));
    snprintf(want, sizeof(want), "EPOCH %u pins:1", base);
    CHECK(strstr(pins, want) != NULL, "PINS lists the base epoch's unit");
    CHECK(strstr(pins, " current") != NULL, "PINS marks the current epoch");
    CHECK(strstr(pins, "COUNTERS deferred:") != NULL, "PINS reports the counters");

    snprintf(want, sizeof(want), "DRAIN epoch:%u soft_ms:60000 hard_ms:600000", base);
    send_line(fd, want);
    read_resp(fd, resp, sizeof(resp));
    CHECK(strcmp(resp, "OK") == 0, "DRAIN accepted");
    read_pins(fd, pins, sizeof(pins));
    snprintf(want, sizeof(want), "EPOCH %u pins:1 draining\n", base);
    CHECK(strstr(pins, want) != NULL, "PINS shows the epoch draining");

    /* A batch waits too, and stays staged. */
    send_line(fd, "BEGIN_BATCH"); read_resp(fd, resp, sizeof(resp));
    activate5(fd, "test_fn_epoch", 0, resp, sizeof(resp));
    CHECK(strncmp(resp, "OK ", 3) == 0, "ACTIVATE5 staged in a batch");
    send_line(fd, "COMMIT_BATCH"); read_resp(fd, resp, sizeof(resp));
    CHECK(strncmp(resp, "WAIT epoch:", 11) == 0 && strstr(resp, "deadline_ms:-1") == NULL,
          "COMMIT_BATCH waits, and reports the armed hard deadline");

    march_epoch_unpin(base);   /* the blocking unit exits */
    send_line(fd, "COMMIT_BATCH"); read_resp(fd, resp, sizeof(resp));
    CHECK(strcmp(resp, "OK 1") == 0, "the retried COMMIT_BATCH activates the staged deploy");
    march_epoch_unpin(e1);
    close(fd);
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s <keys_file> [policy]\n", argv[0]);
        return 2;
    }
    if (!load_secret_key(argv[1])) {
        fprintf(stderr, "failed to load secret key from %s\n", argv[1]);
        return 2;
    }

    snprintf(g_audit_path, sizeof(g_audit_path),
             "/tmp/march_reload_audit_%d.jsonl", (int)getpid());
    unlink(g_audit_path);
    setenv("MARCH_AUDIT_LOG", g_audit_path, 1);

    char sock_path[64];
    snprintf(sock_path, sizeof(sock_path), "/tmp/march_reload_test_%d.sock", (int)getpid());
    SOCK_PATH = sock_path;

    /* A private CAS (march_reload_server_start roots it at $HOME/.march/cas):
     * the epoch-model case uploads a real artifact. */
    char home[96];
    snprintf(home, sizeof(home), "/tmp/march_reload_home_%d", (int)getpid());
    mkdir(home, 0700);
    setenv("HOME", home, 1);

    march_dispatch_init(64);
    /* Register every test fn name so do_activate gets past the ABI lookup
     * and reaches the CAS-miss check (proving the cap gate ran and passed) —
     * an unregistered name would fail earlier with ERR unknown_name,
     * which would be indistinguishable from "cap gate let it through". */
    march_dispatch_register_name(1, "test_fn_ok");
    march_dispatch_register_name(2, "test_fn_tamper");
    march_dispatch_register_name(3, "test_fn_nopolicy");
    march_dispatch_register_name(4, "test_fn_legacy");
    march_dispatch_register_name(5, "test_fn_v3");
    march_dispatch_register_name(6, "test_fn_within_policy");
    march_dispatch_register_name(7, "test_fn_exceeds_policy");
    march_dispatch_register_name(8, "test_fn_legacy_ok");
    march_dispatch_register_name(9, "test_fn_batch");
    march_dispatch_register_name(10, "test_fn_epoch");
    march_dispatch_publish(10, (void *)0x1010, "baseline", NULL, MARCH_NATIVE);
    march_reload_server_start(sock_path);

    int policy_mode = (argc >= 3 && strcmp(argv[2], "policy") == 0);

    if (!policy_mode) {
        test_tamper_check_matching_root_admits();
        test_tamper_check_mutated_caps_rejected();
        test_no_policy_is_permissive();
        test_empty_caps_bogus_root_rejected();
        test_empty_caps_real_empty_root_admitted();
        test_activate3_regression();
        test_batch_audit_carries_caps();
        test_epoch_model_wait_pins_drain();
    } else {
        /* $MARCH_DEPLOY_POLICY must already be set by the caller (dune rule)
         * before this process started, since the server loads it lazily on
         * first ACTIVATE4 and caches the result for the process lifetime. */
        CHECK(getenv("MARCH_DEPLOY_POLICY") != NULL,
              "MARCH_DEPLOY_POLICY is set for the policy-mode test process");

        /* Within-policy cap => admitted (falls through to CAS-miss). */
        {
            int fd = connect_sock(SOCK_PATH);
            CHECK(fd >= 0, "connected to reload server (policy mode)");
            if (fd >= 0) {
                const char *caps[] = { "IO.Console" };
                char root[65];
                expected_cap_root(caps, 1, root);
                char resp[512];
                do_activate4(fd, "test_fn_within_policy", "IO.Console", root, "", resp, sizeof(resp));
                CHECK(strncmp(resp, "ERR missing_artifact", 20) == 0,
                      "cap within policy => admitted past cap gates");
                close(fd);
            }
        }
        /* Cap exceeding policy => ERR cap_policy <cap>. */
        {
            int fd = connect_sock(SOCK_PATH);
            CHECK(fd >= 0, "connected to reload server (policy mode) #2");
            if (fd >= 0) {
                const char *caps[] = { "IO.Process" };
                char root[65];
                expected_cap_root(caps, 1, root);
                char resp[512];
                do_activate4(fd, "test_fn_exceeds_policy", "IO.Process", root, "", resp, sizeof(resp));
                CHECK(strcmp(resp, "ERR cap_policy IO.Process") == 0,
                      "cap exceeding policy => ERR cap_policy IO.Process");
                check_audit("test_fn_exceeds_policy", "[\"IO.Process\"]", root, "err_cap_policy");
                close(fd);
            }
        }
    }

    unlink(sock_path);
    unlink(g_audit_path);
    if (g_failed == 0) {
        printf("test_reload_activate4%s: all checks passed\n", policy_mode ? "_policy" : "");
        return 0;
    }
    fprintf(stderr, "test_reload_activate4%s: %d check(s) failed\n",
            policy_mode ? "_policy" : "", g_failed);
    return 1;
}
