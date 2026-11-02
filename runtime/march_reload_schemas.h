/* Activated schema metadata. Only the reload thread mutates this table.
 * JSON is copied from the loaded image, never from an operator sidecar. */
#ifndef MARCH_RELOAD_SCHEMAS_H
#define MARCH_RELOAD_SCHEMAS_H
#include <ctype.h>
#include <dirent.h>
/* Non-HCR executables and runtime shared libraries have no embedded metadata.
 * Weak definitions keep those libraries self-contained on Mach-O too; a hot
 * reload binary's strong compiler-generated globals replace these sentinels. */
__attribute__((weak)) const char __march_hcr_schemas[] = "";
__attribute__((weak)) const char __march_hcr_manifest[] = "";

typedef struct schema_entry {
    char *name, *json;
    unsigned long long seq;
    char release[40];
    struct schema_entry *next;
} schema_entry;
static schema_entry *g_schemas;
static int g_schemas_known;

static const char *schema_ws(const char *p) {
    while (isspace((unsigned char)*p)) p++;
    return p;
}
/* A bounded recursive JSON scanner. Preserves schema bytes without trying to
 * reinterpret the compiler's schema vocabulary. */
static const char *schema_string_end(const char *p) {
    if (*p++ != '"') return NULL;
    while (*p && *p != '"') {
        if ((unsigned char)*p < 32) return NULL;
        if (*p++ == '\\') {
            if (!*p) return NULL;
            if (*p == 'u') {
                p++;
                for (int i = 0; i < 4; i++) if (!isxdigit((unsigned char)*p++)) return NULL;
            } else if (!strchr("\"\\/bfnrt", *p++)) return NULL;
        }
    }
    return *p == '"' ? p + 1 : NULL;
}
static const char *schema_value_end(const char *p, int depth) {
    p = schema_ws(p);
    if (depth > 64) return NULL;
    if (*p == '"') return schema_string_end(p);
    if (*p == '{' || *p == '[') {
        int obj = *p == '{'; char end = obj ? '}' : ']';
        p = schema_ws(p + 1);
        if (*p == end) return p + 1;
        for (;;) {
            if (obj) {
                p = schema_string_end(p); if (!p) return NULL;
                p = schema_ws(p); if (*p++ != ':') return NULL;
            }
            p = schema_value_end(p, depth + 1); if (!p) return NULL;
            p = schema_ws(p);
            if (*p == end) return p + 1;
            if (*p++ != ',') return NULL;
            p = schema_ws(p);
        }
    }
    if (!strncmp(p, "true", 4)) return p + 4;
    if (!strncmp(p, "false", 5)) return p + 5;
    if (!strncmp(p, "null", 4)) return p + 4;
    if (*p == '-') p++;
    if (*p == '0') p++;
    else { if (*p < '1' || *p > '9') return NULL; while (isdigit((unsigned char)*p)) p++; }
    if (*p == '.') { p++; if (!isdigit((unsigned char)*p)) return NULL; while (isdigit((unsigned char)*p)) p++; }
    if (*p == 'e' || *p == 'E') { p++; if (*p == '+' || *p == '-') p++; if (!isdigit((unsigned char)*p)) return NULL; while (isdigit((unsigned char)*p)) p++; }
    return p;
}
static void schemas_free(schema_entry *s) {
    while (s) { schema_entry *n = s->next; free(s->name); free(s->json); free(s); s = n; }
}
static int schema_dispatch_matches(const char *actor, const char *fn) {
    for (; *actor; actor++, fn++) {
        if (!*fn || (*actor != *fn && !(*actor == '.' && *fn == '_'))) return 0;
    }
    return strcmp(fn, "_dispatch") == 0;
}
/* Parse all base actors, or only the actor whose dispatch is being activated.
 * NULL metadata is supported for old images, but never clears a known schema. */
