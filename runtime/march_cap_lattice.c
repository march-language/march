/* =================================================================
* DO NOT EDIT --- this file is GENERATED from lib/caps/cap_lattice.ml
* by lib/caps/emit_c_table.ml.
*
* Regenerate with:
*   dune build --root . lib/caps/emit_c_table.exe
*   ./_build/default/lib/caps/emit_c_table.exe runtime
*
* A CI freshness check (test/dune) regenerates and diffs this file
* against the committed copy; edits made here will be silently
* overwritten and will fail that check until regenerated.
* ================================================================= */

#include "march_cap_lattice.h"
#include <string.h>

typedef struct {
  const char *path;
  const char *parent; /* NULL if this is a root */
} march_cap_entry_t;

static const march_cap_entry_t march_cap_lattice[] = {
  { "IO", NULL },
  { "IO.Console", "IO" },
  { "IO.FileSystem", "IO" },
  { "IO.FileRead", "IO.FileSystem" },
  { "IO.FileWrite", "IO.FileSystem" },
  { "IO.Network", "IO" },
  { "IO.NetConnect", "IO.Network" },
  { "IO.NetListen", "IO.Network" },
  { "IO.Process", "IO" },
  { "IO.Clock", "IO" },
  { "IO.Random", "IO" },
  { "IO.Signal", "IO" },
  { "IO.Database", "IO.NetConnect" },
  { "IO.Spawn", "IO" },
  { "IO.Mut", "IO" },
  { "IO.Telemetry", "IO" },
  { "IO.NetConnect.TLS", "IO.NetConnect" },
  { "IO.WebSocket", "IO.NetConnect" },
  { "IO.Foreign", "IO" },
  { "IO.Foreign.Blocking", "IO.Foreign" },
};

const int march_cap_lattice_size = 20;

/* Looks up `path` in the static table; returns its parent (or NULL if
 * `path` is a root, or if `path` is not present in the table at all). */
static const char *march_cap_parent(const char *path) {
  int i;
  for (i = 0; i < march_cap_lattice_size; i++) {
    if (strcmp(march_cap_lattice[i].path, path) == 0) {
      return march_cap_lattice[i].parent;
    }
  }
  return NULL;
}

int march_cap_subsumes(const char *parent, const char *child) {
  const char *cur = child;
  /* Walk cur's ancestor chain (cur, then parent-of-cur, ...), mirroring
   * Cap_lattice.cap_ancestors, looking for an exact match with `parent`. */
  while (cur != NULL) {
    if (strcmp(cur, parent) == 0) {
      return 1;
    }
    cur = march_cap_parent(cur);
  }
  return 0;
}

int march_cap_normalize(const char **in_caps, int n, const char **out_caps) {
  int out_n = 0;
  int i, j;
  for (i = 0; i < n; i++) {
    int subsumed = 0;
    for (j = 0; j < n; j++) {
      if (j == i) continue;
      if (strcmp(in_caps[j], in_caps[i]) == 0) continue;
      if (march_cap_subsumes(in_caps[j], in_caps[i])) {
        subsumed = 1;
        break;
      }
    }
    if (!subsumed) {
      out_caps[out_n++] = in_caps[i];
    }
  }
  return out_n;
}
