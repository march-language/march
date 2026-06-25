/*
 * march_monitor_registry.c — cross-node (distributed) monitor table.
 *
 * Stores per-target-pid lists of remote watchers.  When a target actor exits
 * (or its node loses a peer connection), we send MONITOR_FIRE frames over the
 * existing TCP fds.
 *
 * MONITOR_FIRE wire format (Msgpack array, mirrors NetKernel.encode_monitor_fire):
 *   [8, target_pid:Int, reason_tag:Int, reason_msg:Str]
 *
 * We build this by hand using a minimal msgpack encoder rather than pulling in
 * the full March runtime (this file is included in the C runtime, not the
 * March layer).
 */

#include "march_monitor_registry.h"

#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <pthread.h>
#include <unistd.h>

/* ── Simple msgpack encoder (only int + str + array, enough for MONITOR_FIRE) ─ */

static void mp_write_byte(uint8_t **p, uint8_t b) { *(*p)++ = b; }

static void mp_write_int(uint8_t **p, int64_t v) {
    if (v >= 0 && v <= 127) {
        mp_write_byte(p, (uint8_t)v);
    } else if (v >= -32 && v < 0) {
        mp_write_byte(p, (uint8_t)(0xe0 | (v & 0x1f)));
    } else if (v >= 0 && v <= 0xff) {
        mp_write_byte(p, 0xcc); mp_write_byte(p, (uint8_t)v);
    } else if (v >= 0 && v <= 0xffff) {
        mp_write_byte(p, 0xcd);
        mp_write_byte(p, (uint8_t)(v >> 8)); mp_write_byte(p, (uint8_t)v);
    } else if (v >= 0 && v <= 0xffffffff) {
        mp_write_byte(p, 0xce);
        mp_write_byte(p, (uint8_t)(v >> 24)); mp_write_byte(p, (uint8_t)(v >> 16));
        mp_write_byte(p, (uint8_t)(v >>  8)); mp_write_byte(p, (uint8_t)v);
    } else {
        mp_write_byte(p, 0xd3);
        for (int i = 7; i >= 0; i--) mp_write_byte(p, (uint8_t)(v >> (8*i)));
    }
}

static void mp_write_str(uint8_t **p, const char *s) {
    size_t len = s ? strlen(s) : 0;
    if (len <= 31) {
        mp_write_byte(p, (uint8_t)(0xa0 | len));
    } else if (len <= 0xff) {
        mp_write_byte(p, 0xd9); mp_write_byte(p, (uint8_t)len);
    } else {
        mp_write_byte(p, 0xda);
        mp_write_byte(p, (uint8_t)(len >> 8)); mp_write_byte(p, (uint8_t)len);
    }
    if (s && len > 0) memcpy(*p, s, len), *p += len;
}

/* Build MONITOR_FIRE frame: [8, target_pid, reason_tag, reason_msg]
 * Returns malloc'd buffer and its length (includes 4-byte NetFrame length header).
 * Caller must free(). */
static uint8_t *build_monitor_fire_frame(int64_t target_pid, int reason_tag,
                                          const char *reason_msg, size_t *out_len) {
    size_t msg_len = reason_msg ? strlen(reason_msg) : 0;
    /* Generous upper bound: 4 (header) + 1 (fixarray) + 5+5+5 (ints) + 3+msg_len (str) */
    size_t cap = 64 + msg_len;
    uint8_t *buf = (uint8_t *)malloc(cap);
    if (!buf) return NULL;

    uint8_t *p = buf + 4;  /* reserve 4 bytes for NetFrame length header */

    /* fixarray of 4 */
    mp_write_byte(&p, 0x94);
    mp_write_int(&p, 8);                 /* tag = MONITOR_FIRE */
    mp_write_int(&p, target_pid);
    mp_write_int(&p, (int64_t)reason_tag);
    mp_write_str(&p, reason_msg ? reason_msg : "");

    size_t payload_len = (size_t)(p - buf - 4);
    /* NetFrame: 4-byte big-endian length header */
    buf[0] = (uint8_t)(payload_len >> 24);
    buf[1] = (uint8_t)(payload_len >> 16);
    buf[2] = (uint8_t)(payload_len >>  8);
    buf[3] = (uint8_t)(payload_len);

    *out_len = 4 + payload_len;
    return buf;
}

/* ── Watcher entry ─────────────────────────────────────────────────────────── */

typedef struct dist_watcher {
    char       *watcher_node;   /* owning node_id (malloc'd) */
    int64_t     watcher_pid;
    int         fd;             /* TCP fd to send MONITOR_FIRE on */
    struct dist_watcher *next;
} dist_watcher;

/* ── Target bucket ─────────────────────────────────────────────────────────── */

#define DIST_MON_BUCKETS 256

typedef struct dist_target {
    int64_t          target_pid;
    char            *target_node;  /* node_id that hosts this target (NULL = local) */
    dist_watcher    *watchers;
    struct dist_target *next;
} dist_target;

static dist_target   *g_buckets[DIST_MON_BUCKETS];
static pthread_mutex_t g_mu = PTHREAD_MUTEX_INITIALIZER;

static unsigned int bucket_for(int64_t pid) {
    return (unsigned int)((uint64_t)pid % DIST_MON_BUCKETS);
}

