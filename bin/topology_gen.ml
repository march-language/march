(** [--topology]: the driver's half of a topology app (build step 3).

    [Desugar_topology] reads the AST and writes March source; this module
    converts forge's digest into its input, parses what it writes, splices
    the result into the entry module and its imports, and after
    typechecking derives each pool's capabilities and initiated roles from
    the solved capability rows (D22) and enforces a written [caps] against
    them. The generated code is parsed from source for the same reason the
    capability-dispatch wrappers are: it is then checked like hand-written
    code. *)

module Ast = March_ast.Ast
module DT = March_desugar.Desugar_topology
module FT = March_forge.Topology

let of_digest (t : FT.t) : DT.t =
  let place (r : FT.role) =
    match r.place with
    | None -> DT.Everywhere
    | Some { on = Some l; count = Some n } -> DT.Count_on (l, n)
    | Some { on = Some l; count = None } -> DT.On l
    | Some { on = None; count = Some n } -> DT.Count n
    | Some { on = None; count = None } -> DT.Everywhere
  in
  { DT.roles =
      List.map (fun (r : FT.role) ->
          { DT.r_name = r.role_name; r_protocol = r.protocol; r_role = r.role; r_body = r.body;
            r_actor = r.actor; r_capacity = r.capacity; r_place = place r })
        t.roles;
    pools =
      List.map (fun (p : FT.pool) ->
          { DT.p_name = p.pool_name; p_start = p.start; p_serves = p.serves; p_caps = p.caps;
            p_isolate = p.isolate })
        t.pools;
    soft_ms = (match t.drain with Some { soft_ms = Some n; _ } -> n | _ -> DT.default_soft_ms);
    hard_ms = (match t.drain with Some { hard_ms = Some n; _ } -> n | _ -> DT.default_hard_ms) }

(** Parse [src] (declarations) as a module body and desugar it. *)
let parse_decls ~(fname : string) (src : string) : Ast.decl list =
  let text = "mod TopologyGenerated do\n" ^ src ^ "end\n" in
  let lexbuf = Lexing.from_string text in
  lexbuf.Lexing.lex_curr_p <- { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = fname };
  let m =
    try March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf
    with _ ->
      Printf.eprintf "march: internal error: the generated topology code does not parse:\n%s\n" text;
      exit 2
  in
  (March_desugar.Desugar.desugar_module m).Ast.mod_decls

(** The state carried from before typechecking to after it. *)
type session = { facts : DT.facts; topo : DT.t; pools : string list option; generated : bool }

(** Check the digest against the loaded modules and, when the entry module
    has no [main], generate one. Returns the (possibly extended) entry
    declarations and imports. Exits 1 on an error. *)
let prepare ~path ~(entry : Ast.module_) ~(imports : Ast.decl list) ~pools ~foreign_isolated
    (digest : FT.t) : Ast.decl list * Ast.decl list * session =
  let entry_name = entry.Ast.mod_name.Ast.txt in
  let entry_decls = entry.Ast.mod_decls in
  let index = FT.index_of_decls [ (entry_name, entry_decls); ("", imports) ] in
  let fail errs =
    List.iter (fun e -> Printf.eprintf "%s: error: topology: %s\n" path e) errs;
    exit 1
  in
  (match FT.unresolved_names ~index digest with [] -> () | errs -> fail errs);
  (match pools with
   | Some ps ->
     (match List.filter (fun p -> not (List.exists (fun (q : FT.pool) -> q.pool_name = p) digest.pools)) ps with
      | [] -> ()
      | bad -> fail (List.map (Printf.sprintf "--topology-pools: no pool \"%s\" in the topology") bad))
   | None -> ());
  let topo = of_digest digest in
  let facts = DT.collect ~entry:entry_name ~entry_decls ~imports in
  (match DT.check ~foreign_isolated ?pools facts topo with [] -> () | errs -> fail errs);
  if DT.has_main entry_decls then begin
    Printf.eprintf
      "%s: warning: topology: `%s` has its own `main`, so none is generated: it gives up \
       level-0 composition and runtime-owned offers (the escape hatch of plan 4.1)\n"
      path entry_name;
    (entry_decls, imports, { facts; topo; pools; generated = false })
  end else begin
    let helpers = DT.helper_sources ?pools facts topo in
    let entry_decls, imports =
      List.fold_left (fun (ed, im) (mpath, src) ->
          let ds = parse_decls ~fname:"<topology>" src in
          match mpath with
          | m :: rest when m = entry_name -> (DT.insert_at rest ds ed, im)
          | _ -> (ed, DT.insert_at mpath ds im))
        (entry_decls, imports) helpers
    in
    let main = parse_decls ~fname:"<topology>" (DT.main_source ?pools facts topo) in
    if Sys.getenv_opt "MARCH_DUMP_TOPOLOGY_MAIN" = Some "1" then begin
      List.iter (fun (p, s) -> Printf.eprintf "-- helpers in %s\n%s" (String.concat "." p) s) helpers;
      prerr_string (DT.main_source ?pools facts topo)
    end;
    (entry_decls @ main, imports, { facts; topo; pools; generated = true })
  end

