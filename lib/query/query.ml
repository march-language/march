(** [march query]: ask one compile a question (observability plan §12, A7).

    The driver runs the normal pipeline with a {!Collector} installed as its
    [snap] observer and answers at one of two early exits: after the TIR
    pipeline (where [--dump-tir] stops) for the pipeline queries, or at the
    post-TIR cache key (before any lookup, emit or link) for the cache
    queries.  Nothing is written and no binary is produced.

    {v
    march query fn NAME FILE [--at PASS]   a function's body at a pass, and the passes that changed it
    march query origin NAME FILE           where an emitted function came from (provenance, A2)
    march query callers NAME FILE          who references NAME in the final IR
    march query callees NAME FILE          what NAME references in the final IR
    march query repr TYPE FILE             how each instance of a type is represented
    march query verify FILE                run the TIR verifier (A1) over every stage
    march query key FILE                   both cache keys and every input that fed them
    march query why-miss FILE              which key input changed since the last successful build
    v}

    Every query takes [--json] for one JSON object on stdout, and passes any
    other flag through to the compiler ([--opt 0], [--target ...]), so it
    answers about the build those flags describe. *)

module Tir = March_tir.Tir

(* ── Requests ─────────────────────────────────────────────────────────── *)

type sub = Fn | Origin | Callers | Callees | Repr | Verify | Key | Why_miss

type request = {
  sub  : sub;
  arg  : string;           (** NAME or TYPE; "" for the queries without one *)
  at   : string option;    (** [--at PASS] *)
  json : bool;
}

let sub_of_string = function
  | "fn" -> Some Fn | "origin" -> Some Origin | "callers" -> Some Callers
  | "callees" -> Some Callees | "repr" -> Some Repr | "verify" -> Some Verify
  | "key" -> Some Key | "why-miss" -> Some Why_miss | _ -> None

let string_of_sub = function
  | Fn -> "fn" | Origin -> "origin" | Callers -> "callers" | Callees -> "callees"
  | Repr -> "repr" | Verify -> "verify" | Key -> "key" | Why_miss -> "why-miss"

let takes_arg = function Fn | Origin | Callers | Callees | Repr -> true | _ -> false

(** Answered at the post-TIR cache key (the compiler runs in [--compile]
    mode up to there); the others after the TIR pipeline. *)
let is_cache_query = function Key | Why_miss -> true | _ -> false

let usage =
  "usage: march query <fn NAME | origin NAME | callers NAME | callees NAME |\n\
  \                    repr TYPE | verify | key | why-miss> FILE [--at PASS] [--json]\n\
  \                    [compiler flags...]\n"