static dist_target *find_target(int64_t target_pid) {
    unsigned int b = bucket_for(target_pid);
    for (dist_target *t = g_buckets[b]; t; t = t->next)
        if (t->target_pid == target_pid) return t;
    return NULL;
}

static dist_target *find_or_create_target(int64_t target_pid) {
    dist_target *t = find_target(target_pid);
    if (t) return t;
    t = (dist_target *)calloc(1, sizeof(dist_target));
    t->target_pid = target_pid;
    unsigned int b = bucket_for(target_pid);
    t->next = g_buckets[b];
    g_buckets[b] = t;
    return t;
}

/* ── Public API ────────────────────────────────────────────────────────────── */

void march_dist_monitor_register(int64_t target_pid, const char *watcher_node,
                                  int64_t watcher_pid, int watcher_fd) {
    pthread_mutex_lock(&g_mu);
    dist_target *t = find_or_create_target(target_pid);

    /* Deduplicate: don't register the same (node, pid) twice. */
    for (dist_watcher *w = t->watchers; w; w = w->next) {
        if (w->watcher_pid == watcher_pid &&
            watcher_node && w->watcher_node &&
            strcmp(w->watcher_node, watcher_node) == 0) {
            pthread_mutex_unlock(&g_mu);
            return;
        }
    }

    dist_watcher *w = (dist_watcher *)calloc(1, sizeof(dist_watcher));
    w->watcher_node = watcher_node ? strdup(watcher_node) : NULL;
    w->watcher_pid  = watcher_pid;
    w->fd           = watcher_fd;
    w->next         = t->watchers;
    t->watchers     = w;
    pthread_mutex_unlock(&g_mu);
}

void march_dist_monitor_fire_pid(int64_t target_pid, int reason_tag,
                                  const char *reason_msg) {
    pthread_mutex_lock(&g_mu);
    dist_target *t = find_target(target_pid);
    if (!t) { pthread_mutex_unlock(&g_mu); return; }

    dist_watcher *w = t->watchers;
    t->watchers = NULL;
    pthread_mutex_unlock(&g_mu);

    /* Send MONITOR_FIRE to each watcher; free entries as we go. */
    while (w) {
        dist_watcher *next = w->next;
        size_t frame_len;
        uint8_t *frame = build_monitor_fire_frame(target_pid, reason_tag,
                                                   reason_msg, &frame_len);
        if (frame) {
            /* Best-effort write; ignore errors (watcher may have disconnected). */
            size_t written = 0;
            while (written < frame_len) {
                ssize_t n = write(w->fd, frame + written, frame_len - written);
                if (n <= 0) break;
                written += (size_t)n;
            }
            free(frame);
        }
        free(w->watcher_node);
        free(w);
        w = next;
    }
}

void march_dist_monitor_fire_nodedown(const char *node_id) {
    if (!node_id) return;

    /* Collect (target_pid, watchers) pairs for targets whose watchers
     * include node_id. We fire NodeDown only to watchers ON node_id
     * (i.e., they asked us to monitor a local target, and now they're gone —
     * so actually we want the inverse: fire to any watcher that is watching
     * a target whose host node is node_id.
     *
     * Simpler interpretation (used here): when node_id disconnects,
     * fire NodeDown for every watcher entry whose fd belongs to node_id.
     * The transport layer should call march_dist_monitor_clear_fd first
     * with the relevant fd, so this fires before cleanup.
     */
    pthread_mutex_lock(&g_mu);

    for (int b = 0; b < DIST_MON_BUCKETS; b++) {
        for (dist_target *t = g_buckets[b]; t; t = t->next) {
            dist_watcher **pp = &t->watchers;
            while (*pp) {
                dist_watcher *w = *pp;
                if (w->watcher_node && strcmp(w->watcher_node, node_id) == 0) {
                    *pp = w->next;
                    /* Build and send NodeDown frame — but we hold g_mu here.
                     * Safe: write() does not need the monitor lock. */
                    size_t frame_len;
                    uint8_t *frame = build_monitor_fire_frame(
                        t->target_pid, MARCH_DIST_REASON_NODEDOWN, "", &frame_len);
                    pthread_mutex_unlock(&g_mu);
                    if (frame) {
                        size_t written = 0;
                        while (written < frame_len) {
                            ssize_t n = write(w->fd, frame + written,
                                              frame_len - written);
                            if (n <= 0) break;
                            written += (size_t)n;
                        }
                        free(frame);
                    }
                    free(w->watcher_node);
                    free(w);
                    pthread_mutex_lock(&g_mu);
                } else {
                    pp = &w->next;
                }
            }
        }
    }

    pthread_mutex_unlock(&g_mu);
}

void march_dist_monitor_clear_fd(int watcher_fd) {
    pthread_mutex_lock(&g_mu);
    for (int b = 0; b < DIST_MON_BUCKETS; b++) {
        for (dist_target *t = g_buckets[b]; t; t = t->next) {
            dist_watcher **pp = &t->watchers;
            while (*pp) {
                dist_watcher *w = *pp;
                if (w->fd == watcher_fd) {
                    *pp = w->next;
                    free(w->watcher_node);
                    free(w);
                } else {
                    pp = &w->next;
                }
            }
        }
    }
    pthread_mutex_unlock(&g_mu);
}