static int schemas_extract(schema_entry **out, const char *json,
                           const char *fn, unsigned long long seq, const char *release) {
    if (!json) return 1;
    const char *p = schema_ws(json), *end = schema_value_end(p, 0);
    if (*p != '{' || !end || *schema_ws(end)) return 0;
    p = schema_ws(p + 1);
    while (*p != '}') {
        const char *key = p + 1, *ke = schema_string_end(p);
        if (!ke) return 0;
        /* Actor identifiers cannot contain JSON escapes. */
        size_t kn = (size_t)(ke - key - 1);
        if (memchr(key, '\\', kn)) return 0;
        char *name = strndup(key, kn);
        if (!name) return 0;
        p = schema_ws(schema_ws(ke) + 1);
        end = schema_value_end(p, 0);
        if (*p != '{' || !end) { free(name); return 0; }
        if (!fn || schema_dispatch_matches(name, fn)) {
            schema_entry *s = calloc(1, sizeof(*s));
            if (!s) { free(name); return 0; }
            s->name = name; s->json = strndup(p, (size_t)(end - p));
            s->seq = seq;
            snprintf(s->release, sizeof(s->release), "%s", release && release[0] ? release : "-");
            if (!s->json) { schemas_free(s); return 0; }
            s->next = *out; *out = s;
        } else free(name);
        p = schema_ws(end);
        if (*p == ',') p = schema_ws(p + 1);
    }
    return 1;
}
static void schemas_merge(schema_entry *updates) {
    while (updates) {
        schema_entry *s = updates; updates = s->next;
        schema_entry **p = &g_schemas;
        while (*p && strcmp((*p)->name, s->name)) p = &(*p)->next;
        if (*p) { schema_entry *old = *p; *p = old->next; old->next = NULL; schemas_free(old); }
        s->next = g_schemas; g_schemas = s;
    }
}
static int schemas_shadowed(const schema_entry *s, const schema_entry *updates) {
    for (; updates; updates = updates->next) if (!strcmp(s->name, updates->name)) return 1;
    return 0;
}
static void schemas_json(FILE *f, const schema_entry *updates) {
    fputs("{\"version\":1,\"schemas\":{", f);
    for (int field = 0; field < 2; field++) {
        int comma = 0;
        for (int pass = 0; pass < 2; pass++) {
            for (const schema_entry *s = pass ? g_schemas : updates; s; s = s->next) {
                if (pass && schemas_shadowed(s, updates)) continue;
                if (comma++) fputc(',', f);
                json_write_str(f, s->name, strlen(s->name)); fputc(':', f);
                if (field == 0) {
                    /* Remove formatting whitespace outside JSON strings. */
                    int quoted = 0, escaped = 0;
                    for (const char *p = s->json; *p; p++) {
                        if (quoted || !isspace((unsigned char)*p)) fputc(*p, f);
                        if (!escaped && *p == '"') quoted = !quoted;
                        if (quoted && !escaped && *p == '\\') escaped = 1; else escaped = 0;
                    }
                } else {
                    fprintf(f, "{\"seq\":%llu,\"id\":", s->seq);
                    json_write_str(f, s->release, strlen(s->release)); fputc('}', f);
                }
            }
        }
        fputs(field == 0 ? "},\"releases\":{" : "}}", f);
    }
}
/* Prepare durable bytes before publishing code, so a denied reload write
 * cannot advance either code or baseline. The snapshot is diagnostic only:
 * restart reconstructs metadata from the signature-verified patch stack. */
static int schemas_prepare(const schema_entry *updates) {
    if (!g_state_dir[0]) return 1;
    if (!prepare_state_directory()) return 0;
    char path[820]; snprintf(path, sizeof(path), "%s/schemas.json.tmp", g_state_dir);
    FILE *f = fopen(path, "w"); if (!f) return 0;
    schemas_json(f, updates); fputc('\n', f);
    int ok = !ferror(f) && fflush(f) == 0;
    if (ok) ok = fsync(fileno(f)) == 0;
    ok = fclose(f) == 0 && ok;
    if (!ok) unlink(path);
    return ok;
}
static void schemas_finish(int commit) {
    if (!g_state_dir[0]) return;
    char src[820], dst[820];
    snprintf(src, sizeof(src), "%s/schemas.json.tmp", g_state_dir);
    snprintf(dst, sizeof(dst), "%s/schemas.json", g_state_dir);
    if (commit) {
        if (rename(src, dst) != 0 || !sync_directory(g_state_dir)) persistence_fatal();
    } else unlink(src);
}
/* Keep exact image metadata beside its activated stack records. These files
 * are inspectable provenance, not replay authority: replay always rechecks the
 * artifact digest and extracts the image globals again. */
