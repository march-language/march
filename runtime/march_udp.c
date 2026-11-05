/* march_udp.c — UDP datagram builtins behind stdlib/udp.march.
 *
 * Built for packet rate: every send and receive is a BATCH.
 *   Linux: recvmmsg/sendmmsg, plus UDP GSO (UDP_SEGMENT: one kernel transit
 *          for up to 64 equal-sized datagrams) and, opt-in, UDP GRO on
 *          receive (the kernel coalesces a flow; we split it back by the
 *          UDP_GRO cmsg).  SO_RXQ_OVFL reports the kernel's drop count.
 *   other: a nonblocking recvfrom/sendto drain loop; same semantics.
 *
 * A wait parks the green thread (march_sched_wait_fd), never an OS thread.
 * Sends apply backpressure instead of dropping: EAGAIN parks until writable,
 * ENOBUFS (a full interface queue, common on macOS) yields and retries.
 *
 * Addresses cross into March as an opaque binary String:
 *   [4][port hi][port lo][4 bytes]    IPv4  (7 bytes)
 *   [6][port hi][port lo][16 bytes]   IPv6  (19 bytes)
 * The interpreter (lib/eval/eval_builtins.ml) produces the same encoding, so
 * values compare equal across backends.  The empty String means "the
 * connected peer" (udp_connect).
 *
 * Packets are Strings (march_string is length-prefixed and binary-safe). */

#if defined(__linux__) && !defined(_GNU_SOURCE)
#  define _GNU_SOURCE      /* recvmmsg / sendmmsg */
#endif

#include "march_runtime.h"
#include "march_preempt.h"
#include "march_scheduler.h"
#include "march_udp.h"

#include <sys/types.h>
#include <sys/socket.h>
#include <sys/uio.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdatomic.h>

#if defined(__linux__)
#  include <netinet/udp.h>
#  ifndef SOL_UDP
#    define SOL_UDP 17
#  endif
#  ifndef UDP_SEGMENT
#    define UDP_SEGMENT 103
#  endif
#  ifndef UDP_GRO
#    define UDP_GRO 104
#  endif
#  ifndef SO_RXQ_OVFL
#    define SO_RXQ_OVFL 40
#  endif
#  define MARCH_UDP_MMSG 1
#endif

/* ── Result / list / tuple construction (the march_http.c shapes) ───── */

static void *udp_ok(void *v) {
    void *r = march_alloc(16 + 8);
    *(void **)((char *)r + 16) = v;
    return r;
}

static void *udp_err(const char *msg) {
    void *s = march_string_lit(msg, (int64_t)strlen(msg));
    void *r = march_alloc(16 + 8);
    *(int32_t *)((char *)r + 8) = 1;
    *(void **)((char *)r + 16) = s;
    return r;
}

static void *udp_err_errno(const char *what, int e) {
    char buf[256];
    snprintf(buf, sizeof buf, "%s: %s", what, strerror(e));
    return udp_err(buf);
}

static void *udp_ok_int(int64_t v) {
    void *r = march_alloc(16 + 8);
    *(int64_t *)((char *)r + 16) = (v << 1) | 1;
    return r;
}

static void *udp_tuple2(void *a, void *b) {
    void *t = march_alloc(16 + 16);
    *(void **)((char *)t + 16) = a;
    *(void **)((char *)t + 24) = b;
    return t;
}

static void *udp_cons(void *head) {   /* tail filled in by the caller */
    void *c = march_alloc(16 + 16);
    *(int32_t *)((char *)c + 8) = 1;
    *(void **)((char *)c + 16) = head;
    return c;
}

static void *udp_nil(void) { return march_alloc(16); }

#define UDP_IS_CONS(l) ((l) && ((march_hdr *)(l))->tag == 1)
#define UDP_HEAD(l)    (*(void **)((char *)(l) + 16))
#define UDP_TAIL(l)    (*(void **)((char *)(l) + 24))
#define UDP_FST(t)     (*(void **)((char *)(t) + 16))
#define UDP_SND(t)     (*(void **)((char *)(t) + 24))

/* ── Per-fd state ───────────────────────────────────────────────────── */

#define UDP_FD_MAX 65536
#define UF_OPEN  1u
#define UF_GSO   2u   /* UDP_SEGMENT believed to work on this socket */
#define UF_GRO   4u   /* UDP_GRO enabled: split coalesced reads */
#define UF_V6    8u   /* AF_INET6 socket: map IPv4 destinations */

static _Atomic uint8_t  g_udp_flags[UDP_FD_MAX];
static _Atomic uint32_t g_udp_rx_drops[UDP_FD_MAX];   /* SO_RXQ_OVFL, cumulative */
static _Atomic uint32_t g_udp_tx_stalls[UDP_FD_MAX];  /* ENOBUFS/EAGAIN waits */
/* Largest segment size GSO has been accepted for.  A path MTU below it makes
 * the kernel answer EINVAL; we then lower it and resend without GSO. */
static _Atomic uint16_t g_udp_gso_max[UDP_FD_MAX];

