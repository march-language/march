(** The topology file: `topology.toml` and its `topology.<env>.toml` overlays.

    Build step 7 of the distributed-deploys plan
    (specs/plans/2026-09-21-distributed-authority-and-deploys-plan.md,
    section 4, II.6). Static only: this module parses, merges, validates and
    digests the file; nothing here runs a node.

    {1 Pipeline}

    - [load ~root ?env ()]: parse the base file and, with [env], the overlay;
      tables deep-merge (an inline table too), an array in the overlay
      replaces the base's array. Every key keeps the file and line it came
      from, so a check can say [topology.prod.toml:12: ...].
    - [check ~index t]: the static checks forge can do alone (section 4 and
      the step-7 todo), against [index], the project's parse. Errors and
      warnings both point into the TOML.
    - [digest_json t] / [write_digest ~root t]: `.forge/topology.json`,
      the form the compiler ([march --topology]) and, later, the runtime read.
    - [export_json ~index t]: the digest plus the derived facts (each pool's
      initiated roles, the connectivity graph) for generators.
    - [Gen]: the built-in generators (systemd, ufw, do-firewall, compose)
      and the [forge-topology-<target>] plugin convention.

    {1 The digest, `.forge/topology.json` (schema version 1)}

    {v
    { "version": 1,
      "env": "prod" | null,             -- the overlay that was applied
      "sources": ["topology.toml", "topology.prod.toml"],
      "roles": [                        -- file order
        { "name": "Checkout.Ledger", "protocol": "Checkout", "role": "Ledger",
          "body": "Ledger.serve_one" | null,   -- exactly one of body/actor
          "actor": "Quotes.ServerActor" | null,
          "capacity": 64 | null,
          "place": { "on": "db" | null, "count": 2 | null } | null,  -- null: everywhere (D18)
          "set": false } ],             -- reserved for role sets (D7)
      "pools": [                        -- file order
        { "name": "edge",
          "start": "Edge.start" | null,
          "serves": ["Checkout.Ledger"],  -- "*" already expanded
          "serves_all": false,
          "initiates": ["Quotes.Client"] | null,   -- null: derived (D22)
          "caps": ["IO.FileWrite"] | null,         -- null: derived (D22)
          "isolate": false,
          "public": [443],
          "main": "src/x_main.march" | null,       -- the escape hatch (4.1)
          "replicas": 3 | null,                    -- non-ssh backends
          "hosts": [ { "host": "root@web-1", "labels": ["public"] } ] } ],
      "drain": { "soft_ms": 30000 | null, "hard_ms": 120000 | null } | null,
      "backend": { "kind": "ssh" | null, "port": 7946 | null } | null }
    v}

    [export_json] adds, on top of the digest:

    {v
      "derived": { "<pool>": { "initiates": [...],   -- the compiler's, typed; else from call sites by name
                               "caps": [...] | null, -- the compiler's (D22); null when it could not run
                               "source": "compiler" | "names" } },
      "connectivity": [ { "from": "edge", "to": "ledger", "protocols": ["Checkout"] } ],
      "cluster_port": 7946
    v}

    A connectivity edge joins two pools when a role one of them serves or
    initiates exchanges a message with a role the other serves or initiates,
    by the same rule as the generated [peers_<Role>()]
    (lib/desugar/desugar_endpoints.ml, [peers_of]). Edges are undirected
    ([from] < [to]); a pool whose own roles talk to each other has an edge to
    itself, which matters when the pool spans several hosts. *)

module Ast = March_ast.Ast

(* ── Locations and diagnostics ─────────────────────────────────────────── *)

type loc = { file : string; line : int }

type severity = Error | Warning

type diag = { loc : loc; severity : severity; msg : string }

let render_diag d =
  match d.severity with
  | Error -> Printf.sprintf "%s:%d: %s" (Filename.basename d.loc.file) d.loc.line d.msg
  | Warning ->
    Printf.sprintf "%s:%d: warning: %s" (Filename.basename d.loc.file) d.loc.line d.msg

let has_errors ds = List.exists (fun d -> d.severity = Error) ds

(* ── The merged document ───────────────────────────────────────────────── *)

(** A merged section: every key with the location it was last written at.
    A key inside an inline table has the location of the key that holds the
    table (the TOML parser records one line per top-level key). *)
type pairs = (string * Toml.value * loc) list

type merged = {
  sections : (string * loc * pairs) list;  (** section name, header loc, keys *)
  sources  : string list;                  (** base first, then overlays *)
}

let rec merge_value (base : Toml.value) (over : Toml.value) : Toml.value =
  match base, over with
  | Toml.InlineTable a, Toml.InlineTable b ->
    Toml.InlineTable (merge_inline a b)
  | _ -> over

and merge_inline a b =
  let merged =
    List.map (fun (k, v) ->
        match List.assoc_opt k b with
        | Some v' -> (k, merge_value v v')
        | None -> (k, v))
      a
  in
  merged @ List.filter (fun (k, _) -> not (List.mem_assoc k a)) b