(** Split [march query ...]'s arguments (everything after [query]) into the
    request and the arguments left for the compiler's own [Arg.parse]. *)
let parse_args (args : string list) : (request * string list, string) result =
  match args with
  | [] -> Error usage
  | s :: rest ->
    (match sub_of_string s with
     | None -> Error (Printf.sprintf "march query: unknown query %S\n%s" s usage)
     | Some sub ->
       let arg, rest =
         if takes_arg sub then
           match rest with
           | a :: r when String.length a > 0 && a.[0] <> '-' -> (a, r)
           | _ -> ("", rest)
         else ("", rest) in
       if takes_arg sub && arg = "" then
         Error (Printf.sprintf "march query %s: needs a name\n%s" s usage)
       else
         let rec strip at json acc = function
           | "--json" :: r -> strip at true acc r
           | "--at" :: p :: r -> strip (Some p) json acc r
           | x :: r -> strip at json (x :: acc) r
           | [] -> (at, json, List.rev acc) in
         let at, json, compiler_args = strip None false [] rest in
         Ok ({ sub; arg; at; json }, compiler_args))

(* ── The snapshot collector ──────────────────────────────────────────── *)

(** Retains, per pipeline stage, the printed body of each function the query
    is about, rather than whole modules (a whole-program snapshot per stage
    would hold the stdlib ~40 times).  Installed as the pipeline's [snap] and
    [opt_snap] observer. *)
module Collector = struct
  type t = {
    want : string -> bool;
    mutable stages : (string * (string * string) list) list;  (* reversed *)
  }

  (** [NAME] itself, or a function derived from it by a ['$'] suffix (its
      specialisations [NAME$Int], a lambda's apply fn [NAME$apply$...]). *)
  let matching name n =
    n = name || String.starts_with ~prefix:(name ^ "$") n

  let create want = { want; stages = [] }

  let observe c label (m : Tir.tir_module) =
    let fns = List.filter_map (fun (fd : Tir.fn_def) ->
        if c.want fd.Tir.fn_name
        then Some (fd.Tir.fn_name, March_tir.Pp.string_of_fn_def fd) else None)
        m.Tir.tm_fns in
    c.stages <- (label, fns) :: c.stages

  let stages c = List.rev c.stages
end

(* ── Output ───────────────────────────────────────────────────────────── *)

type answer = { text : string; json : Yojson.Safe.t; ok : bool }

(** [path] relative to the current directory when it is under it: the text
    answers name files the way the user typed them. *)
let display path =
  let cwd = try Sys.getcwd () ^ "/" with Sys_error _ -> "" in
  let cwd_real = try Unix.realpath (Sys.getcwd ()) ^ "/" with Unix.Unix_error _ | Sys_error _ -> cwd in
  let strip pre s =
    if pre <> "/" && String.starts_with ~prefix:pre s
    then Some (String.sub s (String.length pre) (String.length s - String.length pre)) else None in
  match strip cwd path with
  | Some r -> r
  | None -> (match strip cwd_real path with Some r -> r | None -> path)


let print (r : request) (a : answer) : int =
  if r.json then print_endline (Yojson.Safe.pretty_to_string a.json)
  else print_string a.text;
  if a.ok then 0 else 1

let suggestions (names : string list) (q : string) : string list =
  let lq = String.lowercase_ascii q in
  let contains hay =
    let h = String.lowercase_ascii hay in
    let n = String.length h and m = String.length lq in
    let rec go i = i + m <= n && (String.sub h i m = lq || go (i + 1)) in
    m > 0 && go 0 in
  List.filter contains names |> List.sort_uniq compare |> List.filteri (fun i _ -> i < 12)

(** [last_seen]: the last pipeline stage that still had [name], when it
    existed earlier and an optimisation removed it (inlined, or dead). *)
let not_found ?last_seen ~sub ~name ~names () =
  let sug = suggestions names name in
  let headline = match last_seen with
    | Some stage ->
      Printf.sprintf "%s: %S is not in the final IR; it was last seen at %s (inlined or removed by \
                      an optimisation). `march query fn %s FILE` shows each pass that touched it; \
                      --no-opt keeps it.\n" sub name stage name
    | None -> Printf.sprintf "%s: no function named %S in this compile.\n" sub name in
  let text = headline ^
             (if sug = [] then ""
              else "did you mean:\n" ^ String.concat "" (List.map (fun s -> "  " ^ s ^ "\n") sug)) in
  { text; ok = false;
    json = `Assoc [ ("query", `String sub); ("name", `String name);
                    ("found", `Bool false);
                    ("last_seen", match last_seen with Some s -> `String s | None -> `Null);
                    ("suggestions", `List (List.map (fun s -> `String s) sug)) ] }

(** The last stage [c] saw [name] at, exactly. *)
let last_seen (c : Collector.t) name =
  List.fold_left (fun acc (label, fns) -> if List.mem_assoc name fns then Some label else acc)
    None (Collector.stages c)

let fn_names (m : Tir.tir_module) = List.map (fun (fd : Tir.fn_def) -> fd.Tir.fn_name) m.Tir.tm_fns

