(* =================================================================
   Emitter: writes runtime/march_cap_lattice.{h,c} from Cap_lattice.hierarchy.

   Usage: emit_c_table.exe <out_dir> [file_prefix]
   Writes <out_dir>/<file_prefix>march_cap_lattice.h and
   <out_dir>/<file_prefix>march_cap_lattice.c (file_prefix defaults to "",
   giving the plain march_cap_lattice.{h,c} names used in runtime/; the
   freshness check in test/dune passes a prefix so the regenerated copy
   doesn't collide with the checked-in one when both are dune deps in the
   same directory).

   The generated files are checked in to runtime/ (see the CAS
   runtime_identity digest in lib/cas/cas.ml, which hashes every
   runtime/*.c and *.h into the compiled-binary cache key — a generated
   file must physically exist there at link time, generate-at-build-time
   into a build directory is not an option).

   Regenerate with:
     dune build --root . lib/caps/emit_c_table.exe
     ./_build/default/lib/caps/emit_c_table.exe runtime

   A freshness check (test/dune, "cap lattice freshness") regenerates into
   a scratch dir and diffs against the committed copy in CI, so the two
   can never silently drift apart.
   ================================================================= *)

let header_banner = "\
/* =================================================================\n\
 * DO NOT EDIT --- this file is GENERATED from lib/caps/cap_lattice.ml\n\
 * by lib/caps/emit_c_table.ml.\n\
 *\n\
 * Regenerate with:\n\
 *   dune build --root . lib/caps/emit_c_table.exe\n\
 *   ./_build/default/lib/caps/emit_c_table.exe runtime\n\
 *\n\
 * A CI freshness check (test/dune) regenerates and diffs this file\n\
 * against the committed copy; edits made here will be silently\n\
 * overwritten and will fail that check until regenerated.\n\
 * ================================================================= */\n\n"

(* Escape a string for embedding in a C string literal.  Cap paths are
   plain identifiers (letters, digits, dots) in practice, but escape
   defensively anyway. *)
let c_string_literal s =
  let buf = Buffer.create (String.length s + 2) in
  Buffer.add_char buf '"';
  String.iter (fun c ->
    match c with
    | '"' -> Buffer.add_string buf "\\\""
    | '\\' -> Buffer.add_string buf "\\\\"
    | c -> Buffer.add_char buf c
  ) s;
  Buffer.add_char buf '"';
  Buffer.contents buf

let emit_header () =
  let buf = Buffer.create 2048 in
  Buffer.add_string buf header_banner;
  Buffer.add_string buf "#ifndef MARCH_CAP_LATTICE_H\n";
  Buffer.add_string buf "#define MARCH_CAP_LATTICE_H\n\n";
  Buffer.add_string buf "/* Number of entries in the capability hierarchy table. */\n";
  Buffer.add_string buf (Printf.sprintf "extern const int march_cap_lattice_size;\n\n");
  Buffer.add_string buf "/* Returns 1 if `parent` subsumes `child` (parent is an ancestor of\n";
  Buffer.add_string buf " * child, or parent == child), else 0.  Caps not present in the\n";
  Buffer.add_string buf " * hierarchy table (e.g. FFI caps like \"LibC\") are their own root:\n";
  Buffer.add_string buf " * they subsume only themselves.\n";
  Buffer.add_string buf " * Mirrors OCaml Cap_lattice.cap_subsumes. */\n";
  Buffer.add_string buf "int march_cap_subsumes(const char *parent, const char *child);\n\n";
  Buffer.add_string buf "/* Drops any cap in `in_caps` (length `n`) that is subsumed by another\n";
  Buffer.add_string buf " * cap in the same array, preserving relative order of the caps that\n";
  Buffer.add_string buf " * remain.  Writes the surviving caps (borrowed pointers into `in_caps`,\n";
  Buffer.add_string buf " * not copied) into `out_caps`, which must have room for at least `n`\n";
  Buffer.add_string buf " * entries.  Returns the number of surviving caps.\n";
  Buffer.add_string buf " * Mirrors OCaml Cap_lattice.normalize. */\n";
  Buffer.add_string buf "int march_cap_normalize(const char **in_caps, int n, const char **out_caps);\n\n";
  Buffer.add_string buf "#endif /* MARCH_CAP_LATTICE_H */\n";
  Buffer.contents buf

let emit_source hierarchy =
  let buf = Buffer.create 4096 in
  Buffer.add_string buf header_banner;
  Buffer.add_string buf "#include \"march_cap_lattice.h\"\n";
  Buffer.add_string buf "#include <string.h>\n\n";
  Buffer.add_string buf "typedef struct {\n";
  Buffer.add_string buf "  const char *path;\n";
  Buffer.add_string buf "  const char *parent; /* NULL if this is a root */\n";
  Buffer.add_string buf "} march_cap_entry_t;\n\n";
  Buffer.add_string buf "static const march_cap_entry_t march_cap_lattice[] = {\n";
  List.iter (fun (path, parent) ->
    let parent_lit = match parent with
      | None -> "NULL"
      | Some p -> c_string_literal p
    in
    Buffer.add_string buf
      (Printf.sprintf "  { %s, %s },\n" (c_string_literal path) parent_lit)
  ) hierarchy;
  Buffer.add_string buf "};\n\n";
  Buffer.add_string buf
    (Printf.sprintf "const int march_cap_lattice_size = %d;\n\n"
       (List.length hierarchy));
  Buffer.add_string buf "/* Looks up `path` in the static table; returns its parent (or NULL if\n";
  Buffer.add_string buf " * `path` is a root, or if `path` is not present in the table at all). */\n";
  Buffer.add_string buf "static const char *march_cap_parent(const char *path) {\n";
  Buffer.add_string buf "  int i;\n";
  Buffer.add_string buf "  for (i = 0; i < march_cap_lattice_size; i++) {\n";
  Buffer.add_string buf "    if (strcmp(march_cap_lattice[i].path, path) == 0) {\n";
  Buffer.add_string buf "      return march_cap_lattice[i].parent;\n";
  Buffer.add_string buf "    }\n";
  Buffer.add_string buf "  }\n";
  Buffer.add_string buf "  return NULL;\n";
  Buffer.add_string buf "}\n\n";
  Buffer.add_string buf "int march_cap_subsumes(const char *parent, const char *child) {\n";
  Buffer.add_string buf "  const char *cur = child;\n";
  Buffer.add_string buf "  /* Walk cur's ancestor chain (cur, then parent-of-cur, ...), mirroring\n";
  Buffer.add_string buf "   * Cap_lattice.cap_ancestors, looking for an exact match with `parent`. */\n";
  Buffer.add_string buf "  while (cur != NULL) {\n";
  Buffer.add_string buf "    if (strcmp(cur, parent) == 0) {\n";
  Buffer.add_string buf "      return 1;\n";
  Buffer.add_string buf "    }\n";
  Buffer.add_string buf "    cur = march_cap_parent(cur);\n";
  Buffer.add_string buf "  }\n";
  Buffer.add_string buf "  return 0;\n";
  Buffer.add_string buf "}\n\n";
  Buffer.add_string buf "int march_cap_normalize(const char **in_caps, int n, const char **out_caps) {\n";
  Buffer.add_string buf "  int out_n = 0;\n";
  Buffer.add_string buf "  int i, j;\n";
  Buffer.add_string buf "  for (i = 0; i < n; i++) {\n";
  Buffer.add_string buf "    int subsumed = 0;\n";
  Buffer.add_string buf "    for (j = 0; j < n; j++) {\n";
  Buffer.add_string buf "      if (j == i) continue;\n";
  Buffer.add_string buf "      if (strcmp(in_caps[j], in_caps[i]) == 0) continue;\n";
  Buffer.add_string buf "      if (march_cap_subsumes(in_caps[j], in_caps[i])) {\n";
  Buffer.add_string buf "        subsumed = 1;\n";
  Buffer.add_string buf "        break;\n";
  Buffer.add_string buf "      }\n";
  Buffer.add_string buf "    }\n";
  Buffer.add_string buf "    if (!subsumed) {\n";
  Buffer.add_string buf "      out_caps[out_n++] = in_caps[i];\n";
  Buffer.add_string buf "    }\n";
  Buffer.add_string buf "  }\n";
  Buffer.add_string buf "  return out_n;\n";
  Buffer.add_string buf "}\n";
  Buffer.contents buf

let write_file path contents =
  let oc = open_out_bin path in
  output_string oc contents;
  close_out oc

let () =
  let out_dir =
    if Array.length Sys.argv > 1 then Sys.argv.(1)
    else "runtime"
  in
  let file_prefix =
    if Array.length Sys.argv > 2 then Sys.argv.(2)
    else ""
  in
  let h = emit_header () in
  let c = emit_source March_caps.Cap_lattice.hierarchy in
  write_file (Filename.concat out_dir (file_prefix ^ "march_cap_lattice.h")) h;
  write_file (Filename.concat out_dir (file_prefix ^ "march_cap_lattice.c")) c