(* ── After typechecking ────────────────────────────────────────────────── *)

let is_io c = c = "IO" || (String.length c > 3 && String.sub c 0 3 = "IO.")

(** A reference [r] made from the row key [from], resolved the way the row
    solver does: under each enclosing module of [from] first, then as written. *)
let resolve (tbl : (string, 'a) Hashtbl.t) ~from (r : string) : string option =
  let parts = String.split_on_char '.' from in
  let rec prefixes acc = function
    | [] | [ _ ] -> acc
    | p -> prefixes (String.concat "." (List.rev (List.tl (List.rev p))) :: acc) (List.rev (List.tl (List.rev p)))
  in
  let cands = List.rev_map (fun p -> p ^ "." ^ r) (prefixes [] parts) @ [ r ] in
  List.find_opt (Hashtbl.mem tbl) cands

(** Each pool's derived capabilities (IO caps its hook and roles reach) and
    initiated roles (the [<P>_Run.initiate_<R>] its code reaches), with the
    root each cap is first reached from. *)
let derive (s : session) (env : March_typecheck.Typecheck.env)
  : (string * (string * string) list * string list) list =
  let closures = March_typecheck.Typecheck.fn_transitive_capability_closures_tbl env in
  let refs : (string, string list) Hashtbl.t = env.March_typecheck.Typecheck.fn_refs in
  let key q = DT.ref_of s.facts q in
  let reachable roots =
    let seen = Hashtbl.create 64 in
    let rec go k =
      if not (Hashtbl.mem seen k) then begin
        Hashtbl.replace seen k ();
        List.iter (fun r ->
            match resolve refs ~from:k r with
            | Some k' -> go k'
            | None -> Hashtbl.replace seen r ())
          (Option.value ~default:[] (Hashtbl.find_opt refs k))
      end
    in
    List.iter go roots;
    Hashtbl.fold (fun k () acc -> k :: acc) seen []
  in
  let initiate_of (k : string) =
    (* "...<P>_Run.initiate_<R>" -> "P.R" *)
    match List.rev (String.split_on_char '.' k) with
    | leaf :: m :: _ ->
      let ml = String.length m and ll = String.length leaf in
      if ml > 4 && String.sub m (ml - 4) 4 = "_Run" && ll > 9 && String.sub leaf 0 9 = "initiate_" then
        Some (String.sub m 0 (ml - 4) ^ "." ^ String.sub leaf 9 (ll - 9))
      else None
    | _ -> None
  in
  List.map (fun (p : DT.pool) ->
      let roots = DT.pool_roots s.facts s.topo p in
      let caps =
        List.concat_map (fun (label, q) ->
            List.filter_map (fun c -> if is_io c then Some (c, label) else None)
              (Option.value ~default:[] (Hashtbl.find_opt closures (key q))))
          roots
      in
      let caps =
        List.fold_left (fun acc (c, l) -> if List.mem_assoc c acc then acc else acc @ [ (c, l) ]) [] caps
        |> List.sort (fun (a, _) (b, _) -> String.compare a b)
      in
      let initiates =
        reachable (List.map (fun (_, q) -> key q) roots)
        |> List.filter_map initiate_of
        |> List.sort_uniq String.compare
      in
      (p.p_name, caps, initiates))
    (DT.selected_pools ?pools:s.pools s.topo)

(** Errors: a pool whose code reaches beyond its written [caps] (D22: written
    is an upper limit), naming the hook or role that reaches it. *)
let reach_errors (s : session) derived : string list =
  List.concat_map (fun (pn, caps, _) ->
      match List.find_opt (fun (p : DT.pool) -> p.p_name = pn) s.topo.pools with
      | Some { p_caps = Some written; _ } ->
        List.filter_map (fun (c, from) ->
            if DT.subsumes written c then None
            else
              Some (Printf.sprintf "pool \"%s\": its %s reaches `%s`, beyond the pool's written caps [%s]"
                      pn from c (String.concat ", " written)))
          caps
      | _ -> [])
    derived

(** The [topology] object of [--emit-core-ast]'s JSON. *)
let json (s : session) derived : string =
  let str = March_dump.Dump.json_string in
  let strs l = March_dump.Dump.json_list (List.map str l) in
  March_dump.Dump.json_obj [
    ("version", "1");
    ("generated_main", if s.generated then "true" else "false");
    ("pools", March_dump.Dump.json_obj (List.map (fun (pn, caps, inits) ->
         (pn, March_dump.Dump.json_obj [
             ("caps", strs (List.map fst caps));
             ("reached_from", March_dump.Dump.json_obj (List.map (fun (c, l) -> (c, str l)) caps));
             ("initiates", strs inits);
           ]))
         derived));
  ]