(** Every function name this compile produced at any stage (the provenance
    table keeps an entry after a pass removes the function), plus the final
    module's: what a misspelt name is matched against. *)
let all_names (m : Tir.tir_module) =
  List.map fst (March_tir.Provenance.all ()) @ fn_names m

(* ── fn ───────────────────────────────────────────────────────────────── *)

type event = Appears | Changed | Removed

let string_of_event = function Appears -> "appears" | Changed -> "changed" | Removed -> "removed"

let fn_answer (r : request) (c : Collector.t) ~(final : Tir.tir_module) : answer =
  let stages = Collector.stages c in
  let seen = List.concat_map (fun (_, fns) -> List.map fst fns) stages
             |> List.sort_uniq compare in
  let targets = if List.mem r.arg seen then [ r.arg ] else seen in
  if targets = [] then not_found ~sub:"fn" ~name:r.arg ~names:(all_names final) ()
  else begin
    let one name =
      (* Events: the stages where [name]'s printed body differs from the
         previous stage that ran (absent counts as a body). *)
      let _, events =
        List.fold_left (fun (prev, acc) (label, fns) ->
            let cur = List.assoc_opt name fns in
            let ev = match prev, cur with
              | None, Some _ -> Some Appears
              | Some p, Some b when p <> b -> Some Changed
              | Some _, None -> Some Removed
              | _ -> None in
            (cur, match ev with Some e -> (label, e) :: acc | None -> acc))
          (None, []) stages in
      let events = List.rev events in
      let present = List.filter_map (fun (label, fns) ->
          Option.map (fun b -> (label, b)) (List.assoc_opt name fns)) stages in
      (* [--at PASS]: the exact stage label, else the first containing it
         ([--at perceus] finds [tir-perceus]); without it, the last stage. *)
      let picked =
        match r.at with
        | Some p ->
          (match List.find_opt (fun (l, _) -> l = p) present with
           | Some x -> Some x
           | None ->
             List.find_opt (fun (l, _) ->
                 let n = String.length l and m = String.length p in
                 let rec go i = i + m <= n && (String.sub l i m = p || go (i + 1)) in
                 go 0) present)
        | None -> (match List.rev present with x :: _ -> Some x | [] -> None) in
      let body_stage, body =
        match picked with Some (l, b) -> (Some l, Some b) | None -> (None, None) in
      let in_final = List.exists (fun (fd : Tir.fn_def) -> fd.Tir.fn_name = name) final.Tir.tm_fns in
      (name, events, body_stage, body, in_final)
    in
    let all = List.map one targets in
    let text =
      String.concat "\n" (List.map (fun (name, events, bs, body, in_final) ->
          let evs = List.map (fun (l, e) -> Printf.sprintf "  %-8s %s\n" (string_of_event e) l) events in
          Printf.sprintf "fn %s%s\n%s%s" name
            (if in_final then "" else "  (not in the final module)")
            (String.concat "" evs)
            (match bs, body with
             | Some l, Some b -> Printf.sprintf "body at %s:\n%s\n" l b
             | _ -> (match r.at with Some p -> Printf.sprintf "no stage matching %S has it\n" p | None -> "")))
          all) in
    let json = `Assoc [
        ("query", `String "fn"); ("name", `String r.arg); ("found", `Bool true);
        ("stages_observed", `List (List.map (fun (l, _) -> `String l) stages));
        ("matches", `List (List.map (fun (name, events, bs, body, in_final) ->
             `Assoc [ ("name", `String name); ("in_final", `Bool in_final);
                      ("events", `List (List.map (fun (l, e) ->
                           `Assoc [ ("stage", `String l); ("event", `String (string_of_event e)) ]) events));
                      ("body_stage", match bs with Some l -> `String l | None -> `Null);
                      ("body", match body with Some b -> `String b | None -> `Null) ]) all)) ] in
    { text; json; ok = true }
  end

(* ── origin ───────────────────────────────────────────────────────────── *)

let origin_answer (r : request) (c : Collector.t) ~(final : Tir.tir_module) : answer =
  let module P = March_tir.Provenance in
  match P.find r.arg with
  | None ->
    not_found ?last_seen:(last_seen c r.arg) ~sub:"origin" ~name:r.arg ~names:(all_names final) ()
  | Some o ->
    let span = Option.map P.string_of_span o.P.src_span in
    let derived = List.map P.string_of_derivation o.P.derived in
    let passes = List.rev o.P.passes in
    let opt = function Some s -> s | None -> "-" in
    let text = Printf.sprintf
        "origin %s\n  span     %s\n  host     %s\n  derived  %s\n  passes   %s\n"
        r.arg (opt span) (opt o.P.host)
        (if derived = [] then "-" else String.concat "; " derived)
        (String.concat " > " passes) in
    let s = function Some x -> `String x | None -> `Null in
    { text; ok = true;
      json = `Assoc [ ("query", `String "origin"); ("name", `String r.arg); ("found", `Bool true);
                      ("span", s span); ("host", s o.P.host);
                      ("derived", `List (List.map (fun d -> `String d) derived));
                      ("passes", `List (List.map (fun p -> `String p) passes)) ] }

(* ── callers / callees ───────────────────────────────────────────────── *)

(** The final module's reference graph: a call, or a function named as a
    value (a closure's apply fn named in its allocation counts: that is the
    host building the closure). *)