static int schema_image_prepare(const char *cas, const char *json, const char *manifest) {
    if (!g_state_dir[0] || !json) return 1;
    const char *suffixes[] = {"schemas.json", "manifest"};
    const char *contents[] = {json, manifest ? manifest : ""};
    for (int i = 0; i < 2; i++) {
        char path[920];
        snprintf(path, sizeof(path), "%s/artifact-%s.%s.tmp", g_state_dir, cas, suffixes[i]);
        FILE *f = fopen(path, "w"); if (!f) return 0;
        int ok = fputs(contents[i], f) >= 0 && fflush(f) == 0;
        if (ok) ok = fsync(fileno(f)) == 0;
        ok = fclose(f) == 0 && ok;
        if (!ok) return 0;
    }
    return 1;
}
static void schema_image_finish(const char *cas, int commit) {
    if (!g_state_dir[0]) return;
    const char *suffixes[] = {"schemas.json", "manifest"};
    for (int i = 0; i < 2; i++) {
        char path[920], tmp[928];
        snprintf(path, sizeof(path), "%s/artifact-%s.%s", g_state_dir, cas, suffixes[i]);
        snprintf(tmp, sizeof(tmp), "%s.tmp", path);
        if (commit) { if (rename(tmp, path) != 0) persistence_fatal(); }
        else unlink(tmp);
    }
    if (commit && !sync_directory(g_state_dir)) persistence_fatal();
}
static void schema_images_prune(void) {
    if (!g_state_dir[0]) return;
    DIR *dir = opendir(g_state_dir); if (!dir) return;
    struct dirent *ent;
    while ((ent = readdir(dir))) {
        const char *name = ent->d_name;
        if (strncmp(name, "artifact-", 9) || strlen(name) < 74) continue;
        char cas[65]; memcpy(cas, name + 9, 64); cas[64] = '\0';
        const char *suffix = name + 73;
        if (!is_hex64(cas) || (strcmp(suffix, ".schemas.json") && strcmp(suffix, ".manifest") &&
            strcmp(suffix, ".schemas.json.tmp") && strcmp(suffix, ".manifest.tmp"))) continue;
        int keep = 0;
        for (size_t i = 0; i < g_stack_n; i++)
            if (g_stack[i].cas_hash && !strcmp(g_stack[i].cas_hash, cas)) { keep = 1; break; }
        if (!keep) {
            char path[1100]; snprintf(path, sizeof(path), "%s/%s", g_state_dir, name);
            unlink(path);
        }
    }
    closedir(dir);
}
static void schemas_reply(int fd) {
    if (!g_schemas_known) { wresp(fd, "ERR schemas_unavailable\n"); return; }
    char *buf = NULL; size_t n = 0;
    FILE *f = open_memstream(&buf, &n);
    if (!f) { wresp(fd, "ERR oom\n"); return; }
    fputs("SCHEMAS ", f); schemas_json(f, NULL); fputc('\n', f);
    if (fclose(f) == 0) {
        size_t sent = 0;
#ifdef SO_NOSIGPIPE
        int no_sigpipe = 1;
        if (fd >= 0) setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &no_sigpipe, sizeof(no_sigpipe));
#endif
        while (sent < n) {
            size_t chunk = n - sent;
            if (chunk > 65536) chunk = 65536;
            ssize_t written;
#ifdef MSG_NOSIGNAL
            written = fd >= 0 ? send(fd, buf + sent, chunk, MSG_NOSIGNAL)
                              : rl_write(fd, buf + sent, chunk);
#else
            written = rl_write(fd, buf + sent, chunk);
#endif
            if (written < 0 && errno == EINTR) continue;
            if (written <= 0) {
                /* A truncated reply must become EOF, not leave its reader
                 * waiting indefinitely for a newline that will never arrive. */
                if (fd >= 0) shutdown(fd, SHUT_RDWR);
                break;
            }
            sent += (size_t)written;
        }
    }
    free(buf);
}
#endif
