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
  decls : (string, string) Hashtbl.t;   (* key -> [hash48] of its text *)
  tags  : (string, string) Hashtbl.t;   (* variant type -> "Ctor=tag,..." *)
  (* The node's own functions a fragment may call instead of carrying a
     copy (see [linkable]): name -> (LLVM signature, parameter modes). *)
  fns   : (string, string * string) Hashtbl.t;
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

let b64url = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

(* The first 12 hex digits (48 bits) of [h] as 8 base64url characters. *)
let b64_of_hex12 (h : string) : string =
  let v = int_of_string ("0x" ^ String.sub h 0 12) in
  String.init 8 (fun i -> b64url.[(v lsr (6 * (7 - i))) land 63])

(* A declaration's (or a group's) hash: 48 bits, see "the table as text". *)
let hash48 s = b64_of_hex12 (March_cas.Blake3.hash_string s)

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
         Hashtbl.replace out key (hash48 (text ()));
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
  Hashtbl.replace out header_key (hash48 (Buffer.contents header))

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

(* Format 2 (format 1, below, is still read):

     march-shell-ident 2
     t <type> <ctor[=tag],...>     sorted; "=tag" is left out when the tag
                                   is the constructor's position
     x <fn> <signature> <modes>    sorted
     m <group> <digest>            sorted by group, each followed by its
     <rest> <hash>                 declarations, sorted

   None of the fields contains a space or a newline (a signature has its
   spaces removed).  A declaration key is its group, the module prefix it
   starts with ("" or "A.B."), followed by the rest ([split_key]); a group is
   written without its trailing dot, the top level as ".", so a key's module
   prefix, which is most of it, is written once per module.  A group's digest
   is [hash48] of its rows' text: the client computes the same over its own
   declarations and fetches only the groups whose digest differs (IDENT
   SUMMARY and IDENT GROUPS, runtime/march_shell.c), which for an up-to-date
   checkout is none.

   Hashes are 48 bits, as 8 base64url characters ([hash48]).  A hash is
   never looked up among others, only compared with the other side's hash of
   the same key (or group), so an edit goes unnoticed only if the edited
   text hashes to the very 48 bits the node's does: 1 in 2^48 per edited
   declaration, with no birthday bound.  The table guards against a stale
   checkout, not an adversary; the deploy key's signature covers what runs.

   Format 1, which nodes built before format 2 serve, has no header and a
   "d <key> <16 hex>" row per declaration; [parse] reads a hash's first 12
   hex digits, which are the same 48 bits [hash48] encodes. *)

let header = "march-shell-ident 2"

