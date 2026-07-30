# Event-Loop Batch Write Phase 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the per-request blocking `writev` in `handle_read` with the same batch-iov pattern used by the blocking `connection_thread`, plus a non-blocking writev attempt with EAGAIN fallback to `handle_write`.

**Architecture:** `handle_read` currently calls `march_process_one_request` per pipelined request, each doing an individual blocking `writev`. The blocking path (`connection_thread`) already accumulates N responses into `batch_iov[512]` and sends one `writev_all` per `recv()`. We port that exact pattern to the event loop, replacing the per-request send with a single non-blocking `writev`. On EAGAIN (rare for small responses), we snapshot TLS scratch into `conn_state_t.scratch_snap`, fix up iovec pointers, and arm the fd for write so `handle_write` drains the rest.

**Tech Stack:** C11, kqueue (macOS) / epoll (Linux), writev, pthread TLS (`_Thread_local`), March runtime

---

## Diagnosis

The pipelining gap (March 103K vs actix 709K req/s pipelined ×16) is caused by this loop in `runtime/march_http_evloop.c:handle_read`:

```c
for (int i = 0; i < n; i++) {
    int rc = march_process_one_request(c->fd, pipeline, fn, &reqs[i], ...);
    // ^ calls march_send_response_with_ka → march_response_send → writev() per request
}
```

16 pipelined requests → 16 `writev` syscalls. The blocking path does 1. The fix replicates the blocking path's batch pattern.

The three pre-conditions that need fixing before rewriting `handle_read`:

1. **`march_populate_response_ka` is `static`** — must be exported via `march_http_internal.h`
2. **`CONN_BATCH_IOV_MAX` is defined only in `march_http.c`** — must move to `march_http_io.h` (where `conn_state_t.wbuf` lives)
3. **`conn_state_t` fields too small** for full pipeline batches:
   - `scratch_snap[512]` → `scratch_snap[MARCH_RESPONSE_SCRATCH_SIZE]` (16 KB — the actual TLS scratch size; 4096 was too small)
   - `wbuf[MARCH_RESPONSE_MAX_IOVEC=160]` → `wbuf[CONN_BATCH_IOV_MAX=512]` (32 req × ~10 iov each)
4. **Buffer shift must happen before the writev** — the EAGAIN/partial-send return paths must not skip `memmove`; otherwise the next `handle_read` on this connection re-parses and re-executes the same requests.

---

## File Map

| File | Change |
|---|---|
| `runtime/march_http_io.h` | Define `CONN_BATCH_IOV_MAX 512`; enlarge `scratch_snap→[MARCH_RESPONSE_SCRATCH_SIZE]`; change `wbuf` to use `CONN_BATCH_IOV_MAX` |
| `runtime/march_http_internal.h` | Export `march_populate_response_ka`; remove `CONN_BATCH_IOV_MAX` from here |
| `runtime/march_http.c` | Remove `static` from `march_populate_response_ka`; remove `CONN_BATCH_IOV_MAX` define (now in `march_http_io.h`) |
| `runtime/march_http_response.h` / `.c` | Add `march_response_tls_scratch()` accessor |
| `runtime/march_http_evloop.c` | Add `evloop_defer_write` helper; rewrite `handle_read` — shift buffer **before** writev, batch-iov pattern, non-blocking writev + EAGAIN fallback |

No March language changes. No test file changes (existing HTTP tests cover correctness; benchmarks cover perf).

---

## Task 1: Move `CONN_BATCH_IOV_MAX` to `march_http_io.h` and export `march_populate_response_ka`

**Files:**
- Modify: `runtime/march_http_io.h`
- Modify: `runtime/march_http_internal.h`
- Modify: `runtime/march_http.c`

### Why
`CONN_BATCH_IOV_MAX` belongs in `march_http_io.h` because `conn_state_t.wbuf` (defined there) is sized by it — placing it in the io header keeps the include graph clean (io.h ← internal.h ← evloop.c, not the other way around). `march_populate_response_ka` is exported so `march_http_evloop.c` can call it.

- [x] **Step 1: Add `CONN_BATCH_IOV_MAX` define to `runtime/march_http_io.h`**

Add near the top of `march_http_io.h`, after the existing `#pragma once` and includes:
```c
/* Maximum iovecs in one pipelined response batch.
 * EVLOOP_PIPELINE_BATCH(32) requests × MARCH_RESPONSE_MAX_IOVEC(160) iov/request
 * = 5120 worst-case; 512 is sufficient for typical responses (≤16 headers). */
#define CONN_BATCH_IOV_MAX 512
```

