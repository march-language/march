/* march_file_beneath.c — opens beneath a directory handle (File.Dir; ocap
 * phase 2, spec §6 and §15).
 *
 * `File.open_in(dir, rel)` opens `rel` beneath the directory `dir` holds and
 * refuses any path that leaves it.  Two halves:
 *
 *   1. The core (march_beneath_open, march_beneath_open_mode,
 *      march_beneath_list): plain C over a directory fd, returning an fd or
 *      -errno.  It builds no March value, so the interpreter compiles this
 *      same file into its eval library (lib/eval/eval_beneath_stubs.c
 *      #includes it with MARCH_BENEATH_CORE_ONLY defined): both backends run
 *      one implementation.
 *   2. The builtins (march_dir_open, march_dir_open_write, march_file_open_at,
 *      march_dir_list_at): the core plus the Result/FileError cells, built
 *      through helpers march_runtime.c exports.
 *
 * The rule, on every platform, before any syscall: `rel` is refused (EXDEV)
 * when it is empty, absolute, contains a NUL byte, has a `..` that climbs
 * above the directory after lexical normalisation (the rule of
 * lib/caps/cap_scope.ml `segments`, except that a `..` at the top is refused
 * instead of dropped), or normalises to `.`.  `sub/../a.txt` is `a.txt`.
 *
 * Then:
 *   - Linux: openat2(RESOLVE_BENEATH | RESOLVE_NO_MAGICLINKS) on the
 *     normalised path.  The kernel refuses a symlink or `..` that leaves the
 *     directory (EXDEV) and follows one that stays inside.  On ENOSYS (kernel
 *     older than 5.6) it falls back to the walk below.
 *   - macOS, and the fallback: a component walk.  Each intermediate component
 *     is opened with openat(cur, comp, O_DIRECTORY | O_NOFOLLOW) and the last
 *     with O_NOFOLLOW, so a symlink ANYWHERE is refused (ELOOP), even one
 *     that points inside.  Best effort, and stricter than Linux: that is the
 *     documented platform difference.
 *
 * The directory fd follows the inode: renaming the directory after it was
 * opened does not change what `rel` resolves against.
 *
 * Refusals (EXDEV, ELOOP) become FileError `Escapes(rel)`. */
#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/types.h>

#if defined(__linux__)
#include <sys/syscall.h>
#if defined(__has_include)
#if __has_include(<linux/openat2.h>)
#include <linux/openat2.h>
#define MARCH_HAVE_OPENAT2_H 1
#endif
#endif
#if !defined(MARCH_HAVE_OPENAT2_H)
struct open_how { unsigned long long flags, mode, resolve; };
#define RESOLVE_NO_MAGICLINKS 0x02
#define RESOLVE_BENEATH       0x08
#endif
#if !defined(SYS_openat2)
#define SYS_openat2 437   /* the same number on every Linux architecture */
#endif
#endif

#ifndef O_CLOEXEC
#define O_CLOEXEC 0
#endif

/* The march-level flag codes file_open_at takes. */
#define MARCH_BENEATH_READ     0
#define MARCH_BENEATH_TRUNCATE 1
#define MARCH_BENEATH_APPEND   2
#define MARCH_BENEATH_DIR      3   /* internal: a directory to list */

/* Lexically normalise [rel] (length [len]) into a fresh malloc'd string.
 * NULL with errno EXDEV when it is refused (see the header comment), ENOMEM
 * when out of memory. */
static char *beneath_normalize(const char *rel, size_t len) {
    if (len == 0 || rel[0] == '/' || memchr(rel, '\0', len) != NULL) {
        errno = EXDEV;
        return NULL;
    }
    char *out = malloc(len + 1);
    if (!out) { errno = ENOMEM; return NULL; }
    size_t o = 0;          /* bytes written to out */
    size_t i = 0;
    while (i < len) {
        size_t j = i;
        while (j < len && rel[j] != '/') j++;
        size_t n = j - i;
        if (n == 0 || (n == 1 && rel[i] == '.')) {
            /* "//" or "." : nothing */
        } else if (n == 2 && rel[i] == '.' && rel[i + 1] == '.') {
            if (o == 0) { free(out); errno = EXDEV; return NULL; }   /* climbs out */
            /* pop the last segment */
            while (o > 0 && out[o - 1] != '/') o--;
            if (o > 0) o--;   /* its separator */
        } else {
            if (o > 0) out[o++] = '/';
            memcpy(out + o, rel + i, n);
            o += n;
        }
        i = j + 1;
    }
    if (o == 0) { free(out); errno = EXDEV; return NULL; }   /* "." */
    out[o] = '\0';
    return out;
}

/* openat refused a component with O_NOFOLLOW (and maybe O_DIRECTORY).  A
 * symlink is reported as ELOOP whatever the platform said (macOS and Linux
 * disagree on O_DIRECTORY | O_NOFOLLOW over a symlink). */
static int nofollow_errno(int cur, const char *comp, int err) {
    if (err == ELOOP || err == ENOTDIR) {
        struct stat st;
        if (fstatat(cur, comp, &st, AT_SYMLINK_NOFOLLOW) == 0 && S_ISLNK(st.st_mode))
            return ELOOP;
    }
    return err;
}

