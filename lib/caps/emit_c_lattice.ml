(* =================================================================
   Emitter: writes runtime/march_authority_tables.h, the tables the C
   run-time authority (runtime/march_authority.c) judges with: the
   capability lattice and which capabilities take a path, a host or a name
   scope.  Generated from Cap_lattice.hierarchy and Cap_scope, the same
   source of truth stdlib/authority.march's lattice block
   (emit_march_lattice.ml) and runtime/march_cap_lattice.{h,c}
   (emit_c_table.ml) come from.

   Native and JIT programs judge capability operations with the C copy of
   the policy (ocap phase 4, Task 4b); the interpreter and JS with the
   March one.  Both read their tables from here, so they cannot drift.

   Usage: emit_c_lattice.exe <out file>

   Regenerate with:
     dune build --root . lib/caps/emit_c_lattice.exe
     ./_build/default/lib/caps/emit_c_lattice.exe runtime/march_authority_tables.h

   A freshness check (test/dune, "authority tables freshness") regenerates
   into the build dir and diffs against the committed copy.
   ================================================================= *)

let c_string s =
  let b = Buffer.create (String.length s + 2) in
  Buffer.add_char b '"';
  String.iter
    (function
      | '"' -> Buffer.add_string b "\\\""
      | '\\' -> Buffer.add_string b "\\\\"
      | c -> Buffer.add_char b c)
    s;
  Buffer.add_char b '"';
  Buffer.contents b

(* The header type id the compiler stamps on a constructor cell of type
   [name] (Llvm_ctx.type_id_of_name, runtime march_type_id_of_name): the C
   policy stamps the cells it builds the same way, as constants. *)
let type_id_of_name (name : string) : int =
  let h = ref 0x811c9dc5 in
  String.iter (fun c ->
      h := (!h lxor Char.code c) land 0xFFFFFFFF;
      h := (!h * 0x01000193) land 0xFFFFFFFF)
    name;
  - (1 + (!h land 0x3FFFFFFF))

let header (hierarchy : (string * string option) list) : string =
  let b = Buffer.create 2048 in
  let p fmt = Printf.bprintf b fmt in
  p "/* =================================================================\n";
  p " * DO NOT EDIT --- this file is GENERATED from lib/caps/cap_lattice.ml\n";
  p " * and lib/caps/cap_scope.ml by lib/caps/emit_c_lattice.ml.\n";
  p " *\n";
  p " * Regenerate with:\n";
  p " *   dune build --root . lib/caps/emit_c_lattice.exe\n";
  p " *   ./_build/default/lib/caps/emit_c_lattice.exe runtime/march_authority_tables.h\n";
  p " *\n";
  p " * A CI freshness check (test/dune) regenerates and diffs this file.\n";
  p " * ================================================================= */\n\n";
  p "#ifndef MARCH_AUTHORITY_TABLES_H\n#define MARCH_AUTHORITY_TABLES_H\n\n";
  p "/* A capability and its parent in the lattice.  A capability absent from\n";
  p " * this table (a root, or one outside it such as an FFI root) has none.\n";
  p " * Each name carries its length, so a lookup compares lengths first. */\n";
  p "static const struct { const char *kind; int kind_len; const char *parent; int parent_len; }\n";
  p "march_auth_parent_table[] = {\n";
  let rows = List.filter_map (fun (k, par) -> Option.map (fun x -> (k, x)) par) hierarchy in
  List.iter (fun (k, par) ->
      p "  { %s, %d, %s, %d },\n" (c_string k) (String.length k) (c_string par) (String.length par))
    rows;
  p "};\n";
  p "#define MARCH_AUTH_N_PARENTS %d\n\n" (List.length rows);
  let kinds pred = List.filter pred (List.map fst hierarchy) in
  let table name doc ks =
    p "/* %s */\n" doc;
    p "static const struct { const char *kind; int len; } %s[] = {\n" name;
    List.iter (fun k -> p "  { %s, %d },\n" (c_string k) (String.length k)) ks;
    p "  { 0, 0 }\n};\n\n"
  in
  let open March_caps.Cap_scope in
  table "march_auth_path_kinds" "Capabilities that take a path scope (Cap_scope.is_scopable, not host or name)."
    (kinds (fun k -> is_scopable k && not (is_host_scopable k) && not (is_name_scopable k)));
  table "march_auth_host_kinds" "Capabilities that take a host scope (Cap_scope.is_host_scopable)."
    (kinds is_host_scopable);
  table "march_auth_name_kinds" "Capabilities that take a name scope (Cap_scope.is_name_scopable)."
    (kinds is_name_scopable);
  p "/* Header type ids of the March types the C policy builds (march_runtime.h,\n";
  p " * \"What the header pad word means\"). */\n";
  List.iter (fun (macro, name) -> p "#define %s (%d) /* %s */\n" macro (type_id_of_name name) name)
    [ ("MARCH_AUTH_TID_LIST", "List"); ("MARCH_AUTH_TID_RESULT", "Result");
      ("MARCH_AUTH_TID_LAYER", "Authority.Layer"); ("MARCH_AUTH_TID_SCOPE", "Authority.CapEntry");
      ("MARCH_AUTH_TID_ARG", "Authority.Arg"); ("MARCH_AUTH_TID_LIMIT", "CapLimit");
      ("MARCH_AUTH_TID_CAPERR", "CapError") ];
  p "\n#endif /* MARCH_AUTHORITY_TABLES_H */\n";
  Buffer.contents b

let () =
  if Array.length Sys.argv <> 2 then begin
    prerr_endline "usage: emit_c_lattice.exe <out file>";
    exit 2
  end;
  let oc = open_out_bin Sys.argv.(1) in
  output_string oc (header March_caps.Cap_lattice.hierarchy);
  close_out oc
