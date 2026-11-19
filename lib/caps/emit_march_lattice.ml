(* =================================================================
   Emitter: writes the capability lattice into stdlib/authority.march as
   a March function, from Cap_lattice.hierarchy (the one source of truth,
   which runtime/march_cap_lattice.{h,c} are generated from too; see
   emit_c_table.ml).

   The run-time policy (ocap phase 4, specs/plans/2026-11-15-ocap-p4-
   runtime-plan.md, decision 1) lives in March, so `Authority.admits`
   needs the lattice as March code.  The block sits between two marker
   lines in authority.march; everything between them (markers included)
   is replaced.

   Usage: emit_march_lattice.exe <in authority.march> <out file>
   Reads <in>, replaces the block, writes <out> (which may be <in>).

   Regenerate with:
     dune build --root . lib/caps/emit_march_lattice.exe
     ./_build/default/lib/caps/emit_march_lattice.exe \
       stdlib/authority.march stdlib/authority.march

   A freshness check (test/dune, "cap lattice freshness (March)")
   regenerates into the build dir and diffs against the committed file.
   ================================================================= *)

let begin_marker = "-- BEGIN GENERATED capability lattice"
let end_marker = "-- END GENERATED capability lattice"

let march_string s =
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

let block (hierarchy : (string * string option) list) : string list =
  let rows =
    List.filter_map
      (fun (path, parent) ->
         Option.map
           (fun p -> Printf.sprintf "    %s -> %s" (march_string path) (march_string p))
           parent)
      hierarchy
  in
  [ "  " ^ begin_marker ^ ": written by lib/caps/emit_march_lattice.ml";
    "  -- from lib/caps/cap_lattice.ml; do not edit by hand. Regenerate with";
    "  --   dune build --root . lib/caps/emit_march_lattice.exe";
    "  --   ./_build/default/lib/caps/emit_march_lattice.exe stdlib/authority.march stdlib/authority.march";
    "  -- A capability's parent in the lattice, \"\" for a root (and for a";
    "  -- capability outside the table, such as an FFI root: its own root).";
    "  pfn lattice_parent(kind : String) : String do";
    "    match kind do" ]
  @ rows
  @ [ "    _ -> \"\""; "    end"; "  end"; "  " ^ end_marker ]

let contains (s : string) (sub : string) : bool =
  let n = String.length s and m = String.length sub in
  let rec go i = i + m <= n && (String.sub s i m = sub || go (i + 1)) in
  go 0

let read_lines path =
  let ic = open_in_bin path in
  let rec go acc =
    match input_line ic with
    | l -> go (l :: acc)
    | exception End_of_file -> close_in ic; List.rev acc
  in
  go []

let replace_block (lines : string list) (gen : string list) : string list =
  let rec before acc = function
    | [] -> failwith ("emit_march_lattice: no line containing `" ^ begin_marker ^ "`")
    | l :: rest when contains l begin_marker -> (List.rev acc, rest)
    | l :: rest -> before (l :: acc) rest
  in
  let rec after = function
    | [] -> failwith ("emit_march_lattice: no line containing `" ^ end_marker ^ "`")
    | l :: rest when contains l end_marker -> rest
    | _ :: rest -> after rest
  in
  let pre, rest = before [] lines in
  pre @ gen @ after rest

let () =
  if Array.length Sys.argv <> 3 then begin
    prerr_endline "usage: emit_march_lattice.exe <in authority.march> <out file>";
    exit 2
  end;
  let lines = read_lines Sys.argv.(1) in
  let out = replace_block lines (block March_caps.Cap_lattice.hierarchy) in
  let oc = open_out_bin Sys.argv.(2) in
  List.iter (fun l -> output_string oc l; output_char oc '\n') out;
  close_out oc