static unsigned udp_flags(int fd) {
    if (fd < 0 || fd >= UDP_FD_MAX) return 0;
    return atomic_load_explicit(&g_udp_flags[fd], memory_order_relaxed);
}

#if defined(MARCH_UDP_MMSG)
static void udp_flag_clear(int fd, unsigned f) {
    if (fd >= 0 && fd < UDP_FD_MAX)
        atomic_fetch_and_explicit(&g_udp_flags[fd], (uint8_t)~f, memory_order_relaxed);
}
#endif

static void udp_stall(int fd) {
    if (fd >= 0 && fd < UDP_FD_MAX)
        atomic_fetch_add_explicit(&g_udp_tx_stalls[fd], 1, memory_order_relaxed);
}

static int udp_is_v6(int fd) {
    if (fd >= 0 && fd < UDP_FD_MAX) return (udp_flags(fd) & UF_V6) != 0;
    struct sockaddr_storage ss;
    socklen_t l = sizeof ss;
    return getsockname(fd, (struct sockaddr *)&ss, &l) == 0 && ss.ss_family == AF_INET6;
}

/* ── Address encoding ───────────────────────────────────────────────── */

#define UDP_ADDR_MAX 19

/* Encode [sa] into out[]; returns the length (7 or 19), 0 if unsupported.
 * An IPv4-mapped IPv6 address is encoded as IPv4, so a dual-stack socket
 * reports the same address an IPv4 socket would. */
static int udp_addr_pack(const struct sockaddr *sa, unsigned char *out) {
    if (sa->sa_family == AF_INET) {
        const struct sockaddr_in *s4 = (const struct sockaddr_in *)sa;
        out[0] = 4;
        memcpy(out + 1, &s4->sin_port, 2);
        memcpy(out + 3, &s4->sin_addr, 4);
        return 7;
    }
    if (sa->sa_family == AF_INET6) {
        const struct sockaddr_in6 *s6 = (const struct sockaddr_in6 *)sa;
        if (IN6_IS_ADDR_V4MAPPED(&s6->sin6_addr)) {
            out[0] = 4;
            memcpy(out + 1, &s6->sin6_port, 2);
            memcpy(out + 3, (const unsigned char *)&s6->sin6_addr + 12, 4);
            return 7;
        }
        out[0] = 6;
        memcpy(out + 1, &s6->sin6_port, 2);
        memcpy(out + 3, &s6->sin6_addr, 16);
        return 19;
    }
    return 0;
}

/* Decode an encoded address for a socket of family v6/v4.  Returns 0 and
 * fills ss and len, or -1 for a malformed address or an IPv6 destination on an
 * IPv4 socket. */
static int udp_addr_unpack(const unsigned char *a, int64_t n, int v6,
                           struct sockaddr_storage *ss, socklen_t *len) {
    memset(ss, 0, sizeof *ss);
    if (n == 7 && a[0] == 4) {
        if (v6) {
            struct sockaddr_in6 *s6 = (struct sockaddr_in6 *)ss;
            s6->sin6_family = AF_INET6;
            memcpy(&s6->sin6_port, a + 1, 2);
            unsigned char *b = (unsigned char *)&s6->sin6_addr;
            b[10] = 0xff; b[11] = 0xff;
            memcpy(b + 12, a + 3, 4);
            *len = sizeof *s6;
        } else {
            struct sockaddr_in *s4 = (struct sockaddr_in *)ss;
            s4->sin_family = AF_INET;
            memcpy(&s4->sin_port, a + 1, 2);
            memcpy(&s4->sin_addr, a + 3, 4);
            *len = sizeof *s4;
        }
#if defined(__APPLE__)
        ((struct sockaddr *)ss)->sa_len = (uint8_t)*len;
#endif
        return 0;
    }
    if (n == 19 && a[0] == 6 && v6) {
        struct sockaddr_in6 *s6 = (struct sockaddr_in6 *)ss;
        s6->sin6_family = AF_INET6;
        memcpy(&s6->sin6_port, a + 1, 2);
        memcpy(&s6->sin6_addr, a + 3, 16);
        *len = sizeof *s6;
#if defined(__APPLE__)
        s6->sin6_len = (uint8_t)*len;
#endif
        return 0;
    }
    return -1;
}

static void *udp_addr_string(const unsigned char *a, int len) {
    return march_string_lit((const char *)a, len);
}

/* udp_addr_to_string(addr) -> String: "1.2.3.4:53", "[::1]:53", or
 * "<connected peer>" for the empty address. */
void *march_udp_addr_to_string(void *addr) {
    march_string *s = (march_string *)addr;
    const unsigned char *a = (const unsigned char *)s->data;
    char ip[INET6_ADDRSTRLEN], out[INET6_ADDRSTRLEN + 16];
    if (s->len == 0) return march_string_lit("<connected peer>", 16);
    int port = (s->len >= 3) ? (a[1] << 8 | a[2]) : 0;
    if (s->len == 7 && a[0] == 4 && inet_ntop(AF_INET, a + 3, ip, sizeof ip))
        snprintf(out, sizeof out, "%s:%d", ip, port);
    else if (s->len == 19 && a[0] == 6 && inet_ntop(AF_INET6, a + 3, ip, sizeof ip))
        snprintf(out, sizeof out, "[%s]:%d", ip, port);
    else
        snprintf(out, sizeof out, "<invalid address>");
    return march_string_lit(out, (int64_t)strlen(out));
}

