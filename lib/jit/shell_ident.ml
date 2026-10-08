(* lib/jit/shell_ident.ml

   Shell identity (observe plan R5.4): does the code an input reaches match
   the code the node was built from?

   A shell fragment carries its own copy of every function it runs, so it
   never calls into the node's code.  What can still go wrong when the
   operator's checkout differs from the node's build is (a) the fragment runs
   a different version of a function than the node, which returns answers
   that are not the node's, and (b) the two disagree on the constructor tags
   of a type, so a value the fragment builds or reads through the node (an
   actor message, an actor's state) is decoded as the wrong constructor.

   Neither side can reproduce the other's compiled hashes: the node's
   [impl_hash]es come from the fully optimised TIR of its build, and the
   shell never runs that pipeline.  So identity is decided on the SOURCE:

   - one hash per top-level declaration, over its text from its own start to
     the next declaration's start (or the end of its module or file), so a
     multi-clause fn's later clauses and its comments count, whatever the
     merged declaration's span says; plus one per module over its
     non-value declarations (imports, aliases, needs, externs), which change
     how the names in its functions resolve;
   - per variant type, its constructor names and tags, as the build's
     emitter numbered them.

   A `--hot-reload` build embeds this table as `__march_shell_ident`; the
   shell listener serves it (IDENT).  The client computes its own from its
   source and, per input, compares the declarations the fragment's functions
   come from (by provenance span) and the types they mention. *)

open March_ast

type t = {
  decls : (string, string) Hashtbl.t;   (* key -> 16-hex hash of its text *)
  tags  : (string, string) Hashtbl.t;   (* variant type -> "Ctor=tag,..." *)
}

(* A declaration's place, for mapping a fragment fn's span back to it. *)
type region = {
  r_file  : string;
  r_start : int * int;   (* line, col of the declaration's start *)
  r_end   : int * int;   (* where its text ends: the next one's start *)
  r_key   : string;
  r_mod   : string;      (* its module's header key *)
}

let hash16 s = String.sub (March_cas.Blake3.hash_string s) 0 16

(* ── source text ─────────────────────────────────────────────────────── *)

let file_lines : (string, string array) Hashtbl.t = Hashtbl.create 16

let lines_of file =
  match Hashtbl.find_opt file_lines file with
  | Some l -> l
  | None ->
    let l = try
        In_channel.with_open_bin file In_channel.input_all
        |> String.split_on_char '\n' |> Array.of_list
      with Sys_error _ -> [||] in
    Hashtbl.replace file_lines file l;
    l

(* The text of [file] from [(l1, c1)] up to [(l2, c2)], exclusive (lines from
   1, columns in bytes from 0); [None] for the end: the rest of the file.
   A position past the file's end (a derived declaration's synthetic span)
   clamps, so the slice is empty rather than an error. *)
let slice file (l1, c1) stop =
  let lines = lines_of file in
  let n = Array.length lines in
  let b = Buffer.create 256 in
  let l2, c2 = match stop with Some p -> p | None -> (n + 1, 0) in
  for l = max 1 l1 to min n l2 do
    let s = lines.(l - 1) in
    let len = String.length s in
    let a = if l = l1 then min c1 len else 0 in
    let z = if l = l2 then min c2 len else len in
    if z > a then Buffer.add_string b (String.sub s a (z - a));
    if l < l2 then Buffer.add_char b '\n'
  done;
  Buffer.contents b

(* ── declarations ────────────────────────────────────────────────────── *)

let decl_span = March_tir.Lower_decls.decl_span

(* [`Leaf (kind, name)] for a declaration that is hashed on its own;
   [`Header] for one that joins its module's header; [`Mod] to recurse. *)
let classify (d : Ast.decl) =
  match d with
  | Ast.DFn (def, _) -> `Leaf ("f", def.fn_name.txt)
  | Ast.DLet (_, b, _) ->
    `Leaf ("l", match b.bind_pat with Ast.PatVar n -> n.txt | _ -> "")
  | Ast.DType (_, n, _, _, _) | Ast.DAlwaysLinearType (_, n, _, _, _) -> `Leaf ("t", n.txt)
  | Ast.DActor (_, n, _, _) -> `Leaf ("a", n.txt)
  | Ast.DInterface (i, _) -> `Leaf ("i", i.iface_name.txt)
  | Ast.DImpl (i, _) -> `Leaf ("impl", i.impl_iface.txt)
  | Ast.DProtocol (n, _, _) -> `Leaf ("p", n.txt)
  | Ast.DSig (n, _, _) -> `Leaf ("s", n.txt)
  | Ast.DMod (n, _, inner, sp) -> `Mod (n.txt, inner, sp)
  | Ast.DExtern _ | Ast.DUse _ | Ast.DAlias _ | Ast.DNeeds _ | Ast.DProofCap _
  | Ast.DTransitions _ | Ast.DApp _ | Ast.DDeriving _ | Ast.DSatisfy _
  | Ast.DOpts _ -> `Header
  | Ast.DTest _ | Ast.DDescribe _ | Ast.DSetup _ | Ast.DSetupAll _ -> `Skip

let pos (sp : Ast.span) = (sp.start_line, sp.start_col)

(* Walk [decls] (one module level, [prefix] its qualified name plus "."),
   adding each leaf's hash to [out] and its region to [regions].  [stop] is
   where the level's last declaration's text ends: its module's end, or
   [None] (the file's end) at the top. *)
let rec walk ~out ~regions ~prefix ~stop (decls : Ast.decl list) =
  let header_key = prefix ^ "<header>" in
  let header = Buffer.create 64 in
  let seen : (string, int) Hashtbl.t = Hashtbl.create 16 in
  let rec go = function
    | [] -> ()
    | d :: rest ->
      let sp = decl_span d in
      let next = match rest with
        | d' :: _ when (decl_span d').file = sp.file -> Some (pos (decl_span d'))
        | _ -> stop in
      let text () = slice sp.file (pos sp) next in
      (match classify d with
       | `Leaf (kind, name) ->
         let base = prefix ^ kind ^ ":" ^ name in
         let k = (try Hashtbl.find seen base with Not_found -> 0) + 1 in
         Hashtbl.replace seen base k;
         let key = if k = 1 then base else Printf.sprintf "%s#%d" base k in
         Hashtbl.replace out key (hash16 (text ()));
         regions := { r_file = sp.file; r_start = pos sp;
                      r_end = (match next with Some p -> p | None -> (max_int, 0));
                      r_key = key; r_mod = header_key } :: !regions
       | `Header -> Buffer.add_string header (text ()); Buffer.add_char header '\000'
       | `Skip -> ()
       | `Mod (name, inner, _) ->
         (* Its last declaration's text runs to whatever follows the module
            (a span's end is not trusted to cover the whole of it). *)
         walk ~out ~regions ~prefix:(prefix ^ name ^ ".") ~stop:next inner);
      go rest
  in
  go decls;
  Hashtbl.replace out header_key (hash16 (Buffer.contents header))

(** The declaration table of a program's (desugared) declarations, and the
    regions to map spans back to it. *)
let of_decls (decls : Ast.decl list) : (string, string) Hashtbl.t * region list =
  let out = Hashtbl.create 1024 and regions = ref [] in
  walk ~out ~regions ~prefix:"" ~stop:None decls;
  (out, !regions)

(** Variant types' constructor tags, as [Llvm_toplevel] numbers them for
    [types] (which must be the list the code is emitted with, in order). *)
let tags_of_types (types : March_tir.Tir.type_def list) : (string, string) Hashtbl.t =
  let tags = March_tir.Llvm_toplevel.variant_ctor_tags
      ~collision_set:(March_tir.Collision_set.compute types) types in
  let ctors = Hashtbl.create 64 in
  List.iter (function
      | March_tir.Tir.TDVariant (n, cs) when not (Hashtbl.mem ctors n) ->
        Hashtbl.replace ctors n (List.map fst cs)
      | _ -> ()) types;
  let out = Hashtbl.create 256 in
  Hashtbl.iter (fun name ts ->
      match Hashtbl.find_opt ctors name with
      | Some cs when List.length cs = List.length ts ->
        Hashtbl.replace out name
          (String.concat "," (List.map2 (fun c t -> Printf.sprintf "%s=%d" c t) cs ts))
      | _ -> ()) tags;
  out

(* ── the table as text ───────────────────────────────────────────────── *)

(* One line per entry, sorted: "d <key> <hash>" or "t <type> <ctor=tag,...>".
   Keys and type names never contain spaces or newlines. *)
let to_string (t : t) : string =
  let lines = ref [] in
  Hashtbl.iter (fun k v -> lines := Printf.sprintf "d %s %s" k v :: !lines) t.decls;
  Hashtbl.iter (fun k v -> lines := Printf.sprintf "t %s %s" k v :: !lines) t.tags;
  String.concat "\n" (List.sort compare !lines) ^ "\n"

(** A digest of a declaration table alone (the build's CAS tag). *)
let digest (decls : (string, string) Hashtbl.t) : string =
  hash16 (to_string { decls; tags = Hashtbl.create 0 })

(** The table as the `__march_shell_ident` global of a node's IR, which the
    shell listener serves (IDENT).  A `--hot-reload` binary exports its
    symbols, and is not dead-stripped. *)
let ir_global (t : t) : string =
  let s = to_string t in
  let b = Buffer.create (String.length s + 64) in
  String.iter (fun c ->
      if c = '"' || c = '\\' || Char.code c < 0x20 || Char.code c >= 0x7f
      then Buffer.add_string b (Printf.sprintf "\\%02X" (Char.code c))
      else Buffer.add_char b c) s;
  Printf.sprintf "\n@__march_shell_ident = constant [%d x i8] c\"%s\\00\"\n"
    (String.length s + 1) (Buffer.contents b)

let of_string (s : string) : t =
  let t = { decls = Hashtbl.create 1024; tags = Hashtbl.create 256 } in
  List.iter (fun line ->
      match String.split_on_char ' ' line with
      | [ "d"; k; v ] -> Hashtbl.replace t.decls k v
      | [ "t"; k; v ] -> Hashtbl.replace t.tags k v
      | _ -> ()) (String.split_on_char '\n' s);
  t

(** A key as an operator reads it: [Mod.f:name] -> "Mod.name",
    [Mod.t:T] -> "type Mod.T", [Mod.<header>] -> "Mod's imports".  Keys are
    [<prefix><kind>:<name>[#n]] or [<prefix><header>], [prefix] being ""
    or "A.B.". *)
let describe_key (key : string) : string =
  let header = "<header>" in
  let kl = String.length key and hl = String.length header in
  if kl >= hl && String.sub key (kl - hl) hl = header then
    let m = String.sub key 0 (kl - hl) in
    let m = if m = "" then "the entry module" else String.sub m 0 (String.length m - 1) in
    m ^ "'s imports"
  else match String.index_opt key ':' with
    | None -> key
    | Some c ->
      let before = String.sub key 0 c in
      let prefix, kind = match String.rindex_opt before '.' with
        | Some d -> String.sub before 0 (d + 1), String.sub before (d + 1) (c - d - 1)
        | None -> "", before in
      let what = match kind with
        | "t" -> "type " | "a" -> "actor " | "i" -> "interface "
        | "impl" -> "an impl of " | "p" -> "protocol " | "l" -> "let " | _ -> "" in
      what ^ prefix ^ String.sub key (c + 1) (kl - c - 1)

(* ── a fragment's check ──────────────────────────────────────────────── *)

let before (l1, c1) (l2, c2) = l1 < l2 || (l1 = l2 && c1 < c2)

let region_of regions (sp : Ast.span) =
  let p = pos sp in
  List.find_opt (fun r ->
      r.r_file = sp.file && not (before p r.r_start) && before p r.r_end) regions

(* The type a TIR type name was declared as: an actor's message type is the
   actor's, every other is itself. *)
let type_key name =
  let sfx = March_tir.Tir_names.actor_msg_suffix in
  let n = String.length name and k = String.length sfx in
  if n > k && String.sub name (n - k) k = sfx then
    let actor = String.sub name 0 (n - k) in
    match String.rindex_opt actor '.' with
    | Some i -> String.sub actor 0 (i + 1) ^ "a:" ^ String.sub actor (i + 1) (String.length actor - i - 1)
    | None -> "a:" ^ actor
  else match String.rindex_opt name '.' with
    | Some i -> String.sub name 0 (i + 1) ^ "t:" ^ String.sub name (i + 1) (String.length name - i - 1)
    | None -> "t:" ^ name

(** What differs between [client] and [node] in the code [fns] reach: the
    declarations their provenance spans fall in (and those declarations'
    module headers), the types they mention, and those types' constructor
    tags.  [regions] maps the client's spans to its keys.  One line per
    difference, sorted; empty when they agree. *)
let skew ~(client : t) ~(regions : region list) ~(node : t)
    (fns : March_tir.Tir.fn_def list) : string list =
  let out = Hashtbl.create 8 in
  let check_decl key =
    match Hashtbl.find_opt client.decls key, Hashtbl.find_opt node.decls key with
    | Some a, Some b when a = b -> ()
    | Some _, Some _ -> Hashtbl.replace out (describe_key key ^ " differs") ()
    | Some _, None -> Hashtbl.replace out (describe_key key ^ " is not in the node's build") ()
    | None, _ -> () in
  List.iter (fun (fd : March_tir.Tir.fn_def) ->
      let span = match March_tir.Provenance.effective_span fd.fn_name with
        | Some _ as sp -> sp
        | None ->
          (* A pass that did not record its derivation: the fn's source stem
             (`f$Int`, `f$apply$12` -> `f`). *)
          (match String.index_opt fd.fn_name '$' with
           | Some i when i > 0 ->
             March_tir.Provenance.effective_span (String.sub fd.fn_name 0 i)
           | _ -> None) in
      match span with
      | Some sp ->
        (match region_of regions sp with
         | Some r -> check_decl r.r_key; check_decl r.r_mod
         | None -> ())
      | None -> ()) fns;
  let tycons = List.fold_left March_cas.Pipeline.add_tycons_of_fn [] fns
               |> List.sort_uniq compare in
  List.iter (fun name ->
      check_decl (type_key name);
      match Hashtbl.find_opt client.tags name, Hashtbl.find_opt node.tags name with
      | Some a, Some b when a <> b ->
        Hashtbl.replace out (Printf.sprintf "%s has constructor tags %s here, %s on the node" name a b) ()
      | _ -> ()) tycons;
  List.sort compare (Hashtbl.fold (fun k () acc -> k :: acc) out [])


(** What a session checks each input against: the node's table, and the
    client's declarations with their regions. *)
type check = { node : t; client_decls : (string, string) Hashtbl.t; regions : region list }

let check_of ~(node : t) (decls : Ast.decl list) : check =
  let client_decls, regions = of_decls decls in
  { node; client_decls; regions }

(** The declarations that differ anywhere in the program, for a summary when
    a session starts. *)
let differing (c : check) : string list =
  Hashtbl.fold (fun k v acc ->
      match Hashtbl.find_opt c.node.decls k with
      | Some v' when v' = v -> acc
      | _ -> k :: acc) c.client_decls []
  |> List.sort compare

(** [skew] for a fragment whose code is [fns], emitted with [types]. *)
let fragment_skew (c : check) ~(types : March_tir.Tir.type_def list)
    (fns : March_tir.Tir.fn_def list) : string list =
  skew ~client:{ decls = c.client_decls; tags = tags_of_types types }
    ~regions:c.regions ~node:c.node fns
