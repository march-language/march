/* test/native/fatal_trap_report.c -- the shim for fatal_trap_report.march.
 *
 * Forks, and the child executes an illegal instruction (arm64 `udf #0`, x86
 * `ud2`) on the green thread that called the shim, with its stderr on a pipe.
 * The parent reads what the child wrote, reaps it, and returns
 *     exit_status * 16 + flags
 * where the flags say which lines of the runtime's fatal-trap report
 * (march_fatal_trap_handler, runtime/march_scheduler.c) were present:
 *   1  "march: fatal SIGILL si_code=..."      (the fault line)
 *   2  "march: fatal SIGILL static pc=..."    (pc / lr, image-relative)
 *   4  "march: fatal trap frames (static): A B ..." with at least two frames (one on x86_64)
 * Forking keeps the trap out of the test process, so the fixture itself exits
 * 0 (and the sanitizer sweep, which runs every fixture, sees a clean run). The
 * child inherits the handler (sigaction is per process) and only runs the
 * handler's write(2)/_exit path, which is async-signal-safe after a fork. */
#include "march_ffi.h"
#include <errno.h>
#include <stdint.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

__attribute__((noinline)) static void fatal_trap_report_illegal(void) {
#if defined(__aarch64__)
    __asm__ volatile(".inst 0x00000000");   /* udf #0 */
#elif defined(__x86_64__)
    __asm__ volatile("ud2");
#else
    __builtin_trap();
#endif
}

int64_t fatal_trap_report_probe(int64_t unused) {
    (void)unused;
    int fds[2];
    if (pipe(fds) != 0) return -1;
    pid_t pid = fork();
    if (pid < 0) return -2;
    if (pid == 0) {
        dup2(fds[1], 2);
        close(fds[0]);
        close(fds[1]);
        fatal_trap_report_illegal();
        _exit(0);   /* not reached: the handler _exits with 128 + SIGILL */
    }
    close(fds[1]);
    char buf[8192];
    size_t n = 0;
    for (;;) {
        ssize_t r = read(fds[0], buf + n, sizeof buf - 1 - n);
        if (r > 0) { n += (size_t)r; if (n == sizeof buf - 1) break; continue; }
        if (r < 0 && errno == EINTR) continue;   /* a preemption tick */
        break;
    }
    buf[n] = '\0';
    close(fds[0]);
    int st = 0;
    while (waitpid(pid, &st, 0) < 0 && errno == EINTR) {}
    int64_t status = WIFEXITED(st) ? WEXITSTATUS(st)
                   : WIFSIGNALED(st) ? 128 + WTERMSIG(st) : -3;
    int64_t flags = 0;
    if (strstr(buf, "march: fatal SIGILL si_code=")) flags |= 1;
    if (strstr(buf, "march: fatal SIGILL static pc=")) flags |= 2;
    const char *fr = strstr(buf, "march: fatal trap frames (static): ");
    if (fr) {
        int frames = 0;
        for (const char *q = fr; *q && *q != '\n'; q++)
            if (q[0] == ' ' && q[1] == '0' && q[2] == 'x') frames++;
        /* arm64 (AAPCS64) always keeps the frame-pointer chain, so the walk
         * must reach past the trapping frame.  x86_64 code built at -O2
         * omits frame pointers, so the walk can honestly stop after the
         * trapping frame there (Linux x86_64 CI printed one frame). */
#if defined(__x86_64__)
        const int need = 1;
#else
        const int need = 2;
#endif
        if (frames >= need) flags |= 4;
    }
    return status * 16 + flags;
}