/* Copy a march_string into a NUL-terminated stack buffer. */
static int udp_cstr(void *str, char *buf, size_t cap) {
    march_string *s = (march_string *)str;
    if ((size_t)s->len >= cap) return -1;
    memcpy(buf, s->data, (size_t)s->len);
    buf[s->len] = 0;
    return 0;
}

static int udp_lookup(const char *host, int port, int passive, struct addrinfo **res) {
    struct addrinfo hints;
    memset(&hints, 0, sizeof hints);
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_DGRAM;
    hints.ai_flags = passive ? AI_PASSIVE : 0;
    char pbuf[16];
    snprintf(pbuf, sizeof pbuf, "%d", port);
    return march_sched_getaddrinfo(host[0] ? host : NULL, pbuf, &hints, res);
}

/* udp_resolve(host, port) -> Result(String, String): the encoded address of
 * the first result (IPv4 preferred, so a v4 socket can always use it). */
void *march_udp_resolve(void *host_str, int64_t port) {
    char host[256];
    if (udp_cstr(host_str, host, sizeof host) < 0) return udp_err("udp_resolve: host name too long");
    if (port < 0 || port > 65535) return udp_err("udp_resolve: port out of range");
    if (!host[0]) return udp_err("udp_resolve: empty host");
    struct addrinfo *res = NULL;
    int rc = udp_lookup(host, (int)port, 0, &res);
    if (rc != 0 || !res) return udp_err(gai_strerror(rc));
    struct addrinfo *pick = res;
    for (struct addrinfo *ai = res; ai; ai = ai->ai_next)
        if (ai->ai_family == AF_INET) { pick = ai; break; }
    unsigned char buf[UDP_ADDR_MAX];
    int n = udp_addr_pack(pick->ai_addr, buf);
    freeaddrinfo(res);
    if (!n) return udp_err("udp_resolve: unsupported address family");
    return udp_ok(udp_addr_string(buf, n));
}

/* ── Socket lifecycle ───────────────────────────────────────────────── */

#define UDP_OPT_REUSEADDR 1
#define UDP_OPT_REUSEPORT 2
#define UDP_OPT_BROADCAST 4
#define UDP_OPT_GRO       8
#define UDP_OPT_NO_GSO    16

/* Ask for [want] bytes of socket buffer, halving on refusal (macOS rejects
 * anything over kern.ipc.maxsockbuf outright instead of clamping). */
static void udp_set_buf(int fd, int opt, int64_t want) {
    if (want <= 0) return;
    if (want > (1 << 30)) want = 1 << 30;
    int v = (int)want;
#if defined(__linux__)
    /* Linux clamps SO_RCVBUF to rmem_max silently; *FORCE ignores the cap
     * for a CAP_NET_ADMIN process and fails harmlessly otherwise. */
    int force = opt == SO_RCVBUF ? SO_RCVBUFFORCE : SO_SNDBUFFORCE;
    if (setsockopt(fd, SOL_SOCKET, force, &v, sizeof v) == 0) return;
#endif
    while (v >= 65536) {
        if (setsockopt(fd, SOL_SOCKET, opt, &v, sizeof v) == 0) return;
        v /= 2;
    }
}

/* udp_open(host, port, opts, rcvbuf, sndbuf) -> Result(Int, String)
 * Binds a nonblocking datagram socket.  host "" binds the IPv4 wildcard,
 * "::" a dual-stack IPv6 wildcard; port 0 picks an ephemeral port. */
void *march_udp_open(void *host_str, int64_t port, int64_t opts,
                     int64_t rcvbuf, int64_t sndbuf) {
    char host[256];
    if (udp_cstr(host_str, host, sizeof host) < 0) return udp_err("udp_open: host name too long");
    if (port < 0 || port > 65535) return udp_err("udp_open: port out of range");
    struct addrinfo *res = NULL;
    int rc = udp_lookup(host[0] ? host : "0.0.0.0", (int)port, 1, &res);
    if (rc != 0 || !res) return udp_err(gai_strerror(rc));
    struct addrinfo *ai = res;

    int type = SOCK_DGRAM;
#if defined(__linux__)
    type |= SOCK_NONBLOCK | SOCK_CLOEXEC;
#endif
    int fd = socket(ai->ai_family, type, 0);
    if (fd < 0) { int e = errno; freeaddrinfo(res); return udp_err_errno("udp_open: socket", e); }
#if !defined(__linux__)
    fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);
    fcntl(fd, F_SETFD, FD_CLOEXEC);
#endif
    int one = 1, zero = 0;
    if (ai->ai_family == AF_INET6)
        setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, &zero, sizeof zero);
    if (opts & UDP_OPT_REUSEADDR) setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
#ifdef SO_REUSEPORT
    if (opts & UDP_OPT_REUSEPORT) {
        if (setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &one, sizeof one) != 0) {
            int e = errno; close(fd); freeaddrinfo(res);
            return udp_err_errno("udp_open: SO_REUSEPORT", e);
        }
    }