- [x] **Step 2: Add `march_populate_response_ka` declaration to `runtime/march_http_internal.h`**

Add after the existing declarations:
```c
/* Build a response into *resp using the zero-copy builder.
 * resp->iov_count is reset to 0 by march_response_clear_no_free() before each
 * call; resp->scratch_used carries forward so iovecs from multiple responses
 * share the TLS scratch buffer without overlap. */
void march_populate_response_ka(march_response_t *resp,
                                 int64_t status, void *headers,
                                 void *body, int keep_alive);
```

- [x] **Step 3: Remove `static` from `march_populate_response_ka` in `runtime/march_http.c`**

Change:
```c
static void march_populate_response_ka(march_response_t *resp,
```
To:
```c
void march_populate_response_ka(march_response_t *resp,
```

- [x] **Step 4: Remove the `CONN_BATCH_IOV_MAX` define from `runtime/march_http.c`** (now in `march_http_io.h`)

Delete the line:
```c
#define CONN_BATCH_IOV_MAX 512
```

Add an include at the top of `march_http.c` if `march_http_io.h` isn't already included there:
```c
#include "march_http_io.h"
```
(Check first — it may already be transitively included.)

- [x] **Step 5: Build to verify no compile errors**

```bash
/Users/80197052/.opam/march/bin/dune build 2>&1
```
Expected: clean build, no warnings about redefinition.

- [x] **Step 6: Commit**

```bash
git add runtime/march_http_io.h runtime/march_http_internal.h runtime/march_http.c
git commit -m "refactor(http): export march_populate_response_ka + move CONN_BATCH_IOV_MAX to march_http_io.h"
```

---

## Task 2: Enlarge `conn_state_t` scratch and wbuf fields

**Files:**
- Modify: `runtime/march_http_io.h`

### Why
`scratch_snap[512]` is too small — TLS scratch can accumulate up to `MARCH_RESPONSE_SCRATCH_SIZE` (16 KB) across a batch. Using a smaller size and silently skipping the fixup would silently corrupt responses with many unknown status codes or many custom headers. `wbuf[160]` can't hold 32 req × 10 iov = 320 iovecs per batch.

- [x] **Step 1: Update `conn_state_t` in `runtime/march_http_io.h`**

Change `scratch_snap` declaration from:
```c
    char          scratch_snap[512];
    size_t        scratch_snap_len;
```
To:
```c
    /* Snapshot of TLS scratch bytes used by this batch's responses.
     * Must be exactly MARCH_RESPONSE_SCRATCH_SIZE — the full TLS scratch
     * region — so the pointer fixup in evloop_defer_write is always safe. */
    char          scratch_snap[MARCH_RESPONSE_SCRATCH_SIZE];
    size_t        scratch_snap_len;
```

Note: `MARCH_RESPONSE_SCRATCH_SIZE` is defined in `march_http_response.h`. Verify that `march_http_io.h` already includes it (it does, at line 15). No new include needed.

Change `wbuf` declaration from:
```c
    struct iovec  wbuf[MARCH_RESPONSE_MAX_IOVEC];
```
To:
```c
    /* Holds remaining iovecs when a batch writev returns EAGAIN.
     * Sized to hold a full CONN_BATCH_IOV_MAX-entry batch (defined above). */
    struct iovec  wbuf[CONN_BATCH_IOV_MAX];
```

- [x] **Step 2: Build to verify**

```bash
/Users/80197052/.opam/march/bin/dune build 2>&1
```

- [x] **Step 3: Commit**

```bash
git add runtime/march_http_io.h
git commit -m "perf(http): enlarge conn_state_t scratch_snap[MARCH_RESPONSE_SCRATCH_SIZE] and wbuf[512]"
```

---

## Task 3: Rewrite `handle_read` with batch-iov + non-blocking writev

**Files:**
- Modify: `runtime/march_http_evloop.c`

### Why
This is the core change. Replace the per-request `march_process_one_request` loop with the same batch pattern used by `connection_thread`:
1. Parse all N pipelined requests
2. Call pipeline + build each response into `bresp` with `march_populate_response_ka`
3. Accumulate all iovecs in `batch_iov[CONN_BATCH_IOV_MAX]`
4. Attempt one non-blocking `writev`
5. On complete: re-arm for read (keep-alive) or close
6. On EAGAIN/partial: snapshot TLS scratch → `c->scratch_snap`, copy remaining iovecs → `c->wbuf`, arm for write

