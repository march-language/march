/* march_handle.c — the handle box (ocap phase 2, spec §6).
 *
 * A handle is "a reference-counted box holding the descriptor and a closed
 * flag" (spec §6): the runtime form of File.Handle, File.Dir, Socket,
 * Listener and Process (and of the opaque Udp/Tls types over a Socket box).
 *
 *   [rc 0][tag=MARCH_HANDLE_TAG 8][pad=kind 12][raw 16][aux 24][state 32][- 40]
 *
 * The state word is one _Atomic int64:
 *   bit 0      CLOSED    no new use may enter
 *   bit 1      RELEASED  the descriptor has been released (or detached)
 *   bits 2..   in-flight count, in units of IN_ONE
 * Every transition is a CAS loop.  RELEASED is set by exactly one CAS, the one
 * that finds (CLOSED, in-flight 0, not RELEASED) — from close, from the leave
 * that drains the last use, or (for a box dropped unclosed) from the
 * destructor — so the descriptor is released exactly once, and never while a
 * use is in flight (a use cannot see a reused descriptor number).
 *
 * close itself takes an in-flight reference in the same CAS that sets CLOSED,
 * shuts a socket down under that reference, and then leaves: shutdown must
 * not run on a descriptor a concurrent last leave has already released.
 *
 * The box stays a core file: the closers that live in optional runtime files
 * (march_udp.c, march_tls.c) register themselves (march_handle_set_releaser)
 * from a constructor, so a program without the HTTP/TLS stack still links. */
#include "march_runtime.h"
#include "march_reclaim.h"

#include <stdatomic.h>
#include <stdio.h>
#include <sys/socket.h>
#include <unistd.h>

#define ST_CLOSED   ((int64_t)1)
#define ST_RELEASED ((int64_t)2)
#define IN_ONE      ((int64_t)4)
#define IN_MASK     (~(int64_t)3)

void (*march_handle_test_release_hook)(int64_t kind, int64_t raw, int64_t aux) = NULL;

#define MARCH_HANDLE_MAX_KIND MARCH_HANDLE_PROCESS
static void (*_Atomic g_releasers[MARCH_HANDLE_MAX_KIND + 1])(int64_t raw, int64_t aux);

void march_handle_set_releaser(int64_t kind, void (*fn)(int64_t raw, int64_t aux)) {
    if (kind < 1 || kind > MARCH_HANDLE_MAX_KIND) return;
    atomic_store_explicit(&g_releasers[kind], fn, memory_order_release);
}

static inline int32_t h_kind(void *h)        { return ((march_hdr *)h)->pad; }
static inline int64_t h_raw(void *h)         { return *(int64_t *)((char *)h + 16); }
static inline int64_t h_auxv(void *h)        { return *(int64_t *)((char *)h + 24); }
static inline _Atomic int64_t *h_state(void *h) {
    return (_Atomic int64_t *)((char *)h + 32);
}

__attribute__((noinline, cold, noreturn))
static void handle_fatal(const char *what, void *h, int64_t want) {
    char why[160];
    if (IS_HEAP_PTR(h) && ((march_hdr *)h)->tag == MARCH_HANDLE_TAG)
        snprintf(why, sizeof why, "march: handle %s: a %s box used as %s",
                 what, march_handle_kind_name(h_kind(h)), march_handle_kind_name(want));
    else
        snprintf(why, sizeof why, "march: handle %s: not a handle box (%p)", what, h);
    fprintf(stderr, "%s\n", why);
    march_abort(why);
    __builtin_unreachable();
}

static inline void check_box(void *h, const char *what) {
    if (__builtin_expect(!IS_HEAP_PTR(h) || ((march_hdr *)h)->tag != MARCH_HANDLE_TAG, 0))
        handle_fatal(what, h, 0);
}

const char *march_handle_kind_name(int64_t kind) {
    switch (kind) {
    case MARCH_HANDLE_FILE:         return "File.Handle";
    case MARCH_HANDLE_DIR:          return "File.Dir";
    case MARCH_HANDLE_TCP:          return "Socket";
    case MARCH_HANDLE_TCP_BORROWED: return "Socket";
    case MARCH_HANDLE_LISTENER:     return "Listener";
    case MARCH_HANDLE_UDP:          return "Udp.UdpSocket";
    case MARCH_HANDLE_TLS:          return "Tls.TlsConn";
    case MARCH_HANDLE_TLS_CTX:      return "Tls.TlsCtx";
    case MARCH_HANDLE_PROCESS:      return "Process";
    default:                        return "Handle?";
    }
}

static void release_kind(int64_t kind, int64_t raw, int64_t aux) {
    void (*fn)(int64_t, int64_t) =
        (kind >= 1 && kind <= MARCH_HANDLE_MAX_KIND)
            ? atomic_load_explicit(&g_releasers[kind], memory_order_acquire) : NULL;
    switch (kind) {
    case MARCH_HANDLE_FILE:
        march_file_close((void *)(intptr_t)raw);
        break;
    case MARCH_HANDLE_DIR:
        close((int)raw);
        break;
    case MARCH_HANDLE_TCP:
    case MARCH_HANDLE_LISTENER:
        /* march_tcp_close (march_http.c) is exactly close(fd); calling it
         * would make this core file need the HTTP stack to link. */
        close((int)raw);
        break;
    case MARCH_HANDLE_UDP:
        if (fn) fn(raw, aux); else close((int)raw);   /* march_udp_close */
        break;
    case MARCH_HANDLE_TLS:
        if (fn) fn(raw, aux);                          /* march_tls_close */
        close((int)aux);                               /* its TCP fd */
        break;
    case MARCH_HANDLE_TLS_CTX:
        if (fn) fn(raw, aux);                          /* march_tls_ctx_free */
        break;
    case MARCH_HANDLE_PROCESS:
        march_process_release_slot(raw);
        break;
    case MARCH_HANDLE_TCP_BORROWED:
    default:
        break;                         /* the HTTP event loop owns the fd */
    }
}