#else
    if (opts & UDP_OPT_REUSEPORT) { close(fd); freeaddrinfo(res); return udp_err("udp_open: SO_REUSEPORT unsupported"); }
#endif
    if (opts & UDP_OPT_BROADCAST) setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &one, sizeof one);
    udp_set_buf(fd, SO_RCVBUF, rcvbuf);
    udp_set_buf(fd, SO_SNDBUF, sndbuf);

    if (bind(fd, ai->ai_addr, ai->ai_addrlen) != 0) {
        int e = errno; close(fd); freeaddrinfo(res);
        return udp_err_errno("udp_open: bind", e);
    }
    unsigned flags = UF_OPEN;
    if (ai->ai_family == AF_INET6) flags |= UF_V6;
    freeaddrinfo(res);
#if defined(__linux__)
    setsockopt(fd, SOL_SOCKET, SO_RXQ_OVFL, &one, sizeof one);
    if (!(opts & UDP_OPT_NO_GSO)) flags |= UF_GSO;
    if ((opts & UDP_OPT_GRO) && setsockopt(fd, SOL_UDP, UDP_GRO, &one, sizeof one) == 0)
        flags |= UF_GRO;
#endif
    if (fd < UDP_FD_MAX) {
        atomic_store_explicit(&g_udp_rx_drops[fd], 0, memory_order_relaxed);
        atomic_store_explicit(&g_udp_tx_stalls[fd], 0, memory_order_relaxed);
        atomic_store_explicit(&g_udp_gso_max[fd], 1452, memory_order_relaxed);
        atomic_store_explicit(&g_udp_flags[fd], (uint8_t)flags, memory_order_relaxed);
    }
    return udp_ok_int(fd);
}

/* udp_connect(fd, addr) -> Result((), String): fix the peer.  Sends may then
 * pass the empty address, the kernel skips a route lookup per datagram, and
 * ICMP port-unreachable comes back as an error instead of vanishing. */
void *march_udp_connect(int64_t fd_arg, void *addr) {
    int fd = (int)fd_arg;
    march_string *a = (march_string *)addr;
    struct sockaddr_storage ss;
    socklen_t len;
    if (udp_addr_unpack((const unsigned char *)a->data, a->len, udp_is_v6(fd), &ss, &len) < 0)
        return udp_err("udp_connect: invalid address");
    if (connect(fd, (struct sockaddr *)&ss, len) != 0)
        return udp_err_errno("udp_connect", errno);
    return udp_ok(NULL);
}

void march_udp_close(int64_t fd_arg) {
    int fd = (int)fd_arg;
    if (fd >= 0 && fd < UDP_FD_MAX)
        atomic_store_explicit(&g_udp_flags[fd], 0, memory_order_relaxed);
    if (fd >= 0) close(fd);
}

/* udp_local_addr(fd) -> Result(String, String): the bound address. */
void *march_udp_local_addr(int64_t fd_arg) {
    struct sockaddr_storage ss;
    socklen_t l = sizeof ss;
    if (getsockname((int)fd_arg, (struct sockaddr *)&ss, &l) != 0)
        return udp_err_errno("udp_local_addr", errno);
    unsigned char buf[UDP_ADDR_MAX];
    int n = udp_addr_pack((struct sockaddr *)&ss, buf);
    if (!n) return udp_err("udp_local_addr: not an INET socket");
    return udp_ok(udp_addr_string(buf, n));
}

/* udp_stats(fd) -> (Int, Int): (datagrams the kernel dropped for lack of
 * receive-buffer room, as of the last receive; -1 where the platform cannot
 * say), (sends that had to wait for buffer space). */
void *march_udp_stats(int64_t fd_arg) {
    int fd = (int)fd_arg;
    int64_t drops = -1, stalls = 0;
    if (fd >= 0 && fd < UDP_FD_MAX) {
#if defined(__linux__)
        drops = atomic_load_explicit(&g_udp_rx_drops[fd], memory_order_relaxed);
#endif
        stalls = atomic_load_explicit(&g_udp_tx_stalls[fd], memory_order_relaxed);
    }
    return udp_tuple2((void *)((drops << 1) | 1), (void *)((stalls << 1) | 1));
}

/* ── Send ───────────────────────────────────────────────────────────── */

typedef struct {
    const char *p;
    size_t      n;
    int         dst;   /* index into the destination table; -1 = connected */
} udp_out;

typedef struct {
    struct sockaddr_storage ss;
    socklen_t               len;
} udp_dst;

/* Wait out a full send path.  EAGAIN: park until the socket is writable.
 * ENOBUFS: the interface queue is full and poll() will not say when it
 * drains, so yield, then sleep a millisecond if it persists.  Returns 0 to
 * retry, or an errno for a failed wait.  Never called under the preempt mask. */
static int udp_backoff(int fd, int e, int *spins) {
    udp_stall(fd);
    if (e == ENOBUFS) {
        if ((*spins)++ < 8) march_sched_yield();
        else march_sched_park_self_until(march_now_ms() + 1);
        return 0;
    }
    *spins = 0;
    if (march_sched_wait_fd(fd, 1, 0) == MARCH_FDWAIT_ERROR) return march_errno_now();
    return 0;
}