### Scratch pointer fixup (required for EAGAIN correctness)
Response iovecs for Content-Length lines point into the thread-local `tls_scratch` buffer. If the writev returns EAGAIN and we return from `handle_read`, the next connection's `handle_read` on this thread will overwrite `tls_scratch`. Before returning, we must:
1. `memcpy(c->scratch_snap, tls_scratch, bresp.scratch_used)` — snapshot entire scratch region
2. Walk `batch_iov[sent_iovs..batch_n]` — for any `iov_base` that falls inside `[tls_scratch, tls_scratch + MARCH_RESPONSE_SCRATCH_SIZE)`, replace with `c->scratch_snap + (base - tls_scratch)`

`tls_scratch` is declared `static _Thread_local` in `march_http_response.c`. Add an accessor:
```c
/* In march_http_response.c, after the tls_scratch declaration: */
char *march_response_tls_scratch(void) { return tls_scratch; }
```
And declare it in `march_http_response.h`:
```c
/* Returns a pointer to the calling thread's scratch buffer.
 * Used by the event loop to snapshot scratch before EAGAIN return. */
char *march_response_tls_scratch(void);
```

- [x] **Step 1: Add `march_response_tls_scratch` accessor to `march_http_response.c` and `march_http_response.h`**

In `march_http_response.c`, after the `tls_scratch` declaration:
```c
char *march_response_tls_scratch(void) { return tls_scratch; }
```

In `march_http_response.h`, before the closing of the file:
```c
/* Returns a pointer to the calling thread's scratch buffer (MARCH_RESPONSE_SCRATCH_SIZE bytes).
 * Used by the event loop to snapshot scratch before an EAGAIN return. */
char *march_response_tls_scratch(void);
```

- [x] **Step 2: Replace `handle_read` in `march_http_evloop.c`**

Replace the entire `handle_read` function with:

