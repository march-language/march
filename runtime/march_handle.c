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
 * Waking a parked user.  A task blocked in recv/accept on the descriptor is
 * inside a use (in flight), parked on the scheduler's poller.  close wakes it
 * two ways: shutdown(SHUT_RDWR), which is enough on Linux, and
 * march_sched_fdwait_cancel, which is what works on macOS too (there,
 * shutdown on a listening socket or an unconnected UDP socket fails with
 * ENOTCONN and its kqueue filter never fires).  The cancellation lasts until
 * the release, which forgets it (march_sched_fdwait_forget) just before
 * close(fd), so a reused descriptor number never inherits it.  A TLS
 * connection's wait is on its TCP fd (aux); close cancels it and shuts down
 * only its READ side, and only when another use is in flight, so a plain
 * close still lets the release send close_notify (SSL_shutdown) and a write
 * after shutdown cannot raise SIGPIPE.
 *
 * The box stays a core file: the closers that live in optional runtime files
 * (march_udp.c, march_tls.c) register themselves (march_handle_set_releaser)
 * from a constructor, so a program without the HTTP/TLS stack still links.
 * A TLS or TLS_CTX box with no registered closer is fatal at release: it can
 * only exist in a link that left out march_tls.c, and silently leaking the
 * SSL object would hide that. */
#include "march_runtime.h"
#include "march_reclaim.h"

#include <stdatomic.h>
#include <stdio.h>
#include <sys/socket.h>
#include <unistd.h>

/* march_scheduler.c.  Weak, so a test link that leaves the scheduler out
 * still links; every real link (core role) has it. */
extern void march_sched_fdwait_cancel(int fd) __attribute__((weak));
extern void march_sched_fdwait_forget(int fd) __attribute__((weak));
extern void march_sched_fdwait_own(int fd, int owned) __attribute__((weak));

/* The descriptor a box of [kind] owns and can cancel waits on, or -1. */
static inline int64_t owned_fd(int64_t kind, int64_t raw, int64_t aux) {
    switch (kind) {
    case MARCH_HANDLE_TCP: case MARCH_HANDLE_LISTENER: case MARCH_HANDLE_UDP: return raw;
    case MARCH_HANDLE_TLS: return aux;
    default: return -1;
    }
}
static inline void fd_own(int64_t fd, int owned) {
    if (march_sched_fdwait_own && fd >= 0) march_sched_fdwait_own((int)fd, owned);
}

static inline void fd_cancel_waits(int64_t fd) {
    if (march_sched_fdwait_cancel && fd >= 0) march_sched_fdwait_cancel((int)fd);
}
static inline void fd_forget_cancel(int64_t fd) {
    if (march_sched_fdwait_forget && fd >= 0) march_sched_fdwait_forget((int)fd);
}

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

__attribute__((noinline, cold, noreturn))
static void missing_releaser(int64_t kind) {
    char why[160];
    snprintf(why, sizeof why,
             "march: handle release: no closer registered for a %s box "
             "(is march_tls.c linked?)", march_handle_kind_name(kind));
    fprintf(stderr, "%s\n", why);
    march_abort(why);
    __builtin_unreachable();
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
        fd_forget_cancel(raw);
        close((int)raw);
        break;
    case MARCH_HANDLE_UDP:
        fd_forget_cancel(raw);
        if (fn) fn(raw, aux); else close((int)raw);   /* march_udp_close */
        break;
    case MARCH_HANDLE_TLS:
        if (!fn) missing_releaser(kind);
        fn(raw, aux);                                  /* march_tls_close */
        fd_forget_cancel(aux);
        close((int)aux);                               /* its TCP fd */
        break;
    case MARCH_HANDLE_TLS_CTX:
        if (!fn) missing_releaser(kind);
        fn(raw, aux);                                  /* march_tls_ctx_free */
        break;
    case MARCH_HANDLE_PROCESS:
        march_process_release_handle(raw);           /* closes, SIGTERMs, reaps */
        break;
    case MARCH_HANDLE_TCP_BORROWED:
    default:
        break;                         /* the HTTP event loop owns the fd */
    }
}

static void handle_release(void *h) {
    int64_t kind = h_kind(h), raw = h_raw(h), aux = h_auxv(h);
    fd_own(owned_fd(kind, raw, aux), 0);
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
    fd_own(owned_fd(kind, raw, aux), 1);
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
    /* [s] is the state just before our CAS: its in-flight count is exactly
     * the uses that can still be parked (no new one can enter now). */
    int others = (s & IN_MASK) != 0;
    int32_t k = h_kind(h);
    if (k == MARCH_HANDLE_TCP || k == MARCH_HANDLE_LISTENER || k == MARCH_HANDLE_UDP) {
        (void)shutdown((int)h_raw(h), SHUT_RDWR);     /* wake a parked recv/accept (Linux) */
        fd_cancel_waits(h_raw(h));                     /* ... and everywhere else */
    } else if (k == MARCH_HANDLE_TLS && others) {
        (void)shutdown((int)h_auxv(h), SHUT_RD);      /* a reader parked in SSL_read */
        fd_cancel_waits(h_auxv(h));
    }
    march_handle_leave(h);                             /* releases if nothing else is in flight */
    return 1;
}

/* Hand the descriptor over (to a TLS box, or to code that keeps raw fds):
 * close the box without releasing.  Refused (-1, nothing changes) when the
 * box is closed; when it is a TCP_BORROWED box, whose descriptor is not the
 * box's to give away; and while another use is in flight -- an in-flight
 * count above the caller's own one (the caller may be inside a use, as
 * Tls.connect is, or not) -- because that use would go on with a descriptor
 * its new owner may close. */
int64_t march_handle_detach(void *h) {
    check_box(h, "detach");
    if (h_kind(h) == MARCH_HANDLE_TCP_BORROWED) return -1;
    _Atomic int64_t *st = h_state(h);
    int64_t s = atomic_load_explicit(st, memory_order_acquire);
    for (;;) {
        if (s & ST_CLOSED) return -1;
        if ((s & IN_MASK) > IN_ONE) return -1;
        if (atomic_compare_exchange_weak_explicit(st, &s, s | ST_CLOSED | ST_RELEASED,
                                                  memory_order_acq_rel, memory_order_acquire)) {
            fd_own(owned_fd(h_kind(h), h_raw(h), h_auxv(h)), 0);
            return h_raw(h);
        }
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
