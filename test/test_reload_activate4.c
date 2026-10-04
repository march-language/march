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
#include <signal.h>

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
static const char HOT_IMPL_HEX[] =
    "6666666666666666666666666666666666666666666666666666666666666666";

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

/* DD step 12a: march_reload_request (the stdlib-only reload_request builtin)
 * runs the socket's own dispatch, so its answers match the socket's. */
static void test_in_process_request(void) {
    size_t n = 0;
    char *r = march_reload_request("PING", 4, &n);
    CHECK(r && strcmp(r, "PONG\n") == 0 && n == 5, "in-process PING answers like the socket");
    free(r);
    r = march_reload_request("NOPE\n", 5, &n);
    CHECK(r && strcmp(r, "ERR unknown_command\n") == 0, "in-process unknown verb refused");
    free(r);
    int fd = connect_sock(SOCK_PATH);
    send_line(fd, "RELEASE_HEAD\n");
    char resp[256];
    read_resp(fd, resp, sizeof(resp));
    close(fd);
    r = march_reload_request("RELEASE_HEAD", 12, &n);
    CHECK(r && strncmp(r, resp, strlen(r) - 1) == 0 && strncmp(r, "HEAD ", 5) == 0,
          "in-process RELEASE_HEAD equals the socket's");
    free(r);
    /* a body verb: TOPOLOGY reads its body from the request, after READY */
    r = march_reload_request("TOPOLOGY 0000000000000000000000000000000000000000000000000000000000000000 aa 3\nabc", 82, &n);
    CHECK(r && (strstr(r, "ERR bad_signature") || strstr(r, "ERR signing_not_configured")),
          "in-process TOPOLOGY is signature-checked before its body is read");
    free(r);
    r = march_reload_request("NODE_STATE", 10, &n);
    CHECK(r && strncmp(r, "STATE head:", 11) == 0 && strstr(r, " drained:") && strstr(r, "\nARTIFACT ")
          && strcmp(r + strlen(r) - 4, "END\n") == 0,
          "NODE_STATE reports the head, the topology, the drained epoch and the artifacts in effect");
    free(r);
}