static void handle_release(void *h) {
    int64_t kind = h_kind(h), raw = h_raw(h), aux = h_auxv(h);
    void (*hook)(int64_t, int64_t, int64_t) = march_handle_test_release_hook;
    if (hook) { hook(kind, raw, aux); return; }
    release_kind(kind, raw, aux);
}

void *march_handle_new(int64_t kind, int64_t raw, int64_t aux) {
    void *h = march_alloc(MARCH_HANDLE_SIZE);
    ((march_hdr *)h)->tag = MARCH_HANDLE_TAG;
    ((march_hdr *)h)->pad = (int32_t)kind;
    *(int64_t *)((char *)h + 16) = raw;
    *(int64_t *)((char *)h + 24) = aux;
    atomic_init(h_state(h), 0);
    *(int64_t *)((char *)h + 40) = 0;
    return h;
}

int64_t march_handle_enter(void *h, int64_t kind) {
    check_box(h, "enter");
    int32_t k = h_kind(h);
    if (__builtin_expect(k != kind && !(kind == MARCH_HANDLE_TCP && k == MARCH_HANDLE_TCP_BORROWED), 0))
        handle_fatal("enter", h, kind);
    _Atomic int64_t *st = h_state(h);
    int64_t s = atomic_load_explicit(st, memory_order_acquire);
    for (;;) {
        if (s & ST_CLOSED) return -1;
        if (atomic_compare_exchange_weak_explicit(st, &s, s + IN_ONE,
                                                  memory_order_acq_rel, memory_order_acquire))
            return h_raw(h);
    }
}

void march_handle_leave(void *h) {
    check_box(h, "leave");
    _Atomic int64_t *st = h_state(h);
    int64_t s = atomic_load_explicit(st, memory_order_acquire);
    for (;;) {
        if (__builtin_expect((s & IN_MASK) == 0, 0)) {
            fprintf(stderr, "march: handle leave without a matching enter\n");
            march_abort("march: handle leave without a matching enter");
        }
        int64_t ns = s - IN_ONE;
        int release = (ns & IN_MASK) == 0 && (ns & ST_CLOSED) && !(ns & ST_RELEASED);
        if (release) ns |= ST_RELEASED;
        if (atomic_compare_exchange_weak_explicit(st, &s, ns,
                                                  memory_order_acq_rel, memory_order_acquire)) {
            if (release) handle_release(h);
            return;
        }
    }
}

int64_t march_handle_close(void *h) {
    check_box(h, "close");
    _Atomic int64_t *st = h_state(h);
    int64_t s = atomic_load_explicit(st, memory_order_acquire);
    for (;;) {
        if (s & ST_CLOSED) return 0;
        /* Set CLOSED and take an in-flight reference of our own in one step,
         * so the descriptor stays ours through the shutdown below. */
        if (atomic_compare_exchange_weak_explicit(st, &s, (s | ST_CLOSED) + IN_ONE,
                                                  memory_order_acq_rel, memory_order_acquire))
            break;
    }
    int32_t k = h_kind(h);
    if (k == MARCH_HANDLE_TCP || k == MARCH_HANDLE_LISTENER || k == MARCH_HANDLE_UDP)
        (void)shutdown((int)h_raw(h), SHUT_RDWR);     /* wake a parked recv/accept */
    march_handle_leave(h);                             /* releases if nothing else is in flight */
    return 1;
}

int64_t march_handle_detach(void *h) {
    check_box(h, "detach");
    _Atomic int64_t *st = h_state(h);
    int64_t s = atomic_load_explicit(st, memory_order_acquire);
    for (;;) {
        if (s & ST_CLOSED) return -1;
        if (atomic_compare_exchange_weak_explicit(st, &s, s | ST_CLOSED | ST_RELEASED,
                                                  memory_order_acq_rel, memory_order_acquire))
            return h_raw(h);
    }
}

int64_t march_handle_is_closed(void *h) {
    check_box(h, "is_closed");
    return (atomic_load_explicit(h_state(h), memory_order_acquire) & ST_CLOSED) ? 1 : 0;
}

int64_t march_handle_aux(void *h) {
    check_box(h, "aux");
    return h_auxv(h);
}

int64_t march_handle_kind(void *h) {
    check_box(h, "kind");
    return h_kind(h);
}

/* The last reference is gone, so no other thread can touch the box.  A box
 * with a stranded in-flight count (a panic between enter and leave) is still
 * released: nobody is left to use the descriptor. */
void march_handle_dtor(void *h) {
    _Atomic int64_t *st = h_state(h);
    int64_t s = atomic_load_explicit(st, memory_order_acquire);
    for (;;) {
        if (s & ST_RELEASED) return;
        if (atomic_compare_exchange_weak_explicit(st, &s, s | ST_CLOSED | ST_RELEASED,
                                                  memory_order_acq_rel, memory_order_acquire))
            break;
    }
    handle_release(h);
}
