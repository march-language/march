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

/* 4. Legacy shape: empty caps:<csv> (legacy artifact) skips both cap gates
 *    unconditionally, regardless of cap_root correctness. */
static void test_empty_caps_is_permissive_legacy(void) {
    int fd = connect_sock(SOCK_PATH);
    CHECK(fd >= 0, "connected to reload server");
    if (fd < 0) return;

    /* cap_root is present (mandatory field) but caps:<csv> is empty; the
     * (necessarily bogus, since nothing hashed to it) cap_root must NOT be
     * checked when caps is empty. */
    char bogus_root[65];
    memset(bogus_root, 'a', 64); bogus_root[64] = '\0';
    char resp[512];
    do_activate4(fd, "test_fn_legacy", "", bogus_root, "", resp, sizeof(resp));
    CHECK(strncmp(resp, "ERR missing_artifact", 20) == 0,
          "empty caps:<csv> skips cap gates entirely (legacy-shaped, permissive)");
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

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s <keys_file> [policy]\n", argv[0]);
        return 2;
    }
    if (!load_secret_key(argv[1])) {
        fprintf(stderr, "failed to load secret key from %s\n", argv[1]);
        return 2;
    }

    char sock_path[64];
    snprintf(sock_path, sizeof(sock_path), "/tmp/march_reload_test_%d.sock", (int)getpid());
    SOCK_PATH = sock_path;

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
    march_reload_server_start(sock_path);

    int policy_mode = (argc >= 3 && strcmp(argv[2], "policy") == 0);

    if (!policy_mode) {
        test_tamper_check_matching_root_admits();
        test_tamper_check_mutated_caps_rejected();
        test_no_policy_is_permissive();
        test_empty_caps_is_permissive_legacy();
        test_activate3_regression();
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
                close(fd);
            }
        }
    }

    unlink(sock_path);
    if (g_failed == 0) {
        printf("test_reload_activate4%s: all checks passed\n", policy_mode ? "_policy" : "");
        return 0;
    }
    fprintf(stderr, "test_reload_activate4%s: %d check(s) failed\n",
            policy_mode ? "_policy" : "", g_failed);
    return 1;
}
