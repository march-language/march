/* Force-included (`cc -include vault_lock_probe.h`) into every translation
 * unit of test_vault_write_scale_runner, runtime sources included, and into
 * nothing else.  It routes every pthread_mutex_lock in those files through
 * vault_probe_mutex_lock (defined in test_vault_write_scale.c), which counts
 * acquisitions per mutex address while a probed write is running.
 *
 * Deliberately includes NOTHING: the runtime sources pick their own feature
 * macros (_GNU_SOURCE in some, _XOPEN_SOURCE 700 in others) before their
 * first system header, and including <pthread.h> here would lock glibc's
 * choice in first (CPU_ZERO then vanishes from march_scheduler.c).  The
 * macro is object-like, so <pthread.h>'s own prototype, read later under
 * each file's own feature macros, declares the probe instead. */
#ifndef VAULT_LOCK_PROBE_H
#define VAULT_LOCK_PROBE_H
#define pthread_mutex_lock vault_probe_mutex_lock
#endif
