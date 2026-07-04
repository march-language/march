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

#ifndef MARCH_CAP_LATTICE_H
#define MARCH_CAP_LATTICE_H

/* Number of entries in the capability hierarchy table. */
extern const int march_cap_lattice_size;

/* Returns 1 if `parent` subsumes `child` (parent is an ancestor of
 * child, or parent == child), else 0.  Caps not present in the
 * hierarchy table (e.g. FFI caps like "LibC") are their own root:
 * they subsume only themselves.
 * Mirrors OCaml Cap_lattice.cap_subsumes. */
int march_cap_subsumes(const char *parent, const char *child);

/* Drops any cap in `in_caps` (length `n`) that is subsumed by another
 * cap in the same array, preserving relative order of the caps that
 * remain.  Writes the surviving caps (borrowed pointers into `in_caps`,
 * not copied) into `out_caps`, which must have room for at least `n`
 * entries.  Returns the number of surviving caps.
 * Mirrors OCaml Cap_lattice.normalize. */
int march_cap_normalize(const char **in_caps, int n, const char **out_caps);

#endif /* MARCH_CAP_LATTICE_H */