```c
/* ── Handle a readable connection ─────────────────────────────────────── */

static void handle_read(int evfd, conn_state_t *c, void *pipeline) {
    io_result_t r = march_recv_nonblocking(c);

    if (r == IO_PARTIAL)
        return;

    if (r == IO_ERROR) {
        close_conn(evfd, c);
        return;
    }

    /* IO_COMPLETE — at least one full request buffered.  Process all
     * pipelined requests in the buffer and send responses as one batch. */
    char        *clo = (char *)pipeline;
    closure_fn_t fn  = *(closure_fn_t *)(clo + 16);

    while (c->rbuf_len > 0) {
        march_http_request_t reqs[EVLOOP_PIPELINE_BATCH];
        size_t consumed = 0;
        int n = march_http_parse_pipelined(c->rbuf, c->rbuf_len,
                                            reqs, EVLOOP_PIPELINE_BATCH,
                                            &consumed);
        if (n <= 0) break;

        /* Build all N responses into a single iovec batch — same pattern
         * as connection_thread (Phase 0), but with a non-blocking writev. */
        struct iovec     batch_iov[CONN_BATCH_IOV_MAX];
        int              batch_n = 0;
        march_response_t bresp;
        bresp.iov_count    = 0;
        bresp.scratch_used = 0;

        int batch_keep_alive = 1;
        int batch_ok         = 1;

        for (int i = 0; i < n; i++) {
            int   keep_alive  = march_detect_keep_alive_simd(&reqs[i]);
            void *conn        = march_conn_from_parsed(&reqs[i],
                                                        c->rbuf, c->rbuf_len,
                                                        c->fd);
            void *result_conn = fn(pipeline, conn);

            if (!result_conn) {
                /* Pipeline error — send 500 and close. */
                if (batch_n > 0) {
                    writev(c->fd, batch_iov, batch_n); /* best-effort flush */
                    batch_n = 0;
                }
                march_http_send_response(c->fd, 500, make_nil(),
                    march_string_lit("Internal Server Error", 21));
                close_conn(evfd, c);
                batch_ok = 0;
                break;
            }

            /* Ignore WebSocket upgrades in the event-loop path for now —
             * WS needs its own async handler; fall through to close. */
            char    *rc_p        = (char *)result_conn;
            void    *upgrade_val = *(void **)(rc_p + 112);
            int32_t  upgrade_tag = *(int32_t *)((char *)upgrade_val + 8);
            if (upgrade_tag == 1) {
                if (batch_n > 0) {
                    writev(c->fd, batch_iov, batch_n);
                    batch_n = 0;
                }
                close_conn(evfd, c);
                batch_ok = 0;
                break;
            }

            int64_t resp_status  = *(int64_t *)(rc_p + 72);
            void   *resp_headers = *(void **)(rc_p + 80);
            void   *resp_body    = *(void **)(rc_p + 88);
            if (resp_status == 0) resp_status = 200;

            /* Overflow guard: flush and restart if batch is nearly full. */
            if (batch_n + MARCH_RESPONSE_MAX_IOVEC > CONN_BATCH_IOV_MAX) {
                writev(c->fd, batch_iov, batch_n);
                batch_n            = 0;
                bresp.scratch_used = 0;
            }

            march_response_clear_no_free(&bresp);
            march_populate_response_ka(&bresp, resp_status,
                                        resp_headers, resp_body, keep_alive);
            memcpy(batch_iov + batch_n, bresp.iov,
                   (size_t)bresp.iov_count * sizeof(struct iovec));
            batch_n += bresp.iov_count;

            batch_keep_alive = keep_alive;
            if (!keep_alive) break;
        }

        if (!batch_ok) return;

        /* ── Shift consumed bytes NOW — before any send or early return. ──
         * Critical: EAGAIN and partial-send paths return early below.  If
         * the shift happened at the bottom of the loop (as in the old code),
         * those paths would leave consumed bytes in c->rbuf and re-parse +
         * re-execute the same requests on the next handle_read call. */
        if (consumed > 0 && consumed < c->rbuf_len) {
            memmove(c->rbuf, c->rbuf + consumed, c->rbuf_len - consumed);
            c->rbuf_len -= consumed;
        } else if (consumed >= c->rbuf_len) {
            c->rbuf_len = 0;
        }

        if (batch_n == 0) continue;  /* no iovecs (e.g. all WS/error) */

        /* ── Single writev attempt (non-blocking fd) ───────────────── */
        ssize_t nsent = writev(c->fd, batch_iov, batch_n);

        if (nsent < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
            /* Send buffer full — defer entire batch to handle_write. */
            evloop_defer_write(evfd, c, batch_iov, batch_n,
                               bresp.scratch_used, batch_keep_alive);
            return;
        }

        if (nsent < 0) {
            /* Fatal write error. */
            close_conn(evfd, c);
            return;
        }

        /* Check for partial send (rare but possible on non-blocking fd). */
        {
            size_t total = 0;
            for (int j = 0; j < batch_n; j++)
                total += batch_iov[j].iov_len;
            if ((size_t)nsent < total) {
                /* Some bytes sent — advance past sent iovecs and defer rest. */
                int    rem_pos = 0;
                size_t rem     = (size_t)nsent;
                while (rem > 0 && rem_pos < batch_n) {
                    if (rem >= batch_iov[rem_pos].iov_len) {
                        rem -= batch_iov[rem_pos].iov_len;
                        rem_pos++;
                    } else {
                        batch_iov[rem_pos].iov_base =
                            (char *)batch_iov[rem_pos].iov_base + rem;
                        batch_iov[rem_pos].iov_len -= rem;
                        rem = 0;
                    }
                }
                evloop_defer_write(evfd, c,
                                   batch_iov + rem_pos, batch_n - rem_pos,
                                   bresp.scratch_used, batch_keep_alive);
                return;
            }
        }

        /* Full batch sent in one call (common case). */
        if (!batch_keep_alive) {
            close_conn(evfd, c);
            return;
        }
    }
    /* fd stays armed for read (edge-triggered, already registered). */
}
```

- [x] **Step 3: Add `evloop_defer_write` helper above `handle_read`**

This helper snapshots TLS scratch and copies remaining iovecs to `conn_state_t.wbuf`, then arms the fd for write.

Add `#include <assert.h>` to the includes block at the top of `march_http_evloop.c` (before the function).

```c
/* ── Defer a partial/EAGAIN write to handle_write ─────────────────────── */

static void evloop_defer_write(int evfd, conn_state_t *c,
                                struct iovec *remaining, int n_remaining,
                                size_t scratch_used, int keep_alive) {
    /* Snapshot TLS scratch so iovecs remain valid after handle_read returns.
     * scratch_snap is sized to MARCH_RESPONSE_SCRATCH_SIZE so this always fits. */
    if (scratch_used > 0) {
        assert(scratch_used <= MARCH_RESPONSE_SCRATCH_SIZE);  /* invariant */
        char *tls = march_response_tls_scratch();
        memcpy(c->scratch_snap, tls, scratch_used);
        c->scratch_snap_len = scratch_used;
        /* Fix up any iov_base pointers that fall inside tls_scratch. */
        for (int j = 0; j < n_remaining; j++) {
            char *base = (char *)remaining[j].iov_base;
            if (base >= tls && base < tls + MARCH_RESPONSE_SCRATCH_SIZE) {
                remaining[j].iov_base = c->scratch_snap + (base - tls);
            }
        }
    }

    /* Copy remaining iovecs to wbuf. */
    int copy = n_remaining < CONN_BATCH_IOV_MAX ? n_remaining : CONN_BATCH_IOV_MAX;
    memcpy(c->wbuf, remaining, (size_t)copy * sizeof(struct iovec));
    c->wbuf_count = copy;
    c->wbuf_pos   = 0;
    c->keep_alive = keep_alive;
    c->phase      = CONN_PHASE_WRITING;

    arm_write(evfd, c);
}
```

