/* Self-imposed capability sandbox (opt-in via `march --cap-sandbox`).
 *
 * The compiler embeds an SBPL profile derived from the module's capability
 * set as MARCH_CAP_PROFILE, and march_sandbox_install() applies it before
 * any user code runs.  This is DEFENSE IN DEPTH, not a new guarantee:
 * whoever builds the binary chooses whether to compile it in at all, so a
 * hostile publisher simply omits it.  Its value is for a binary you built
 * and trust, deployed somewhere forge is not the launcher (systemd, a
 * container supervisor) — the case `forge cap run` cannot reach.
 *
 * Externally imposed enforcement (`forge cap run --allow-only ...`) remains
 * the stronger mechanism and should be preferred when available.
 *
 * Only compiled in when MARCH_CAP_PROFILE is defined; otherwise every entry
 * point here is a no-op, so default builds are byte-identical.
 */

#include <stdio.h>
#include <stdlib.h>

#ifdef MARCH_CAP_PROFILE

#if defined(__APPLE__)

/* Deprecated since 10.7 but still exported by libSystem, and still the only
 * in-process way to drop privileges on macOS.  Declared locally because the
 * header is not in the public SDK. */
extern int sandbox_init(const char *profile, uint64_t flags, char **errorbuf);
extern void sandbox_free_error(char *errorbuf);

void march_sandbox_install(void) {
    char *err = NULL;
    if (sandbox_init(MARCH_CAP_PROFILE, 0, &err) != 0) {
        /* Fail CLOSED.  A sandbox that silently fails to apply is worse
         * than none: the operator believes the process is contained when
         * it is not. */
        fprintf(stderr,
                "march: capability sandbox failed to install (%s); refusing "
                "to run uncontained\n",
                err ? err : "unknown error");
        if (err) sandbox_free_error(err);
        exit(70);
    }
}

#else /* !__APPLE__ */

/* Linux self-sandboxing needs a seccomp-bpf filter built in-process; the
 * mount-namespace allow-list forge uses externally is not available to a
 * process sandboxing itself (it requires privileges the target does not
 * have post-exec).  Rather than install a filter that enforces less than
 * the profile claims, refuse: the operator should use
 * `forge cap run --allow-only ...`, which is stronger anyway. */
void march_sandbox_install(void) {
    fprintf(stderr,
            "march: --cap-sandbox is not implemented on this platform; use "
            "`forge cap run --allow-only ...` for external enforcement\n");
    exit(70);
}

#endif /* __APPLE__ */

#else /* !MARCH_CAP_PROFILE */

void march_sandbox_install(void) { /* not compiled with --cap-sandbox */ }

#endif /* MARCH_CAP_PROFILE */