static int udp_retryable(int e) {
    return e == EAGAIN || e == EWOULDBLOCK || e == ENOBUFS || e == EINTR;
}

#if defined(MARCH_UDP_MMSG)

#define UDP_GSO_SEGS   64
#define UDP_GSO_BYTES  65000
#define UDP_MMSG_VLEN  256

/* One sendmmsg message: a run of datagrams [first, first+count).  count > 1
 * only under GSO (equal sizes, one destination, last may be shorter). */
typedef struct { int first, count; size_t seg; } udp_run;

static int udp_same_dst(const udp_out *a, const udp_out *b, const udp_dst *dsts) {
    if (a->dst == b->dst) return 1;
    if (a->dst < 0 || b->dst < 0) return 0;
    return dsts[a->dst].len == dsts[b->dst].len &&
           memcmp(&dsts[a->dst].ss, &dsts[b->dst].ss, dsts[a->dst].len) == 0;
}

static int udp_plan_runs(int fd, const udp_out *outs, int n, const udp_dst *dsts,
                         udp_run *runs, int use_gso) {
    size_t gso_max = (fd >= 0 && fd < UDP_FD_MAX)
        ? atomic_load_explicit(&g_udp_gso_max[fd], memory_order_relaxed) : 0;
    int r = 0;
    for (int i = 0; i < n; ) {
        int c = 1;
        size_t seg = outs[i].n, total = seg;
        if (use_gso && seg > 0 && seg <= gso_max) {
            while (i + c < n && c < UDP_GSO_SEGS &&
                   outs[i + c].n <= seg && outs[i + c].n > 0 &&
                   total + outs[i + c].n <= UDP_GSO_BYTES &&
                   udp_same_dst(&outs[i], &outs[i + c], dsts)) {
                total += outs[i + c].n;
                c++;
                if (outs[i + c - 1].n < seg) break;   /* a short segment ends the run */
            }
        }
        runs[r].first = i; runs[r].count = c; runs[r].seg = seg;
        r++;
        i += c;
    }
    return r;
}

/* Returns 0, or an errno for a hard failure with *sent datagrams delivered. */
static int udp_send_outs(int fd, const udp_out *outs, int n, const udp_dst *dsts, int64_t *sent) {
    *sent = 0;
    if (n == 0) return 0;
    udp_run *runs = malloc(sizeof(udp_run) * (size_t)n);
    struct iovec *iov = malloc(sizeof(struct iovec) * (size_t)n);
    struct mmsghdr *msgs = malloc(sizeof(struct mmsghdr) * UDP_MMSG_VLEN);
    char (*ctl)[CMSG_SPACE(sizeof(uint16_t))] = malloc(CMSG_SPACE(sizeof(uint16_t)) * UDP_MMSG_VLEN);
    if (!runs || !iov || !msgs || !ctl) { free(runs); free(iov); free(msgs); free(ctl); return ENOMEM; }
    for (int i = 0; i < n; i++) { iov[i].iov_base = (void *)outs[i].p; iov[i].iov_len = outs[i].n; }

    int use_gso = (udp_flags(fd) & UF_GSO) != 0;
    int nruns = udp_plan_runs(fd, outs, n, dsts, runs, use_gso);
    int r = 0, spins = 0, err = 0;
    while (r < nruns) {
        int vlen = nruns - r < UDP_MMSG_VLEN ? nruns - r : UDP_MMSG_VLEN;
        memset(msgs, 0, sizeof(struct mmsghdr) * (size_t)vlen);
        for (int k = 0; k < vlen; k++) {
            udp_run *ru = &runs[r + k];
            struct msghdr *m = &msgs[k].msg_hdr;
            const udp_out *o = &outs[ru->first];
            if (o->dst >= 0) { m->msg_name = (void *)&dsts[o->dst].ss; m->msg_namelen = dsts[o->dst].len; }
            m->msg_iov = &iov[ru->first];
            m->msg_iovlen = (size_t)ru->count;
            if (ru->count > 1) {
                m->msg_control = ctl[k];
                m->msg_controllen = CMSG_SPACE(sizeof(uint16_t));
                struct cmsghdr *cm = CMSG_FIRSTHDR(m);
                cm->cmsg_level = SOL_UDP;
                cm->cmsg_type = UDP_SEGMENT;
                cm->cmsg_len = CMSG_LEN(sizeof(uint16_t));
                uint16_t gs = (uint16_t)ru->seg;
                memcpy(CMSG_DATA(cm), &gs, sizeof gs);
            }
        }
        sigset_t saved;
        march_block_preempt(&saved);
        int k = sendmmsg(fd, msgs, (unsigned)vlen, MSG_DONTWAIT);
        int e = k < 0 ? march_errno_now() : 0;
        march_unblock_preempt(&saved);
        if (k > 0) {
            for (int j = 0; j < k; j++) *sent += runs[r + j].count;
            r += k;
            spins = 0;
            continue;
        }
        if (udp_retryable(e)) {
            if (e != EINTR && (err = udp_backoff(fd, e, &spins)) != 0) break;
            continue;
        }
        if (runs[r].count > 1 && (e == EIO || e == EINVAL || e == ENOPROTOOPT || e == EOPNOTSUPP)) {
            /* GSO refused: no offload (EIO), a segment over the path MTU
             * (EINVAL) or a pre-4.18 kernel.  Split this run, remember. */
            if (e == EINVAL && runs[r].seg > 512 && fd < UDP_FD_MAX)
                atomic_store_explicit(&g_udp_gso_max[fd], (uint16_t)(runs[r].seg - 1), memory_order_relaxed);
            else
                udp_flag_clear(fd, UF_GSO);
            udp_run *nr = realloc(runs, sizeof(udp_run) * (size_t)(nruns + runs[r].count));
            if (!nr) { err = ENOMEM; break; }
            runs = nr;
            int c = runs[r].count, first = runs[r].first;
            memmove(&runs[r + c], &runs[r + 1], sizeof(udp_run) * (size_t)(nruns - r - 1));
            for (int j = 0; j < c; j++) { runs[r + j].first = first + j; runs[r + j].count = 1; runs[r + j].seg = outs[first + j].n; }
            nruns += c - 1;
            continue;
        }
        err = e ? e : EIO;
        break;
    }
    free(runs); free(iov); free(msgs); free(ctl);
    return err;
}

