/* =================================================================
 * DO NOT EDIT --- this file is GENERATED from lib/caps/cap_lattice.ml
 * and lib/caps/cap_scope.ml by lib/caps/emit_c_lattice.ml.
 *
 * Regenerate with:
 *   dune build --root . lib/caps/emit_c_lattice.exe
 *   ./_build/default/lib/caps/emit_c_lattice.exe runtime/march_authority_tables.h
 *
 * A CI freshness check (test/dune) regenerates and diffs this file.
 * ================================================================= */

#ifndef MARCH_AUTHORITY_TABLES_H
#define MARCH_AUTHORITY_TABLES_H

/* A capability and its parent in the lattice.  A capability absent from
 * this table (a root, or one outside it such as an FFI root) has none.
 * Each name carries its length, so a lookup compares lengths first. */
static const struct { const char *kind; int kind_len; const char *parent; int parent_len; }
march_auth_parent_table[] = {
  { "IO.Console", 10, "IO", 2 },
  { "IO.FileSystem", 13, "IO", 2 },
  { "IO.FileRead", 11, "IO.FileSystem", 13 },
  { "IO.FileWrite", 12, "IO.FileSystem", 13 },
  { "IO.Network", 10, "IO", 2 },
  { "IO.NetConnect", 13, "IO.Network", 10 },
  { "IO.NetListen", 12, "IO.Network", 10 },
  { "IO.Process", 10, "IO", 2 },
  { "IO.Clock", 8, "IO", 2 },
  { "IO.Random", 9, "IO", 2 },
  { "IO.Signal", 9, "IO", 2 },
  { "IO.Database", 11, "IO.NetConnect", 13 },
  { "IO.Spawn", 8, "IO", 2 },
  { "IO.Mut", 6, "IO", 2 },
  { "IO.Telemetry", 12, "IO", 2 },
  { "IO.NetConnect.TLS", 17, "IO.NetConnect", 13 },
  { "IO.WebSocket", 12, "IO.NetConnect", 13 },
  { "IO.Foreign", 10, "IO", 2 },
  { "IO.Foreign.Blocking", 19, "IO.Foreign", 10 },
  { "IO.Registry", 11, "IO", 2 },
};
#define MARCH_AUTH_N_PARENTS 20

/* Capabilities that take a path scope (Cap_scope.is_scopable, not host or name). */
static const struct { const char *kind; int len; } march_auth_path_kinds[] = {
  { "IO.FileSystem", 13 },
  { "IO.FileRead", 11 },
  { "IO.FileWrite", 12 },
  { 0, 0 }
};

/* Capabilities that take a host scope (Cap_scope.is_host_scopable). */
static const struct { const char *kind; int len; } march_auth_host_kinds[] = {
  { "IO.NetConnect", 13 },
  { 0, 0 }
};

/* Capabilities that take a name scope (Cap_scope.is_name_scopable). */
static const struct { const char *kind; int len; } march_auth_name_kinds[] = {
  { "IO.Mut", 6 },
  { "IO.Registry", 11 },
  { 0, 0 }
};

/* Header type ids of the March types the C policy builds (march_runtime.h,
 * "What the header pad word means"). */
#define MARCH_AUTH_TID_LIST (-220805026) /* List */
#define MARCH_AUTH_TID_RESULT (-273346629) /* Result */
#define MARCH_AUTH_TID_LAYER (-184861742) /* Authority.Layer */
#define MARCH_AUTH_TID_SCOPE (-539569765) /* Authority.CapEntry */
#define MARCH_AUTH_TID_ARG (-87892741) /* Authority.Arg */
#define MARCH_AUTH_TID_LIMIT (-546513735) /* CapLimit */
#define MARCH_AUTH_TID_CAPERR (-440949316) /* CapError */

#endif /* MARCH_AUTHORITY_TABLES_H */
