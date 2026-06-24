/* march_reload.c — HCR Phase 3 reload server (Linux + macOS, Unix-domain socket).
 *
 * Protocol (newline-terminated text):
 *   PING                              → PONG
 *   ABI_QUERY                         → SLOT <id> <impl_hash>  (one per slot), then END
 *   ACTIVATE <name> <impl_hash> <so>  → OK <impl_hash>  or  ERR <reason>
 */
#if defined(__linux__) || defined(__APPLE__)

#include "march_reload.h"
#include "march_dispatch.h"
#include <pthread.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>
#include <errno.h>

#define RELOAD_BACKLOG  4
#define RELOAD_LINE_MAX 4096

static char g_socket_path[256];

/* Read a newline-terminated line into buf (NUL-terminated, newline stripped).
 * Returns bytes read (>=0), or -1 on error. */
static int read_line(int fd, char *buf, int max) {
    int n = 0;
    while (n < max - 1) {
        char c;
        int r = (int)read(fd, &c, 1);
        if (r <= 0) return r;
        if (c == '\n') break;
        if (c == '\r') continue;  /* handle CRLF from netcat on Windows */
        buf[n++] = c;
    }
    buf[n] = '\0';
    return n;
}

static void handle_client(int fd) {
    char line[RELOAD_LINE_MAX];
    while (1) {
        int r = read_line(fd, line, RELOAD_LINE_MAX);
        if (r <= 0) break;  /* 0 = EOF, negative = read error */

        if (strcmp(line, "PING") == 0) {
            write(fd, "PONG\n", 5);

        } else if (strcmp(line, "ABI_QUERY") == 0) {
            /* Enumerate all slots: SLOT <id> <impl_hash>, then END. */
            for (uint32_t i = 0; i < 65536; i++) {
                uint32_t cur = march_dispatch_current(i);
                const char *h = march_dispatch_impl_hash(i, cur);
                /* march_dispatch_impl_hash returns NULL for out-of-range ids. */
                if (!h) break;
                char resp[192];
                int n = snprintf(resp, sizeof(resp), "SLOT %u %s\n", i,
                                 h[0] ? h : "(none)");
                write(fd, resp, (size_t)n);
            }
            write(fd, "END\n", 4);

        } else if (strncmp(line, "ACTIVATE ", 9) == 0) {
            /* Parse: ACTIVATE <name> <impl_hash> <so_path> */
            char name[256], impl_hash[128], so_path[1024];
            if (sscanf(line + 9, "%255s %127s %1023s", name, impl_hash, so_path) != 3) {
                write(fd, "ERR bad_format\n", 15);
                continue;
            }

            uint32_t slot_id;
            if (!march_dispatch_name_to_id(name, &slot_id)) {
                char resp[512];
                int n = snprintf(resp, sizeof(resp), "ERR unknown_name %s\n", name);
                write(fd, resp, (size_t)n);
                continue;
            }

            void *handle = dlopen(so_path, RTLD_NOW | RTLD_GLOBAL);
            if (!handle) {
                char resp[512];
                int n = snprintf(resp, sizeof(resp), "ERR dlopen_failed %s\n", dlerror());
                write(fd, resp, (size_t)n);
                continue;
            }

            void *fn_ptr = dlsym(handle, name);
            if (!fn_ptr) {
                char resp[512];
                int n = snprintf(resp, sizeof(resp), "ERR dlsym_failed %s\n", name);
                dlclose(handle);
                write(fd, resp, (size_t)n);
                continue;
            }

            int idx = march_dispatch_publish(slot_id, fn_ptr, impl_hash,
                                             (uint8_t)MARCH_NATIVE);
            if (idx < 0) {
                write(fd, "ERR publish_failed all_slots_pinned\n", 36);
                dlclose(handle);
                continue;
            }

            char resp[256];
            int n = snprintf(resp, sizeof(resp), "OK %s\n", impl_hash);
            write(fd, resp, (size_t)n);

        } else {
            write(fd, "ERR unknown_command\n", 20);
        }
    }
    close(fd);
}

static void *reload_server_thread(void *arg) {
    (void)arg;
    int srv = socket(AF_UNIX, SOCK_STREAM, 0);
    if (srv < 0) { perror("march_reload: socket"); return NULL; }

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, g_socket_path, sizeof(addr.sun_path) - 1);

    unlink(g_socket_path);  /* remove stale socket from a prior run */
    if (bind(srv, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        perror("march_reload: bind"); close(srv); return NULL;
    }
    listen(srv, RELOAD_BACKLOG);
    fprintf(stderr, "[hcr] reload server listening on %s\n", g_socket_path);

    while (1) {
        int cli = accept(srv, NULL, NULL);
        if (cli < 0) {
            if (errno == EINTR) continue;
            perror("march_reload: accept");
            break;
        }
        handle_client(cli);  /* serial: one client at a time (sufficient for deploys) */
    }
    unlink(g_socket_path);
    close(srv);
    return NULL;
}

void march_reload_server_start(const char *socket_path) {
    if (!socket_path || socket_path[0] == '\0') return;
    strncpy(g_socket_path, socket_path, sizeof(g_socket_path) - 1);
    g_socket_path[sizeof(g_socket_path) - 1] = '\0';
    pthread_t tid;
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    pthread_create(&tid, &attr, reload_server_thread, NULL);
    pthread_attr_destroy(&attr);
}

#else  /* non-POSIX stub (WASM, Windows, etc.) */

#include "march_reload.h"

void march_reload_server_start(const char *socket_path) {
    (void)socket_path;
    /* No-op on unsupported platforms. */
}

#endif /* __linux__ || __APPLE__ */