let merge_pairs (base : pairs) (over : pairs) : pairs =
  let merged =
    List.map (fun (k, v, l) ->
        match List.find_opt (fun (k', _, _) -> k' = k) over with
        | Some (_, v', l') -> (k, merge_value v v', l')
        | None -> (k, v, l))
      base
  in
  merged @ List.filter (fun (k, _, _) -> not (List.exists (fun (k', _, _) -> k' = k) base)) over

let of_document ~file (doc : Toml.document) : merged =
  let sections =
    List.map (fun (ls : Toml.located_section) ->
        (ls.sec_name, { file; line = ls.sec_line },
         List.map (fun (k, v, l) -> (k, v, { file; line = l })) ls.sec_pairs))
      doc.Toml.located
  in
  { sections; sources = [ file ] }

let merge (base : merged) (over : merged) : merged =
  let sections =
    List.map (fun (name, hl, ps) ->
        match List.find_opt (fun (n, _, _) -> n = name) over.sections with
        | Some (_, hl', ps') -> (name, hl', merge_pairs ps ps')
        | None -> (name, hl, ps))
      base.sections
  in
  let extra =
    List.filter (fun (n, _, _) -> not (List.exists (fun (n', _, _) -> n' = n) base.sections))
      over.sections
  in
  { sections = sections @ extra; sources = base.sources @ over.sources }

(* ── The typed topology ────────────────────────────────────────────────── *)

type place = { on : string option; count : int option }

type role = {
  role_name : string;          (** "Checkout.Ledger" *)
  protocol  : string;          (** "Checkout" *)
  role      : string;          (** "Ledger" *)
  body      : string option;
  actor     : string option;
  capacity  : int option;
  place     : place option;
  set       : bool;
  role_loc  : loc;
}

type host = { host : string; labels : string list }

type pool = {
  pool_name  : string;
  start      : string option;
  serves     : string list;    (** expanded: "*" becomes every role in [roles] *)
  serves_all : bool;
  initiates  : string list option;
  caps       : string list option;
  isolate    : bool;
  public     : int list;
  main       : string option;
  replicas   : int option;
  hosts      : host list;
  pool_loc   : loc;
  key_locs   : (string * loc) list;  (** where each written key is, for diagnostics *)
}

type drain = { soft_ms : int option; hard_ms : int option }

type backend = { kind : string option; port : int option }

type t = {
  roles   : role list;
  pools   : pool list;
  drain   : drain option;
  backend : backend option;
  env     : string option;
  sources : string list;
}

let default_cluster_port = 7946

let cluster_port t =
  match t.backend with
  | Some { port = Some p; _ } -> p
  | _ -> default_cluster_port

let key_loc (p : pool) key =
  match List.assoc_opt key p.key_locs with Some l -> l | None -> p.pool_loc

(* ── Reading the merged document ───────────────────────────────────────── *)

let known_role_keys = [ "body"; "actor"; "capacity"; "place"; "set" ]
let known_place_keys = [ "on"; "count" ]
let known_pool_keys =
  [ "start"; "serves"; "initiates"; "caps"; "isolate"; "public"; "main"; "hosts"; "replicas" ]
let known_host_keys = [ "host"; "labels" ]
let known_drain_keys = [ "soft_ms"; "hard_ms" ]
let known_backend_keys = [ "kind"; "port" ]

let int_of_value = function
  | Toml.Str s -> int_of_string_opt (String.trim s)
  | _ -> None

let read (m : merged) : (t, diag list) result =
  let diags = ref [] in
  let err loc msg = diags := { loc; severity = Error; msg } :: !diags in
  let section name = List.find_opt (fun (n, _, _) -> n = name) m.sections in
  let pairs name = match section name with Some (_, _, ps) -> ps | None -> [] in
  let check_unknown ~where known (ps : pairs) =
    List.iter (fun (k, _, l) ->
        if not (List.mem k known) then
          err l (Printf.sprintf "unknown key '%s' in %s" k where))
      ps
  in
  (* Sections: only the ones this file owns. *)
  List.iter (fun (name, hl, ps) ->
      let is_pool =
        String.length name > 5 && String.sub name 0 5 = "pool."
        && not (String.contains (String.sub name 5 (String.length name - 5)) '.')
      in
      if name = "" then
        List.iter (fun (k, _, l) ->
            err l (Printf.sprintf "unknown top-level key '%s' (keys go under [roles], [pool.<name>], [drain] or [backend])" k))
          ps
      else if not (List.mem name [ "roles"; "drain"; "backend" ] || is_pool) then
        err hl (Printf.sprintf "unknown section [%s] (expected [roles], [pool.<name>], [drain] or [backend])" name))
    m.sections;
  (* [roles] *)
  let roles =
    List.filter_map (fun (key, v, l) ->
        match String.split_on_char '.' key with
        | [ protocol; role ] when protocol <> "" && role <> "" ->
          (match v with
           | Toml.InlineTable tbl ->
             let ps = List.map (fun (k, v) -> (k, v, l)) tbl in
             check_unknown ~where:(Printf.sprintf "[roles] \"%s\"" key) known_role_keys ps;
             let str k = Toml.get_string tbl k in
             let body = str "body" and actor = str "actor" in
             (match body, actor with
              | None, None ->
                err l (Printf.sprintf "role \"%s\" needs a `body = \"Mod.fn\"` or an `actor = \"Mod.Actor\"` binding" key)
              | Some _, Some _ ->
                err l (Printf.sprintf "role \"%s\" binds both `body` and `actor`; a role is stateless (body) or stateful (actor), not both" key)
              | _ -> ());
             let capacity =
               match List.assoc_opt "capacity" tbl with
               | None -> None
               | Some v ->
                 (match int_of_value v with
                  | Some n when n > 0 -> Some n
                  | _ -> err l (Printf.sprintf "role \"%s\": `capacity` must be a positive integer" key); None)
             in
             let place =
               match List.assoc_opt "place" tbl with
               | None -> None
               | Some (Toml.InlineTable pt) ->
                 check_unknown ~where:(Printf.sprintf "[roles] \"%s\" place" key) known_place_keys
                   (List.map (fun (k, v) -> (k, v, l)) pt);
                 let on = Toml.get_string pt "on" in
                 let count =
                   match List.assoc_opt "count" pt with
                   | None -> None
                   | Some v ->
                     (match int_of_value v with
                      | Some n when n > 0 -> Some n
                      | _ -> err l (Printf.sprintf "role \"%s\": `place.count` must be a positive integer" key); None)
                 in
                 if on = None && count = None then
                   err l (Printf.sprintf "role \"%s\": `place` needs `on = \"label\"`, `count = n`, or both" key);
                 Some { on; count }
               | Some _ ->
                 err l (Printf.sprintf "role \"%s\": `place` must be an inline table, e.g. `place = { on = \"db\" }`" key);
                 None
             in
             let set =
               match List.assoc_opt "set" tbl with
               | Some (Toml.Bool b) -> b
               | Some _ -> err l (Printf.sprintf "role \"%s\": `set` must be true or false" key); false
               | None -> false
             in
             Some { role_name = key; protocol; role; body; actor; capacity; place; set; role_loc = l }
           | _ ->
             err l (Printf.sprintf "role \"%s\" must be an inline table, e.g. `{ body = \"Mod.fn\" }`" key);
             None)
        | _ ->
          err l (Printf.sprintf "role key \"%s\" must be \"Protocol.Role\"" key);
          None)
      (pairs "roles")
  in
  let all_role_names = List.map (fun r -> r.role_name) roles in
  (* [pool.*] *)
  let pools =
    List.filter_map (fun (name, hl, ps) ->
        if String.length name > 5 && String.sub name 0 5 = "pool." then begin
          let pname = String.sub name 5 (String.length name - 5) in
          if String.contains pname '.' then None
          else begin
            let where = Printf.sprintf "[pool.%s]" pname in
            check_unknown ~where known_pool_keys ps;
            let find k = List.find_map (fun (k', v, l) -> if k' = k then Some (v, l) else None) ps in
            let str k =
              match find k with
              | None -> None
              | Some (Toml.Str s, _) -> Some s
              | Some (_, l) -> err l (Printf.sprintf "%s: `%s` must be a string" where k); None
            in
            let str_list k =
              match find k with
              | None -> None
              | Some (Toml.Array items, l) ->
                Some (List.filter_map (function
                    | Toml.Str s -> Some s
                    | _ -> err l (Printf.sprintf "%s: `%s` must be an array of strings" where k); None)
                    items)
              | Some (_, l) -> err l (Printf.sprintf "%s: `%s` must be an array of strings" where k); None
            in
            let serves, serves_all =
              match find "serves" with
              | None -> ([], false)
              | Some (Toml.Str "*", _) -> (all_role_names, true)
              | Some (Toml.Str _, l) ->
                err l (Printf.sprintf "%s: `serves` is an array of \"Protocol.Role\" names, or \"*\"" where);
                ([], false)
              | Some _ -> (Option.value ~default:[] (str_list "serves"), false)
            in
            let isolate =
              match find "isolate" with
              | None -> false
              | Some (Toml.Bool b, _) -> b
              | Some (_, l) -> err l (Printf.sprintf "%s: `isolate` must be true or false" where); false
            in
            let public =
              match find "public" with
              | None -> []
              | Some (Toml.Array items, l) ->
                List.filter_map (fun v ->
                    match int_of_value v with
                    | Some n when n >= 1 && n <= 65535 -> Some n
                    | _ -> err l (Printf.sprintf "%s: `public` must be an array of ports (1-65535)" where); None)
                  items
              | Some (_, l) -> err l (Printf.sprintf "%s: `public` must be an array of ports" where); []
            in
            let replicas =
              match find "replicas" with
              | None -> None
              | Some (v, l) ->
                (match int_of_value v with
                 | Some n when n > 0 -> Some n
                 | _ -> err l (Printf.sprintf "%s: `replicas` must be a positive integer" where); None)
            in
            let hosts =
              match find "hosts" with
              | None -> []
              | Some (Toml.Array items, l) ->
                List.filter_map (function
                    | Toml.Str h -> Some { host = h; labels = [] }
                    | Toml.InlineTable ht ->
                      check_unknown ~where:(where ^ " hosts") known_host_keys
                        (List.map (fun (k, v) -> (k, v, l)) ht);
                      (match Toml.get_string ht "host" with
                       | None -> err l (Printf.sprintf "%s: a `hosts` entry needs `host = \"user@name\"`" where); None
                       | Some h -> Some { host = h; labels = Toml.get_string_list ht "labels" })
                    | _ ->
                      err l (Printf.sprintf "%s: `hosts` entries are strings or `{ host = ..., labels = [...] }`" where);
                      None)
                  items
              | Some (_, l) -> err l (Printf.sprintf "%s: `hosts` must be an array" where); []
            in
            Some {
              pool_name = pname;
              start = str "start";
              serves; serves_all;
              initiates = str_list "initiates";
              caps = str_list "caps";
              isolate; public;
              main = str "main";
              replicas; hosts;
              pool_loc = hl;
              key_locs = List.map (fun (k, _, l) -> (k, l)) ps;
            }
          end
        end else None)
      m.sections
  in
  (* [drain] *)
  let drain =
    match section "drain" with
    | None -> None
    | Some (_, hl, ps) ->
      check_unknown ~where:"[drain]" known_drain_keys ps;
      let ms k =
        match List.find_opt (fun (k', _, _) -> k' = k) ps with
        | None -> None
        | Some (_, v, l) ->
          (match int_of_value v with
           | Some n when n >= 0 -> Some n
           | _ -> err l (Printf.sprintf "[drain] `%s` must be a non-negative integer of milliseconds" k); None)
      in
      let soft_ms = ms "soft_ms" and hard_ms = ms "hard_ms" in
      (match soft_ms, hard_ms with
       | Some s, Some h when h < s ->
         err hl "[drain] `hard_ms` must be at least `soft_ms` (the hard deadline comes after the soft one)"
       | _ -> ());
      Some { soft_ms; hard_ms }
  in
  (* [backend] *)
  let backend =
    match section "backend" with
    | None -> None
    | Some (_, _, ps) ->
      check_unknown ~where:"[backend]" known_backend_keys ps;
      let kind =
        match List.find_opt (fun (k, _, _) -> k = "kind") ps with
        | Some (_, Toml.Str s, _) -> Some s
        | Some (_, _, l) -> err l "[backend] `kind` must be a string"; None
        | None -> None
      in
      let port =
        match List.find_opt (fun (k, _, _) -> k = "port") ps with
        | None -> None
        | Some (_, v, l) ->
          (match int_of_value v with
           | Some n when n >= 1 && n <= 65535 -> Some n
           | _ -> err l "[backend] `port` must be a port (1-65535)"; None)
      in
      Some { kind; port }
  in
  let sources = m.sources in
  if !diags <> [] then Error (List.rev !diags)
  else Ok { roles; pools; drain; backend; env = None; sources }

(* ── Files ─────────────────────────────────────────────────────────────── *)

let base_file ~root = Filename.concat root "topology.toml"
let overlay_file ~root env = Filename.concat root (Printf.sprintf "topology.%s.toml" env)
let digest_file ~root = Filename.concat (Filename.concat root ".forge") "topology.json"

(** Whether the project has a topology at all. *)
let exists ~root = Sys.file_exists (base_file ~root)

let read_text path =
  let ic = open_in_bin path in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic;
  s

let parse_file path : (merged, diag list) result =
  match read_text path with
  | exception Sys_error m -> Error [ { loc = { file = path; line = 0 }; severity = Error; msg = m } ]
  | text ->
    match Toml.parse_located text with
    | Ok doc -> Ok (of_document ~file:path doc)
    | Error (line, msg) -> Error [ { loc = { file = path; line }; severity = Error; msg } ]

(** Parse `topology.toml` and, with [env], merge `topology.<env>.toml` on top.
    A named overlay that does not exist is an error; with no [env], only the
    base file is read. *)
let load ~root ?env () : (t, diag list) result =
  match parse_file (base_file ~root) with
  | Error ds -> Error ds
  | Ok base ->
    let merged =
      match env with
      | None -> Ok base
      | Some e ->
        let path = overlay_file ~root e in
        if not (Sys.file_exists path) then
          Error [ { loc = { file = path; line = 0 }; severity = Error;
                    msg = Printf.sprintf "no overlay %s for environment '%s'" (Filename.basename path) e } ]
        else Result.map (merge base) (parse_file path)
    in
    match merged with
    | Error ds -> Error ds
    | Ok m -> Result.map (fun t -> { t with env }) (read m)

(** Parse from strings, for tests: [(file_name, text)] pairs, base first. *)
let of_strings (files : (string * string) list) : (t, diag list) result =
  let rec go (acc : merged) = function
    | [] -> Ok acc
    | (file, text) :: rest ->
      (match Toml.parse_located text with
       | Error (line, msg) -> Error [ { loc = { file; line }; severity = Error; msg } ]
       | Ok doc ->
         let m = of_document ~file doc in
         go (match acc.sources with [] -> m | _ -> merge acc m) rest)
  in
  match go ({ sections = []; sources = [] } : merged) files with
  | Error ds -> Error ds
  | Ok m -> read m

(* ── The project index: what the .march sources declare ────────────────── *)

(** The names the topology binds resolve against the project's parse: every
    `.march` file under the root (test files excluded), parsed but not
    typechecked, the same walk `forge cap query` does. Qualified names are
    `Mod.fn` for a file's top-level module and `Mod.Sub.fn` for a nested one. *)
type index = {
  fns       : (string, unit) Hashtbl.t;
  actors    : (string, unit) Hashtbl.t;
  mutable protocols : (string * string * Ast.protocol_def) list;
  (** qualified name, short name, definition *)
  calls     : (string, string list) Hashtbl.t;
  (** every fn or actor (qualified) to the callee names as written in its body *)
  initiate_refs : (string, string list) Hashtbl.t;
  (** every fn or actor (qualified) to the ["Proto.Role"] it references
      through [<Proto>_Run.initiate_<Role>] *)
  mutable parse_errors : (string * string) list;
  sites     : (string, Ast.span) Hashtbl.t;
  (** Where each indexed name is declared, keyed [site_key kind qname]
      ([`Fn], [`Actor], [`Protocol]): the span of the declaration's NAME.
      Nothing here reads it; it is for navigation (the LSP's go-to-definition
      on a `body`/`actor`/`start` string), so an editor jumps to exactly the
      declaration the check resolved the string to. *)
}

let empty_index () =
  { fns = Hashtbl.create 64; actors = Hashtbl.create 8; protocols = [];
    calls = Hashtbl.create 64; initiate_refs = Hashtbl.create 8; parse_errors = [];
    sites = Hashtbl.create 64 }

let site_key kind qname =
  (match kind with `Fn -> "fn:" | `Actor -> "actor:" | `Protocol -> "protocol:") ^ qname

(** The declaration site of an indexed name, if the index has one. *)
let site idx kind qname = Hashtbl.find_opt idx.sites (site_key kind qname)

(** Every dotted reference and call target in an expression, as written. *)
let rec refs_in_expr acc (e : Ast.expr) : string list =
  let rec dotted = function
    | Ast.EVar n -> Some n.Ast.txt
    | Ast.ECon (n, [], _) -> Some n.Ast.txt  (* a module name parses as a nullary ctor *)
    | Ast.EField (inner, f, _) ->
      (match dotted inner with Some p -> Some (p ^ "." ^ f.Ast.txt) | None -> None)
    | _ -> None
  in
  let acc = match e with
    | Ast.EVar n -> n.Ast.txt :: acc
    | Ast.EField _ -> (match dotted e with Some d -> d :: acc | None -> acc)
    | _ -> acc
  in
  let go = refs_in_expr in
  let gol acc es = List.fold_left go acc es in
  match e with
  | Ast.EApp (f, args, _) -> gol (go acc f) args
  | Ast.ECon (_, es, _) | Ast.ETuple (es, _) | Ast.EAtom (_, es, _) | Ast.EBlock (es, _) -> gol acc es
  | Ast.ELam (_, b, _) | Ast.ELetFn (_, _, _, b, _) -> go acc b
  | Ast.ELet (b, _) -> go acc b.Ast.bind_expr
  | Ast.EMatch (s, brs, _) ->
    List.fold_left (fun a (br : Ast.branch) ->
        let a = match br.Ast.branch_guard with Some g -> go a g | None -> a in
        go a br.Ast.branch_body) (go acc s) brs
  | Ast.ERecord (fs, _) -> List.fold_left (fun a (_, e) -> go a e) acc fs
  | Ast.ERecordUpdate (e, fs, _) -> List.fold_left (fun a (_, e) -> go a e) (go acc e) fs
  | Ast.EField (inner, _, _) -> (match dotted e with Some _ -> acc | None -> go acc inner)
  | Ast.EIf (c, t, f, _) -> go (go (go acc c) t) f
  | Ast.ECond (arms, _) -> List.fold_left (fun a (c, b) -> go (go a c) b) acc arms
  | Ast.EPipe (x, y, _) | Ast.ESend (x, y, _) -> go (go acc x) y
  | Ast.EAnnot (e, _, _) | Ast.ESpawn (e, _) | Ast.EAssert (e, _) | Ast.ESigil (_, e, _) -> go acc e
  | Ast.EDbg (Some e, _) -> go acc e
  | Ast.ELetQ (_, e1, e2, _) | Ast.ELetStar (_, e1, e2, _) -> go (go acc e1) e2
  | _ -> acc

(** [Some "Proto.Role"] for a reference spelled [<Proto>_Run.initiate_<Role>]
    (possibly module-qualified in front). *)
let initiate_target (r : string) : string option =
  match List.rev (String.split_on_char '.' r) with
  | last :: run_mod :: _ ->
    let pre = "initiate_" and suf = "_Run" in
    let lp = String.length pre and ls = String.length suf in
    if String.length last > lp && String.sub last 0 lp = pre
       && String.length run_mod > ls
       && String.sub run_mod (String.length run_mod - ls) ls = suf
    then
      Some (String.sub run_mod 0 (String.length run_mod - ls) ^ "."
            ^ String.sub last lp (String.length last - lp))
    else None
  | _ -> None

let add_body idx qname (refs : string list) =
  let refs = List.sort_uniq String.compare refs in
  let prev = match Hashtbl.find_opt idx.calls qname with Some c -> c | None -> [] in
  Hashtbl.replace idx.calls qname (List.sort_uniq String.compare (prev @ refs));
  let inits = List.filter_map initiate_target refs in
  if inits <> [] then begin
    let prev = match Hashtbl.find_opt idx.initiate_refs qname with Some c -> c | None -> [] in
    Hashtbl.replace idx.initiate_refs qname (List.sort_uniq String.compare (prev @ inits))
  end

(** Add the declarations of one module (its top-level name is [prefix]). *)
let rec index_decls idx ~prefix (decls : Ast.decl list) =
  let q n = if prefix = "" then n else prefix ^ "." ^ n in
  List.iter (function
      | Ast.DFn (fn, _) ->
        let name = q fn.Ast.fn_name.Ast.txt in
        Hashtbl.replace idx.fns name ();
        if not (Hashtbl.mem idx.sites (site_key `Fn name)) then
          Hashtbl.replace idx.sites (site_key `Fn name) fn.Ast.fn_name.Ast.span;
        add_body idx name
          (List.concat_map (fun (cl : Ast.fn_clause) ->
               let g = match cl.Ast.fc_guard with Some g -> refs_in_expr [] g | None -> [] in
               g @ refs_in_expr [] cl.Ast.fc_body) fn.Ast.fn_clauses)
      | Ast.DActor (_, aname, def, _) ->
        let name = q aname.Ast.txt in
        Hashtbl.replace idx.actors name ();
        Hashtbl.replace idx.sites (site_key `Actor name) aname.Ast.span;
        add_body idx name
          (refs_in_expr [] def.Ast.actor_init
           @ List.concat_map (fun (h : Ast.actor_handler) -> refs_in_expr [] h.Ast.ah_body)
             def.Ast.actor_handlers)
      | Ast.DProtocol (name, def, _) ->
        Hashtbl.replace idx.sites (site_key `Protocol (q name.Ast.txt)) name.Ast.span;
        idx.protocols <- idx.protocols @ [ (q name.Ast.txt, name.Ast.txt, def) ]
      | Ast.DMod (name, _, inner, _) -> index_decls idx ~prefix:(q name.Ast.txt) inner
      | _ -> ())
    decls

(** Index one parsed module: its own name is the prefix of its declarations. *)
let index_module idx (m : Ast.module_) =
  index_decls idx ~prefix:m.Ast.mod_name.Ast.txt m.Ast.mod_decls

let is_test_file name =
  (String.length name > 5 && String.sub name 0 5 = "test_" && Filename.check_suffix name ".march")
  || Filename.check_suffix name "_test.march"

let find_march_files dir =
  let rec walk acc d =
    if not (Sys.file_exists d) then acc
    else begin
      let entries = Sys.readdir d in
      Array.sort compare entries;
      Array.fold_left (fun acc name ->
          let path = Filename.concat d name in
          if Sys.is_directory path then
            (if name = ".forge" || name = ".march" || name = "_build" || name = ".git" then acc
             else walk acc path)
          else if Filename.check_suffix name ".march" && not (is_test_file name) then path :: acc
          else acc)
        acc entries
    end
  in
  List.rev (walk [] dir)

(** Parse [src] as the module in file [path] (the path goes into every span). *)
let parse_source ~path (src : string) : (Ast.module_, string) result =
  try
    let lexbuf = Lexing.from_string src in
    lexbuf.Lexing.lex_curr_p <- { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = path };
    Ok (March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf)
  with exn -> Error (Printexc.to_string exn)

let parse_module path : (Ast.module_, string) result =
  match read_text path with
  | exception Sys_error msg -> Error msg
  | src -> parse_source ~path src

(** Parse every `.march` under [root] (test files skipped) into an index. A
    file that does not parse is recorded, not fatal: the compiler reports it
    properly; here it only means its names cannot be resolved.

    [index_project_with ~parse] takes how one file's module is obtained
    ([index_project] uses [parse_module], reading the disk). The LSP passes
    one that reads an editor buffer in place of the file when the file is
    open, so the walk, the naming and the parse-error handling stay this
    function's. *)
let index_project_with ~(parse : string -> (Ast.module_, string) result) ~root : index =
  let idx = empty_index () in
  List.iter (fun path ->
      match parse path with
      | Ok m -> index_module idx m
      | Error msg -> idx.parse_errors <- idx.parse_errors @ [ (path, msg) ])
    (find_march_files root);
  idx

let index_project ~root : index = index_project_with ~parse:parse_module ~root

(** The index of a set of already-parsed declaration lists, as the compiler
    holds them after import resolution: the entry module's flat decls under
    its own name, imported modules wrapped in [DMod]. *)
let index_of_decls (mods : (string * Ast.decl list) list) : index =
  let idx = empty_index () in
  List.iter (fun (prefix, decls) -> index_decls idx ~prefix decls) mods;
  idx

(* ── Protocol facts ────────────────────────────────────────────────────── *)

let rec proto_msgs (steps : Ast.protocol_step list) : (string * string * bool) list =
  (* sender, receiver, labelled *)
  List.concat_map (function
      | Ast.ProtoMsg (s, r, _, label) -> [ (s.Ast.txt, r.Ast.txt, label <> None) ]
      | Ast.ProtoLoop inner -> proto_msgs inner
      | Ast.ProtoChoice (_, branches) ->
        List.concat_map (fun (_, steps) ->
            (* A branch's head message is named by the branch label, so it
               counts as labelled (desugar_endpoints, [annotate]). *)
            match proto_msgs steps with
            | (s, r, _) :: rest -> (s, r, true) :: rest
            | [] -> [])
          branches
      | Ast.ProtoCrashOr (inner, crash, _) -> proto_msgs [ inner ] @ proto_msgs crash
      | Ast.ProtoStop _ | Ast.ProtoMayCrash _ | Ast.ProtoRoleNeeds _ -> [])
    steps

let proto_roles (def : Ast.protocol_def) : string list =
  let seen = ref [] in
  List.iter (fun (s, r, _) ->
      if not (List.mem s !seen) then seen := !seen @ [ s ];
      if not (List.mem r !seen) then seen := !seen @ [ r ])
    (proto_msgs def.Ast.proto_steps);
  !seen

(** Whether two roles of a protocol exchange a message: the generator's
    [peers_of] rule (lib/desugar/desugar_endpoints.ml). *)
let are_peers (def : Ast.protocol_def) a b =
  a <> b
  && List.exists (fun (s, r, _) -> (s = a && r = b) || (s = b && r = a))
    (proto_msgs def.Ast.proto_steps)

let unlabelled_count (def : Ast.protocol_def) =
  List.length (List.filter (fun (_, _, labelled) -> not labelled) (proto_msgs def.Ast.proto_steps))

(** Find a protocol by the short name the topology uses ("Checkout"), or by
    its qualified name. *)
let find_protocol (idx : index) (name : string) =
  match List.find_opt (fun (q, _, _) -> q = name) idx.protocols with
  | Some p -> Some p
  | None -> List.find_opt (fun (_, s, _) -> s = name) idx.protocols

let role_exists idx (role_name : string) =
  match String.split_on_char '.' role_name with
  | [ p; r ] ->
    (match find_protocol idx p with
     | Some (_, _, def) -> List.mem r (proto_roles def)
     | None -> false)
  | _ -> false

(* ── Reachability and derived initiates (D22, forge's half) ────────────── *)

(** Resolve a callee as written from inside [caller] (qualified): the name
    itself, then the name under each enclosing module of the caller. *)
let resolve_callee idx ~caller (name : string) : string option =
  let known n = Hashtbl.mem idx.fns n || Hashtbl.mem idx.actors n in
  if known name then Some name
  else begin
    let parts = String.split_on_char '.' caller in
    let rec try_prefix = function
      | [] -> None
      | [ _ ] -> None
      | ps ->
        let prefix = String.concat "." (List.rev (List.tl (List.rev ps))) in
        let cand = prefix ^ "." ^ name in
        if known cand then Some cand else try_prefix (List.rev (List.tl (List.rev ps)))
    in
    try_prefix parts
  end

(** Every fn/actor reachable from [roots] through call references. *)
let reachable idx (roots : string list) : string list =
  let seen = Hashtbl.create 64 in
  let rec visit n =
    if not (Hashtbl.mem seen n) then begin
      Hashtbl.replace seen n ();
      let callees = match Hashtbl.find_opt idx.calls n with Some c -> c | None -> [] in
      List.iter (fun c ->
          match resolve_callee idx ~caller:n c with
          | Some q -> visit q
          | None -> ())
        callees
    end
  in
  List.iter visit roots;
  Hashtbl.fold (fun k () acc -> k :: acc) seen [] |> List.sort String.compare

let pool_roots t (p : pool) : string list =
  let roles = List.filter (fun r -> List.mem r.role_name p.serves) t.roles in
  Option.to_list p.start
  @ List.concat_map (fun r -> Option.to_list r.body @ Option.to_list r.actor) roles

(** The roles a pool's reachable code initiates, each with the fn that does
    it: the derived half of [initiates] (D22). *)
let derived_initiates idx t (p : pool) : (string * string) list =
  List.concat_map (fun fn ->
      match Hashtbl.find_opt idx.initiate_refs fn with
      | Some rs -> List.map (fun r -> (r, fn)) rs
      | None -> [])
    (reachable idx (pool_roots t p))
  |> List.sort_uniq compare

let pool_initiates idx t p =
  match p.initiates with
  | Some written -> written
  | None -> List.sort_uniq String.compare (List.map fst (derived_initiates idx t p))

(* ── The static checks ─────────────────────────────────────────────────── *)

let check ~(index : index) (t : t) : diag list =
  let diags = ref [] in
  let add severity loc msg = diags := { loc; severity; msg } :: !diags in
  let err = add Error and warn = add Warning in
  let served_by role_name = List.filter (fun p -> List.mem role_name p.serves) t.pools in
  (* Roles: bindings resolve, names are real protocol roles. *)
  List.iter (fun r ->
      if not (role_exists index r.role_name) then begin
        match find_protocol index r.protocol with
        | None -> err r.role_loc (Printf.sprintf "\"%s\": no protocol named '%s' is declared in the project" r.role_name r.protocol)
        | Some (_, _, def) ->
          err r.role_loc (Printf.sprintf "\"%s\": protocol '%s' has no role '%s' (its roles: %s)"
                            r.role_name r.protocol r.role (String.concat ", " (proto_roles def)))
      end;
      (match r.body with
       | Some b when not (Hashtbl.mem index.fns b) ->
         err r.role_loc (Printf.sprintf "\"%s\": body '%s' is not a function declared in the project" r.role_name b)
       | _ -> ());
      (match r.actor with
       | Some a when not (Hashtbl.mem index.actors a) ->
         err r.role_loc (Printf.sprintf "\"%s\": actor '%s' is not an actor declared in the project" r.role_name a)
       | _ -> ());
      if served_by r.role_name = [] then
        err r.role_loc (Printf.sprintf "\"%s\" is bound but no pool serves it" r.role_name);
      (* Placement against the hosts of the pools that serve it. *)
      let hosts = List.concat_map (fun p -> p.hosts) (served_by r.role_name) in
      (match r.place with
       | Some { on = Some label; _ } when hosts <> [] ->
         if not (List.exists (fun h -> List.mem label h.labels) hosts) then
           err r.role_loc (Printf.sprintf "\"%s\": place.on = \"%s\", but no host of %s carries that label"
                             r.role_name label
                             (String.concat ", " (List.map (fun p -> "[pool." ^ p.pool_name ^ "]") (served_by r.role_name))))
       | _ -> ());
      (match r.place with
       | Some { count = Some n; on } when hosts <> [] ->
         let eligible =
           match on with
           | Some label -> List.filter (fun h -> List.mem label h.labels) hosts
           | None -> hosts
         in
         if n > List.length eligible then
           err r.role_loc (Printf.sprintf "\"%s\": place.count = %d, but only %d host%s %s"
                             r.role_name n (List.length eligible)
                             (if List.length eligible = 1 then "" else "s")
                             (match on with
                              | Some l -> Printf.sprintf "carr%s the label \"%s\"" (if List.length eligible = 1 then "ies" else "y") l
                              | None -> "serve it"))
       | _ -> ()))
    t.roles;
  (* Pools. *)
  List.iter (fun p ->
      List.iter (fun s ->
          if not (List.exists (fun r -> r.role_name = s) t.roles) then
            err (key_loc p "serves") (Printf.sprintf "[pool.%s] serves \"%s\", which has no binding in [roles]" p.pool_name s))
        p.serves;
      (match p.start with
       | Some s when not (Hashtbl.mem index.fns s) ->
         err (key_loc p "start") (Printf.sprintf "[pool.%s] start = \"%s\" is not a function declared in the project" p.pool_name s)
       | _ -> ());
      (match p.initiates with
       | Some written ->
         List.iter (fun r ->
             if not (role_exists index r) then
               err (key_loc p "initiates") (Printf.sprintf "[pool.%s] initiates \"%s\", which is not a role of any declared protocol" p.pool_name r))
           written;
         (* D22: a written list is an upper limit on what the code reaches. *)
         List.iter (fun (r, fn) ->
             if not (List.mem r written) then
               err (key_loc p "initiates")
                 (Printf.sprintf "[pool.%s] code initiates \"%s\" (in %s) but `initiates` does not list it" p.pool_name r fn))
           (derived_initiates index t p)
       | None -> ());
      if p.isolate then
        List.iter (fun s ->
            let others = List.filter (fun q -> q.pool_name <> p.pool_name) (served_by s) in
            if others <> [] then
              err (key_loc p "isolate")
                (Printf.sprintf "[pool.%s] is isolated but \"%s\" is also served by %s" p.pool_name s
                   (String.concat ", " (List.map (fun q -> "[pool." ^ q.pool_name ^ "]") others))))
          p.serves;
      (match p.main with
       | Some m ->
         warn (key_loc p "main")
           (Printf.sprintf "[pool.%s] main = \"%s\": a hand-written entry gives up level-0 composition (`forge run`) and runtime-owned offers" p.pool_name m)
       | None -> ());
      if p.serves = [] && p.start = None && p.main = None then
        warn p.pool_loc (Printf.sprintf "[pool.%s] serves nothing and has no `start` hook" p.pool_name);
      List.iter (fun h ->
          if not (String.contains h.host '@') && String.contains h.host ' ' then
            err (key_loc p "hosts") (Printf.sprintf "[pool.%s] host \"%s\" is not a host name" p.pool_name h.host))
        p.hosts)
    t.pools;
  (* D25: unlabelled steps in any protocol the topology names. *)
  let protocols_named =
    List.sort_uniq String.compare
      (List.map (fun r -> r.protocol) t.roles
       @ List.concat_map (fun p ->
           List.filter_map (fun r ->
               match String.split_on_char '.' r with [ pr; _ ] -> Some pr | _ -> None)
             (Option.value ~default:[] p.initiates))
         t.pools)
  in
  List.iter (fun pname ->
      match find_protocol index pname with
      | Some (_, _, def) ->
        let n = unlabelled_count def in
        if n > 0 then begin
          let loc =
            match List.find_opt (fun r -> r.protocol = pname) t.roles with
            | Some r -> r.role_loc
            | None -> { file = List.hd t.sources; line = 0 }
          in
          warn loc (Printf.sprintf "protocol '%s' has %d unlabelled step%s; positional names (Msg_A_B_n) renumber when a step is added before them, which changes wire tags on a hot deploy. Label each step: `label: A -> B : T`"
                      pname n (if n = 1 then "" else "s"))
        end
      | None -> ())
    protocols_named;
  List.iter (fun (path, msg) ->
      warn { file = path; line = 0 } (Printf.sprintf "could not parse %s (%s); names in it cannot be resolved" (Filename.basename path) msg))
    index.parse_errors;
  List.rev !diags

(* ── JSON ──────────────────────────────────────────────────────────────── *)

let json_opt f = function None -> `Null | Some v -> f v
let json_str s = `String s
let json_int n = `Int n
let json_strs l = `List (List.map json_str l)

let role_json r : Yojson.Safe.t =
  `Assoc [
    ("name", `String r.role_name);
    ("protocol", `String r.protocol);
    ("role", `String r.role);
    ("body", json_opt json_str r.body);
    ("actor", json_opt json_str r.actor);
    ("capacity", json_opt json_int r.capacity);
    ("place", json_opt (fun p -> `Assoc [ ("on", json_opt json_str p.on); ("count", json_opt json_int p.count) ]) r.place);
    ("set", `Bool r.set);
  ]

let pool_json p : Yojson.Safe.t =
  `Assoc [
    ("name", `String p.pool_name);
    ("start", json_opt json_str p.start);
    ("serves", json_strs p.serves);
    ("serves_all", `Bool p.serves_all);
    ("initiates", json_opt json_strs p.initiates);
    ("caps", json_opt json_strs p.caps);
    ("isolate", `Bool p.isolate);
    ("public", `List (List.map json_int p.public));
    ("main", json_opt json_str p.main);
    ("replicas", json_opt json_int p.replicas);
    ("hosts", `List (List.map (fun h -> `Assoc [ ("host", `String h.host); ("labels", json_strs h.labels) ]) p.hosts));
  ]

let digest_fields t : (string * Yojson.Safe.t) list =
  [
    ("version", `Int 1);
    ("env", json_opt json_str t.env);
    ("sources", json_strs (List.map Filename.basename t.sources));
    ("roles", `List (List.map role_json t.roles));
    ("pools", `List (List.map pool_json t.pools));
    ("drain", json_opt (fun d -> `Assoc [ ("soft_ms", json_opt json_int d.soft_ms); ("hard_ms", json_opt json_int d.hard_ms) ]) t.drain);
    ("backend", json_opt (fun b -> `Assoc [ ("kind", json_opt json_str b.kind); ("port", json_opt json_int b.port) ]) t.backend);
  ]

let digest_json t : Yojson.Safe.t = `Assoc (digest_fields t)

(** The digest's bytes, as [write_digest] writes them (a node hashes what it
    read, so the reconciler compares against the same bytes). *)
let digest_text t = Yojson.Safe.pretty_to_string (digest_json t) ^ "\n"

let write_digest ~root t =
  let dir = Filename.concat root ".forge" in
  if not (Sys.file_exists dir) then Sys.mkdir dir 0o755;
  let path = digest_file ~root in
  let oc = open_out_bin path in
  output_string oc (digest_text t);
  close_out oc;
  path

(** Read a digest back. Checks [version] is 1 first: a reader that skipped
    the check would accept a future schema and misread it. *)
let read_digest path : (t, string) result =
  match Yojson.Safe.from_file path with
  | exception Sys_error m -> Error m
  | exception Yojson.Json_error m -> Error (Printf.sprintf "%s: not JSON: %s" path m)
  | json ->
    let module U = Yojson.Safe.Util in
    try
      (match U.member "version" json with
       | `Int 1 -> ()
       | `Int n -> failwith (Printf.sprintf "%s: topology schema version %d, but this build reads version 1" path n)
       | _ -> failwith (Printf.sprintf "%s: missing \"version\" (expected 1)" path));
      let str_opt j = match j with `String s -> Some s | _ -> None in
      let int_opt j = match j with `Int n -> Some n | _ -> None in
      let strs j = match j with `List l -> List.filter_map str_opt l | _ -> [] in
      let strs_opt j = match j with `List _ -> Some (strs j) | _ -> None in
      let loc = { file = path; line = 0 } in
      let roles =
        List.map (fun j ->
            let name = U.to_string (U.member "name" j) in
            let protocol, role =
              match String.split_on_char '.' name with
              | [ p; r ] -> (p, r)
              | _ -> failwith (Printf.sprintf "%s: role name \"%s\" is not Protocol.Role" path name)
            in
            let place =
              match U.member "place" j with
              | `Assoc _ as pj -> Some { on = str_opt (U.member "on" pj); count = int_opt (U.member "count" pj) }
              | _ -> None
            in
            { role_name = name; protocol; role;
              body = str_opt (U.member "body" j); actor = str_opt (U.member "actor" j);
              capacity = int_opt (U.member "capacity" j); place;
              set = (match U.member "set" j with `Bool b -> b | _ -> false);
              role_loc = loc })
          (U.to_list (U.member "roles" json))
      in
      let pools =
        List.map (fun j ->
            { pool_name = U.to_string (U.member "name" j);
              start = str_opt (U.member "start" j);
              serves = strs (U.member "serves" j);
              serves_all = (match U.member "serves_all" j with `Bool b -> b | _ -> false);
              initiates = strs_opt (U.member "initiates" j);
              caps = strs_opt (U.member "caps" j);
              isolate = (match U.member "isolate" j with `Bool b -> b | _ -> false);
              public = (match U.member "public" j with `List l -> List.filter_map int_opt l | _ -> []);
              main = str_opt (U.member "main" j);
              replicas = int_opt (U.member "replicas" j);
              hosts = (match U.member "hosts" j with
                  | `List l -> List.map (fun h -> { host = U.to_string (U.member "host" h); labels = strs (U.member "labels" h) }) l
                  | _ -> []);
              pool_loc = loc; key_locs = [] })
          (U.to_list (U.member "pools" json))
      in
      let drain =
        match U.member "drain" json with
        | `Assoc _ as d -> Some { soft_ms = int_opt (U.member "soft_ms" d); hard_ms = int_opt (U.member "hard_ms" d) }
        | _ -> None
      in
      let backend =
        match U.member "backend" json with
        | `Assoc _ as b -> Some { kind = str_opt (U.member "kind" b); port = int_opt (U.member "port" b) }
        | _ -> None
      in
      Ok { roles; pools; drain; backend; env = str_opt (U.member "env" json); sources = strs (U.member "sources" json) }
    with
    | Failure m -> Error m
    | U.Type_error (m, _) -> Error (Printf.sprintf "%s: malformed topology digest: %s" path m)

(** The compiler's half of [--topology]: every bound name must be declared in
    the modules it loaded. Returns one message per unresolved name. *)
let unresolved_names ~(index : index) (t : t) : string list =
  List.concat_map (fun r ->
      (match r.body with
       | Some b when not (Hashtbl.mem index.fns b) ->
         [ Printf.sprintf "role \"%s\": body '%s' is not a function in the loaded modules" r.role_name b ]
       | _ -> [])
      @ (match r.actor with
          | Some a when not (Hashtbl.mem index.actors a) ->
            [ Printf.sprintf "role \"%s\": actor '%s' is not an actor in the loaded modules" r.role_name a ]
          | _ -> [])
      @ (if role_exists index r.role_name then []
         else [ Printf.sprintf "role \"%s\": no protocol '%s' with a role '%s' in the loaded modules" r.role_name r.protocol r.role ]))
    t.roles
  @ List.concat_map (fun p ->
      match p.start with
      | Some s when not (Hashtbl.mem index.fns s) ->
        [ Printf.sprintf "pool \"%s\": start '%s' is not a function in the loaded modules" p.pool_name s ]
      | _ -> [])
    t.pools

(* ── Connectivity and export ───────────────────────────────────────────── *)

type edge = { e_from : string; e_to : string; e_protocols : string list }

(** The roles a pool takes part in: what it serves plus what it initiates
    (written, else derived). *)
let pool_roles idx t p = List.sort_uniq String.compare (p.serves @ pool_initiates idx t p)

let connectivity (idx : index) (t : t) : edge list =
  let pools = List.map (fun p -> (p.pool_name, pool_roles idx t p)) t.pools in
  let talk (ra : string) (rb : string) =
    match String.split_on_char '.' ra, String.split_on_char '.' rb with
    | [ pa; a ], [ pb; b ] when pa = pb ->
      (match find_protocol idx pa with
       | Some (_, _, def) when are_peers def a b -> Some pa
       | _ -> None)
    | _ -> None
  in
  let edges = ref [] in
  List.iter (fun (na, ra) ->
      List.iter (fun (nb, rb) ->
          if na <= nb then begin
            let protos =
              List.concat_map (fun x -> List.filter_map (fun y -> talk x y) rb) ra
              |> List.sort_uniq String.compare
            in
            if protos <> [] then edges := { e_from = na; e_to = nb; e_protocols = protos } :: !edges
          end)
        pools)
    pools;
  List.rev !edges

(** [compiler]: each pool's derived caps and initiated roles as the compiler
    computed them (`march --topology ... --emit-core-ast`'s [topology]
    object, [Topology_run.compiler_derived]). Given, they replace the
    name-based [initiates] and the [null] [caps]; without them (no toolchain,
    or a program that does not typecheck) [caps] stays [null], never a guess. *)
let export_json ?(compiler : (string * (string list * string list)) list option) ~(index : index) (t : t)
  : Yojson.Safe.t =
  `Assoc (
    digest_fields t
    @ [
      ("derived", `Assoc (List.map (fun p ->
           match Option.bind compiler (List.assoc_opt p.pool_name) with
           | Some (caps, initiates) ->
             (p.pool_name, `Assoc [
                 ("initiates", json_strs initiates);
                 ("caps", json_strs caps);
                 ("source", `String "compiler");
               ])
           | None ->
             (p.pool_name, `Assoc [
                 ("initiates", json_strs (List.sort_uniq String.compare (List.map fst (derived_initiates index t p))));
                 ("caps", `Null);
                 ("source", `String "names");
               ])) t.pools));
      ("connectivity", `List (List.map (fun e ->
           `Assoc [ ("from", `String e.e_from); ("to", `String e.e_to); ("protocols", json_strs e.e_protocols) ])
           (connectivity index t)));
      ("cluster_port", `Int (cluster_port t));
    ])

(** The export as a value the generators read: parsed back from the digest
    fields plus the derived edges, so an external generator and a built-in
    one see the same facts. *)
type export = { topo : t; edges : edge list; port : int }

let export_of_json (json : Yojson.Safe.t) : (export, string) result =
  let module U = Yojson.Safe.Util in
  let tmp = Filename.temp_file "forge-topology-" ".json" in
  let oc = open_out_bin tmp in
  output_string oc (Yojson.Safe.to_string json);
  close_out oc;
  let r = read_digest tmp in
  (try Sys.remove tmp with Sys_error _ -> ());
  match r with
  | Error m -> Error m
  | Ok topo ->
    (try
       let edges =
         match U.member "connectivity" json with
         | `List l ->
           List.map (fun e ->
               { e_from = U.to_string (U.member "from" e);
                 e_to = U.to_string (U.member "to" e);
                 e_protocols = List.map U.to_string (U.to_list (U.member "protocols" e)) })
             l
         | _ -> []
       in
       let port = match U.member "cluster_port" json with `Int n -> n | _ -> default_cluster_port in
       Ok { topo; edges; port }
     with U.Type_error (m, _) -> Error ("malformed export: " ^ m))

(* ── Generators ────────────────────────────────────────────────────────── *)

module Gen = struct
  (** Replace every [{{key}}] in an embedded template. Plain substring
      replacement: a value is inserted literally, whatever it contains. *)
  let replace_all ~sub ~by s =
    let ls = String.length sub and n = String.length s in
    let b = Buffer.create n in
    let rec go i =
      if i > n - ls then Buffer.add_string b (String.sub s i (n - i))
      else if String.sub s i ls = sub then (Buffer.add_string b by; go (i + ls))
      else (Buffer.add_char b s.[i]; go (i + 1))
    in
    if ls = 0 then s else (go 0; Buffer.contents b)

  let render (tmpl : string) (vars : (string * string) list) : string =
    let tmpl =
      (* The dune embed rule puts a newline before the file's first byte. *)
      if String.length tmpl > 0 && tmpl.[0] = '\n' then String.sub tmpl 1 (String.length tmpl - 1) else tmpl
    in
    List.fold_left (fun acc (k, v) -> replace_all ~sub:("{{" ^ k ^ "}}") ~by:v acc) tmpl vars

  let host_name h =
    match String.index_opt h.host '@' with
    | Some i -> String.sub h.host (i + 1) (String.length h.host - i - 1)
    | None -> h.host

  let stop_sec t =
    match t.drain with
    | Some { hard_ms = Some ms; _ } -> (ms + 999) / 1000
    | _ -> 120

  let peers_of (ex : export) pool =
    List.filter_map (fun e ->
        if e.e_from = pool then Some e.e_to
        else if e.e_to = pool then Some e.e_from
        else None)
      ex.edges
    |> List.sort_uniq String.compare

  let binary_name ~project (p : pool) =
    if p.isolate then project ^ "-" ^ p.pool_name else project

  (** The pool-level environment every node of [p] shares (the runtime's
      names: [MARCH_POOLS], [MARCH_TOPOLOGY_FILE]). *)
  let pool_environment ~project (p : pool) =
    [ ("MARCH_POOLS", p.pool_name);
      ("MARCH_TOPOLOGY_FILE", Printf.sprintf "/etc/march/%s/topology.json" project) ]

  let environment_lines (env : (string * string) list) =
    String.concat "\n" (List.map (fun (k, v) -> Printf.sprintf "Environment=%s=%s" k v) env)

  (** One pool's unit. [environment] is written as [Environment=] lines;
      [forge topology gen systemd] gives the pool-level ones, [forge host
      init] each host's own (node name, labels, ports, seeds, sockets). *)
  let systemd_unit ?(generator = "forge topology gen systemd") ~project ~(topo : t) ~environment (p : pool) =
    render Topology_tmpl_systemd.content [
      ("pool", p.pool_name);
      ("project", project);
      ("generator", generator);
      ("user", "march");
      ("exec", Printf.sprintf "/opt/march/%s/%s" project (binary_name ~project p));
      ("environment", environment_lines environment);
      ("stop_sec", string_of_int (stop_sec topo));
      ("roles", if p.serves = [] then "(no roles; hook only)" else String.concat " " p.serves);
    ]

  (** One output file per pool: `march-<pool>.service`. *)
  let systemd ~project (ex : export) : (string * string) list =
    List.map (fun p ->
        ( Printf.sprintf "march-%s.service" p.pool_name,
          systemd_unit ~project ~topo:ex.topo
            ~environment:(pool_environment ~project p
                          @ [ ("MARCH_TOPOLOGY_STATUS", Printf.sprintf "/var/lib/march/%s/run/%s.status" project p.pool_name);
                              ("MARCH_HOT_RELOAD_SOCKET", Printf.sprintf "/var/lib/march/%s/run/%s.sock" project p.pool_name);
                              ("HOME", Printf.sprintf "/var/lib/march/%s" project) ])
            p ))
      ex.topo.pools

  (** One shell script per host: its pool's public ports from anywhere, the
      cluster port from every host of every pool it talks to (itself
      included when its pool talks to itself and spans several hosts). *)
  let ufw (ex : export) : (string * string) list =
    let hosts_of pool =
      match List.find_opt (fun p -> p.pool_name = pool) ex.topo.pools with
      | Some p -> p.hosts
      | None -> []
    in
    List.concat_map (fun p ->
        List.map (fun h ->
            let me = host_name h in
            let public =
              List.map (fun port -> Printf.sprintf "ufw allow %d/tcp comment 'march %s public'" port p.pool_name) p.public
            in
            let cluster =
              List.concat_map (fun peer ->
                  List.filter_map (fun ph ->
                      let pn = host_name ph in
                      if pn = me then None
                      else Some (Printf.sprintf "ufw allow from %s to any port %d proto tcp comment 'march cluster from %s'" pn ex.port peer))
                    (hosts_of peer))
                (peers_of ex p.pool_name)
            in
            let rules = String.concat "\n" (public @ cluster) in
            ( Printf.sprintf "ufw-%s.sh" me,
              render Topology_tmpl_ufw.content [
                ("host", me); ("pool", p.pool_name);
                ("rules", if rules = "" then "# no inbound rules" else rules);
              ] ))
          p.hosts)
      ex.topo.pools

  (** One DigitalOcean firewall per pool, keyed by droplet tag `march-<pool>`. *)
  let do_firewall (ex : export) : (string * string) list =
    let rule_json port sources =
      `Assoc [ ("protocol", `String "tcp"); ("ports", `String (string_of_int port)); ("sources", `Assoc sources) ]
    in
    let firewalls =
      List.map (fun p ->
          let public =
            List.map (fun port -> rule_json port [ ("addresses", `List [ `String "0.0.0.0/0"; `String "::/0" ]) ]) p.public
          in
          let peers = peers_of ex p.pool_name in
          let cluster =
            if peers = [] then []
            else [ rule_json ex.port [ ("tags", `List (List.map (fun peer -> `String ("march-" ^ peer)) peers)) ] ]
          in
          `Assoc [
            ("name", `String ("march-" ^ p.pool_name));
            ("tags", `List [ `String ("march-" ^ p.pool_name) ]);
            ("inbound_rules", `List (public @ cluster));
            ("outbound_rules", `List [
                `Assoc [ ("protocol", `String "tcp"); ("ports", `String "all");
                         ("destinations", `Assoc [ ("addresses", `List [ `String "0.0.0.0/0"; `String "::/0" ]) ]) ];
                `Assoc [ ("protocol", `String "udp"); ("ports", `String "all");
                         ("destinations", `Assoc [ ("addresses", `List [ `String "0.0.0.0/0"; `String "::/0" ]) ]) ];
              ]);
          ])
        ex.topo.pools
    in
    [ ("do-firewalls.json",
       render Topology_tmpl_do_firewall.content [
         ("firewalls", Yojson.Safe.pretty_to_string (`List firewalls));
       ]) ]

  (** A docker-compose file with one service per pool. *)
  let compose ~project (ex : export) : (string * string) list =
    let services =
      String.concat "\n" (List.map (fun p ->
          let replicas =
            match p.replicas with
            | Some n -> n
            | None -> max 1 (List.length p.hosts)
          in
          let ports =
            if p.public = [] then ""
            else
              "    ports:\n"
              ^ String.concat "\n" (List.map (fun port -> Printf.sprintf "      - \"%d:%d\"" port port) p.public)
              ^ "\n"
          in
          let rendered =
            render Topology_tmpl_compose_service.content [
              ("pool", p.pool_name);
              ("image", Printf.sprintf "%s:%s" project (if p.isolate then p.pool_name else "latest"));
              ("replicas", string_of_int replicas);
              ("ports", ports);
            ]
          in
          (* One newline between services, whatever the template and the
             optional ports block left behind. *)
          let n = ref (String.length rendered) in
          while !n > 0 && rendered.[!n - 1] = '\n' do decr n done;
          String.sub rendered 0 !n ^ "\n") ex.topo.pools)
    in
    [ ("docker-compose.yml",
       render Topology_tmpl_compose.content [ ("project", project); ("services", services) ]) ]

  let builtins = [ "systemd"; "ufw"; "do-firewall"; "compose" ]

  let builtin ~project target ex =
    match target with
    | "systemd" -> Some (systemd ~project ex)
    | "ufw" -> Some (ufw ex)
    | "do-firewall" -> Some (do_firewall ex)
    | "compose" -> Some (compose ~project ex)
    | _ -> None

  (** Print a file set as one stream, each file behind a `# ==> name <==`
      line (the `head` convention), or write them under [out]. *)
  let emit ?out (files : (string * string) list) =
    match out with
    | None ->
      List.iter (fun (name, content) ->
          Printf.printf "# ==> %s <==\n%s%s" name content
            (if content <> "" && content.[String.length content - 1] = '\n' then "" else "\n"))
        files
    | Some dir ->
      if not (Sys.file_exists dir) then Sys.mkdir dir 0o755;
      List.iter (fun (name, content) ->
          let path = Filename.concat dir name in
          let oc = open_out_bin path in
          output_string oc content;
          close_out oc;
          Printf.printf "wrote %s\n" path)
        files

  (** Look up [forge-topology-<target>] on PATH. *)
  let path_lookup name =
    let path = try Sys.getenv "PATH" with Not_found -> "" in
    List.find_map (fun dir ->
        let cand = Filename.concat dir name in
        if dir <> "" && Sys.file_exists cand && not (Sys.is_directory cand) then Some cand else None)
      (String.split_on_char ':' path)

  (** Run an external generator with the export JSON on its stdin; its stdout
      is the user's. Returns its exit code. *)
  let run_external exe (json : Yojson.Safe.t) : int =
    let tmp = Filename.temp_file "forge-topology-" ".json" in
    let oc = open_out_bin tmp in
    output_string oc (Yojson.Safe.pretty_to_string json);
    output_char oc '\n';
    close_out oc;
    let rc = Sys.command (Printf.sprintf "%s < %s" (Filename.quote exe) (Filename.quote tmp)) in
    (try Sys.remove tmp with Sys_error _ -> ());
    rc
end

(* ── The gate: what `forge build`/`run`/`deploy` call ──────────────────── *)

(** With a `topology.toml` in the project: load (plus the [env] overlay when
    one exists for that name), check against the project's parse, print
    warnings, and write the digest. Errors are printed and turn into
    [Error]; without a topology file this is a no-op. *)
let gate ?env ~(proj : Project.project) () : (unit, string) result =
  let root = proj.Project.root in
  if not (exists ~root) then Ok ()
  else begin
    let env =
      match env with
      | Some e when Sys.file_exists (overlay_file ~root e) -> Some e
      | _ -> None
    in
    match load ~root ?env () with
    | Error ds ->
      List.iter (fun d -> prerr_endline (render_diag d)) ds;
      Error (Printf.sprintf "topology check failed (%d error%s)" (List.length ds) (if List.length ds = 1 then "" else "s"))
    | Ok t ->
      let index = index_project ~root in
      let ds = check ~index t in
      List.iter (fun d -> prerr_endline (render_diag d)) ds;
      if has_errors ds then begin
        let n = List.length (List.filter (fun d -> d.severity = Error) ds) in
        Error (Printf.sprintf "topology check failed (%d error%s)" n (if n = 1 then "" else "s"))
      end else begin
        ignore (write_digest ~root t);
        Ok ()
      end
  end