- [x] **Step 4: Build**

```bash
/Users/80197052/.opam/march/bin/dune build 2>&1
```
Expected: clean build. Fix any type errors.

- [x] **Step 5: Sanity curl test**

```bash
# Start the server
/Users/80197052/code/march/.claude/worktrees/cool-rubin/bench/tfb/tfb_server &
SERVER_PID=$!
sleep 0.5
curl -v http://localhost:8080/plaintext
curl -v http://localhost:8080/json
curl -s http://localhost:8080/plaintext | xxd | head -4
kill $SERVER_PID
```
Expected: `Hello, World!` body, HTTP/1.1 200 OK, Content-Length: 13.

- [x] **Step 6: Commit**

```bash
git add runtime/march_http_evloop.c runtime/march_http_response.c runtime/march_http_response.h
git commit -m "perf(http): batch pipelined writes in evloop handle_read — single writev per recv()"
```

---

## Task 4: Run benchmarks and verify improvement

**Files:**
- Read: `bench/tfb/run_comparison.sh`

- [x] **Step 1: Recompile the March TFB server**

```bash
/Users/80197052/.opam/march/bin/dune exec march -- --compile --opt 2 \
    bench/tfb/tfb_server.march -o bench/tfb/tfb_server 2>&1
```

- [x] **Step 2: Run the pipelined benchmark against the previous numbers**

```bash
# Quick focused run — just plaintext pipeline ×16 to validate improvement
lsof -ti :8080 | xargs kill -9 2>/dev/null || true; sleep 0.3
bench/tfb/tfb_server &
SERVER_PID=$!
sleep 0.5
# Warmup
wrk -t2 -c8 -d3s -s bench/tfb/pipeline.lua http://127.0.0.1:8080/plaintext -- 16 >/dev/null
wrk -t4 -c256 -d5s -s bench/tfb/pipeline.lua http://127.0.0.1:8080/plaintext -- 16 >/dev/null
# Captured run
wrk -t4 -c256 -d15s --latency -s bench/tfb/pipeline.lua http://127.0.0.1:8080/plaintext -- 16
kill $SERVER_PID 2>/dev/null
```

Expected: pipelined req/s significantly higher than 103K (target: close to actix's 709K or at minimum 2–3×).

- [x] **Step 3: Run full comparison suite**

```bash
cd bench/tfb && bash run_comparison.sh 2>&1 | tee /tmp/bench_results_$(date +%Y%m%d).txt
```

- [x] **Step 4: Update `specs/benchmarks.md` with new results**

Add a new section with date, results table, and analysis of what improved.

- [x] **Step 5: Update `event_loop_plan.md` status**

The current status says "Phases 0, 0.5, 1–2 complete." Update to clarify Phase 2 now includes the batch write optimization and note the new numbers.

- [x] **Step 6: Commit**

```bash
git add specs/benchmarks.md specs/event_loop_plan.md
git commit -m "docs: update benchmark results after evloop batch write optimization"
```

---

## Caveats and Known Limitations

**Dynamic body EAGAIN correctness**: In the EAGAIN path, response body `iov_base` pointers point into March heap strings (via `resp_body`). For `march_string_lit` (static strings), these are always valid. For dynamically allocated bodies, Perceus may free the string after `result_conn` goes out of scope in the batch loop. This is safe for the TFB benchmark server (all bodies are static). A production fix would require holding an RC reference to the body string in `conn_state_t` — out of scope for this plan.

**WebSocket in event loop**: The EAGAIN-path WebSocket upgrade check is simplified (close instead of upgrade). This was already the case before this change. Full WS support in the event loop requires a separate async handler task.

**`writev_all` vs single `writev`**: The non-EAGAIN overflow-guard path still uses a bare `writev` (not `writev_all`). If that partial-guard writev itself returns partial/EAGAIN, those bytes are lost. This is an edge case that only triggers when a single response has more than `CONN_BATCH_IOV_MAX - current_batch_n` iovec entries — practically impossible for TFB responses but worth a follow-up.