(* [key] as (group prefix, rest): the prefix is everything up to the last
   '.' before the kind's ':' (or before "<header>"). *)
let split_key (key : string) : string * string =
  let stop = match String.index_opt key ':' with Some c -> c | None -> String.length key in
  match String.rindex_from_opt key (stop - 1) '.' with
  | Some i -> String.sub key 0 (i + 1), String.sub key (i + 1) (String.length key - i - 1)
  | None -> "", key

let group_name p = if p = "" then "." else String.sub p 0 (String.length p - 1)
let group_prefix n = if n = "." then "" else n ^ "."

(* "A=0,B=1,C=5" <-> "A,B,C=5". *)
let compact_tags (v : string) : string =
  if v = "" then v else
    String.split_on_char ',' v
    |> List.mapi (fun i c ->
        match String.index_opt c '=' with
        | Some e when String.sub c (e + 1) (String.length c - e - 1) = string_of_int i ->
          String.sub c 0 e
        | _ -> c)
    |> String.concat ","

let expand_tags (v : string) : string =
  if v = "" then v else
    String.split_on_char ',' v
    |> List.mapi (fun i c -> if String.contains c '=' then c else Printf.sprintf "%s=%d" c i)
    |> String.concat ","

(* The declarations by group prefix, each group's rows (rest, hash) sorted. *)
let group_rows (decls : (string, string) Hashtbl.t) : (string, (string * string) list) Hashtbl.t =
  let g = Hashtbl.create 64 in
  Hashtbl.iter (fun k v ->
      let p, r = split_key k in
      Hashtbl.replace g p ((r, v) :: (try Hashtbl.find g p with Not_found -> []))) decls;
  Hashtbl.filter_map_inplace (fun _ rows -> Some (List.sort compare rows)) g;
  g

let rows_text rows =
  String.concat "" (List.map (fun (r, h) -> r ^ " " ^ h ^ "\n") rows)

let group_digest rows = hash48 (rows_text rows)

let to_string (t : t) : string =
  let b = Buffer.create 65536 in
  Buffer.add_string b header; Buffer.add_char b '\n';
  let sorted lines = List.iter (fun l -> Buffer.add_string b l; Buffer.add_char b '\n')
      (List.sort compare lines) in
  sorted (Hashtbl.fold (fun k v acc -> Printf.sprintf "t %s %s" k (compact_tags v) :: acc) t.tags []);
  sorted (Hashtbl.fold (fun k (sg, m) acc -> Printf.sprintf "x %s %s %s" k sg m :: acc) t.fns []);
  let groups = group_rows t.decls in
  List.iter (fun p ->
      let rows = Hashtbl.find groups p in
      Printf.bprintf b "m %s %s\n" (group_name p) (group_digest rows);
      Buffer.add_string b (rows_text rows))
    (List.sort compare (Hashtbl.fold (fun p _ acc -> p :: acc) groups []));
  Buffer.contents b

(** A table in either format, and (format 2) its groups' digests, by group
    prefix.  A summary (IDENT SUMMARY) has the digests and no rows. *)
let parse (s : string) : t * (string * string) list =
  let t = { decls = Hashtbl.create 1024; tags = Hashtbl.create 256;
            fns = Hashtbl.create 256 } in
  let groups = ref [] in
  (match String.split_on_char '\n' s with
   | h :: lines when h = header ->
     let cur = ref None in
     List.iter (fun line ->
         match String.split_on_char ' ' line, !cur with
         | [ "m"; g; d ], _ ->
           let p = group_prefix g in
           cur := Some p; groups := (p, d) :: !groups
         | [ r; h ], Some p -> Hashtbl.replace t.decls (p ^ r) h
         | [ "t"; k; v ], None -> Hashtbl.replace t.tags k (expand_tags v)
         | [ "x"; k; sg; m ], None -> Hashtbl.replace t.fns k (sg, m)
         | _ -> ()) lines
   | lines ->
     let is_hex c = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') in
     List.iter (fun line ->
         match String.split_on_char ' ' line with
         | [ "d"; k; v ] ->
           Hashtbl.replace t.decls k
             (if String.length v >= 12 && String.for_all is_hex v then b64_of_hex12 v else v)
         | [ "t"; k; v ] -> Hashtbl.replace t.tags k v
         | [ "x"; k; sg; m ] -> Hashtbl.replace t.fns k (sg, m)
         | _ -> ()) lines);
  (t, List.rev !groups)

let of_string (s : string) : t = fst (parse s)

(** A digest of a declaration table alone (the build's CAS tag). *)
let digest (decls : (string, string) Hashtbl.t) : string =
  hash16 (to_string { decls; tags = Hashtbl.create 0; fns = Hashtbl.create 0 })

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

(** The node's table, as far as [client_decls] need it, fetched with [ask]
    (a request line -> the reply's decoded table, or [Error reply]): the
    summary (types, linkable functions and group digests), then only the
    groups whose digest differs from the client's; a group that agrees takes
    the client's own rows, which are the node's.  A node that predates the
    summary (ERR unknown_verb) is asked for the whole table (IDENT). *)
let fetch ~(ask : string -> (string, string) result)
    (client_decls : (string, string) Hashtbl.t) : (t, string) result =
  let starts p s = String.length s >= String.length p && String.sub s 0 (String.length p) = p in
  match ask "IDENT SUMMARY" with
  | Error r when starts "ERR unknown_verb" r -> Result.map of_string (ask "IDENT")
  | Error r -> Error r
  | Ok s ->
    let node, digests = parse s in
    let mine = group_rows client_decls in
    let want = List.filter_map (fun (p, d) ->
        match Hashtbl.find_opt mine p with
        | Some rows when group_digest rows = d ->
          List.iter (fun (r, h) -> Hashtbl.replace node.decls (p ^ r) h) rows; None
        | Some _ -> Some p
        | None -> None) digests in
    if want = [] then Ok node
    else match ask ("IDENT GROUPS " ^ String.concat "," (List.map group_name want)) with
      | Error r -> Error r
      | Ok s ->
        Hashtbl.iter (Hashtbl.replace node.decls) (of_string s).decls;
        Ok node

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
type skew_parts = {
  sk_decls : string list;  (* functions, lets, impls and module headers that differ *)
  sk_types : string list;  (* types, actors and protocols that differ *)
  sk_tags  : string list;  (* types whose constructor tags differ *)
}

(* The kind of a declaration key ("f", "t", "a", ... or "<header>"). *)
let key_kind (key : string) : string =
  match String.index_opt key ':' with
  | None -> "<header>"
  | Some c ->
    let before = String.sub key 0 c in
    (match String.rindex_opt before '.' with
     | Some d -> String.sub before (d + 1) (c - d - 1)
     | None -> before)

let skew_parts ~(client : t) ~(regions : region list) ~(node : t)
    (fns : March_tir.Tir.fn_def list) : skew_parts =
  let out = Hashtbl.create 8 and type_out = Hashtbl.create 2 and tag_out = Hashtbl.create 2 in
  let check_decl key =
    (* A type's, actor's or protocol's definition is a value layout the
       node's data has; anything else is code the fragment carries. *)
    let into = if List.mem (key_kind key) [ "t"; "a"; "p" ] then type_out else out in
    match Hashtbl.find_opt client.decls key, Hashtbl.find_opt node.decls key with
    | Some a, Some b when a = b -> ()
    | Some _, Some _ -> Hashtbl.replace into (describe_key key ^ " differs") ()
    | Some _, None -> Hashtbl.replace into (describe_key key ^ " is not in the node's build") ()
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
        Hashtbl.replace tag_out (Printf.sprintf "%s has constructor tags %s here, %s on the node" name a b) ()
      | _ -> ()) tycons;
  let keys h = List.sort compare (Hashtbl.fold (fun k () acc -> k :: acc) h []) in
  { sk_decls = keys out; sk_types = keys type_out; sk_tags = keys tag_out }

let skew ~client ~regions ~node fns : string list =
  let p = skew_parts ~client ~regions ~node fns in
  List.sort compare (p.sk_decls @ p.sk_types @ p.sk_tags)


(** What a session checks each input against: the node's table, and the
    client's declarations with their regions. *)
type check = { node : t; client_decls : (string, string) Hashtbl.t; regions : region list }

let check_of ~(node : t) (decls : Ast.decl list) : check =
  let client_decls, regions = of_decls decls in
  { node; client_decls; regions }

(** [check_of] with the node's table fetched by [fetch] ([ask] as there). *)
let fetch_check ~(ask : string -> (string, string) result) (decls : Ast.decl list)
  : (check, string) result =
  let client_decls, regions = of_decls decls in
  Result.map (fun node -> { node; client_decls; regions }) (fetch ~ask client_decls)

(** The declarations that differ anywhere in the program, for a summary when
    a session starts. *)
let differing (c : check) : string list =
  Hashtbl.fold (fun k v acc ->
      match Hashtbl.find_opt c.node.decls k with
      | Some v' when v' = v -> acc
      | _ -> k :: acc) c.client_decls []
  |> List.sort compare

(** [skew_parts] for a fragment whose code is [fns], emitted with [types]. *)
let fragment_skew_parts (c : check) ~(types : March_tir.Tir.type_def list)
    (fns : March_tir.Tir.fn_def list) : skew_parts =
  skew_parts ~client:{ decls = c.client_decls; tags = tags_of_types types; fns = Hashtbl.create 0 }
    ~regions:c.regions ~node:c.node fns


(* ── --force: read-only inputs over skewed code ──────────────────────── *)

(* `march --shell --shell-force` runs an input that reaches declarations
   differing from the node's build, but only when the input is read-only:
   it runs this checkout's version of that code against the node's state,
   and must not leave anything behind that the node's own code would then
   meet.  Only differing code is forced ([sk_decls]: functions, lets,
   impls, module headers).  A differing type, actor or protocol definition
   ([sk_types]) and a constructor-tag difference ([sk_tags]) never are: a
   value of the node's (read from a Vault, say) would be decoded with this
   checkout's layout, or as the wrong constructor.

   "Read-only" is decided on the fragment as compiled, with nothing linked
   to the node (every body it runs is in the fragment, so the C symbols it
   calls are all of what it can do), by an allowlist and a denylist:

   - its capabilities (the cap manifest) are all in [read_only_caps]:
     printing (captured into the reply), the clock, randomness and reading
     files.  Anything else, including a capability this list does not know
     (IO.FileWrite, IO.Net*, IO.Process, IO.Spawn, IO.Mut (Vault writes),
     IO.Signal, an FFI cap), disqualifies it;
   - it calls no runtime entry point that acts on other actors or on
     process-wide state without a capability ([is_mutating_sym]: send,
     spawn, kill, stop, Actor.call, register, monitor, reply, setters,
     close, cancel, the logger, epoch holds, ...);
   - it does not reach the Actor.Debug tier ([debug_fns], and the
     `march_actor_inspect` symbol): the plan's rule (R5.4), kept although
     reading state is itself read-only, since Debug is the authority to see
     anything an actor holds and the reviewer of a skewed session should
     not also have to reason about that;
   - it uses no earlier `let` binding that may hold a closure
     ([may_hold_closure]): that closure's code is in an earlier fragment,
     out of sight of the symbol check.

   Limits: the runtime-symbol denylist is by name (substrings plus a list),
   so a new entry point that mutates without a capability and has none of
   the words is allowed until it is added here; a closure reached some
   other way than a session binding (read out of a Vault, say), or hidden
   in a binding whose type is a bare type variable, is not seen; and a
   read-only input still runs this checkout's code, so its answer can
   differ from what the node's own code would compute.  The shell says so
   (a warning naming the declarations, `[skew]` at the prompt, `skew:1` in
   the node's audit line). *)

let read_only_caps = [ "IO.Console"; "IO.Clock"; "IO.Random"; "IO.FileRead" ]

(* Runtime symbols (`march_*`, without a leading underscore) that change
   something outside the fragment, mostly without a capability.  Matched two ways, so
   that a runtime entry point added later with a telling name is caught
   without an edit here:
   - by substring ([mutating_words]): any symbol naming a send, spawn, kill,
     stop, registration, monitor, reply, setter, close, cancel, ...;
   - exactly ([mutating_syms]): the rest, whose names do not say so.
   A false positive only refuses a forced input (run it on a matching
   checkout instead); a false negative lets one through, so the words are
   broad.  [repl_set] (a `let` storing into the session's own slot) is not
   emitted as a call the emitter records, and is the session's anyway. *)
let mutating_words = [
  "send"; "spawn"; "kill"; "stop"; "register"; "monitor"; "reply"; "revoke";
  "reload"; "_set"; "close"; "cancel"; "drop"; "free"; "write"; "delete";
  "remove"; "rename"; "update"; "incr"; "push"; "reap"; "exit"; "drain";
]

let mutating_syms = [
  "march_actor_call"; "march_try_call"; "march_try_call_val";
  "march_remote_invoke_march"; "march_actor_inspect"; "march_actor_inspect_store";
  "march_run_until_idle"; "march_io_read_line"; "march_io_read_byte";
  "march_delivery_failed_watch"; "march_http_fetch"; "march_epoch_hold";
  "march_epoch_release"; "march_sched_delivery_origin_clear";
]

(* Whole families: the logger's process-wide configuration and output. *)
let mutating_prefixes = [ "march_logger_" ]

let is_mutating_sym (s : string) : bool =
  let has sub =
    let n = String.length s and m = String.length sub in
    let rec go i = i + m <= n && (String.sub s i m = sub || go (i + 1)) in
    go 0 in
  let starts p = String.length s >= String.length p && String.sub s 0 (String.length p) = p in
  (* The emitter records program and library functions it calls too
     (`evens`, `List.drop`): only the runtime's own entry points count. *)
  starts "march_"
  && (List.mem s mutating_syms || List.exists starts mutating_prefixes
      || List.exists has mutating_words)

(* The stdlib functions of the Actor.Debug tier: minting the capability
   and using it. *)
let debug_fns = [ "Actor.debug"; "Actor.inspect_state" ]

(** Whether a value of type [t] may hold a closure: a function type, or a
    type that has one in its arguments or (by [types], the program's type
    definitions) in a constructor's or field's type.  A named type with no
    definition in [types] (a builtin such as [Pid]) counts by its arguments
    only. *)
let may_hold_closure ~(types : March_tir.Tir.type_def list) (t : March_tir.Tir.ty) : bool =
  let module T = March_tir.Tir in
  let seen = Hashtbl.create 8 in
  let rec go t =
    match t with
    | T.TFn _ -> true
    (* A type variable: in a definition, a parameter, whose argument is
       checked at the use; at the top, an erased slot (a phantom such as
       `Pid(a)`'s, in practice).  Not counted: see the limits. *)
    | T.TVar _ -> false
    | T.TTuple ts -> List.exists go ts
    | T.TRecord fs -> List.exists (fun (_, t) -> go t) fs
    | T.TPtr t -> go t
    | T.TInt | T.TFloat | T.TBool | T.TString | T.TUnit -> false
    | T.TCon (name, args) ->
      List.exists go args
      || (not (Hashtbl.mem seen name)
          && (Hashtbl.replace seen name ();
              List.exists (function
                  | T.TDVariant (n, cs) when n = name -> List.exists (fun (_, ts) -> List.exists go ts) cs
                  | T.TDRecord (n, fs) when n = name -> List.exists (fun (_, t) -> go t) fs
                  | T.TDClosure (n, _) when n = name -> true
                  | _ -> false) types))
  in
  go t

(** Why a fragment is not read-only, one reason per line; empty when it is.
    [caps] is its cap manifest, [syms] the C symbols its emitted code calls,
    [fns] the names of the functions it reaches, [closure_lets] the earlier
    `let` bindings it uses that may hold a closure (whose code is in another
    fragment, out of this check's sight). *)
let not_read_only ?(closure_lets = []) ~(caps : string list) ~(syms : string list)
    ~(fns : string list) () : string list =
  let strip s = if String.length s > 0 && s.[0] = '_' then String.sub s 1 (String.length s - 1) else s in
  let stem n = match String.index_opt n '$' with Some i -> String.sub n 0 i | None -> n in
  let caps_r = List.filter_map (fun c ->
      if List.mem c read_only_caps then None else Some ("uses " ^ c)) caps in
  let syms_r = List.filter_map (fun s ->
      let s = strip s in
      if is_mutating_sym s then Some ("calls " ^ s) else None) syms in
  let debug_r =
    if List.exists (fun f -> List.mem (stem f) debug_fns) fns then [ "uses Actor.Debug" ] else [] in
  let lets_r = List.map (fun n ->
      Printf.sprintf "uses `%s`, an earlier binding that may hold a closure" n) closure_lets in
  List.sort_uniq compare (caps_r @ syms_r @ debug_r @ lets_r)

(* ── calling the node's own functions ────────────────────────────────── *)

(* A fragment carries a copy of every function it runs unless the node has
   the same function, compiled the same way, which it can call instead: the
   copy of a Depot query was ~0.5 MB of IR, compiled by clang for every
   input.  "The same way" is three checks, none assumed:
   - the same specialised name (mono mangles the types into it);
   - the same LLVM signature, taken from the node's own `define` and the
     fragment's `declare`, which covers representation (an unboxed struct
     passed inline, a Float as double);
   - the node's parameter modes (borrowed or owned, as its Perceus decided
     them, [Clo_flags]), which the fragment's Perceus then uses at its call
     sites, so neither side frees or keeps what the other expects.
   The declaration's source is checked equal by [skew] first. *)

(* Linkage words that may precede a function's return type. *)
let linkage_words = [ "internal"; "private"; "dso_local"; "fastcc"; "ccc"; "tailcc";
                      "linkonce_odr"; "weak_odr"; "hidden"; "protected"; "noundef";
                      "noalias"; "nonnull"; "zeroext"; "signext"; "inreg" ]

(* The type a parameter (or return) spelling starts with: a brace- or
   bracket-balanced aggregate, or the first word.  Attributes and the
   parameter's name after it are dropped. *)
let leading_type (s : string) : string =
  let s = String.trim s in
  let n = String.length s in
  if n > 0 && (s.[0] = '{' || s.[0] = '[' || s.[0] = '<') then begin
    let depth = ref 0 and i = ref 0 and stop = ref n in
    (try while !i < n do
         (match s.[!i] with
          | '{' | '[' | '<' -> incr depth
          | '}' | ']' | '>' -> decr depth; if !depth = 0 then (stop := !i + 1; raise Exit)
          | _ -> ());
         incr i
       done with Exit -> ());
    String.sub s 0 !stop
  end else
    match String.index_opt s ' ' with Some i -> String.sub s 0 i | None -> s

(* Split [s] on commas at nesting depth 0. *)
let split_top (s : string) : string list =
  let parts = ref [] and depth = ref 0 and start = ref 0 in
  String.iteri (fun i c ->
      match c with
      | '{' | '[' | '<' | '(' -> incr depth
      | '}' | ']' | '>' | ')' -> decr depth
      | ',' when !depth = 0 -> parts := String.sub s !start (i - !start) :: !parts; start := i + 1
      | _ -> ()) s;
  let last = String.sub s !start (String.length s - !start) in
  List.rev (if String.trim last = "" && !parts = [] then [] else last :: !parts)

let strip_spaces s = String.concat "" (String.split_on_char ' ' s)

(** Each `define`d (or, with [~declares:true], `declare`d) function of [ir]
    that is visible outside its object, with its signature
    ["ret(param,param)"].  Internal and private functions are left out. *)
let signatures ?(declares = false) (ir : string) : (string * string) list =
  let kw = if declares then "declare " else "define " in
  List.filter_map (fun line ->
      let kl = String.length kw in
      if String.length line <= kl || String.sub line 0 kl <> kw then None
      else match String.index_opt line '@' with
        | None -> None
        | Some at ->
          let head = String.split_on_char ' ' (String.trim (String.sub line kl (at - kl))) in
          if List.exists (fun w -> w = "internal" || w = "private") head then None
          else
            let ret = String.concat " " (List.filter (fun w -> w <> "" && not (List.mem w linkage_words)) head) in
            let rest = String.sub line (at + 1) (String.length line - at - 1) in
            let name, after =
              if String.length rest > 0 && rest.[0] = '"' then
                match String.index_from_opt rest 1 '"' with
                | Some q -> String.sub rest 1 (q - 1), String.sub rest (q + 1) (String.length rest - q - 1)
                | None -> rest, ""
              else match String.index_opt rest '(' with
                | Some p -> String.sub rest 0 p, String.sub rest p (String.length rest - p)
                | None -> rest, "" in
            if String.length after = 0 || after.[0] <> '(' then None
            else
              (* The parameter list: up to the ')' that closes the first '('. *)
              let depth = ref 0 and close = ref (-1) in
              String.iteri (fun i c ->
                  if !close < 0 then match c with
                    | '(' -> incr depth
                    | ')' -> decr depth; if !depth = 0 then close := i
                    | _ -> ()) after;
              if !close < 0 then None
              else
                let params = split_top (String.sub after 1 (!close - 1)) in
                let ps = List.map (fun p -> strip_spaces (leading_type p)) params in
                Some (name, Printf.sprintf "%s(%s)" (strip_spaces (leading_type ret)) (String.concat "," ps)))
    (String.split_on_char '\n' ir)

(* A name the same on both sides only if it is derived from the source and
   the types.  Lifted lambdas, their apply functions, join points and other
   pass-made functions are numbered by a per-build counter
   (`go$apply$1349`, `f$lam12`): the client's `go$apply$0` is an unrelated
   function that happens to share the node's name, and calling the node's
   would run the wrong code.  So any `$`-segment that is a number, or one of
   the generated kinds, rules a name out.  This also rules out default-arg
   arity wrappers (`greet$1`), which only costs a copy. *)
let stable_name (name : string) : bool =
  let digits s = s <> "" && String.for_all (fun c -> c >= '0' && c <= '9') s in
  let generated seg =
    digits seg
    || List.mem seg [ "apply"; "clo_wrap"; "clo"; "lam"; "jp"; "trmc"; "spec"; "fused"; "inl" ]
    (* a counter-numbered kind: lam12, jp3, t5, p2, trmc4, ... *)
    || List.exists (fun p ->
        let n = String.length p in
        String.length seg > n && String.sub seg 0 n = p
        && digits (String.sub seg n (String.length seg - n)))
      [ "lam"; "jp"; "t"; "p"; "trmc"; "spec"; "fused"; "inl"; "clo" ] in
  match String.split_on_char '$' name with
  | [] -> false
  | _ :: segs -> List.for_all (fun seg -> seg <> "" && not (generated seg)) segs

(** The node side: the functions of a `--hot-reload` build's [ir] a fragment
    may call, with their signatures and their parameter modes from [modes]
    ("b" borrowed / "o" owned per parameter, "-" for none).  Left out: a hot
    reload slot ([is_slot]: a deploy can replace it, and a fragment calling
    the baseline symbol would bypass the dispatch table), anything with no
    recorded modes, and the program's entry points and trampolines. *)
let node_fns ~(ir : string) ~(is_slot : string -> bool)
    ~(modes : string -> bool list option) : (string, string * string) Hashtbl.t =
  let out = Hashtbl.create 256 in
  List.iter (fun (name, sg) ->
      let generated =
        name = "main" || name = "march_main"
        || (let sfx = "$clo_wrap" in
            let n = String.length name and k = String.length sfx in
            n >= k && String.sub name (n - k) k = sfx) in
      if not generated && stable_name name && not (is_slot name) then
        match modes name with
        | Some ms ->
          let m = if ms = [] then "-"
            else String.concat "" (List.map (fun b -> if b then "b" else "o") ms) in
          Hashtbl.replace out name (sg, m)
        | None -> ()) (signatures ir);
  out

(* A type a fragment may pass to or get from a node function: no closure (a
   fragment's lambda has its own apply code) and no type variable (an erased
   slot, where ownership of a boxed Float is a per-call agreement). *)
let rec plain_ty (t : March_tir.Tir.ty) : bool =
  match t with
  | March_tir.Tir.TFn _ | March_tir.Tir.TVar _ -> false
  | March_tir.Tir.TCon (_, args) -> List.for_all plain_ty args
  | March_tir.Tir.TTuple ts -> List.for_all plain_ty ts
  | March_tir.Tir.TRecord fs -> List.for_all (fun (_, t) -> plain_ty t) fs
  | March_tir.Tir.TPtr t -> plain_ty t
  | March_tir.Tir.TInt | March_tir.Tir.TFloat | March_tir.Tir.TBool
  | March_tir.Tir.TString | March_tir.Tir.TUnit -> true

(** The client side: of [fns] (a fragment's functions), those the node [t]
    has under the same name and whose types are plain; the caller still
    compares signatures ([signatures ~declares:true] of its fragment). *)
let linkable (t : t) (fns : March_tir.Tir.fn_def list) : March_tir.Tir.fn_def list =
  List.filter (fun (fd : March_tir.Tir.fn_def) ->
      Hashtbl.mem t.fns fd.fn_name
      && stable_name fd.fn_name
      && plain_ty fd.fn_ret_ty
      && List.for_all (fun (v : March_tir.Tir.var) -> plain_ty v.v_ty) fd.fn_params) fns

(** The node's modes for [name], as a borrow-map row. *)
let node_modes (t : t) (name : string) : bool array option =
  match Hashtbl.find_opt t.fns name with
  | Some (_, "-") -> Some [||]
  | Some (_, m) -> Some (Array.init (String.length m) (fun i -> m.[i] = 'b'))
  | None -> None
