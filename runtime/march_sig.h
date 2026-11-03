#ifndef MARCH_SIG_H
#define MARCH_SIG_H
/* march_sig — the deploy key's signature check, request freshness (nonces
 * and expiry), the debug-verb policy, and the audit log, shared by the
 * hot-reload server (march_reload.c) and the observe socket's signed debug
 * verbs (march_observe_debug.c).  R4 of
 * specs/plans/2026-09-28-observe-recon-shell-plan.md.
 *
 * The public key is compiled in: the driver passes
 * -DMARCH_SIGNING_PUBKEY_HEX on the one command line that compiles every
 * runtime source of a `--hot-reload --signing-pubkey` build.  Without it
 * (or with an all-zero key) nothing verifies. */
#include <stdint.h>
#include <stdio.h>

/* Parse the compiled-in key (idempotent; every function below calls it). */
void march_sig_load_key(void);
/* 1 iff a usable (well-formed, non-zero) key is compiled in. */
int  march_sig_key_loaded(void);
/* The 32 key bytes (all zero without a key). */
const unsigned char *march_sig_pubkey(void);
/* The key as 64 lowercase hex chars, or "" without a key. */
void march_sig_pubkey_hex(char out[65]);

/* This process's boot id: 32 lowercase hex chars from the OS entropy source,
 * drawn once.  A signed observe request names it (`boot:`), so a captured
 * request is useless against a restarted process or another node. */
const char *march_sig_boot_id(void);

/* 1 iff [sig_b64] (base64, standard or URL-safe, padding optional) is a valid
 * ed25519 signature over [msg] by the compiled-in key. */
int  march_sig_verify(const char *msg, const char *sig_b64);

/* Longest a signed request may stay valid: not_after_ms beyond now plus this
 * is refused, so the nonce ring only has to remember this long. */
#define MARCH_SIG_MAX_WINDOW_MS 60000
/* Nonces remembered per process; a request is refused rather than evict a
 * nonce that has not expired yet, so a replay is never possible. */
#define MARCH_SIG_NONCE_RING 256
/* Longest nonce accepted (hex digits). */
#define MARCH_SIG_NONCE_MAX 64

/* Admit a request's nonce and expiry at wall-clock [now_ms].  NULL when
 * admitted (the nonce is then remembered), else the error code: "expired"
 * (not_after_ms already passed), "not_after_too_far" (more than
 * MARCH_SIG_MAX_WINDOW_MS ahead), "bad_nonce" (not 16-64 hex digits),
 * "replay" (seen before), "nonce_ring_full" (MARCH_SIG_NONCE_RING unexpired
 * nonces already held). */
const char *march_sig_admit(const char *nonce, int64_t not_after_ms, int64_t now_ms);

/* 1 iff $MARCH_DEBUG_POLICY names a readable file listing [verb] on a line
 * of its own ('#' starts a comment).  No file: nothing is allowed.  Read on
 * every call, so an operator's edit applies to the next request. */
int  march_sig_debug_allowed(const char *verb);

/* Open the audit log for appending: $MARCH_AUDIT_LOG, else
 * ${XDG_DATA_HOME:-$HOME/.local/share}/march/audit.jsonl (its directory is
 * created).  NULL when there is no path or it cannot be opened.  Pair with
 * march_audit_close, which writes the line out under a process-wide lock. */
FILE *march_audit_open(void);
void  march_audit_close(FILE *f);

/* The node's CAS root: $HOME/.march/cas, or /tmp/.march_cas without $HOME.
 * The reload server stores uploads under it; the observe socket's SOURCE
 * verb (R10) reads function source text from <root>/sources/. */
const char *march_cas_root(void);

/* The largest source text a node stores or serves for one function. */
#define MARCH_SOURCE_MAX_BYTES 262144

/* Write "<root>/sources/<2 hex>/<62 hex>" for the 64-lowercase-hex [hash]
 * into [out]; 0 (and [out] untouched) when [hash] is not exactly that, or
 * [outsz] is too small. */
int march_source_path(char *out, size_t outsz, const char *hash);

#endif /* MARCH_SIG_H */