let graph (m : Tir.tir_module) =
  let known = March_cas.Scc.known_of_names (fn_names m) in
  List.map (fun (fd : Tir.fn_def) ->
      (fd.Tir.fn_name, March_cas.Scc.deps_of known fd)) m.Tir.tm_fns

let edges_answer (r : request) (c : Collector.t) ~(final : Tir.tir_module) : answer =
  let g = graph final in
  let sub = string_of_sub r.sub in
  match List.assoc_opt r.arg g with
  | None -> not_found ?last_seen:(last_seen c r.arg) ~sub ~name:r.arg ~names:(all_names final) ()
  | Some deps ->
    let names =
      if r.sub = Callees then List.filter (fun d -> d <> r.arg) deps
      else List.filter_map (fun (n, ds) -> if n <> r.arg && List.mem r.arg ds then Some n else None) g
    in
    let self = List.mem r.arg deps in
    let text = Printf.sprintf "%s %s (final IR, %d)%s\n%s" sub r.arg (List.length names)
        (if self then ", self-recursive" else "")
        (String.concat "" (List.map (fun n -> "  " ^ n ^ "\n") names)) in
    { text; ok = true;
      json = `Assoc [ ("query", `String sub); ("name", `String r.arg); ("found", `Bool true);
                      ("self_recursive", `Bool self);
                      (sub, `List (List.map (fun n -> `String n) names)) ] }

(* ── repr ─────────────────────────────────────────────────────────────── *)

let repr_answer (r : request) ~(final : Tir.tir_module) ~(k_table : March_tir.Kind.table) : answer =
  let module K = March_tir.Kind in
  (* Every instance of the type the final module mentions in a signature,
     plus the bare name. *)
  let found = Hashtbl.create 8 in
  let rec walk (t : Tir.ty) = match t with
    | Tir.TCon (n, args) ->
      if n = r.arg || String.starts_with ~prefix:(r.arg ^ "$") n then Hashtbl.replace found t ();
      List.iter walk args
    | Tir.TTuple ts -> List.iter walk ts
    | Tir.TRecord fs -> List.iter (fun (_, t) -> walk t) fs
    | Tir.TFn (ps, rt) -> List.iter walk ps; walk rt
    | Tir.TPtr t -> walk t
    | _ -> () in
  List.iter (fun (fd : Tir.fn_def) ->
      List.iter (fun (v : Tir.var) -> walk v.Tir.v_ty) fd.Tir.fn_params;
      walk fd.Tir.fn_ret_ty) final.Tir.tm_fns;
  let defined = List.exists (fun (td : Tir.type_def) ->
      match td with
      | Tir.TDVariant (n, _) | Tir.TDRecord (n, _) | Tir.TDClosure (n, _) -> n = r.arg)
      (K.type_defs k_table) in
  if defined || Hashtbl.length found = 0 then Hashtbl.replace found (Tir.TCon (r.arg, [])) ();
  let instances = Hashtbl.fold (fun t () acc -> t :: acc) found [] |> List.sort compare in
  if not defined && Hashtbl.length found <= 1
     && not (List.exists (function Tir.TCon (_, _ :: _) -> true | _ -> false) instances) then
    let names = List.filter_map (fun (td : Tir.type_def) ->
        match td with Tir.TDVariant (n, _) | Tir.TDRecord (n, _) -> Some n | _ -> None)
        (K.type_defs k_table) in
    let sug = suggestions names r.arg in
    { ok = false;
      text = Printf.sprintf "repr: no type named %S in this compile.\n%s" r.arg
          (if sug = [] then "" else "did you mean:\n" ^ String.concat "" (List.map (fun s -> "  " ^ s ^ "\n") sug));
      json = `Assoc [ ("query", `String "repr"); ("type", `String r.arg); ("found", `Bool false);
                      ("suggestions", `List (List.map (fun s -> `String s) sug)) ] }
  else begin
    let ty = March_tir.Pp.string_of_ty in
    let repr_desc = function
      | K.Boxed -> ("boxed", "a heap cell with a constructor tag")
      | K.Newtype t -> ("newtype", "represented as its single field: " ^ ty t)
      | K.Niche { payload; tagged } ->
        ("niche", Printf.sprintf "the empty constructor is a null word; the other holds %s %s"
           (ty payload) (if tagged then "behind a tag (its payload could itself be null)" else "directly"))
      | K.Unboxed { ctor; fields } ->
        ("unboxed", Printf.sprintf "passed by value as %s(%s)" ctor (String.concat ", " (List.map ty fields))) in
    let layout = function
      | K.Imm -> "imm" | K.Flt -> "float" | K.Vec n -> Printf.sprintf "vec%d" n
      | K.Agg s -> "agg " ^ s | K.Heap -> "heap" | K.Cell -> "cell" | K.Erased -> "erased" in
    let rows = List.map (fun t ->
        let k = K.of_ty k_table t in
        let rname, why = repr_desc k.K.repr in
        (t, k, rname, why)) instances in
    let text = String.concat "" (List.map (fun (t, k, rname, why) ->
        Printf.sprintf "%s\n  repr     %s: %s\n  layout   %s   llvm %s\n  rc %b  borrowable %b  niche-ok payload %b  needs tag %b\n"
          (ty t) rname why (layout k.K.layout) k.K.llvm_ty k.K.needs_rc k.K.borrowable
          k.K.niche_ok k.K.needs_tag) rows) in
    { text; ok = true;
      json = `Assoc [ ("query", `String "repr"); ("type", `String r.arg); ("found", `Bool true);
                      ("instances", `List (List.map (fun (t, k, rname, why) ->
                           `Assoc [ ("type", `String (ty t)); ("repr", `String rname); ("why", `String why);
                                    ("layout", `String (layout k.K.layout)); ("llvm_ty", `String k.K.llvm_ty);
                                    ("needs_rc", `Bool k.K.needs_rc); ("borrowable", `Bool k.K.borrowable);
                                    ("niche_ok", `Bool k.K.niche_ok); ("needs_tag", `Bool k.K.needs_tag) ]) rows)) ] }
  end

(* ── verify ───────────────────────────────────────────────────────────── *)

let verify_answer ~(stages : string list) ~(failure : (string * (string * string) list) option) : answer =
  match failure with
  | None ->
    { ok = true;
      text = Printf.sprintf "verify: no findings across %d stages\n" (List.length stages);
      json = `Assoc [ ("query", `String "verify"); ("findings", `List []);
                      ("stages_checked", `Int (List.length stages)) ] }
  | Some (stage, findings) ->
    { ok = false;
      text = March_tir.Tir_verify.render ~stage findings ^ "\n";
      json = `Assoc [ ("query", `String "verify"); ("stage", `String stage);
                      ("findings", `List (List.map (fun (fn, msg) ->
                           `Assoc [ ("fn", `String fn); ("finding", `String msg) ]) findings)) ] }

(* ── Cache keys: the record and the diff ────────────────────────────── *)

(** Everything that fed one compile's two cache keys
    ([bin/main.ml]'s [build_cas_key] and the source-level key before it).
    The driver fills it while computing the keys; a successful build writes
    it to [<project>/.march/cas/keyrecords/], and [why-miss] diffs a fresh
    one against that. *)
module Key = struct
  type t = {
    target      : string;
    flags       : string list;
    compiler    : string;               (** digest of the compiler executable *)
    runtime_dir : string;
    runtime     : string;               (** digest of runtime/*.c, *.h *)
    stdlib      : string;               (** digest of the stdlib sources *)
    entry       : string;               (** realpath *)
    mode        : string;               (** "depend" (B7.2 load set) or "walk" (every sibling) *)
    files       : (string * string) list; (** path, digest: entry first, then the keyed files *)
    source_key  : string;               (** the source-level cache key *)
    mutable tir_hash : string option;   (** digest of the module's per-SCC impl hashes *)
    mutable post_key : string option;   (** the post-TIR cache key *)
  }

  let version = "march-keyrecord v1"

  let digest_file path =
    try
      let ic = open_in_bin path in
      let s = Fun.protect ~finally:(fun () -> close_in ic)
          (fun () -> really_input_string ic (in_channel_length ic)) in
      Digest.to_hex (Digest.string s)
    with Sys_error _ -> "missing"

  let path ~store_root ~entry ~target =
    Printf.sprintf "%s/keyrecords/%s" store_root
      (Digest.to_hex (Digest.string (entry ^ "\x00" ^ target)))

  let to_lines (k : t) =
    let opt = function Some s -> s | None -> "-" in
    version
    :: [ "target\t" ^ k.target; "compiler\t" ^ k.compiler; "runtime_dir\t" ^ k.runtime_dir;
         "runtime\t" ^ k.runtime; "stdlib\t" ^ k.stdlib; "entry\t" ^ k.entry; "mode\t" ^ k.mode;
         "source_key\t" ^ k.source_key; "tir_hash\t" ^ opt k.tir_hash;
         "post_key\t" ^ opt k.post_key ]
    @ List.map (fun f -> "flag\t" ^ f) k.flags
    @ List.map (fun (p, d) -> "file\t" ^ p ^ "\t" ^ d) k.files

  let write ~path (k : t) =
    try
      let dir = Filename.dirname path in
      (try Unix.mkdir dir 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
      let tmp = path ^ ".tmp." ^ string_of_int (Unix.getpid ()) in
      Out_channel.with_open_bin tmp (fun oc ->
          output_string oc (String.concat "\n" (to_lines k) ^ "\n"));
      Sys.rename tmp path
    with Sys_error _ | Unix.Unix_error _ -> ()

  let read ~path : t option =
    match In_channel.with_open_bin path In_channel.input_all with
    | exception Sys_error _ -> None
    | text ->
      let lines = List.filter (fun l -> l <> "") (String.split_on_char '\n' text) in
      (match lines with
       | v :: rest when v = version ->
         let f = List.map (String.split_on_char '\t') rest in
         let one k = List.find_map (function [k'; v] when k' = k -> Some v | _ -> None) f
                     |> Option.value ~default:"" in
         let opt k = match one k with "" | "-" -> None | v -> Some v in
         Some { target = one "target"; compiler = one "compiler"; runtime_dir = one "runtime_dir";
                runtime = one "runtime"; stdlib = one "stdlib"; entry = one "entry"; mode = one "mode";
                source_key = one "source_key"; tir_hash = opt "tir_hash"; post_key = opt "post_key";
                flags = List.filter_map (function ["flag"; v] -> Some v | _ -> None) f;
                files = List.filter_map (function ["file"; p; d] -> Some (p, d) | _ -> None) f }
       | _ -> None)

  (** One line per input that differs, most explanatory first. *)
  let diff ~(before : t) ~(now : t) : (string * string) list =
    (* Digests are shortened; a path is shown whole. *)
    let short s =
      if String.length s > 12 && not (String.contains s '/') then String.sub s 0 12 else display s in
    let scalar name a b why =
      if a = b then [] else [ (name, Printf.sprintf "%s (%s -> %s)" why (short a) (short b)) ] in
    let files_before = before.files and files_now = now.files in
    let changed = List.filter_map (fun (p, d) ->
        match List.assoc_opt p files_before with
        | Some d0 when d0 <> d -> Some ("file", "changed: " ^ display p)
        | None -> Some ("file", "now keyed: " ^ display p ^ (if now.mode = "walk" then " (new file in a walked directory)" else ""))
        | _ -> None) files_now in
    let removed = List.filter_map (fun (p, _) ->
        if List.mem_assoc p files_now then None else Some ("file", "no longer keyed: " ^ display p)) files_before in
    let added_flags = List.filter (fun f -> not (List.mem f before.flags)) now.flags in
    let removed_flags = List.filter (fun f -> not (List.mem f now.flags)) before.flags in
    scalar "compiler" before.compiler now.compiler "the compiler executable changed (rebuilt or a different march)"
    @ scalar "runtime" before.runtime now.runtime "a runtime/*.c or *.h source changed"
    @ scalar "runtime_dir" before.runtime_dir now.runtime_dir "the compiler now compiles a different runtime directory"
    @ scalar "stdlib" before.stdlib now.stdlib "a stdlib source changed"
    @ scalar "target" before.target now.target "a different target"
    @ List.map (fun f -> ("flag", "added: " ^ f)) added_flags
    @ List.map (fun f -> ("flag", "removed: " ^ f)) removed_flags
    @ (if before.mode <> now.mode then
         [ ("mode", Printf.sprintf "source key mode %s -> %s%s" before.mode now.mode
              (if now.mode = "walk" then
                 " (the recorded load set no longer holds: a sibling .march file appeared, or a pruned one changed in a way the resolver might now load)"
               else "")) ]
       else [])
    @ changed @ removed
end

let key_json (k : Key.t) ~source_cached ~post_cached =
  let s x = `String x and o = function Some x -> `String x | None -> `Null in
  `Assoc [ ("target", s k.Key.target); ("flags", `List (List.map s k.Key.flags));
           ("compiler", s k.Key.compiler); ("runtime_dir", s k.Key.runtime_dir);
           ("runtime", s k.Key.runtime); ("stdlib", s k.Key.stdlib); ("entry", s k.Key.entry);
           ("mode", s k.Key.mode);
           ("files", `List (List.map (fun (p, d) -> `Assoc [ ("path", s p); ("digest", s d) ]) k.Key.files));
           ("source_key", s k.Key.source_key); ("source_cached", `Bool source_cached);
           ("tir_hash", o k.Key.tir_hash); ("post_key", o k.Key.post_key);
           ("post_cached", `Bool post_cached) ]

let key_answer (k : Key.t) ~source_cached ~post_cached : answer =
  let o = function Some x -> x | None -> "-" in
  let text = Printf.sprintf
      "key %s (target %s)\n\
      \  source-level key  %s  %s\n\
      \  post-TIR key      %s  %s\n\
      \  inputs\n\
      \    compiler        %s\n\
      \    runtime         %s  (%s)\n\
      \    stdlib          %s\n\
      \    flags           %s\n\
      \    source mode     %s (%s)\n\
      %s"
      (display k.Key.entry) k.Key.target
      k.Key.source_key (if source_cached then "cached" else "not cached")
      (o k.Key.post_key) (if post_cached then "cached" else "not cached")
      k.Key.compiler k.Key.runtime k.Key.runtime_dir k.Key.stdlib
      (String.concat " " k.Key.flags)
      k.Key.mode (if k.Key.mode = "depend" then "the files the last build loaded" else "every .march file the resolver could load")
      (String.concat "" (List.map (fun (p, d) -> Printf.sprintf "      %s  %s\n" d (display p)) k.Key.files)) in
  { text; ok = true;
    json = `Assoc (("query", `String "key") :: (match key_json k ~source_cached ~post_cached with `Assoc l -> l | _ -> [])) }

let why_miss_answer ~(before : Key.t option) ~(now : Key.t) ~source_cached ~post_cached : answer =
  match before with
  | None ->
    { ok = true;
      text = Printf.sprintf
          "why-miss %s (target %s): no successful build of this file is recorded in this project's\n\
           .march/cas yet. Build it once, then ask again.\n  now: source-level key %s, post-TIR key %s\n"
          (display now.Key.entry) now.Key.target
          (if source_cached then "cached" else "not cached")
          (if post_cached then "cached" else "not cached");
      json = `Assoc [ ("query", `String "why-miss"); ("recorded", `Bool false);
                      ("source_cached", `Bool source_cached); ("post_cached", `Bool post_cached) ] }
  | Some before ->
    let changes = Key.diff ~before ~now in
    let src_same = before.Key.source_key = now.Key.source_key in
    let post_same = before.Key.post_key = now.Key.post_key && now.Key.post_key <> None in
    let verdict =
      if source_cached then "a source-level hit: the build is served from the cache before parsing"
      else if post_cached then
        "a source-level miss but a post-TIR hit: the inputs changed without changing the compiled \
         program (a comment or formatting edit, or a sibling the program does not use), so the \
         front end and TIR pipeline run and the binary is reused"
      else if src_same && post_same then
        "the keys are the same as the last successful build, but the artifact is gone from the store \
         (cleared, or never stored for this output)"
      else "a full miss: the program compiles and links again" in
    let text = Printf.sprintf
        "why-miss %s (target %s)\n  %s.\n  source-level key %s since the last successful build; post-TIR key %s.\n%s"
        (display now.Key.entry) now.Key.target verdict
        (if src_same then "unchanged" else "changed")
        (if post_same then "unchanged" else "changed")
        (if changes = [] then
           (if src_same then "" else "  (no recorded input differs: a key component outside the record changed)\n")
         else "  what changed:\n" ^ String.concat "" (List.map (fun (_, d) -> "    - " ^ d ^ "\n") changes)) in
    { ok = true; text;
      json = `Assoc [ ("query", `String "why-miss"); ("recorded", `Bool true);
                      ("source_cached", `Bool source_cached); ("post_cached", `Bool post_cached);
                      ("source_key_changed", `Bool (not src_same)); ("post_key_changed", `Bool (not post_same));
                      ("changes", `List (List.map (fun (kind, d) ->
                           `Assoc [ ("input", `String kind); ("change", `String d) ]) changes)) ] }
