/* test_fatal_hook.c — march_abort / march_fatal_dump (R7.4 of
 * specs/plans/2026-09-28-observe-recon-shell-plan.md), the gate in front of
 * the crash-dump writer.  Links runtime/march_reclaim.c alone; the writer
 * itself (march_observe_snapshot.c) is covered by test/native/crash_dump.march.
 *
 * Each case runs in a forked child that calls march_abort and dies of SIGABRT;
 * the hook leaves a byte in a pipe if it ran.  The dump may be attempted only
 *   - when a writer is installed,
 *   - outside a reclamation critical section,
 *   - not on a signal stack,
 * and the process must abort whether or not it was attempted. */
#define _GNU_SOURCE
#include "march_reclaim.h"

#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

static int failures, checks;
#define CHECK(cond, ...) do { \
    checks++; \
    if (!(cond)) { failures++; fprintf(stderr, "FAIL %s:%d: ", __FILE__, __LINE__); \
                   fprintf(stderr, __VA_ARGS__); fprintf(stderr, "\n"); } \
} while (0)

static int g_pipe[2];

static void hook(const char *why) {
    char c = why && strcmp(why, "site-x") == 0 ? 'x' : '?';
    (void)!write(g_pipe[1], &c, 1);
}

static void on_alt_stack(int sig) {
    (void)sig;
    march_abort("site-x");   /* inside a handler running on the alternate stack */
}

enum scenario { PLAIN, NO_HOOK, IN_SECTION, ON_SIGNAL_STACK, DUMP_ONLY };

/* Run one scenario in a child; returns whether the hook ran (-1: no pipe
 * byte, 'x': ran with the right reason) and sets *sig to how it died. */
static int run(enum scenario sc, int *died_of, int *exit_code) {
    if (pipe(g_pipe) != 0) { perror("pipe"); exit(2); }
    pid_t pid = fork();
    if (pid == 0) {
        close(g_pipe[0]);
        if (sc != NO_HOOK) march_fatal_set_hook(hook);
        if (sc == IN_SECTION) march_reclaim_enter();
        if (sc == ON_SIGNAL_STACK) {
            static char stack[1 << 16];
            stack_t ss = { .ss_sp = stack, .ss_size = sizeof stack, .ss_flags = 0 };
            sigaltstack(&ss, NULL);
            struct sigaction sa;
            memset(&sa, 0, sizeof sa);
            sa.sa_handler = on_alt_stack;
            sa.sa_flags = SA_ONSTACK;
            sigemptyset(&sa.sa_mask);
            sigaction(SIGUSR2, &sa, NULL);
            raise(SIGUSR2);
            _exit(77);   /* the handler aborts; not reached */
        }
        if (sc == DUMP_ONLY) {
            int r = march_fatal_dump("site-x");
            _exit(r ? 10 : 11);   /* exit codes carry the return value */
        }
        march_abort("site-x");
        _exit(77);
    }
    close(g_pipe[1]);
    char c = 0;
    ssize_t k = read(g_pipe[0], &c, 1);
    close(g_pipe[0]);
    int st = 0;
    waitpid(pid, &st, 0);
    *died_of = WIFSIGNALED(st) ? WTERMSIG(st) : 0;
    *exit_code = WIFEXITED(st) ? WEXITSTATUS(st) : -1;
    return k == 1 ? c : -1;
}

int main(void) {
    int sig, code, r;

    r = run(PLAIN, &sig, &code);
    CHECK(r == 'x', "a writer installed and a clean context: the hook runs with the caller's reason (got %d)", r);
    CHECK(sig == SIGABRT, "and the process still aborts (signal %d, exit %d)", sig, code);

    r = run(NO_HOOK, &sig, &code);
    CHECK(r == -1, "no writer installed: nothing is called");
    CHECK(sig == SIGABRT, "and it aborts (signal %d)", sig);

    r = run(IN_SECTION, &sig, &code);
    CHECK(r == -1, "inside a reclamation critical section: no dump");
    CHECK(sig == SIGABRT, "but it still aborts (signal %d)", sig);

    r = run(ON_SIGNAL_STACK, &sig, &code);
    CHECK(r == -1, "on a signal stack: no dump");
    CHECK(sig == SIGABRT, "but it still aborts (signal %d, exit %d)", sig, code);

    r = run(DUMP_ONLY, &sig, &code);
    CHECK(r == 'x' && code == 10 && sig == 0, "march_fatal_dump alone runs the hook and returns 1 (hook %d, exit %d)", r, code);

    printf("test_fatal_hook: %d checks, %d failures\n", checks, failures);
    return failures ? 1 : 0;
}