#else  /* !MARCH_UDP_MMSG: one sendto per datagram */

static int udp_send_outs(int fd, const udp_out *outs, int n, const udp_dst *dsts, int64_t *sent) {
    *sent = 0;
    int spins = 0;
    for (int i = 0; i < n; ) {
        sigset_t saved;
        march_block_preempt(&saved);
        int e = 0;
        /* Burst under one mask: a run of sends costs two sigprocmask calls,
         * not two per datagram. */
        for (; i < n; i++) {
            const struct sockaddr *to = outs[i].dst >= 0 ? (const struct sockaddr *)&dsts[outs[i].dst].ss : NULL;
            socklen_t tl = outs[i].dst >= 0 ? dsts[outs[i].dst].len : 0;
            ssize_t w = to ? sendto(fd, outs[i].p, outs[i].n, 0, to, tl)
                           : send(fd, outs[i].p, outs[i].n, 0);
            if (w < 0) { e = march_errno_now(); break; }
            (*sent)++;
            spins = 0;
        }
        march_unblock_preempt(&saved);
        if (i >= n) break;
        if (udp_retryable(e)) {
            if (e != EINTR) { int we = udp_backoff(fd, e, &spins); if (we) return we; }
            continue;
        }
        return e ? e : EIO;
    }
    return 0;
}

#endif

static void *udp_send_result(int err, int64_t sent, int64_t total) {
    if (!err) return udp_ok_int(sent);
    char buf[256];
    snprintf(buf, sizeof buf, "send failed after %lld of %lld datagrams: %s",
             (long long)sent, (long long)total, strerror(err));
    return udp_err(buf);
}

static int udp_list_len(void *l) {
    int n = 0;
    for (; UDP_IS_CONS(l); l = UDP_TAIL(l)) n++;
    return n;
}

/* udp_send_batch(fd, addr, payloads) -> Result(Int, String): send every
 * payload to one destination (the empty addr: the connected peer), in order.
 * Waits for buffer space rather than dropping; Ok(count) once all are sent. */
void *march_udp_send_batch(int64_t fd_arg, void *addr, void *payloads) {
    int fd = (int)fd_arg;
    march_string *a = (march_string *)addr;
    udp_dst dst;
    int di = -1;
    if (a->len > 0) {
        if (udp_addr_unpack((const unsigned char *)a->data, a->len, udp_is_v6(fd), &dst.ss, &dst.len) < 0)
            return udp_err("udp_send: invalid address");
        di = 0;
    }
    int n = udp_list_len(payloads);
    if (n == 0) return udp_ok_int(0);
    udp_out *outs = malloc(sizeof(udp_out) * (size_t)n);
    if (!outs) return udp_err("udp_send: out of memory");
    int i = 0;
    for (void *l = payloads; UDP_IS_CONS(l); l = UDP_TAIL(l), i++) {
        march_string *p = (march_string *)UDP_HEAD(l);
        outs[i].p = p->data; outs[i].n = (size_t)p->len; outs[i].dst = di;
    }
    int64_t sent;
    int err = udp_send_outs(fd, outs, n, &dst, &sent);
    free(outs);
    return udp_send_result(err, sent, n);
}

/* udp_send_many(fd, [(addr, payload)]) -> Result(Int, String): like
 * udp_send_batch with a destination per datagram.  Consecutive datagrams to
 * one destination still share a GSO run. */
