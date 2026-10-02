/* observe_client.c — a minimal observe-socket client for the native test
 * test/native/observe_ping.march (R0 of
 * specs/plans/2026-09-28-observe-recon-shell-plan.md).  The stdlib Socket
 * module has no Unix-domain connect, so the dune rule uses this instead.
 *
 * Usage: observe_client <socket> <verb> <expected-substring>
 * Waits up to 5 s for the socket to appear, sends <verb>, and prints
 * "<verb>: ok" when the reply contains the observe envelope and
 * <expected-substring>; otherwise a line saying what went wrong.  Always
 * exits 0 so the golden diff, not the exit code, is the verdict. */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc != 4) { fprintf(stderr, "usage: observe_client <socket> <verb> <expect>\n"); return 2; }
    const char *path = argv[1], *verb = argv[2], *expect = argv[3];
    struct sockaddr_un a;
    memset(&a, 0, sizeof a);
    a.sun_family = AF_UNIX;
    snprintf(a.sun_path, sizeof a.sun_path, "%s", path);
    int fd = -1;
    for (int i = 0; i < 100 && fd < 0; i++) {
        int s = socket(AF_UNIX, SOCK_STREAM, 0);
        if (connect(s, (struct sockaddr *)&a, sizeof a) == 0) { fd = s; break; }
        close(s);
        struct timespec ts = { 0, 50 * 1000 * 1000 };
        nanosleep(&ts, NULL);
    }
    if (fd < 0) { printf("%s: no socket\n", verb); return 0; }
    char line[256];
    int n = snprintf(line, sizeof line, "%s\n", verb);
    send(fd, line, (size_t)n, 0);
    char buf[65536];
    size_t len = 0;
    for (;;) {
        ssize_t k = recv(fd, buf + len, sizeof buf - 1 - len, 0);
        if (k <= 0) break;
        len += (size_t)k;
        if (len == sizeof buf - 1) break;
    }
    buf[len] = '\0';
    close(fd);
    if (strstr(buf, "\"proto\":\"march.observe/1\"") && strstr(buf, expect))
        printf("%s: ok\n", verb);
    else
        printf("%s: unexpected reply: %s", verb, buf);
    return 0;
}