/* The component walk: every symlink refused.  [norm] is normalised and is
 * modified in place. */
static int beneath_walk(int dirfd, char *norm, int flags, int mode) {
    int cur = dirfd, owned = 0;
    char *p = norm;
    for (;;) {
        char *slash = strchr(p, '/');
        if (!slash) break;
        *slash = '\0';
        int nfd = openat(cur, p, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        int err = nfd < 0 ? nofollow_errno(cur, p, errno) : 0;
        if (owned) close(cur);
        if (nfd < 0) return -err;
        cur = nfd;
        owned = 1;
        p = slash + 1;
    }
    int fd = openat(cur, p, flags | O_NOFOLLOW | O_CLOEXEC, mode);
    int err = fd < 0 ? nofollow_errno(cur, p, errno) : 0;
    if (owned) close(cur);
    return fd < 0 ? -err : fd;
}

/* Open [rel] beneath [dirfd] with open(2) [flags] / [mode].  The fd, or
 * -errno: -EXDEV / -ELOOP when the path is refused for leaving the
 * directory. */
int march_beneath_open(int dirfd, const char *rel, int flags, int mode) {
    char *norm = beneath_normalize(rel, strlen(rel));
    if (!norm) return -errno;
    int r;
#if defined(__linux__)
    {
        struct open_how how;
        memset(&how, 0, sizeof how);
        how.flags = (unsigned long long)(flags | O_CLOEXEC);
        how.mode = (flags & O_CREAT) ? (unsigned long long)mode : 0;
        how.resolve = RESOLVE_BENEATH | RESOLVE_NO_MAGICLINKS;
        long fd = syscall(SYS_openat2, dirfd, norm, &how, sizeof how);
        if (fd >= 0) r = (int)fd;
        /* No openat2 (ENOSYS: kernel < 5.6; EPERM: a seccomp profile that
         * predates it): walk instead.  Never on EXDEV/ELOOP or any other
         * refusal, which is the kernel's answer for this path. */
        else if (errno == ENOSYS || errno == EPERM) r = beneath_walk(dirfd, norm, flags, mode);
        else r = -errno;
    }
#else
    r = beneath_walk(dirfd, norm, flags, mode);
#endif
    free(norm);
    return r;
}

/* As march_beneath_open, for a March string of [len] bytes (a NUL byte inside
 * is refused) and a march flag code. */
int march_beneath_open_mode(int dirfd, const char *rel, size_t len, int64_t code) {
    if (len == 0 || memchr(rel, '\0', len) != NULL) return -EXDEV;
    int flags;
    switch (code) {
    case MARCH_BENEATH_READ:     flags = O_RDONLY; break;
    case MARCH_BENEATH_TRUNCATE: flags = O_WRONLY | O_CREAT | O_TRUNC; break;
    case MARCH_BENEATH_APPEND:   flags = O_WRONLY | O_CREAT | O_APPEND; break;
    case MARCH_BENEATH_DIR:      flags = O_RDONLY | O_DIRECTORY; break;
    default: return -EINVAL;
    }
    return march_beneath_open(dirfd, rel, flags, 0644);
}

static int cmp_names(const void *a, const void *b) {
    return strcmp(*(char *const *)a, *(char *const *)b);
}

void march_beneath_free_names(char **names, int n) {
    for (int i = 0; i < n; i++) free(names[i]);
    free(names);
}

/* The entries of [rel] beneath [dirfd], without "." and "..", sorted.  An
 * empty [rel] lists [dirfd] itself (the one place "" is accepted).  0 with
 * *out / *count set (free with march_beneath_free_names), or -errno. */
int march_beneath_list(int dirfd, const char *rel, size_t len, char ***out, int *count) {
    int fd;
    if (len == 0) {
        /* A fresh open file description, so this listing's offset is its
         * own (a dup would share the handle's). */
        fd = openat(dirfd, ".", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
        if (fd < 0) return -errno;
    } else {
        fd = march_beneath_open_mode(dirfd, rel, len, MARCH_BENEATH_DIR);
        if (fd < 0) return fd;
    }
    DIR *d = fdopendir(fd);
    if (!d) { int e = errno; close(fd); return -e; }
    char **names = NULL;
    int n = 0, cap = 0;
    struct dirent *ent;
    while ((ent = readdir(d)) != NULL) {
        if (strcmp(ent->d_name, ".") == 0 || strcmp(ent->d_name, "..") == 0) continue;
        if (n == cap) {
            int ncap = cap ? cap * 2 : 16;
            char **t = realloc(names, (size_t)ncap * sizeof *t);
            if (!t) { closedir(d); march_beneath_free_names(names, n); return -ENOMEM; }
            names = t;
            cap = ncap;
        }
        names[n] = strdup(ent->d_name);
        if (!names[n]) { closedir(d); march_beneath_free_names(names, n); return -ENOMEM; }
        n++;
    }
    closedir(d);   /* closes fd */
    if (n > 1) qsort(names, (size_t)n, sizeof *names, cmp_names);
    *out = names;
    *count = n;
    return 0;
}

/* Whether -errno [err] from the core means "leaves the directory". */
int march_beneath_is_escape(int err) {
    return err == EXDEV || err == ELOOP;
}

#ifndef MARCH_BENEATH_CORE_ONLY
/* ── The builtins (compiled runtime only) ────────────────────────────── */
#include "march_runtime.h"
#include <stdio.h>

/* How beneath_err maps an errno: an open beneath a dir, a listing beneath
 * one (ENOTDIR is IsDirectory, as dir_list reports it), or dir_open's plain
 * open of a path (no "beneath": ELOOP/EXDEV are an IoError, not Escapes). */
#define BENEATH_OPEN    0
#define BENEATH_LIST    1
#define BENEATH_DIROPEN 2

/* The FileError for -errno [neg] from an operation on [rel] (or [path]):
 * the file_open_write / dir_list mapping of march_runtime.c, plus Escapes. */
static void *beneath_err(int neg, const char *rel, size_t len, int mode) {
    int err = -neg;
    int listing = mode != BENEATH_OPEN;
    if (mode != BENEATH_DIROPEN && march_beneath_is_escape(err))
        return march_file_err(FILEERR_ESCAPES, rel, (int64_t)len);
    switch (err) {
    case ENOENT: return march_file_err(FILEERR_NOT_FOUND, rel, (int64_t)len);
    case EACCES:
    case EPERM:  return march_file_err(FILEERR_PERMISSION, rel, (int64_t)len);
    case EISDIR: return march_file_err(FILEERR_IS_DIRECTORY, rel, (int64_t)len);
    case ENOTDIR:
        if (listing) return march_file_err(FILEERR_IS_DIRECTORY, rel, (int64_t)len);
        /* fallthrough */
    default: {
        char buf[1024];
        int k = snprintf(buf, sizeof buf, "%.*s: %s", (int)len, rel, strerror(err));
        if (k < 0) k = 0;
        if ((size_t)k >= sizeof buf) k = (int)sizeof buf - 1;
        return march_file_err(FILEERR_IO_ERROR, buf, (int64_t)k);
    }
    }
}

/* dir_open(path) / dir_open_write(path) : Result(Int, FileError).  The same
 * open: a write-capable File.Dir differs only in its box's aux word, and the
 * two builtins exist so each is charged its own capability. */
void *march_dir_open(void *path_ptr) {
    march_string *ps = (march_string *)path_ptr;
    /* An embedded NUL would truncate the path open() sees: NotFound, as the
     * interpreter's stub reports it. */
    if (memchr(ps->data, '\0', (size_t)ps->len) != NULL)
        return beneath_err(-ENOENT, ps->data, (size_t)ps->len, BENEATH_DIROPEN);
    int fd = open(ps->data, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (fd < 0) return beneath_err(-errno, ps->data, (size_t)ps->len, BENEATH_DIROPEN);
    /* An Int in a Result payload is tagged (n<<1)|1 (see march_file_seek). */
    return march_file_ok((void *)(intptr_t)(((int64_t)fd << 1) | 1));
}

void *march_dir_open_write(void *path_ptr) {
    return march_dir_open(path_ptr);
}

/* file_open_at(dirfd, rel, flags) : Result(Int, FileError).  flags 0 read,
 * 1 truncate, 2 append (create 0644).  The stream goes into the file handle
 * table, like file_open's, so the File.Handle box closes it. */
void *march_file_open_at(int64_t dirfd, void *rel_ptr, int64_t flags) {
    march_string *rs = (march_string *)rel_ptr;
    if (flags < 0 || flags > 2)
        return march_file_err(FILEERR_IO_ERROR, "file_open_at: bad flags", 23);
    int fd = march_beneath_open_mode((int)dirfd, rs->data, (size_t)rs->len, flags);
    if (fd < 0) return beneath_err(fd, rs->data, (size_t)rs->len, BENEATH_OPEN);
    FILE *f = fdopen(fd, flags == 0 ? "rb" : (flags == 1 ? "wb" : "ab"));
    if (!f) { int e = errno; close(fd); return beneath_err(-e, rs->data, (size_t)rs->len, BENEATH_OPEN); }
    int64_t h = march_fh_register(f);
    if (h == 0) { fclose(f); return beneath_err(-EMFILE, rs->data, (size_t)rs->len, BENEATH_OPEN); }
    return march_file_ok((void *)(intptr_t)h);
}

/* dir_list_at(dirfd, rel) : Result(List(String), FileError), sorted. */
void *march_dir_list_at(int64_t dirfd, void *rel_ptr) {
    march_string *rs = (march_string *)rel_ptr;
    char **names = NULL;
    int n = 0;
    int r = march_beneath_list((int)dirfd, rs->data, (size_t)rs->len, &names, &n);
    if (r < 0) return beneath_err(r, rs->data, (size_t)rs->len, BENEATH_LIST);
    void *lst = march_file_string_list(names, n);
    march_beneath_free_names(names, n);
    return march_file_ok(lst);
}
#endif