void *march_udp_send_many(int64_t fd_arg, void *pairs) {
    int fd = (int)fd_arg;
    int n = udp_list_len(pairs);
    if (n == 0) return udp_ok_int(0);
    int v6 = udp_is_v6(fd);
    udp_out *outs = malloc(sizeof(udp_out) * (size_t)n);
    udp_dst *dsts = malloc(sizeof(udp_dst) * (size_t)n);
    if (!outs || !dsts) { free(outs); free(dsts); return udp_err("udp_send: out of memory"); }
    int i = 0, nd = 0;
    march_string *prev = NULL;
    for (void *l = pairs; UDP_IS_CONS(l); l = UDP_TAIL(l), i++) {
        void *t = UDP_HEAD(l);
        march_string *a = (march_string *)UDP_FST(t);
        march_string *p = (march_string *)UDP_SND(t);
        outs[i].p = p->data; outs[i].n = (size_t)p->len;
        if (a->len == 0) { outs[i].dst = -1; prev = NULL; continue; }
        if (prev && (prev == a || (prev->len == a->len && memcmp(prev->data, a->data, (size_t)a->len) == 0))) {
            outs[i].dst = nd - 1;
            continue;
        }
        if (udp_addr_unpack((const unsigned char *)a->data, a->len, v6, &dsts[nd].ss, &dsts[nd].len) < 0) {
            free(outs); free(dsts);
            return udp_err("udp_send: invalid address");
        }
        outs[i].dst = nd++;
        prev = a;
    }
    int64_t sent;
    int err = udp_send_outs(fd, outs, n, dsts, &sent);
    free(outs); free(dsts);
    return udp_send_result(err, sent, n);
}

/* ── Receive ────────────────────────────────────────────────────────── */

#define UDP_MAX_MSGS   1024
#define UDP_ARENA_CAP  (4u << 20)

/* A per-scheduler-thread receive arena.  noinline and fetched only under the
 * preempt mask, after any park: the green thread may have moved threads, and
 * a TLS address computed before the park would be the old thread's. */
static __thread char  *tl_udp_arena;
static __thread size_t tl_udp_arena_cap;

__attribute__((noinline))
static char *udp_arena(size_t need) {
    if (tl_udp_arena_cap < need) {
        char *p = realloc(tl_udp_arena, need);
        if (!p) return NULL;
        tl_udp_arena = p;
        tl_udp_arena_cap = need;
    }
    return tl_udp_arena;
}

/* Appends to a list being built front to back. */
typedef struct {
    void  *head;
    void **slot;
    int    count;
    unsigned char prev_raw[UDP_ADDR_MAX];
    int    prev_len;
    void  *prev_str;
} udp_acc;

static void udp_acc_push(udp_acc *acc, const struct sockaddr *from, const char *data, size_t len) {
    unsigned char raw[UDP_ADDR_MAX];
    int rl = from ? udp_addr_pack(from, raw) : 0;
    void *astr;
    if (acc->prev_str && rl == acc->prev_len && memcmp(raw, acc->prev_raw, (size_t)rl) == 0) {
        astr = acc->prev_str;
        march_incrc(astr);   /* a flow's datagrams share one address String */
    } else {
        astr = udp_addr_string(raw, rl);
        memcpy(acc->prev_raw, raw, (size_t)rl);
        acc->prev_len = rl;
        acc->prev_str = astr;
    }
    void *cell = udp_cons(udp_tuple2(astr, march_string_lit(data, (int64_t)len)));
    *acc->slot = cell;
    acc->slot = &UDP_TAIL(cell);
    acc->count++;
}

#if defined(MARCH_UDP_MMSG)

/* One recvmmsg under the preempt mask.  Returns datagrams appended, 0 for
 * nothing pending, or -errno. */
