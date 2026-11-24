(* Literal targets against a scoped bound (ocap phase 6, Q3).

   One helper that runs the module-scope literal checks over a set of
   functions, against given scope entries:
   - hosts: a literal URL (or a literal URL prefix concatenated with more) at
     a network entry point's destination argument, judged by
     [March_caps.Host_scope] (host, port, path, and the entry point's fixed
     method);
   - paths: a literal path at a filesystem builtin or entry point
     ([Typecheck_caps.literal_path_uses]), judged by [March_caps.Cap_scope];
   - names: a literal name at a name-taking function
     ([Typecheck_caps.name_uses]), judged by [March_caps.Name_scope].

   Only definite violations are found: a computed target is left to the
   run-time check, as is any capability no entry covers (the kind check
   reports that one) and any capability an unscoped entry covers.

   Turned on for dependency grants only ([Typecheck.check_dep_grants],
   [dep_grant_scope]).  A scoped `needs` clause or a literal `restrict` can
   call [check] with its own entries and wording; that is the open half of
   specs/todos/2026-11-17-ocap-scoped-fn-needs-literal-check.md. *)

open Typecheck_types

type what = Host | Path | Name

type finding = {
  fn : string;  (** the key of the function the literal is in *)
  cap : string;  (** the capability the operation needs *)
  target : string;  (** the literal, as written *)
  what : what;
  span : Ast.span;  (** the literal's span *)
}

(* The network entry points that take a destination URL, and the argument it
   sits at: the stdlib functions marked `@[net_dest(url)]`
   (stdlib/http_client.march, stdlib/http_transport.march). *)
let url_entry_points : (string * int) list = [
  ("HttpClient.get", 1); ("HttpClient.post", 1); ("HttpClient.put_request", 1);
  ("HttpClient.delete", 1); ("HttpClient.with_connection", 1);
  ("HttpClient.stream_get", 1); ("HttpTransport.simple_get", 0);
]

let callee_name (f : Ast.expr) : string option =
  match f with
  | Ast.EVar fn -> Some fn.Ast.txt
  | Ast.EField (Ast.EVar m, fn, _) | Ast.EField (Ast.ECon (m, [], _), fn, _) ->
    Some (m.Ast.txt ^ "." ^ fn.Ast.txt)
  | _ -> None

(* (entry point, literal, whether it is only a prefix, its span), in source
   order. *)
let literal_urls (e : Ast.expr) : (string * string * bool * Ast.span) list =
  let acc = ref [] in
  let rec go (e : Ast.expr) =
    (match e with
     | Ast.EApp (f, args, _) -> (
       match Option.bind (callee_name f) (fun n ->
           Option.map (fun i -> (n, i)) (List.assoc_opt n url_entry_points)) with
       | Some (n, i) -> (
         match List.nth_opt args i with
         | Some (Ast.ELit (Ast.LitString s, sp)) -> acc := (n, s, false, sp) :: !acc
         | Some (Ast.EApp (Ast.EVar op, [ Ast.ELit (Ast.LitString s, sp); _ ], _))
           when op.Ast.txt = "++" -> acc := (n, s, true, sp) :: !acc
         | _ -> ())
       | None -> ())
     | _ -> ());
    sub e
  and sub (e : Ast.expr) =
    match e with
    | Ast.ELit _ | Ast.EVar _ | Ast.EHole _ | Ast.EResultRef _ | Ast.EDbg (None, _) -> ()
    | Ast.EDbg (Some x, _) | Ast.EField (x, _, _) | Ast.EAnnot (x, _, _) | Ast.ESpawn (x, _)
    | Ast.EAssert (x, _) | Ast.ESigil (_, x, _) | Ast.ERefineMsg (x, _, _)
    | Ast.ELam (_, x, _) | Ast.ELetFn (_, _, _, x, _) -> go x
    | Ast.EApp (h, args, _) -> go h; List.iter go args
    | Ast.ECon (_, xs, _) | Ast.EAtom (_, xs, _) | Ast.ETuple (xs, _) | Ast.EBlock (xs, _) ->
      List.iter go xs
    | Ast.ELet (b, _) -> go b.Ast.bind_expr
    | Ast.EMatch (scrut, branches, _) ->
      go scrut;
      List.iter (fun (br : Ast.branch) ->
          Option.iter go br.Ast.branch_guard; go br.Ast.branch_body) branches
    | Ast.ERecord (fields, _) -> List.iter (fun (_, x) -> go x) fields
    | Ast.ERecordUpdate (base, fields, _) -> go base; List.iter (fun (_, x) -> go x) fields
    | Ast.EIf (c, t, f, _) -> go c; go t; go f
    | Ast.ERestrict (es, b, _) -> List.iter go es; go b
    | Ast.ECond (arms, _) -> List.iter (fun (c, b) -> go c; go b) arms
    | Ast.EPipe (a, b, _) | Ast.ESend (a, b, _) | Ast.ELetQ (_, a, b, _)
    | Ast.ELetStar (_, a, b, _) -> go a; go b
    | Ast.EProof (p, _) -> List.iter go (Ast.proof_children p)
  in
  go e;
  List.rev !acc

(* The entries that cover [cap]: [None] when none does (the kind check's
   business) or an unscoped one does (anything goes), else the scopes. *)
let scopes_covering (entries : (string * string option) list) (cap : string)
    : string list option =
  let relevant = List.filter (fun (c, _) -> March_caps.Cap_lattice.cap_subsumes c cap) entries in
  if relevant = [] || List.exists (fun (_, sc) -> sc = None) relevant then None
  else Some (List.filter_map snd relevant)

let host_violation (entries : (string * string option) list) (entry : string)
    (url : string) ~(prefix : bool) : bool =
  match scopes_covering entries "IO.NetConnect" with
  | None -> false
  | Some scopes -> (
    let decls =
      List.filter_map (fun s -> Result.to_option (March_caps.Host_scope.parse_decl (Some s)))
        scopes
    in
    if decls = [] then false
    else
      match March_caps.Host_scope.authority_of_url ~prefix url with
      | None -> false (* not a literal the compiler vouches for: run time *)
      | Some { March_caps.Host_scope.a_host = host; a_port = port } ->
        let meth = March_caps.Net_dest.method_of entry in
        if prefix then
          not (March_caps.Host_scope.permits_host_ignoring_path decls ~host ~port ~meth)
        else
          let path = March_caps.Host_scope.url_path_of_literal ~prefix:false url in
          not (March_caps.Host_scope.permits_request decls ~host ~port ~meth ~path))

(** Every definite violation in [fns] (each a key and its bodies), against
    [entries] ((capability, scope) pairs), in the order the functions are
    given and, within one, in source order. *)
let find ~(entries : (string * string option) list)
    (fns : (string * Ast.expr list) list) : finding list =
  List.concat_map (fun (fn, bodies) ->
      List.concat_map (fun body ->
          let hosts =
            List.filter_map (fun (entry, url, prefix, span) ->
                if host_violation entries entry url ~prefix then
                  Some { fn; cap = "IO.NetConnect"; target = url; what = Host; span }
                else None)
              (literal_urls body)
          in
          let paths =
            List.filter_map (fun (builtin, path, span) ->
                match List.assoc_opt builtin Typecheck_builtins.builtin_cap_table with
                | None -> None
                | Some cap -> (
                  match scopes_covering entries cap with
                  | Some scopes
                    when not (List.exists (fun scope -> March_caps.Cap_scope.within ~scope path) scopes) ->
                    Some { fn; cap; target = path; what = Path; span }
                  | _ -> None))
              (List.rev (Typecheck_caps.literal_path_uses [] body))
          in
          let names =
            List.filter_map (function
                | Typecheck_caps.NameLit (_, cap, name, span) -> (
                  match Typecheck_caps.name_scopes_for entries cap with
                  | Some ss when not (List.exists (fun s -> March_caps.Name_scope.admits s name) ss) ->
                    Some { fn; cap; target = name; what = Name; span }
                  | _ -> None)
                | _ -> None)
              (List.rev (Typecheck_caps.name_uses [] body))
          in
          List.sort (fun a b ->
              compare (a.span.Ast.start_line, a.span.Ast.start_col)
                (b.span.Ast.start_line, b.span.Ast.start_col))
            (hosts @ paths @ names))
        bodies)
    fns

(** The verb phrase a diagnostic uses for a finding: "connects to `h`". *)
let describe (f : finding) : string =
  match f.what with
  | Host -> Printf.sprintf "connects to `%s`" f.target
  | Path -> Printf.sprintf "uses the path `%s`" f.target
  | Name -> Printf.sprintf "uses the name `%s`" f.target

(** Run [find] and hand each finding to [report], which words and files it
    under the caller's code. *)
let check ~(entries : (string * string option) list) ~(report : finding -> unit)
    (fns : (string * Ast.expr list) list) : unit =
  List.iter report (find ~entries fns)