static void test_hcr_info(void) {
    int fd = connect_sock(SOCK_PATH);
    CHECK(fd >= 0, "HCR_INFO connects");
    send_line(fd, "HCR_INFO\n");
    char resp[1024];
    int n = read_resp(fd, resp, sizeof(resp));
    CHECK(n > 0 && strncmp(resp, "HCR_INFO target:", 16) == 0,
          "HCR_INFO returns identity");
    CHECK(strstr(resp, " abi:march-hcr-v3;triple:") == NULL,
          "HCR_INFO uses abi field");
    CHECK(strstr(resp, " prefix:") != NULL && strstr(resp, " key:") != NULL,
          "HCR_INFO includes prefix and key");
    close(fd);
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

    /* DRAIN is signed (its hard deadline kills actors) and refuses the
     * current epoch, which every live unit is pinned at or below. */
    snprintf(want, sizeof(want), "DRAIN epoch:%u soft_ms:60000 hard_ms:600000", base);
    send_line(fd, want);
    read_resp(fd, resp, sizeof(resp));
    CHECK(strcmp(resp, "ERR bad_signature") == 0, "an unsigned DRAIN is refused");
    {
        char msg[128], sig[128], line[256];
        uint32_t cur = march_epoch_current();
        snprintf(msg, sizeof(msg), "DRAIN epoch:%u soft_ms:60000 hard_ms:600000", cur);
        sign_b64(msg, sig);
        snprintf(line, sizeof(line), "DRAIN %s epoch:%u soft_ms:60000 hard_ms:600000", sig, cur);
        send_line(fd, line);
        read_resp(fd, resp, sizeof(resp));
        CHECK(strcmp(resp, "ERR bad_epoch") == 0, "DRAIN of the current epoch is refused");
        snprintf(msg, sizeof(msg), "DRAIN epoch:%u soft_ms:60000 hard_ms:600000", base);
        sign_b64(msg, sig);
        snprintf(line, sizeof(line), "DRAIN %s epoch:%u soft_ms:60000 hard_ms:1", sig, base);
        send_line(fd, line);
        read_resp(fd, resp, sizeof(resp));
        CHECK(strcmp(resp, "ERR bad_signature") == 0, "a signature over other deadlines is refused");
        snprintf(line, sizeof(line), "DRAIN %s epoch:%u soft_ms:60000 hard_ms:600000", sig, base);
        send_line(fd, line);
        read_resp(fd, resp, sizeof(resp));
        CHECK(strcmp(resp, "OK") == 0, "a signed DRAIN of an older epoch is accepted");
    }
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

/* ── ACTIVATE6 (DD build step 10): per-role closures ─────────────────────
 * Build+send one ACTIVATE6.  [role_caps] is the SIGNED block ("R=hex;...");
 * [roles] the unsigned one ("R=csv;...").  [cas] may be NULL (a fake hash:
 * admission then falls through to CAS-miss). */
/* ACTIVATE6 for [name] whose own caps are own[0..nown) (sorted) and whose
 * signed role roots / unsigned role closures are [role_caps] / [roles]. */
static void do_activate6_caps(int fd, const char *name, const char *cas,
                              const char **own, int nown,
                              const char *role_caps, const char *roles,
                              char *resp, int resp_max) {
    char impl_hash[65], cas_hash[65];
    memset(impl_hash, '7', 64); impl_hash[64] = '\0';
    if (cas) snprintf(cas_hash, sizeof(cas_hash), "%s", cas);
    else { memset(cas_hash, '8', 64); cas_hash[64] = '\0'; }
    char root[65];
    expected_cap_root(own, nown, root);
    char own_csv[1024]; size_t ol = 0;
    own_csv[0] = '\0';
    for (int i = 0; i < nown; i++)
        ol += (size_t)snprintf(own_csv + ol, sizeof(own_csv) - ol, "%s%s", i ? "," : "", own[i]);
    char signed_msg[4096];
    snprintf(signed_msg, sizeof(signed_msg),
             "ACTIVATE6 %s %s %s %d epoch:%u cap_root:%s role_caps:%s callers:%s",
             name, impl_hash, cas_hash, 0, 0u, root, role_caps, "");
    char sig_b64[128];
    sign_b64(signed_msg, sig_b64);
    char line[8192];
    snprintf(line, sizeof(line),
             "ACTIVATE6 %s %s %s %s %d epoch:%u cap_root:%s role_caps:%s caps:%s roles:%s callers:",
             name, impl_hash, cas_hash, sig_b64, 0, 0u, root, role_caps, own_csv, roles);
    send_line(fd, line);
    read_resp(fd, resp, resp_max);
}

static void do_activate6(int fd, const char *name, const char *cas,
                         const char *role_caps, const char *roles,
                         char *resp, int resp_max) {
    do_activate6_caps(fd, name, cas, NULL, 0, role_caps, roles, resp, resp_max);
}

/* "Stream.Cons=<root(caps)>" for one role. */
static void role_root_entry(const char *role, const char **caps, int n, char *out, size_t max) {
    char root[65];
    expected_cap_root(caps, n, root);
    snprintf(out, max, "%s=%s", role, root);
}

static void test_activate6_role_closures(void) {
    int fd = connect_sock(SOCK_PATH);
    CHECK(fd >= 0, "connected to reload server (ACTIVATE6)");
    if (fd < 0) return;
    char resp[512];
    const char *cons[] = { "IO.Console", "IO.FileWrite" };
    const char *prod[] = { "IO.Console" };
    char rc_cons[256], rc_prod[256], rc_both[600];
    role_root_entry("Stream.Cons", cons, 2, rc_cons, sizeof(rc_cons));
    role_root_entry("Stream.Prod", prod, 1, rc_prod, sizeof(rc_prod));
    snprintf(rc_both, sizeof(rc_both), "%s;%s", rc_cons, rc_prod);

    do_activate6(fd, "test_fn_role", NULL, rc_both,
                 "Stream.Cons=IO.Console,IO.FileWrite;Stream.Prod=IO.Console",
                 resp, sizeof(resp));
    CHECK(strncmp(resp, "ERR missing_artifact", 20) == 0,
          "ACTIVATE6: matching role roots pass admission (falls through to CAS-miss)");
    {
        char line[4096]; last_audit_line(line, sizeof(line));
        CHECK(strstr(line, "\"roles\":\"Stream.Cons=IO.Console,IO.FileWrite;Stream.Prod=IO.Console\"") != NULL,
              "ACTIVATE6: the audit line records the role closures");
    }

    /* The unsigned closure narrowed by a MITM (drop IO.FileWrite): the
     * signed root no longer recomputes. */
    do_activate6(fd, "test_fn_role", NULL, rc_both,
                 "Stream.Cons=IO.Console;Stream.Prod=IO.Console", resp, sizeof(resp));
    CHECK(strcmp(resp, "ERR role_cap_tamper") == 0,
          "ACTIVATE6: a stripped role closure is ERR role_cap_tamper");
    check_audit("test_fn_role", "[]",
                "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262",
                "err_role_cap_tamper");

    do_activate6(fd, "test_fn_role", NULL, rc_both,
                 "Stream.Cons=IO.Console,IO.FileWrite", resp, sizeof(resp));
    CHECK(strcmp(resp, "ERR role_cap_tamper") == 0,
          "ACTIVATE6: a signed role missing from roles: is ERR role_cap_tamper");

    do_activate6(fd, "test_fn_role", NULL, rc_cons,
                 "Stream.Cons=IO.Console,IO.FileWrite;Stream.Prod=IO.Console", resp, sizeof(resp));
    CHECK(strcmp(resp, "ERR role_cap_tamper") == 0,
          "ACTIVATE6: an unsigned role in roles: is ERR role_cap_tamper");

    char rc_unsorted[600];
    snprintf(rc_unsorted, sizeof(rc_unsorted), "%s;%s", rc_prod, rc_cons);
    do_activate6(fd, "test_fn_role", NULL, rc_unsorted,
                 "Stream.Cons=IO.Console,IO.FileWrite;Stream.Prod=IO.Console", resp, sizeof(resp));
    CHECK(strcmp(resp, "ERR bad_format bad_role_caps") == 0,
          "ACTIVATE6: role_caps: must be strictly sorted (canonical)");

    /* The signature covers role_caps: swap in another root, keep the sig. */
    {
        char impl_hash[65], cas_hash[65], root[65];
        memset(impl_hash, '7', 64); impl_hash[64] = '\0';
        memset(cas_hash, '8', 64); cas_hash[64] = '\0';
        expected_cap_root(NULL, 0, root);
        char signed_msg[4096], sig_b64[128], line[8192];
        snprintf(signed_msg, sizeof(signed_msg),
                 "ACTIVATE6 %s %s %s %d epoch:%u cap_root:%s role_caps:%s callers:%s",
                 "test_fn_role", impl_hash, cas_hash, 0, 0u, root, rc_cons, "");
        sign_b64(signed_msg, sig_b64);
        char rc_other[256];
        role_root_entry("Stream.Cons", prod, 1, rc_other, sizeof(rc_other));
        snprintf(line, sizeof(line),
                 "ACTIVATE6 %s %s %s %s 0 epoch:0 cap_root:%s role_caps:%s caps: roles:%s callers:",
                 "test_fn_role", impl_hash, cas_hash, sig_b64, root, rc_other,
                 "Stream.Cons=IO.Console");
        send_line(fd, line);
        read_resp(fd, resp, sizeof(resp));
        CHECK(strcmp(resp, "ERR bad_signature") == 0,
              "ACTIVATE6: role_caps: is inside the signed message");
    }

    /* The old verbs still work beside it (ACTIVATE4 path unchanged). */
    {
        const char *caps[] = { "IO.Console" };
        char root[65];
        expected_cap_root(caps, 1, root);
        do_activate4(fd, "test_fn_role", "IO.Console", root, "", resp, sizeof(resp));
        CHECK(strncmp(resp, "ERR missing_artifact", 20) == 0,
              "ACTIVATE4 unchanged beside ACTIVATE6");
    }

    /* A real activation through ACTIVATE6 (the stub patch is in the CAS). */
    do_activate6(fd, "test_fn_epoch", STUB_CAS, rc_both,
                 "Stream.Cons=IO.Console,IO.FileWrite;Stream.Prod=IO.Console",
                 resp, sizeof(resp));
    CHECK(strncmp(resp, "OK ", 3) == 0, "ACTIVATE6 activates a real patch");
    if (strncmp(resp, "OK ", 3) != 0) fprintf(stderr, "    got: %s\n", resp);
    close(fd);
}

/* Policy mode: the node policy (IO.Console, IO.NetConnect) bounds every
 * role closure.  A closure that widened to IO.FileWrite (a patch whose role
 * body now reaches file_write through an existing helper) is refused by the
 * SERVER, whatever the client's gate did. */
static void test_activate6_role_policy(void) {
    int fd = connect_sock(SOCK_PATH);
    CHECK(fd >= 0, "connected to reload server (ACTIVATE6 policy)");
    if (fd < 0) return;
    char resp[512];
    const char *narrow[] = { "IO.Console" };
    const char *wide[] = { "IO.Console", "IO.FileWrite" };
    char rc[256];
    role_root_entry("Stream.Cons", narrow, 1, rc, sizeof(rc));
    do_activate6(fd, "test_fn_role", NULL, rc, "Stream.Cons=IO.Console", resp, sizeof(resp));
    CHECK(strncmp(resp, "ERR missing_artifact", 20) == 0,
          "ACTIVATE6: a role closure within policy is admitted");
    role_root_entry("Stream.Cons", wide, 2, rc, sizeof(rc));
    do_activate6(fd, "test_fn_role", NULL, rc, "Stream.Cons=IO.Console,IO.FileWrite",
                 resp, sizeof(resp));
    CHECK(strcmp(resp, "ERR role_cap_policy Stream.Cons IO.FileWrite") == 0,
          "ACTIVATE6: a widened role closure outside policy is ERR role_cap_policy");
    if (strcmp(resp, "ERR role_cap_policy Stream.Cons IO.FileWrite") != 0)
        fprintf(stderr, "    got: %s\n", resp);
    {
        char line[4096]; last_audit_line(line, sizeof(line));
        CHECK(strstr(line, "\"result\":\"err_role_cap_policy\"") != NULL,
              "ACTIVATE6: the refusal is audited");
    }
    close(fd);
}

/* Policy mode: the policy speaks only about IO capabilities.  A proof cap
 * (Session.Live, ClusterNode.Live, Actor.Introspect, a user's Db.Migrated)
 * carries no IO authority of its own and only its declaring module can mint
 * it, so the gate does not police it: a role body's own caps include the
 * session it is handed (caps=IO.Console,Session.Live), and a node policy
 * generated from the pool's IO caps admits it.  An IO cap outside the
 * policy is refused exactly as before, beside a proof cap or not, in the
 * function's own caps and in a role closure. */
static void test_policy_ignores_proof_caps(void) {
    int fd = connect_sock(SOCK_PATH);
    CHECK(fd >= 0, "connected to reload server (proof caps)");
    if (fd < 0) return;
    char resp[512], root[65];

    /* ACTIVATE4: a role body's own caps. */
    {
        const char *caps[] = { "IO.Console", "Session.Live" };
        expected_cap_root(caps, 2, root);
        do_activate4(fd, "test_fn_within_policy", "IO.Console,Session.Live", root, "", resp, sizeof(resp));
        CHECK(strncmp(resp, "ERR missing_artifact", 20) == 0,
              "proof cap beside an IO cap within policy => admitted past cap gates");
        if (strncmp(resp, "ERR missing_artifact", 20) != 0) fprintf(stderr, "    got: %s\n", resp);
    }
    /* A proof cap does not launder an IO cap the policy lacks. */
    {
        const char *caps[] = { "IO.Process", "Session.Live" };
        expected_cap_root(caps, 2, root);
        do_activate4(fd, "test_fn_exceeds_policy", "IO.Process,Session.Live", root, "", resp, sizeof(resp));
        CHECK(strcmp(resp, "ERR cap_policy IO.Process") == 0,
              "proof cap beside an IO cap outside policy => ERR cap_policy IO.Process");
        if (strcmp(resp, "ERR cap_policy IO.Process") != 0) fprintf(stderr, "    got: %s\n", resp);
    }
    /* An unknown IO-rooted path is still IO: refused, not mistaken for a proof cap. */
    {
        const char *caps[] = { "IO.Bogus" };
        expected_cap_root(caps, 1, root);
        do_activate4(fd, "test_fn_exceeds_policy", "IO.Bogus", root, "", resp, sizeof(resp));
        CHECK(strcmp(resp, "ERR cap_policy IO.Bogus") == 0,
              "an IO-rooted path outside policy => ERR cap_policy IO.Bogus");
        if (strcmp(resp, "ERR cap_policy IO.Bogus") != 0) fprintf(stderr, "    got: %s\n", resp);
    }
    /* The bare IO root itself: refused under a narrower policy. */
    {
        const char *caps[] = { "IO" };
        expected_cap_root(caps, 1, root);
        do_activate4(fd, "test_fn_exceeds_policy", "IO", root, "", resp, sizeof(resp));
        CHECK(strcmp(resp, "ERR cap_policy IO") == 0, "the IO root outside policy => ERR cap_policy IO");
        if (strcmp(resp, "ERR cap_policy IO") != 0) fprintf(stderr, "    got: %s\n", resp);
    }

    /* ACTIVATE6: a role body, own caps and closure both holding proof caps. */
    {
        const char *own[] = { "IO.Console", "Session.Live" };
        const char *closure[] = { "ClusterNode.Live", "IO.Console", "Session.Live" };
        char rc[256];
        role_root_entry("Echo.Server", closure, 3, rc, sizeof(rc));
        do_activate6_caps(fd, "test_fn_role", NULL, own, 2, rc,
                          "Echo.Server=ClusterNode.Live,IO.Console,Session.Live", resp, sizeof(resp));
        CHECK(strncmp(resp, "ERR missing_artifact", 20) == 0,
              "ACTIVATE6: a role body holding Session.Live within an IO policy is admitted");
        if (strncmp(resp, "ERR missing_artifact", 20) != 0) fprintf(stderr, "    got: %s\n", resp);
    }
    /* The same role body whose closure widened to IO.FileWrite: refused. */
    {
        const char *own[] = { "IO.Console", "Session.Live" };
        const char *closure[] = { "IO.Console", "IO.FileWrite", "Session.Live" };
        char rc[256];
        role_root_entry("Echo.Server", closure, 3, rc, sizeof(rc));
        do_activate6_caps(fd, "test_fn_role", NULL, own, 2, rc,
                          "Echo.Server=IO.Console,IO.FileWrite,Session.Live", resp, sizeof(resp));
        CHECK(strcmp(resp, "ERR role_cap_policy Echo.Server IO.FileWrite") == 0,
              "ACTIVATE6: a role closure widened beyond policy beside Session.Live is ERR role_cap_policy");
        if (strcmp(resp, "ERR role_cap_policy Echo.Server IO.FileWrite") != 0) fprintf(stderr, "    got: %s\n", resp);
    }
    close(fd);

    /* The control plane's path: the Agent relays a release's ACTIVATE lines
     * through march_reload_request (the reload_request builtin), the same
     * dispatch and the same gate as the socket. */
    {
        char impl_hash[65], cas_hash[65], signed_msg[1024], sig_b64[128], line[2048];
        memset(impl_hash, '1', 64); impl_hash[64] = '\0';
        memset(cas_hash,  '2', 64); cas_hash[64]  = '\0';
        const char *variants[2][2] = {
            { "IO.Console,Session.Live", "ERR missing_artifact" },
            { "IO.Process,Session.Live", "ERR cap_policy IO.Process" },
        };
        const char *caps_ok[] = { "IO.Console", "Session.Live" };
        const char *caps_bad[] = { "IO.Process", "Session.Live" };
        for (int v = 0; v < 2; v++) {
            expected_cap_root(v == 0 ? caps_ok : caps_bad, 2, root);
            const char *name = v == 0 ? "test_fn_within_policy" : "test_fn_exceeds_policy";
            uint32_t epoch = g_epoch++;
            snprintf(signed_msg, sizeof(signed_msg), "ACTIVATE4 %s %s %s 0 epoch:%u cap_root:%s callers:",
                     name, impl_hash, cas_hash, epoch, root);
            sign_b64(signed_msg, sig_b64);
            int len = snprintf(line, sizeof(line),
                               "ACTIVATE4 %s %s %s %s 0 epoch:%u cap_root:%s caps:%s callers:",
                               name, impl_hash, cas_hash, sig_b64, epoch, root, variants[v][0]);
            size_t n = 0;
            char *r = march_reload_request(line, (size_t)len, &n);
            int ok = r && strncmp(r, variants[v][1], strlen(variants[v][1])) == 0;
            CHECK(ok, v == 0 ? "in-process (Agent relay): Session.Live within an IO policy is admitted"
                             : "in-process (Agent relay): an IO cap outside policy is still ERR cap_policy");
            if (!ok) fprintf(stderr, "    got: %s", r ? r : "(null)\n");
            free(r);
        }
    }
}

/* A role the node does not serve: the control plane's Agent (generated into
 * every node's main), whose closure reaches IO.FileRead, which this pool's
 * policy (IO.Console, IO.NetConnect) does not allow.  [scoped]: the policy
 * names the roles the node serves (`serves Echo.Server Stream.Cons`, as
 * `forge host init` writes it), so Ctl.Agent is not this policy's to bound
 * and the patch is admitted; a served role is still bounded.  Unscoped (a
 * hand-written policy with no `serves` line): every role is bounded, as
 * before. */
static void test_policy_served_roles(int scoped) {
    int fd = connect_sock(SOCK_PATH);
    CHECK(fd >= 0, "connected to reload server (served roles)");
    if (fd < 0) return;
    char resp[512];
    const char *agent[] = { "IO.Clock", "IO.FileRead", "IO.Mut", "IO.NetConnect" };
    const char *echo[] = { "IO.Console", "IO.FileWrite" };
    char ra[256], re[256], both[600];
    role_root_entry("Ctl.Agent", agent, 4, ra, sizeof(ra));
    role_root_entry("Echo.Server", echo, 2, re, sizeof(re));
    snprintf(both, sizeof(both), "%s;%s", ra, re);

    do_activate6(fd, "test_fn_role", NULL, ra, "Ctl.Agent=IO.Clock,IO.FileRead,IO.Mut,IO.NetConnect",
                 resp, sizeof(resp));
    if (scoped) {
        CHECK(strncmp(resp, "ERR missing_artifact", 20) == 0,
              "scoped policy: a role the node does not serve (Ctl.Agent) is not bounded by it");
    } else {
        CHECK(strcmp(resp, "ERR role_cap_policy Ctl.Agent IO.Clock") == 0,
              "unscoped policy: every role closure is bounded (Ctl.Agent refused)");
    }
    if (strncmp(resp, scoped ? "ERR missing_artifact" : "ERR role_cap_policy Ctl.Agent", scoped ? 20 : 29) != 0)
        fprintf(stderr, "    got: %s\n", resp);

    /* Beside it, a served role widened beyond the policy: refused either way. */
    do_activate6(fd, "test_fn_role", NULL, both,
                 "Ctl.Agent=IO.Clock,IO.FileRead,IO.Mut,IO.NetConnect;Echo.Server=IO.Console,IO.FileWrite",
                 resp, sizeof(resp));
    const char *want = scoped ? "ERR role_cap_policy Echo.Server IO.FileWrite"
                              : "ERR role_cap_policy Ctl.Agent IO.Clock";
    CHECK(strcmp(resp, want) == 0,
          scoped ? "scoped policy: a served role widened beyond it is still ERR role_cap_policy"
                 : "unscoped policy: the first role outside it is ERR role_cap_policy");
    if (strcmp(resp, want) != 0) fprintf(stderr, "    got: %s\n", resp);
    close(fd);
}

/* ── TOPOLOGY (DD build step 10): a signed reconciler action ──────────── */
static const char TOPO_BODY[] = "[pools.edge]\nserves = [\"Stream.Cons\"]\n";

/* Push [body] signed over "TOPOLOGY <digest_claim>"; [send_digest] is what
 * the line claims (normally the body's own digest). */
static void push_topology(int fd, const char *body, const char *sign_digest,
                          const char *send_digest, char *resp, int max) {
    char sig[128], msg[128], line[512];
    snprintf(msg, sizeof(msg), "TOPOLOGY %s", sign_digest);
    sign_b64(msg, sig);
    snprintf(line, sizeof(line), "TOPOLOGY %s %s %zu", send_digest, sig, strlen(body));
    send_line(fd, line);
    read_resp(fd, resp, max);
    if (strcmp(resp, "READY") != 0) return;
    write(fd, body, strlen(body));
    read_resp(fd, resp, max);
}

static void topo_digest(const char *body, char out[65]) {
    march_blake3_hex((const unsigned char *)body, strlen(body), out);
}

static void test_topology_push(void) {
    int fd = connect_sock(SOCK_PATH);
    CHECK(fd >= 0, "connected to reload server (TOPOLOGY)");
    if (fd < 0) return;
    char resp[512], d[65], other[65], want[128];
    topo_digest(TOPO_BODY, d);
    topo_digest("something else", other);

    push_topology(fd, TOPO_BODY, other, d, resp, sizeof(resp));
    CHECK(strcmp(resp, "ERR bad_signature") == 0,
          "TOPOLOGY: a signature over another digest is refused before the body");
    push_topology(fd, TOPO_BODY, other, other, resp, sizeof(resp));
    CHECK(strcmp(resp, "ERR digest_mismatch") == 0,
          "TOPOLOGY: a body that does not hash to the signed digest is refused");
    push_topology(fd, TOPO_BODY, d, d, resp, sizeof(resp));
    snprintf(want, sizeof(want), "OK %s", d);
    CHECK(strcmp(resp, want) == 0, "TOPOLOGY: a signed push is accepted");
    {
        char line[4096]; last_audit_line(line, sizeof(line));
        CHECK(strstr(line, "\"type\":\"topology\"") && strstr(line, "\"result\":\"ok\""),
              "TOPOLOGY: the push is audited");
    }
    send_line(fd, "PING");   /* the connection is still in sync */
    read_resp(fd, resp, sizeof(resp));
    CHECK(strcmp(resp, "PONG") == 0, "TOPOLOGY: the stream stays in sync after the body");
    close(fd);
}

/* ── Sequenced releases (DD step 12-pre) ──────────────────────────────────
 * "SEQ <seq> <id> <sig> <signed line>", signed over "SEQ <seq> <id> <line>".
 * Run LAST in the shared server: once a release is accepted, unwrapped
 * signed verbs are refused for the rest of the process. */
static const char REL_A[] = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
static const char REL_B[] = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";

/* Wrap [inner] as release (seq, id); [sign_seq] is the seq the signature
 * covers (normally seq itself). */
static void seq_wrap(unsigned long long seq, unsigned long long sign_seq, const char *id,
                     const char *inner, char *out, size_t max) {
    char msg[2048], sig[128];
    snprintf(msg, sizeof(msg), "SEQ %llu %s %s", sign_seq, id, inner);
    sign_b64(msg, sig);
    snprintf(out, max, "SEQ %llu %s %s %s", seq, id, sig, inner);
}

/* A TOPOLOGY push of [body] as release (seq, id); resp gets the final line
 * (or the refusal). */
static void push_topology_seq(int fd, unsigned long long seq, const char *id,
                              const char *body, char *resp, int max) {
    char d[65], sig[128], msg[128], inner[512], line[2048];
    topo_digest(body, d);
    snprintf(msg, sizeof(msg), "TOPOLOGY %s", d);
    sign_b64(msg, sig);
    snprintf(inner, sizeof(inner), "TOPOLOGY %s %s %zu", d, sig, strlen(body));
    seq_wrap(seq, seq, id, inner, line, sizeof(line));
    send_line(fd, line);
    read_resp(fd, resp, max);
    if (strcmp(resp, "READY") != 0) return;
    write(fd, body, strlen(body));
    read_resp(fd, resp, max);
}

static void head_of(int fd, char *resp, int max) {
    send_line(fd, "RELEASE_HEAD");
    read_resp(fd, resp, max);
}

static int audit_has(const char *type, const char *result) {
    char t[64], r[96], line[4096];
    snprintf(t, sizeof(t), "\"type\":\"%s\"", type);
    snprintf(r, sizeof(r), "\"result\":\"%s\"", result);
    int found = 0;
    FILE *f = fopen(g_audit_path, "r");
    while (f && fgets(line, sizeof(line), f))
        if (strstr(line, t) && strstr(line, r)) found = 1;
    if (f) fclose(f);
    return found;
}

static void test_sequenced_releases(void) {
    int fd = connect_sock(SOCK_PATH);
    CHECK(fd >= 0, "connected to reload server (releases)");
    if (fd < 0) return;
    char resp[512], line[2048], want[160];
    const char *body2 = "[pools.edge]\nserves = [\"Stream.Prod\"]\n";

    head_of(fd, resp, sizeof(resp));
    CHECK(strcmp(resp, "HEAD 0 -") == 0, "RELEASE_HEAD: no release accepted yet");

    /* DRAIN is audited (epoch 1 is below current after the epoch-model case). */
    {
        char sig[128], msg[128];
        snprintf(msg, sizeof(msg), "DRAIN epoch:1 soft_ms:0 hard_ms:0");
        sign_b64(msg, sig);
        snprintf(line, sizeof(line), "DRAIN %s epoch:1", sig);
        send_line(fd, line);
        read_resp(fd, resp, sizeof(resp));
        CHECK(strcmp(resp, "OK") == 0, "DRAIN: an unwrapped drain is accepted before any release");
        CHECK(audit_has("drain", "ok"), "DRAIN: the drain is audited");
    }

    push_topology_seq(fd, 5, REL_A, TOPO_BODY, resp, sizeof(resp));
    CHECK(strncmp(resp, "OK ", 3) == 0, "SEQ: release 5 is accepted");
    CHECK(audit_has("release", "ok"), "SEQ: the accepted release is audited");
    head_of(fd, resp, sizeof(resp));
    snprintf(want, sizeof(want), "HEAD 5 %s", REL_A);
    CHECK(strcmp(resp, want) == 0, "RELEASE_HEAD: the head is release 5");

    {
        char d[65], sig[128], msg[128];
        topo_digest(TOPO_BODY, d);
        snprintf(msg, sizeof(msg), "TOPOLOGY %s", d);
        sign_b64(msg, sig);
        snprintf(line, sizeof(line), "TOPOLOGY %s %s %zu", d, sig, strlen(TOPO_BODY));
        send_line(fd, line);
        read_resp(fd, resp, sizeof(resp));
        CHECK(strcmp(resp, "ERR release_required") == 0,
              "SEQ: once a release is held, an unwrapped signed line (a replay) is refused");
    }

    push_topology_seq(fd, 4, REL_A, TOPO_BODY, resp, sizeof(resp));
    CHECK(strcmp(resp, "ERR stale_release head:5") == 0, "SEQ: an older release is refused");

    push_topology_seq(fd, 5, REL_B, body2, resp, sizeof(resp));
    snprintf(want, sizeof(want), "ERR release_fork head:5:%s", REL_A);
    CHECK(strcmp(resp, want) == 0, "SEQ: another release with the same number is a fork");
    CHECK(audit_has("release", "err_release_fork"), "SEQ: the fork is audited");

    push_topology_seq(fd, 5, REL_A, TOPO_BODY, resp, sizeof(resp));
    CHECK(strncmp(resp, "OK ", 3) == 0, "SEQ: the same release again (a retry) is accepted");

    {
        char d[65], sig[128], msg[128], inner[512];
        topo_digest(TOPO_BODY, d);
        snprintf(msg, sizeof(msg), "TOPOLOGY %s", d);
        sign_b64(msg, sig);
        snprintf(inner, sizeof(inner), "TOPOLOGY %s %s %zu", d, sig, strlen(TOPO_BODY));
        seq_wrap(9, 8, REL_B, inner, line, sizeof(line));   /* signed as 8, sent as 9 */
        send_line(fd, line);
        read_resp(fd, resp, sizeof(resp));
        CHECK(strcmp(resp, "ERR bad_signature") == 0,
              "SEQ: a release number the operator did not sign is refused");
        seq_wrap(9, 9, REL_B, "PING", line, sizeof(line));
        send_line(fd, line);
        read_resp(fd, resp, sizeof(resp));
        CHECK(strcmp(resp, "ERR bad_format not_a_signed_verb") == 0,
              "SEQ: only signed verbs can be wrapped");
    }

    push_topology_seq(fd, 7, REL_B, body2, resp, sizeof(resp));
    CHECK(strncmp(resp, "OK ", 3) == 0, "SEQ: a later release is accepted (gaps are fine)");
    head_of(fd, resp, sizeof(resp));
    snprintf(want, sizeof(want), "HEAD 7 %s", REL_B);
    CHECK(strcmp(resp, want) == 0, "RELEASE_HEAD: the head moved to release 7");

    send_line(fd, "PING");
    read_resp(fd, resp, sizeof(resp));
    CHECK(strcmp(resp, "PONG") == 0, "SEQ: the stream stays in sync");
    close(fd);
}

/* ── Signed artifact digests (review 2026-10-04, dd12 P1) ─────────────────
 * The review's CAS-substitution repro (specs/reviews/dd12/): the operator
 * signs an activation of ITS bytes (hcr_stub.so); whoever can write the CAS
 * (CAS_PUT is unauthenticated) stages other bytes (hcr_evil.so, the same
 * exports and identity markers, and a constructor that drops a marker file)
 * under the signed cas_hash.  Before ACTIVATE7 the node loaded them and ran
 * the attacker's code; now the bytes must hash to the signed so_blake3, and
 * a refused artifact is never mapped (the marker never appears). */
static const char ART_CAS[] =
    "7777777777777777777777777777777777777777777777777777777777777777";
static char g_marker[160];

static void file_digest(const char *path, char out[65]) {
    static unsigned char buf[1 << 20];
    FILE *f = fopen(path, "rb");
    size_t n = f ? fread(buf, 1, sizeof(buf), f) : 0;
    if (f) fclose(f);
    march_blake3_hex(buf, n, out);
}

/* CAS_PUT [file] under [cas], with " so_blake3:<so>" when [so]; the verdict. */
static void put_file(int fd, const char *cas, const char *file, const char *so,
                     char *resp, int max) {
    static unsigned char buf[1 << 20];
    FILE *f = fopen(file, "rb");
    size_t n = f ? fread(buf, 1, sizeof(buf), f) : 0;
    if (f) fclose(f);
    char line[256];
    snprintf(line, sizeof(line), "CAS_PUT %s %zu%s%s", cas, n, so ? " so_blake3:" : "", so ? so : "");
    send_line(fd, line);
    read_resp(fd, resp, max);
    if (strcmp(resp, "READY") != 0) return;
    if (write(fd, buf, n) != (ssize_t)n) { snprintf(resp, max, "short write"); return; }
    read_resp(fd, resp, max);
}

static void cas_check(int fd, const char *cas, const char *so, char *resp, int max) {
    char line[256];
    snprintf(line, sizeof(line), "CAS_CHECK %s%s%s", cas, so ? " so_blake3:" : "", so ? so : "");
    send_line(fd, line);
    read_resp(fd, resp, max);
}

/* The ACTIVATE7 line for [name] over artifact [cas] whose bytes the operator
 * signed as [signed_so]; [wire_so] is the digest the line carries (an
 * attacker may change it, but not the signature). */
static void activate7_line(const char *name, const char *cas, const char *signed_so,
                           const char *wire_so, char *line, size_t max) {
    char root[65];
    expected_cap_root(NULL, 0, root);
    char msg[2048], sig[128];
    snprintf(msg, sizeof(msg),
             "ACTIVATE7 %s %s %s 0 epoch:0 so_blake3:%s cap_root:%s callers:",
             name, HOT_IMPL_HEX, cas, signed_so, root);
    sign_b64(msg, sig);
    snprintf(line, max,
             "ACTIVATE7 %s %s %s %s 0 epoch:0 so_blake3:%s cap_root:%s caps: callers:",
             name, HOT_IMPL_HEX, cas, sig, wire_so, root);
}

static int marker_exists(void) {
    struct stat st;
    return stat(g_marker, &st) == 0;
}

/* The live version of [name]: what it returns, or 0 while the baseline
 * (the test's placeholder pointer, not code) is live. */
static int64_t call_current(const char *name) {
    uint32_t id, ver;
    if (!march_dispatch_name_to_id(name, &id)) return -1;
    void *p = march_dispatch_enter(id, &ver);
    int64_t r = -2;
    if (p == (void *)0x1010) r = 0;
    else if (p) { int64_t (*fn)(void); memcpy(&fn, &p, sizeof(fn)); r = fn(); }
    march_dispatch_leave(id, ver);
    return r;
}

static void test_artifact_digest(void) {
    int fd = connect_sock(SOCK_PATH);
    CHECK(fd >= 0, "connected to reload server (artifact digest)");
    if (fd < 0) return;
    char good[65], evil[65], resp[512], line[4096];
    file_digest("hcr_stub.so", good);
    file_digest("hcr_evil.so", evil);
    CHECK(strcmp(good, evil) != 0, "digest: the two artifacts differ");
    unlink(g_marker);

    /* 1. The CAS is not a trust boundary: the attacker's bytes go in. */
    put_file(fd, ART_CAS, "hcr_evil.so", NULL, resp, sizeof(resp));
    CHECK(strncmp(resp, "OK ", 3) == 0, "digest: an undigested CAS_PUT stores any bytes");
    cas_check(fd, ART_CAS, NULL, resp, sizeof(resp));
    CHECK(strcmp(resp, "PRESENT") == 0, "digest: CAS_CHECK by key alone says PRESENT");
    cas_check(fd, ART_CAS, good, resp, sizeof(resp));
    CHECK(strcmp(resp, "MISSING") == 0,
          "digest: CAS_CHECK with the signed digest says MISSING (forge re-uploads)");

    /* 2. The operator's genuinely signed line over those bytes is refused,
     *    and none of the attacker's code ever ran. */
    activate7_line("test_fn_digest", ART_CAS, good, good, line, sizeof(line));
    send_line(fd, line);
    read_resp(fd, resp, sizeof(resp));
    CHECK(strcmp(resp, "ERR artifact_digest") == 0,
          "digest: a signed ACTIVATE7 over substituted bytes is refused");
    if (strcmp(resp, "ERR artifact_digest") != 0) fprintf(stderr, "    got: %s\n", resp);
    CHECK(!marker_exists(), "digest: the substituted artifact's constructor never ran");
    CHECK(call_current("test_fn_digest") == 0, "digest: the baseline is still live");
    {
        char a[4096]; last_audit_line(a, sizeof(a));
        CHECK(strstr(a, "\"fn\":\"test_fn_digest\"") && strstr(a, "\"result\":\"err_artifact_digest\""),
              "digest: the refusal is audited");
    }

    /* 3. The same through a batch. */
    send_line(fd, "BEGIN_BATCH"); read_resp(fd, resp, sizeof(resp));
    send_line(fd, line); read_resp(fd, resp, sizeof(resp));
    CHECK(strncmp(resp, "OK ", 3) == 0, "digest: ACTIVATE7 stages in a batch");
    send_line(fd, "COMMIT_BATCH"); read_resp(fd, resp, sizeof(resp));
    CHECK(strcmp(resp, "ERR commit_partial_failure") == 0,
          "digest: COMMIT_BATCH over substituted bytes activates nothing");
    CHECK(!marker_exists(), "digest: and maps none of them");

    /* 4. so_blake3 is inside the signature: rewriting it to the attacker's
     *    digest breaks the signature. */
    activate7_line("test_fn_digest", ART_CAS, good, evil, line, sizeof(line));
    send_line(fd, line);
    read_resp(fd, resp, sizeof(resp));
    CHECK(strcmp(resp, "ERR bad_signature") == 0, "digest: so_blake3 is signed");
    {
        char bad[4096];
        activate7_line("test_fn_digest", ART_CAS, good, good, line, sizeof(line));
        char *so = strstr(line, " so_blake3:");
        snprintf(bad, sizeof(bad), "%.*s%s", (int)(so - line), line, so + 11 + 64);
        send_line(fd, bad);
        read_resp(fd, resp, sizeof(resp));
        CHECK(strcmp(resp, "ERR bad_format missing_so_blake3") == 0,
              "digest: ACTIVATE7 without so_blake3 is malformed");
    }

    /* 5. A digested CAS_PUT refuses bytes that are not the named ones. */
    put_file(fd, ART_CAS, "hcr_stub.so", evil, resp, sizeof(resp));
    CHECK(strcmp(resp, "ERR digest_mismatch") == 0, "digest: CAS_PUT refuses bytes off their digest");
    cas_check(fd, ART_CAS, evil, resp, sizeof(resp));
    CHECK(strcmp(resp, "PRESENT") == 0, "digest: and the refused upload stored nothing");

    /* 6. The operator's bytes, uploaded with their digest, activate. */
    put_file(fd, ART_CAS, "hcr_stub.so", good, resp, sizeof(resp));
    CHECK(strncmp(resp, "OK ", 3) == 0, "digest: CAS_PUT of the signed bytes with their digest");
    cas_check(fd, ART_CAS, good, resp, sizeof(resp));
    CHECK(strcmp(resp, "PRESENT") == 0, "digest: CAS_CHECK with the digest says PRESENT");
    activate7_line("test_fn_digest", ART_CAS, good, good, line, sizeof(line));
    send_line(fd, line);
    read_resp(fd, resp, sizeof(resp));
    CHECK(strncmp(resp, "OK ", 3) == 0, "digest: ACTIVATE7 over the signed bytes activates");
    CHECK(call_current("test_fn_digest") == 42, "digest: the operator's function is live");
    CHECK(!marker_exists(), "digest: no attacker code ran at any point");
    {
        /* What was mapped is the private verified copy, not the CAS file. */
        char cmd[512];
        snprintf(cmd, sizeof(cmd), "test -f \"$(ls -d %s/.march/cas/hcr_state/*/loaded)/%s.so\"",
                 getenv("HOME"), good);
        CHECK(system(cmd) == 0, "digest: the activation loaded the verified private copy");
    }

    /* 7. After the activation, replacing the CAS file does not change the
     *    live code, and a re-activation over the new bytes is refused. */
    put_file(fd, ART_CAS, "hcr_evil.so", NULL, resp, sizeof(resp));
    activate7_line("test_fn_digest", ART_CAS, good, good, line, sizeof(line));
    send_line(fd, line);
    read_resp(fd, resp, sizeof(resp));
    CHECK(strcmp(resp, "ERR artifact_digest") == 0, "digest: substituted after the fact, still refused");
    CHECK(call_current("test_fn_digest") == 42 && !marker_exists(),
          "digest: and the live function is still the operator's");
    put_file(fd, ART_CAS, "hcr_stub.so", good, resp, sizeof(resp));
    close(fd);
}

/* Once the node holds a release (run after test_sequenced_releases: head 7,
 * REL_B), a line from before ACTIVATE7 -- no digest of the bytes -- is
 * refused even when it is wrapped in the current release; ACTIVATE7 is not. */
static void test_unbound_activate_after_release(void) {
    int fd = connect_sock(SOCK_PATH);
    CHECK(fd >= 0, "connected to reload server (unbound after release)");
    if (fd < 0) return;
    char resp[512], inner[4096], line[8192], good[65];
    char root[65], msg[2048], sig[128];
    expected_cap_root(NULL, 0, root);
    snprintf(msg, sizeof(msg), "ACTIVATE5 test_fn_digest %s %s 0 epoch:0 cap_root:%s callers:",
             HOT_IMPL_HEX, ART_CAS, root);
    sign_b64(msg, sig);
    snprintf(inner, sizeof(inner), "ACTIVATE5 test_fn_digest %s %s %s 0 epoch:0 cap_root:%s caps: callers:",
             HOT_IMPL_HEX, ART_CAS, sig, root);
    seq_wrap(7, 7, REL_B, inner, line, sizeof(line));
    send_line(fd, line);
    read_resp(fd, resp, sizeof(resp));
    CHECK(strcmp(resp, "ERR artifact_digest_required") == 0,
          "release: a wrapped ACTIVATE5 (no signed digest) is refused once a release is held");
    if (strcmp(resp, "ERR artifact_digest_required") != 0) fprintf(stderr, "    got: %s\n", resp);
    CHECK(audit_has("activate", "err_artifact_digest_required"), "release: the refusal is audited");
    file_digest("hcr_stub.so", good);
    activate7_line("test_fn_digest", ART_CAS, good, good, inner, sizeof(inner));
    seq_wrap(7, 7, REL_B, inner, line, sizeof(line));
    send_line(fd, line);
    read_resp(fd, resp, sizeof(resp));
    CHECK(strncmp(resp, "OK ", 3) == 0, "release: a wrapped ACTIVATE7 is accepted");
    close(fd);
}

/* ── Restart durability (plan 6.5, DD build step 10) ─────────────────────
 * Each phase is its own process (fork), i.e. its own server lifetime, over
 * one HOME (the CAS root and the persisted state) and one socket path. */
#include <sys/wait.h>

static const char *g_restore_home;

/* The dispatch table a restarted binary has: the same names, the same
 * baseline (or a different one, for base_changed). */
static void restore_boot(const char *baseline) {
    /* The default SIGHUP action with SA_SIGINFO set: what a process started
     * by a parent that caught SIGHUP inherits on macOS (the flag survives
     * exec, the handler does not).  The topology hook must not read that as
     * a watcher: a SIGHUP here would kill the phase. */
    struct sigaction dfl;
    memset(&dfl, 0, sizeof(dfl));
    dfl.sa_handler = SIG_DFL;
    dfl.sa_flags = SA_SIGINFO;
    sigaction(SIGHUP, &dfl, NULL);
    march_dispatch_init(64);
    march_dispatch_register_name(1, "test_fn_epoch");
    march_dispatch_publish(1, (void *)0x1010, baseline, NULL, MARCH_NATIVE);
    march_reload_server_start(SOCK_PATH);
}

static void restore_versions(int fd, char *out, size_t max, const char *verb) {
    send_line(fd, verb);
    out[0] = '\0';
    char line[1024];
    for (int i = 0; i < 64; i++) {
        read_resp(fd, line, sizeof(line));
        if (strcmp(line, "END") == 0 || !line[0]) break;
        strncat(out, line, max - strlen(out) - 2);
        strncat(out, "\n", max - strlen(out) - 1);
    }
}

static const char HOT_IMPL[] =
    "6666666666666666666666666666666666666666666666666666666666666666";

static void phase_activate(void) {
    restore_boot("baseline");
    int fd = connect_sock(SOCK_PATH);
    CHECK(fd >= 0, "phase 1: connected");
    if (fd < 0) return;
    char resp[512], v[4096];
    CHECK(put_stub(fd), "phase 1: stub patch uploaded");
    activate5(fd, "test_fn_epoch", 0, resp, sizeof(resp));
    CHECK(strncmp(resp, "OK ", 3) == 0, "phase 1: activated");
    restore_versions(fd, v, sizeof(v), "VERSIONS");
    char want[200];
    snprintf(want, sizeof(want), "VERSION test_fn_epoch hot %s", HOT_IMPL);
    CHECK(strstr(v, want) != NULL, "phase 1: VERSIONS shows the hot version");
    char d[65];
    topo_digest(TOPO_BODY, d);
    push_topology(fd, TOPO_BODY, d, d, resp, sizeof(resp));
    CHECK(strncmp(resp, "OK ", 3) == 0, "phase 1: a topology pushed");
    close(fd);
}

static void phase_restored(int expect_hot, const char *expect_mode, int expect_skipped) {
    int fd = connect_sock(SOCK_PATH);
    CHECK(fd >= 0, "restart: connected");
    if (fd < 0) return;
    char v[4096], want[200];
    restore_versions(fd, v, sizeof(v), "VERSIONS");
    snprintf(want, sizeof(want), "VERSION test_fn_epoch hot %s", HOT_IMPL);
    if (expect_hot)
        CHECK(strstr(v, want) != NULL, "restart: VERSIONS shows the hot version without a redeploy");
    else
        CHECK(strstr(v, " hot ") == NULL, "restart: VERSIONS shows only the baseline");
    restore_versions(fd, v, sizeof(v), "VERSIONS_DETAIL");
    snprintf(want, sizeof(want), "RESTORED entries:%d skipped:%d mode:%s ",
             expect_hot, expect_skipped, expect_mode);
    CHECK(strstr(v, want) != NULL, "restart: VERSIONS_DETAIL has the RESTORED line");
    if (!strstr(v, want)) fprintf(stderr, "    want: %s\n    got:\n%s", want, v);
    close(fd);
}

static int run_phase(void (*body)(void)) {
    fflush(stdout); fflush(stderr);
    pid_t pid = fork();
    if (pid == 0) {
        g_failed = 0;
        body();
        _exit(g_failed > 100 ? 100 : g_failed);
    }
    int st = 0;
    waitpid(pid, &st, 0);
    return WIFEXITED(st) ? WEXITSTATUS(st) : 101;
}

static void ph_restored_hot(void) {
    restore_boot("baseline");
    phase_restored(1, "replayed", 0);
    int fd = connect_sock(SOCK_PATH);
    if (fd < 0) return;
    char v[4096], d[65], want[128];
    {
        /* COMPACT: one persisted patch, one deploy, one artifact (the stub). */
        struct stat st;
        char path[512], resp[256];
        snprintf(path, sizeof(path), "%s/.march/cas/artifacts/%.2s/%.62s",
                 g_restore_home, STUB_CAS, STUB_CAS + 2);
        send_line(fd, "COMPACT");
        read_resp(fd, resp, sizeof(resp));
        snprintf(want, sizeof(want),
                 "STACK entries:1 functions:1 deploys:1 artifacts:1 cas_bytes:%lld",
                 stat(path, &st) == 0 ? (long long)st.st_size : -1LL);
        CHECK(strcmp(resp, want) == 0, "restart: COMPACT reports the persisted stack");
        if (strcmp(resp, want) != 0) fprintf(stderr, "    want: %s\n    got:  %s\n", want, resp);
    }
    restore_versions(fd, v, sizeof(v), "VERSIONS_DETAIL");
    topo_digest(TOPO_BODY, d);
    snprintf(want, sizeof(want), "topology:%s", d);
    CHECK(strstr(v, want) != NULL, "restart: the last pushed topology is restored");
    char line[4096]; last_audit_line(line, sizeof(line));
    CHECK(strstr(line, "\"type\":\"topology\"") && strstr(line, "\"result\":\"restored\""),
          "restart: the topology went back through the hook (audited)");
    close(fd);
}
static void ph_no_replay(void)      { setenv("MARCH_HCR_NO_REPLAY", "1", 1);
                                      restore_boot("baseline"); phase_restored(0, "off", 1); }
static void ph_after_no_replay(void){ restore_boot("baseline"); phase_restored(0, "none", 0); }
static void ph_corrupt_skipped(void){ restore_boot("baseline"); phase_restored(0, "replayed", 1); }
static void ph_base_changed(void)   { restore_boot("another-build"); phase_restored(0, "base_changed", 1); }

/* Releases across restarts (DD step 12-pre). */
static void ph_require_release(void) {
    setenv("MARCH_HCR_REQUIRE_RELEASE", "1", 1);
    restore_boot("another-build");
    int fd = connect_sock(SOCK_PATH);
    CHECK(fd >= 0, "require: connected");
    if (fd < 0) return;
    char resp[256], d[65];
    head_of(fd, resp, sizeof(resp));
    CHECK(strcmp(resp, "HEAD 0 - required") == 0, "require: RELEASE_HEAD says a release is required");
    topo_digest(TOPO_BODY, d);
    push_topology(fd, TOPO_BODY, d, d, resp, sizeof(resp));
    CHECK(strcmp(resp, "ERR release_required") == 0,
          "require: an unwrapped signed line is refused before any release");
    close(fd);
}

static volatile sig_atomic_t g_hups;
static void on_hup(int sig) { (void)sig; g_hups++; }

static void ph_release_push(void) {
    restore_boot("another-build");
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = on_hup;
    sa.sa_flags = SA_RESTART;   /* as march_install_async_signal: the client's read survives it */
    sigaction(SIGHUP, &sa, NULL);
    int fd = connect_sock(SOCK_PATH);
    CHECK(fd >= 0, "release: connected");
    if (fd < 0) return;
    char resp[256];
    push_topology_seq(fd, 3, REL_A, TOPO_BODY, resp, sizeof(resp));
    CHECK(strncmp(resp, "OK ", 3) == 0, "release: release 3 accepted");
    if (strncmp(resp, "OK ", 3) != 0) fprintf(stderr, "    got: %s\n", resp);
    for (int i = 0; i < 100 && g_hups == 0; i++) {
        struct timespec ts = { 0, 10 * 1000 * 1000 };
        nanosleep(&ts, NULL);
    }
    CHECK(g_hups == 1, "release: the topology hook woke the SIGHUP watcher once");
    const char *vf = getenv("MARCH_TOPOLOGY_VERIFIED_FILE");
    struct stat st;
    CHECK(vf && stat(vf, &st) == 0, "release: MARCH_TOPOLOGY_VERIFIED_FILE names the verified copy");
    close(fd);
}

static void ph_release_after_restart(void) {
    restore_boot("yet-another-build");   /* the stack is set aside; the head is not */
    int fd = connect_sock(SOCK_PATH);
    CHECK(fd >= 0, "after restart: connected");
    if (fd < 0) return;
    char resp[256], want[96], d[65];
    head_of(fd, resp, sizeof(resp));
    snprintf(want, sizeof(want), "HEAD 3 %s", REL_A);
    CHECK(strcmp(resp, want) == 0, "after restart: the release head survived");
    topo_digest(TOPO_BODY, d);
    push_topology(fd, TOPO_BODY, d, d, resp, sizeof(resp));
    CHECK(strcmp(resp, "ERR release_required") == 0,
          "after restart: an unwrapped replay is still refused");
    push_topology_seq(fd, 2, REL_A, TOPO_BODY, resp, sizeof(resp));
    CHECK(strcmp(resp, "ERR stale_release head:3") == 0,
          "after restart: an older release is still refused");
    close(fd);
}

/* ── Artifact digests across restarts (review 2026-10-04, dd12 P1) ────────
 * The release head (3, REL_A) is held from phase 10 on. */

/* What an older runtime left behind: a persisted ACTIVATE5 entry (no signed
 * digest of the bytes) for this binary, its artifact (the stub) in the CAS. */
static int write_old_format_state(void) {
    char key[65], base[65], dir[512], path[600];
    march_blake3_hex((const unsigned char *)SOCK_PATH, strlen(SOCK_PATH), key);
    static const char slots[] = "test_fn_epoch baseline\n";
    march_blake3_hex((const unsigned char *)slots, strlen(slots), base);
    snprintf(dir, sizeof(dir), "%s/.march/cas/hcr_state/%.16s", g_restore_home, key);
    snprintf(path, sizeof(path), "%s/state", dir);
    char root[65], msg[1024], sig[128];
    expected_cap_root(NULL, 0, root);
    snprintf(msg, sizeof(msg), "ACTIVATE5 test_fn_epoch %s %s 0 epoch:0 cap_root:%s callers:",
             HOT_IMPL, STUB_CAS, root);
    sign_b64(msg, sig);
    FILE *f = fopen(path, "w");
    if (!f) return 0;
    fprintf(f, "# march-hcr-state v1\nbase %s\ntopology - -\nmanifest %s\nseq 1\nentry 1 2 - %s %s\n",
            base, base, sig, msg);
    return fclose(f) == 0;
}

static void ph_old_entry_not_replayed(void) {
    restore_boot("baseline");
    phase_restored(0, "replayed", 1);
}

/* An ACTIVATE7 deploy, in the held release. */
static void ph_digest_activate(void) {
    restore_boot("baseline");
    int fd = connect_sock(SOCK_PATH);
    CHECK(fd >= 0, "digest phase: connected");
    if (fd < 0) return;
    char resp[512], good[65], inner[4096], line[8192];
    file_digest("hcr_stub.so", good);
    put_file(fd, ART_CAS, "hcr_stub.so", good, resp, sizeof(resp));
    CHECK(strncmp(resp, "OK ", 3) == 0, "digest phase: the signed bytes uploaded");
    activate7_line("test_fn_epoch", ART_CAS, good, good, inner, sizeof(inner));
    seq_wrap(4, 4, REL_A, inner, line, sizeof(line));
    send_line(fd, line);
    read_resp(fd, resp, sizeof(resp));
    CHECK(strncmp(resp, "OK ", 3) == 0, "digest phase: a wrapped ACTIVATE7 activates");
    if (strncmp(resp, "OK ", 3) != 0) fprintf(stderr, "    got: %s\n", resp);
    CHECK(call_current("test_fn_epoch") == 42, "digest phase: the operator's code is live");
    close(fd);
}

static void ph_digest_replayed(void) {
    restore_boot("baseline");
    phase_restored(1, "replayed", 0);
    CHECK(call_current("test_fn_epoch") == 42, "digest restart: the replayed code is the operator's");
}

static void ph_digest_substituted(void) {
    restore_boot("baseline");
    phase_restored(0, "replayed", 1);
    CHECK(call_current("test_fn_epoch") == 0, "substituted restart: the node is on its base build");
}

/* Replace the artifact's bytes in the CAS, as CAS_PUT would. */
static int substitute_artifact(void) {
    char cmd[640];
    snprintf(cmd, sizeof(cmd), "cp hcr_evil.so %s/.march/cas/artifacts/%.2s/%.62s",
             g_restore_home, ART_CAS, ART_CAS + 2);
    return system(cmd) == 0;
}

static int restore_audit_has(const char *result) {
    char r[96], line[4096];
    snprintf(r, sizeof(r), "\"result\":\"%s\"", result);
    int found = 0;
    FILE *f = fopen(g_audit_path, "r");
    while (f && fgets(line, sizeof(line), f))
        if (strstr(line, "\"type\":\"restore\"") && strstr(line, r)) found = 1;
    if (f) fclose(f);
    return found;
}

/* Flip one character of the first entry's signature in the state file. */
static int corrupt_state_signature(void) {
    char cmd[512];
    snprintf(cmd, sizeof(cmd),
             "f=$(ls %s/.march/cas/hcr_state/*/state) && "
             "awk '/^entry /{ s=$5; c=substr(s,1,1); $5=(c==\"A\"?\"B\":\"A\") substr(s,2) } {print}' "
             "\"$f\" > \"$f.x\" && mv \"$f.x\" \"$f\"", g_restore_home);
    return system(cmd) == 0;
}

static int state_has_entries(void) {
    char cmd[512];
    snprintf(cmd, sizeof(cmd), "grep -q '^entry ' %s/.march/cas/hcr_state/*/state 2>/dev/null",
             g_restore_home);
    return system(cmd) == 0;
}

static void test_restart_durability(void) {
    CHECK(run_phase(phase_activate) == 0, "phase 1: activate a patch, then exit");
    CHECK(state_has_entries(), "the patch stack is persisted under the CAS root");
    CHECK(run_phase(ph_restored_hot) == 0, "phase 2: a restart replays it");
    CHECK(run_phase(ph_no_replay) == 0, "phase 3: MARCH_HCR_NO_REPLAY starts from the base");
    CHECK(run_phase(ph_after_no_replay) == 0, "phase 4: and the stack stays set aside");
    CHECK(run_phase(phase_activate) == 0, "phase 5: activate again");
    CHECK(corrupt_state_signature(), "phase 6: corrupt the stored signature");
    CHECK(run_phase(ph_corrupt_skipped) == 0, "phase 6: the corrupt entry is skipped, no crash");
    {
        int found = 0;
        FILE *f = fopen(g_audit_path, "r");
        char line[4096];
        while (f && fgets(line, sizeof(line), f))
            if (strstr(line, "\"type\":\"restore\"") && strstr(line, "\"result\":\"err_restore_sig\""))
                found = 1;
        if (f) fclose(f);
        CHECK(found, "phase 6: the skipped entry has an audit line");
    }
    CHECK(run_phase(phase_activate) == 0, "phase 7: activate again");
    CHECK(run_phase(ph_base_changed) == 0, "phase 8: another build on the socket does not replay it");
    CHECK(run_phase(ph_require_release) == 0, "phase 9: MARCH_HCR_REQUIRE_RELEASE refuses unwrapped lines");
    CHECK(run_phase(ph_release_push) == 0, "phase 10: a release, with the topology hook signalling");
    CHECK(run_phase(ph_release_after_restart) == 0,
          "phase 11: after a restart onto another build the head still refuses replays");
    /* Review 2026-10-04 (dd12 P1): the bytes, across restarts. */
    CHECK(write_old_format_state(), "phase 12: an older runtime's ACTIVATE5 entry is on disk");
    CHECK(run_phase(ph_old_entry_not_replayed) == 0,
          "phase 12: with a release held, an entry with no signed digest is not replayed");
    CHECK(restore_audit_has("err_restore_no_digest"), "phase 12: and the skip is audited");
    CHECK(run_phase(ph_digest_activate) == 0, "phase 13: an ACTIVATE7 deploy in the release");
    CHECK(run_phase(ph_digest_replayed) == 0, "phase 14: a restart replays it, bytes re-verified");
    unlink(g_marker);
    CHECK(substitute_artifact(), "phase 15: the artifact's bytes replaced in the CAS");
    CHECK(run_phase(ph_digest_substituted) == 0,
          "phase 15: a restart does not replay substituted bytes");
    CHECK(restore_audit_has("err_restore_digest"), "phase 15: and the skip is audited");
    CHECK(!marker_exists(), "phase 15: the substituted artifact's code never ran");
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s <keys_file> [policy|policy-all|restore]\n", argv[0]);
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
    snprintf(g_marker, sizeof(g_marker), "/tmp/march_reload_evil_%d.marker", (int)getpid());
    unlink(g_marker);
    setenv("MARCH_TEST_EVIL_MARKER", g_marker, 1);

    /* A private CAS (march_reload_server_start roots it at $HOME/.march/cas):
     * the epoch-model case uploads a real artifact. */
    char home[96];
    snprintf(home, sizeof(home), "/tmp/march_reload_home_%d", (int)getpid());
    mkdir(home, 0700);
    setenv("HOME", home, 1);
    if (argc >= 3 && strcmp(argv[2], "restore") == 0) {
        /* Nothing is started in this process: every server lifetime is a
         * forked child (see test_restart_durability). */
        g_restore_home = home;
        test_restart_durability();
        unlink(g_audit_path);
        unlink(g_marker);
        if (g_failed == 0) {
            printf("test_reload_activate4_restore: all checks passed\n");
            return 0;
        }
        fprintf(stderr, "test_reload_activate4_restore: %d check(s) failed\n", g_failed);
        return 1;
    }

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
    march_dispatch_register_name(11, "test_fn_role");
    march_dispatch_register_name(12, "test_fn_digest");
    march_dispatch_publish(10, (void *)0x1010, "baseline", NULL, MARCH_NATIVE);
    march_dispatch_publish(12, (void *)0x1010, "baseline", NULL, MARCH_NATIVE);
    /* Review 2026-10-04 (dd12 P3): the socket is owner-only whatever the
     * umask the node inherited.  Started under umask 0, it would otherwise
     * be 0777: any local user could connect. */
    mode_t old_umask = umask(0);
    march_reload_server_start(sock_path);
    test_hcr_info();   /* connects: the server is listening */
    umask(old_umask);
    {
        struct stat st;
        CHECK(stat(sock_path, &st) == 0 && (st.st_mode & 0777) == 0600,
              "the reload socket is 0600 even under umask 0");
        if (stat(sock_path, &st) == 0 && (st.st_mode & 0777) != 0600)
            fprintf(stderr, "    mode: %o\n", (unsigned)(st.st_mode & 0777));
    }

    /* policy: test_reload_policy.txt, which names the roles the node serves
     * (`serves`, as forge host init writes it); policy-all: the same caps
     * with no `serves` line (every role bounded). */
    int policy_all = (argc >= 3 && strcmp(argv[2], "policy-all") == 0);
    int policy_mode = policy_all || (argc >= 3 && strcmp(argv[2], "policy") == 0);

    if (!policy_mode) {
        test_tamper_check_matching_root_admits();
        test_tamper_check_mutated_caps_rejected();
        test_no_policy_is_permissive();
        test_empty_caps_bogus_root_rejected();
        test_empty_caps_real_empty_root_admitted();
        test_activate3_regression();
        test_batch_audit_carries_caps();
        test_epoch_model_wait_pins_drain();
        test_activate6_role_closures();
        test_topology_push();
        {
            int fd = connect_sock(SOCK_PATH);
            char resp[256];
            send_line(fd, "COMPACT");
            read_resp(fd, resp, sizeof(resp));
            /* The epoch-model case activated test_fn_epoch three times (two
             * single deploys and one batch) and ACTIVATE6 once more. */
            static const char want[] =
                "STACK entries:4 functions:1 deploys:4 artifacts:1 cas_bytes:";
            CHECK(strncmp(resp, want, sizeof(want) - 1) == 0,
                  "COMPACT counts every persisted activation");
            if (strncmp(resp, want, sizeof(want) - 1) != 0) fprintf(stderr, "    got: %s\n", resp);
            close(fd);
        }
        test_artifact_digest();
        test_in_process_request();
        test_sequenced_releases();   /* it makes the server require releases */
        test_unbound_activate_after_release();
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
        test_activate6_role_policy();
        test_policy_ignores_proof_caps();
        test_policy_served_roles(!policy_all);
        /* Capless, so within every policy: the policy gate never stands in
         * for the bytes check. */
        test_artifact_digest();
    }

    unlink(sock_path);
    unlink(g_audit_path);
    unlink(g_marker);
    if (g_failed == 0) {
        printf("test_reload_activate4%s: all checks passed\n",
               policy_all ? "_policy_all" : policy_mode ? "_policy" : "");
        return 0;
    }
    fprintf(stderr, "test_reload_activate4%s: %d check(s) failed\n",
            policy_all ? "_policy_all" : policy_mode ? "_policy" : "", g_failed);
    return 1;
}