static int udp_drain(int fd, int max_msgs, size_t max_size, udp_acc *acc) {
    int gro = (udp_flags(fd) & UF_GRO) != 0;
    size_t bufsz = gro ? 65536 : max_size;
    int vlen = max_msgs;
    if ((size_t)vlen * bufsz > UDP_ARENA_CAP) vlen = (int)(UDP_ARENA_CAP / bufsz);
    if (vlen < 1) vlen = 1;
    if (vlen > UDP_MAX_MSGS) vlen = UDP_MAX_MSGS;
    enum { CTL = CMSG_SPACE(sizeof(uint32_t)) + CMSG_SPACE(sizeof(int)) + 32 };
    size_t per = bufsz + sizeof(struct mmsghdr) + sizeof(struct iovec)
               + sizeof(struct sockaddr_storage) + CTL;

    sigset_t saved;
    march_block_preempt(&saved);
    char *arena = udp_arena(per * (size_t)vlen);
    if (!arena) { march_unblock_preempt(&saved); return -ENOMEM; }
    struct mmsghdr *msgs = (struct mmsghdr *)arena;
    struct iovec *iov = (struct iovec *)(msgs + vlen);
    struct sockaddr_storage *from = (struct sockaddr_storage *)(iov + vlen);
    char *ctl = (char *)(from + vlen);
    char *bufs = ctl + (size_t)CTL * (size_t)vlen;
    memset(msgs, 0, sizeof(struct mmsghdr) * (size_t)vlen);
    for (int k = 0; k < vlen; k++) {
        iov[k].iov_base = bufs + (size_t)k * bufsz;
        iov[k].iov_len = bufsz;
        msgs[k].msg_hdr.msg_iov = &iov[k];
        msgs[k].msg_hdr.msg_iovlen = 1;
        msgs[k].msg_hdr.msg_name = &from[k];
        msgs[k].msg_hdr.msg_namelen = sizeof from[k];
        msgs[k].msg_hdr.msg_control = ctl + (size_t)k * CTL;
        msgs[k].msg_hdr.msg_controllen = CTL;
    }
    int got = recvmmsg(fd, msgs, (unsigned)vlen, MSG_DONTWAIT, NULL);
    int e = got < 0 ? march_errno_now() : 0;
    int pushed = 0;
    for (int k = 0; k < got && acc->count < max_msgs; k++) {
        struct msghdr *m = &msgs[k].msg_hdr;
        size_t len = msgs[k].msg_len;
        int seg = 0;
        for (struct cmsghdr *cm = CMSG_FIRSTHDR(m); cm; cm = CMSG_NXTHDR(m, cm)) {
            if (cm->cmsg_level == SOL_SOCKET && cm->cmsg_type == SO_RXQ_OVFL && fd < UDP_FD_MAX) {
                uint32_t d; memcpy(&d, CMSG_DATA(cm), sizeof d);
                atomic_store_explicit(&g_udp_rx_drops[fd], d, memory_order_relaxed);
            } else if (cm->cmsg_level == SOL_UDP && cm->cmsg_type == UDP_GRO) {
                memcpy(&seg, CMSG_DATA(cm), sizeof seg);
            }
        }
        const struct sockaddr *sa = m->msg_namelen ? (const struct sockaddr *)&from[k] : NULL;
        const char *base = (const char *)iov[k].iov_base;
        if (seg <= 0 || (size_t)seg >= len) {
            udp_acc_push(acc, sa, base, len < max_size ? len : max_size);
            pushed++;
        } else {
            /* A GRO-coalesced read: equal-sized datagrams, last may be short.
             * Every one is returned even past max_msgs -- they are already
             * off the socket and dropping them would lose data. */
            for (size_t off = 0; off < len; off += (size_t)seg) {
                size_t n = len - off < (size_t)seg ? len - off : (size_t)seg;
                udp_acc_push(acc, sa, base + off, n < max_size ? n : max_size);
                pushed++;
            }
        }
    }
    march_unblock_preempt(&saved);
    if (got < 0) return (e == EAGAIN || e == EWOULDBLOCK || e == EINTR) ? 0 : -e;
    return pushed;
}

#else

static int udp_drain(int fd, int max_msgs, size_t max_size, udp_acc *acc) {
    sigset_t saved;
    march_block_preempt(&saved);
    char *buf = udp_arena(max_size);
    if (!buf) { march_unblock_preempt(&saved); return -ENOMEM; }
    int pushed = 0, e = 0;
    while (acc->count < max_msgs) {
        struct sockaddr_storage from;
        socklen_t fl = sizeof from;
        ssize_t n = recvfrom(fd, buf, max_size, MSG_DONTWAIT, (struct sockaddr *)&from, &fl);
        if (n < 0) { e = march_errno_now(); break; }
        udp_acc_push(acc, fl ? (const struct sockaddr *)&from : NULL, buf, (size_t)n);
        pushed++;
    }
    march_unblock_preempt(&saved);
    if (pushed > 0 || e == 0 || e == EAGAIN || e == EWOULDBLOCK || e == EINTR) return pushed;
    return -e;
}

#endif

/* udp_recv_batch(fd, max_msgs, max_size, timeout_ms)
 *   -> Result(List((String, String)), String)
 * Up to max_msgs (addr, payload) pairs in arrival order.  Whatever is already
 * queued is returned at once; otherwise the green thread parks until data
 * arrives or timeout_ms passes (0: never wait, < 0: wait for ever), and a
 * timeout is Ok([]).  A payload longer than max_size is truncated to it. */
void *march_udp_recv_batch(int64_t fd_arg, int64_t max_msgs, int64_t max_size, int64_t timeout_ms) {
    int fd = (int)fd_arg;
    if (max_msgs < 1) max_msgs = 1;
    if (max_msgs > UDP_MAX_MSGS) max_msgs = UDP_MAX_MSGS;
    if (max_size < 1) max_size = 1;
    if (max_size > 65535) max_size = 65535;
    int64_t deadline = timeout_ms > 0 ? march_now_ms() + timeout_ms : 0;

    udp_acc acc;
    memset(&acc, 0, sizeof acc);
    acc.slot = &acc.head;
    for (;;) {
        int r = udp_drain(fd, (int)max_msgs, (size_t)max_size, &acc);
        if (r < 0 && acc.count == 0) {
            *acc.slot = NULL;
            return udp_err_errno("udp_recv", -r);
        }
        if (acc.count > 0 || timeout_ms == 0) break;
        if (deadline && march_now_ms() >= deadline) break;
        int w = march_sched_wait_fd(fd, 0, deadline);
        if (w == MARCH_FDWAIT_TIMEOUT) break;
        if (w == MARCH_FDWAIT_ERROR) return udp_err_errno("udp_recv: wait", march_errno_now());
    }
    *acc.slot = udp_nil();
    return udp_ok(acc.head);
}
