/* march_observe.h — the node observe socket (R0 of
 * specs/plans/2026-09-28-observe-recon-shell-plan.md).
 *
 * A read-only control socket, SEPARATE from the hot-reload server
 * (march_reload.c serves one client at a time on one thread, so an observer
 * held open there would block a deploy).  It is started from
 * march_run_scheduler when MARCH_OBSERVE_SOCKET is set, or, when only
 * MARCH_HOT_RELOAD_SOCKET is set, at "<reload socket>.observe".
 *
 * Protocol: the client sends ONE line (a verb and its arguments), the server
 * answers ONE line of JSON and closes.  Every answer is an envelope:
 *
 *   {"proto":"march.observe/1","node":"…","at_ms":…,"took_us":…,
 *    "truncated":false,"data":…}
 *
 * or, on failure, the same envelope with "error":"<code>" in place of data.
 *
 * This file also declares the small JSON writer the verbs build their data
 * with (march_jw_*). */
#ifndef MARCH_OBSERVE_H
#define MARCH_OBSERVE_H

#include <stddef.h>
#include <stdint.h>

/* ── JSON writer ──────────────────────────────────────────────────────────
 * A growable buffer with a hard size limit.  Commas are inserted for you:
 * call jw_key before each object member's value, nothing between array
 * elements.  Once a write would pass [limit] bytes, the writer stops writing
 * and sets [truncated]; the partial buffer is then NOT valid JSON, and the
 * server replaces it with null and reports "truncated":true. */
#define MARCH_JW_MAX_DEPTH 32

typedef struct march_jw {
    char   *buf;
    size_t  len;
    size_t  cap;
    size_t  limit;
    int     truncated;
    int     oom;
    int     depth;
    int     after_key;
    unsigned char first[MARCH_JW_MAX_DEPTH + 1];
} march_jw;

void march_jw_init(march_jw *w, size_t limit);
void march_jw_free(march_jw *w);
/* The NUL-terminated text written so far ("" if nothing). */
const char *march_jw_text(const march_jw *w);
/* True iff the text is complete and usable: not truncated, no allocation
 * failure, and every object/array closed. */
int march_jw_ok(const march_jw *w);

void march_jw_obj_begin(march_jw *w);
void march_jw_obj_end(march_jw *w);
void march_jw_arr_begin(march_jw *w);
void march_jw_arr_end(march_jw *w);
void march_jw_key(march_jw *w, const char *key);
void march_jw_str(march_jw *w, const char *s);
void march_jw_strn(march_jw *w, const char *s, size_t n);
void march_jw_i64(march_jw *w, int64_t v);
void march_jw_u64(march_jw *w, uint64_t v);
void march_jw_f64(march_jw *w, double v);   /* non-finite -> null */
void march_jw_bool(march_jw *w, int v);
void march_jw_null(march_jw *w);

/* ── Server ───────────────────────────────────────────────────────────── */

/* Start the server once, from the environment (see the file comment).  A
 * no-op when neither variable is set or on any later call.  Called from
 * march_run_scheduler on the main OS thread, before any green thread runs. */
void march_observe_maybe_start(void);

/* Start the server on [path].  Returns 0 on success, -1 on failure (bad or
 * too-long path, an existing non-socket file at [path], socket errors); the
 * reason is printed to stderr.  Never removes a file that is not a socket. */
int march_observe_server_start(const char *path);

/* Connections currently being served (for tests). */
int march_observe_active_conns(void);

/* Most connections served at once; a further client gets "error":"busy". */
#define MARCH_OBSERVE_MAX_CONNS 8
/* Longest request line accepted, including arguments. */
#define MARCH_OBSERVE_LINE_MAX 4096

#endif /* MARCH_OBSERVE_H */
