(* Host scopes on IO.NetConnect, checked on post-lowering TIR.
   See net_scope.mli and specs/2026-11-09-host-scoped-network-capabilities-design.md. *)

module H = March_caps.Host_scope
module D = March_caps.Net_dest
module SMap = Map.Make (String)
module SSet = Set.Make (String)

type violation = { code : string; owner : string; fn_name : string; message : string }

let describe v = v.message

(* What a variable holds, as far as destinations go. *)
type value =
  | VLit of string  (** a string literal *)
  | VPrefix of string  (** a string that starts with this literal *)
  | VInt of int
  | VParam of int  (** the enclosing top-level function's parameter i *)
  | VOther

type site = { callee : string; args : value list }

(* Where a parameter's value was seen: as argument [k] of a direct call to
   [callee], or anywhere else. *)
type use = At of string * int | Elsewhere

type fn_info = {
  name : string;
  params : Tir.var list;
  sites : site list;
  fn_values : string list;  (** top-level names passed as VALUES *)
  param_uses : (int * use) list;
}

let is_concat n = n = "++" || n = "string_concat"

(* ── Collecting call sites ─────────────────────────────────────────── *)

let collect ~(is_defined : string -> bool) (fn : Tir.fn_def) : fn_info =
  let sites = ref [] and fn_values = ref [] and uses = ref [] in
  let value_of env (a : Tir.atom) =
    match a with
    | Tir.ALit (March_ast.Ast.LitString s) -> VLit s
    | Tir.ALit (March_ast.Ast.LitInt n) -> VInt n
    | Tir.AVar v -> Option.value ~default:VOther (SMap.find_opt v.Tir.v_name env)
    | _ -> VOther
  in
  let note env bound ctx (a : Tir.atom) =
    (match value_of env a with
     | VParam i -> uses := (i, ctx) :: !uses
     | _ -> ());
    match a with
    | Tir.AVar v when not (SSet.mem v.Tir.v_name bound) ->
      let n = v.Tir.v_name in
      if is_defined n || D.builtin_dest n <> None then fn_values := n :: !fn_values
    | _ -> ()
  in
  let notes env bound atoms = List.iter (note env bound Elsewhere) atoms in
  let rec walk env bound (e : Tir.expr) =
    match e with
    | Tir.EApp (f, args) when SSet.mem f.Tir.v_name bound ->
      (* A call through a local or parameter: a callback, charged to whoever
         supplied it. *)
      notes env bound args
    | Tir.EApp (f, args) ->
      sites := { callee = f.Tir.v_name; args = List.map (value_of env) args } :: !sites;
      List.iteri
        (fun k a ->
           (match value_of env a with
            | VParam i -> uses := (i, At (f.Tir.v_name, k)) :: !uses
            | _ -> ());
           match a with
           | Tir.AVar v when not (SSet.mem v.Tir.v_name bound) ->
             let n = v.Tir.v_name in
             if is_defined n || D.builtin_dest n <> None then
               fn_values := n :: !fn_values
           | _ -> ())
        args
    | Tir.ELet (v, rhs, body) ->
      let rv =
        match rhs with
        | Tir.EAtom a -> value_of env a
        | Tir.EApp (f, [ a; _ ]) when is_concat f.Tir.v_name
                                    && not (SSet.mem f.Tir.v_name bound) -> (
            match value_of env a with
            | VLit s | VPrefix s -> VPrefix s
            | _ -> VOther)
        | _ -> VOther
      in
      (match rhs with
       | Tir.EAtom a ->
         (* An alias is not a use; record only a top-level name passed on. *)
         (match a with
          | Tir.AVar x when not (SSet.mem x.Tir.v_name bound) ->
            let n = x.Tir.v_name in
            if is_defined n || D.builtin_dest n <> None then
              fn_values := n :: !fn_values
          | _ -> ())
       | _ -> walk env bound rhs);
      walk (SMap.add v.Tir.v_name rv env) (SSet.add v.Tir.v_name bound) body
    | Tir.ELetRec (fns, body) ->
      let bound =
        List.fold_left (fun s (fd : Tir.fn_def) -> SSet.add fd.Tir.fn_name s) bound fns
      in
      List.iter
        (fun (fd : Tir.fn_def) ->
           let env' =
             List.fold_left (fun m (p : Tir.var) -> SMap.add p.Tir.v_name VOther m)
               env fd.Tir.fn_params
           in
           let bound' =
             List.fold_left (fun s (p : Tir.var) -> SSet.add p.Tir.v_name s)
               bound fd.Tir.fn_params
           in
           walk env' bound' fd.Tir.fn_body)
        fns;
      walk env bound body
    | Tir.ECase (scrut, branches, default) ->
      notes env bound [ scrut ];
      List.iter
        (fun (br : Tir.branch) ->
           let env' =
             List.fold_left (fun m (p : Tir.var) -> SMap.add p.Tir.v_name VOther m)
               env br.Tir.br_vars
           in
           let bound' =
             List.fold_left (fun s (p : Tir.var) -> SSet.add p.Tir.v_name s)
               bound br.Tir.br_vars
           in
           walk env' bound' br.Tir.br_body)
        branches;
      Option.iter (walk env bound) default
    | Tir.ESeq (a, b) -> walk env bound a; walk env bound b
    | Tir.ECallPtr (f, args) -> notes env bound (f :: args)
    | Tir.EAtom a -> notes env bound [ a ]
    | Tir.ETuple atoms -> notes env bound atoms
    | Tir.ERecord fields -> notes env bound (List.map snd fields)
    | Tir.EField (a, _) -> notes env bound [ a ]
    | Tir.EUpdate (a, fields) -> notes env bound (a :: List.map snd fields)
    | Tir.EAlloc (_, atoms) | Tir.EStackAlloc (_, atoms) -> notes env bound atoms
    | Tir.EReuse (a, _, atoms) -> notes env bound (a :: atoms)
    | Tir.EAllocHole (_, _, atoms, _) -> notes env bound atoms
    | Tir.ESetField (o, _, v) -> notes env bound [ o; v ]
    | Tir.EFree a | Tir.EIncRC a | Tir.EDecRC a | Tir.EAtomicIncRC a
    | Tir.EAtomicDecRC a ->
      notes env bound [ a ]
  in
  let env, bound =
    List.fold_left
      (fun (m, s) (i, (p : Tir.var)) ->
         (SMap.add p.Tir.v_name (VParam i) m, SSet.add p.Tir.v_name s))
      (SMap.empty, SSet.empty)
      (List.mapi (fun i p -> (i, p)) fn.Tir.fn_params)
  in
  walk env bound fn.Tir.fn_body;
  { name = fn.Tir.fn_name; params = fn.Tir.fn_params; sites = List.rev !sites;
    fn_values = !fn_values; param_uses = !uses }

(* ── Reachability ─────────────────────────────────────────────────── *)

(* A builtin that makes or uses an outbound connection.  Inbound (server)
   and neutral (no remote host) operations do not count. *)
let outbound_builtin n =
  match D.builtin_dest n with
  | Some (D.Url _ | D.Host _ | D.Handle | D.Unknown) -> true
  | Some (D.Inbound | D.Neutral) | None -> false

(* Least fixpoint of "reaches": direct seeds, then any function with a call
   or value edge into the set. *)
let fixpoint (infos : fn_info list) ~(is_defined : string -> bool)
    ~(seed : fn_info -> bool) : (string, unit) Hashtbl.t =
  let set = Hashtbl.create 64 in
  List.iter (fun i -> if seed i then Hashtbl.replace set i.name ()) infos;
  let changed = ref true in
  while !changed do
    changed := false;
    List.iter
      (fun i ->
         if not (Hashtbl.mem set i.name) then
           let edge n = is_defined n && Hashtbl.mem set n in
           if List.exists (fun s -> edge s.callee) i.sites
              || List.exists edge i.fn_values
           then begin
             Hashtbl.replace set i.name ();
             changed := true
           end)
      infos
  done;
  set

(* ── The check ────────────────────────────────────────────────────── *)

(* How a request is made: an HTTP method the compiler can see, a raw
   connection (no method at all), or an HTTP method decided at run time (the
   guard in HttpClient checks it). *)
type meth = MHttp of string | MRaw | MDynamic

type dest_use = { auth : H.authority; meth : meth }

type result = Fixed of dest_use list | Opaque of string

let combine (rs : result list) : result =
  match List.find_opt (function Opaque _ -> true | Fixed _ -> false) rs with
  | Some o -> o
  | None -> Fixed (List.concat_map (function Fixed a -> a | Opaque _ -> []) rs)

let url_evidence ?(meths = [ MDynamic ]) ~(callee : string) (v : value) : result =
  let opaque why = Opaque (Printf.sprintf "the URL passed to `%s` %s" callee why) in
  match v with
  | VLit s -> (
      match H.authority_of_url ~prefix:false s with
      | Some a -> Fixed (List.map (fun meth -> { auth = a; meth }) meths)
      | None ->
        opaque
          (Printf.sprintf
             "is the literal %S, which is not an `http://` or `https://` URL whose \
              host the compiler can read (only letters, digits, `-`, `.` and one \
              `:port`, ended by `/`)"
             s))
  | VPrefix s -> (
      match H.authority_of_url ~prefix:true s with
      | Some a -> Fixed (List.map (fun meth -> { auth = a; meth }) meths)
      | None ->
        opaque
          (Printf.sprintf
             "starts with %S, but the host could still be extended by what is \
              appended; end the literal with `/` after the host (e.g. \
              `\"https://example.com/\" ++ path`)"
             s))
  | VParam _ -> opaque "is a parameter, so its host is decided by the caller"
  | VInt _ | VOther -> opaque "is computed, so its host is not visible here"

let host_evidence ~(callee : string) (host : value) (port : value option) : result =
  match (host, port) with
  | VLit h, Some (VInt p) -> (
      (* The host must be a plain name or IP literal: anything else (a NUL
         byte, which ends the C string getaddrinfo sees; a space; a scheme)
         could connect somewhere the suffix match did not describe. *)
      match H.parse_pattern h with
      | Ok pat when (not pat.H.wildcard) && pat.H.port = None ->
        Fixed [ { auth = { H.a_host = pat.H.host; a_port = p }; meth = MRaw } ]
      | _ ->
        Opaque
          (Printf.sprintf
             "the host %S passed to `%s` is not a plain host name or IP literal"
             h callee))
  | VLit _, _ ->
    Opaque (Printf.sprintf "the port passed to `%s` is not a literal" callee)
  | _ -> Opaque (Printf.sprintf "the host passed to `%s` is not a literal" callee)

let check ~(scopes : (string * H.decl list) list) ~(transparent : string -> bool)
    ~(transparent_fns : string -> bool) ~(annotated : (string * int) list)
    (m : Tir.tir_module) : violation list =
  let entry = if m.Tir.tm_name = "" then "main" else m.Tir.tm_name in
  let owner_of = Cap_attrib.owner_of ~entry in
  let defined = Hashtbl.create 256 in
  List.iter (fun (fn : Tir.fn_def) -> Hashtbl.replace defined fn.Tir.fn_name ()) m.Tir.tm_fns;
  let is_defined = Hashtbl.mem defined in
  let see_through n =
    transparent_fns n
    || (let o = owner_of n in o <> entry && transparent o)
  in
  let infos = List.map (collect ~is_defined) m.Tir.tm_fns in
  let info_of = Hashtbl.create 256 in
  List.iter (fun i -> Hashtbl.replace info_of i.name i) infos;
  let reaches =
    fixpoint infos ~is_defined ~seed:(fun i ->
        List.exists (fun s -> (not (is_defined s.callee)) && outbound_builtin s.callee) i.sites
        || List.exists (fun n -> (not (is_defined n)) && outbound_builtin n) i.fn_values)
  in
  let reaches_redirect =
    fixpoint infos ~is_defined ~seed:(fun i ->
        List.exists (fun s -> D.redirect_capable s.callee) i.sites)
  in
  let annotation n = List.assoc_opt n annotated in
  let nth_value args i = Option.value ~default:VOther (List.nth_opt args i) in
  let decls_of o = Option.value ~default:[] (List.assoc_opt o scopes) in

  (* Summaries of non-stdlib functions, memoised; a cycle with no annotation
     is opaque. *)
  let memo = Hashtbl.create 64 in
  let rec summary (n : string) : result =
    match Hashtbl.find_opt memo n with
    | Some (Some r) -> r
    | Some None -> Opaque (Printf.sprintf "`%s` is recursive" n)
    | None ->
      Hashtbl.replace memo n None;
      let i = Hashtbl.find info_of n in
      let r =
        combine
          (List.filter_map (site_result ~forwarding:None) i.sites
           @ value_results i)
      in
      Hashtbl.replace memo n (Some r);
      r
  and value_results (i : fn_info) =
    List.filter_map
      (fun n ->
         if (is_defined n && Hashtbl.mem reaches n) || ((not (is_defined n)) && outbound_builtin n)
         then
           Some
             (Opaque
                (Printf.sprintf
                   "`%s`, which reaches the network, is passed as a value, so the \
                    compiler cannot see where it connects"
                   n))
         else None)
      i.fn_values
  (* [forwarding]: inside an annotated function, the parameter index whose
     forwarding sites are judged by the caller, not here. *)
  and site_result ~(forwarding : int option) (s : site) : result option =
    let c = s.callee in
    let forwards k = match (forwarding, nth_value s.args k) with
      | Some p, VParam q -> p = q
      | _ -> false
    in
    if is_defined c then
      if not (Hashtbl.mem reaches c) then None
      else if see_through c then
        match annotation c with
        | Some k ->
          if forwards k then None
          else Some (url_evidence ~meths:(entry_meths c) ~callee:c (nth_value s.args k))
        | None ->
          Some
            (Opaque
               (Printf.sprintf
                  "`%s` reaches the network, and the compiler cannot see where it \
                   connects (it takes no URL it can check)"
                  c))
      else if Hashtbl.mem reaches_redirect c then
        Some
          (Opaque
             (Printf.sprintf
                "`%s` makes HttpClient calls that can follow redirects, and the \
                 redirect guard cannot follow a scope through another module yet; \
                 call HttpClient from this module instead"
                c))
      else
        match annotation c with
        | Some k ->
          let own =
            if forwards k then Fixed []
            else url_evidence ~meths:(forwarded_meths c k) ~callee:c (nth_value s.args k)
          in
          Some (combine [ own; annotated_rest c k ])
        | None -> (
            match summary c with
            | Fixed a -> Some (Fixed a)
            | Opaque _ ->
              Some
                (Opaque
                   (Printf.sprintf
                      "`%s` reaches the network with a destination this module cannot \
                       see; if it takes the URL as a parameter, mark it \
                       `@[net_dest(<param>)]`"
                      c)))
    else
      match D.builtin_dest c with
      | Some (D.Url k) ->
        if forwards k then None
        else Some (url_evidence ~meths:(entry_meths c) ~callee:c (nth_value s.args k))
      | Some (D.Host (k, j)) ->
        if forwards k then None
        else Some (host_evidence ~callee:c (nth_value s.args k) (Option.map (nth_value s.args) j))
      | Some D.Handle ->
        Some
          (Opaque
             (Printf.sprintf
                "`%s` acts on an already-open connection (an integer handle), whose \
                 host the compiler cannot see"
                c))
      | Some D.Unknown ->
        Some
          (Opaque
             (Printf.sprintf "`%s` takes an address in a form the compiler does not read" c))
      | Some (D.Inbound | D.Neutral) | None -> None
  (* The method an entry point uses, as far as the compiler can see. *)
  and entry_meths (c : string) : meth list =
    match D.method_of c with Some m -> [ MHttp m ] | None -> [ MDynamic ]
  (* The methods an annotated function uses on the URL it forwards: those of
     the calls it forwards the parameter to. *)
  and forwarded_meths (n : string) (k : int) : meth list =
    let i = Hashtbl.find info_of n in
    let ms =
      List.concat_map
        (fun s ->
             List.concat
               (List.mapi
                  (fun j v ->
                     match v with
                     | VParam q when q = k ->
                       if is_defined s.callee then
                         (match annotation s.callee with
                          | Some j' when j' = j ->
                            if see_through s.callee then entry_meths s.callee
                            else forwarded_meths s.callee j
                          | _ -> [])
                       else (
                         match D.builtin_dest s.callee with
                         | Some (D.Url j') when j' = j -> entry_meths s.callee
                         | Some (D.Host (j', _)) when j' = j -> [ MRaw ]
                         | _ -> [])
                     | _ -> [])
                  s.args))
        i.sites
    in
    if ms = [] then [ MDynamic ] else List.sort_uniq compare ms
  (* What an annotated function reaches besides forwarding its parameter. *)
  and annotated_rest (n : string) (k : int) : result =
    let i = Hashtbl.find info_of n in
    combine (List.filter_map (site_result ~forwarding:(Some k)) i.sites @ value_results i)
  in

  let out = ref [] in
  let add code owner fn_name message =
    out := { code; owner; fn_name; message } :: !out
  in
  let pattern_list ds =
    String.concat ", "
      (List.concat_map
         (fun (d : H.decl) ->
            match d.patterns with
            | [] -> [ "any host" ]
            | ps -> List.map (fun p -> "`" ^ H.pattern_to_string p ^ "`") ps)
         ds)
  in
  let allowed_methods ds (a : H.authority) =
    let ms =
      List.concat_map
        (fun (d : H.decl) ->
           if H.permits [ d ] ~host:a.a_host ~port:a.a_port then
             match d.methods with Some ms -> ms | None -> H.http_methods
           else [])
        ds
    in
    String.concat ", " (List.map String.uppercase_ascii (List.sort_uniq compare ms))
  in
  (* A host-less declaration admits ANY host, so a direct call to a URL entry
     point (or a raw connection) needs no visible host there: only its method
     is judged, and the run-time guard checks redirects and steps.  [`No]
     when no host-less declaration applies, or the call is not a direct
     entry point. *)
  let any_host_methods ds =
    let ms =
      List.concat_map
        (fun (d : H.decl) ->
           if d.patterns = [] then
             match d.methods with Some ms -> ms | None -> H.http_methods
           else [])
        ds
    in
    String.concat ", " (List.map String.uppercase_ascii (List.sort_uniq compare ms))
  in
  let any_host_fallback (ds : H.decl list) (s : site) =
    let anyhost = List.filter (fun (d : H.decl) -> d.patterns = []) ds in
    if anyhost = [] then `No
    else
      let c = s.callee in
      let is_url_entry =
        (is_defined c && see_through c && annotation c <> None)
        || (match D.builtin_dest c with Some (D.Url _) -> true | _ -> false)
      in
      let is_raw = match D.builtin_dest c with Some (D.Host _) -> true | _ -> false in
      if is_url_entry then
        match D.method_of c with
        | None -> `Ok
        | Some m ->
          if List.exists
               (fun (d : H.decl) ->
                  match d.methods with None -> true | Some ms -> List.mem m ms)
               anyhost
          then `Ok
          else `Method m
      else if is_raw && List.exists (fun (d : H.decl) -> d.methods = None) anyhost then `Ok
      else `No
  in
  let subject n =
    let base = match String.rindex_opt n '.' with
      | Some i -> String.sub n (i + 1) (String.length n - i - 1)
      | None -> n
    in
    "`" ^ base ^ "`"
  in
  List.iter
    (fun (i : fn_info) ->
       let o = owner_of i.name in
       if not (see_through i.name) then begin
         let ds = decls_of o in
         (* 1. A host-scoped module's own code. *)
         if ds <> [] then begin
           List.iter
             (fun s ->
                match site_result ~forwarding:None s with
                | None -> ()
                | Some (Fixed uses) ->
                  List.iter
                    (fun (u : dest_use) ->
                       let a = u.auth in
                       if not (H.permits ds ~host:a.a_host ~port:a.a_port) then
                         add March_errors.Code.cap_host_scope o i.name
                           (Printf.sprintf
                              "%s connects to `%s` (port %d), but module `%s` may \
                               reach only %s.\n\
                               hint: add `needs IO.NetConnect(\"%s\")` to module `%s`, \
                               or connect to a host it already names."
                              (subject i.name) a.a_host a.a_port o (pattern_list ds)
                              a.a_host o)
                       else
                         match u.meth with
                         | MHttp m when not (H.permits_method ds ~host:a.a_host ~port:a.a_port ~meth:m) ->
                           add March_errors.Code.cap_host_scope o i.name
                             (Printf.sprintf
                                "%s sends %s to `%s`, but module `%s` allows only %s \
                                 there.\n\
                                 hint: add `%s` to that host's `methods(...)` in module \
                                 `%s`, or use a method it already allows."
                                (subject i.name) (String.uppercase_ascii m) a.a_host o
                                (allowed_methods ds a) m o)
                         | MRaw when not (H.permits_raw ds ~host:a.a_host ~port:a.a_port) ->
                           add March_errors.Code.cap_host_unproven o i.name
                             (Printf.sprintf
                                "%s opens a raw connection to `%s`, but module `%s` \
                                 scopes that host by HTTP method, and a raw connection \
                                 shows no method.\n\
                                 hint: use HttpClient or HttpTransport, or declare the \
                                 host without `methods(...)`."
                                (subject i.name) a.a_host o)
                         | _ -> ())
                    uses
                | Some (Opaque why) when any_host_fallback ds s <> `No ->
                  (match any_host_fallback ds s with
                   | `Method m ->
                     add March_errors.Code.cap_host_scope o i.name
                       (Printf.sprintf
                          "%s sends %s, but module `%s` allows only %s.\n\
                           hint: add `%s` to its `methods(...)`, or use a method it \
                           already allows."
                          (subject i.name) (String.uppercase_ascii m) o
                          (any_host_methods ds) m)
                   | _ -> ignore why)
                | Some (Opaque why) ->
                  add March_errors.Code.cap_host_unproven o i.name
                    (Printf.sprintf
                       "%s reaches the network from module `%s`, which may reach only \
                        %s, but %s.\n\
                        hint: pass a literal URL, end a literal prefix with `/` after \
                        the host, or make the call from a module without a host scope \
                        and hand this one a function."
                       (subject i.name) o (pattern_list ds) why))
             i.sites;
           List.iter
             (function
               | Opaque why ->
                 add March_errors.Code.cap_host_unproven o i.name
                   (Printf.sprintf "%s in module `%s`: %s." (subject i.name) o why)
               | Fixed _ -> ())
             (value_results i);
           (* no_redirects, at compile time. *)
           if List.for_all (fun (d : H.decl) -> d.no_redirects) ds then
             List.iter
               (fun s ->
                  if s.callee = "HttpClient.with_redirects" then
                    match nth_value s.args 1 with
                    | VInt n when n > 0 ->
                      add March_errors.Code.cap_host_scope o i.name
                        (Printf.sprintf
                           "%s turns on redirect-following (`with_redirects(_, %d)`), \
                            but module `%s` declares `no_redirects`.\n\
                            hint: remove the `with_redirects` call, or drop \
                            `no_redirects` from the declaration."
                           (subject i.name) n o)
                    | _ -> ())
               i.sites
         end;
         (* 2. Every non-stdlib `@[net_dest(p)]` must be honest. *)
         match annotation i.name with
         | None -> ()
         | Some k ->
           let pname =
             match List.nth_opt i.params k with
             | Some p -> p.Tir.v_name
             | None -> string_of_int k
           in
           let allowed = function
             | Elsewhere -> false
             | At (c, j) -> (
                 if is_defined c then annotation c = Some j
                 else
                   (* A URL position only: a host argument's caller could not
                      be judged (its port is a separate argument). *)
                   match D.builtin_dest c with
                   | Some (D.Url j') -> j = j'
                   | _ -> false)
           in
           let bad = List.filter (fun (q, u) -> q = k && not (allowed u)) i.param_uses in
           if bad <> [] then
             add March_errors.Code.cap_host_annotation o i.name
               (Printf.sprintf
                  "%s is marked `@[net_dest(%s)]`, but it does more with `%s` than \
                   pass it unchanged to a connection, so a caller's host check would \
                   not describe where it connects.\n\
                   hint: pass `%s` straight to the HTTP or TCP call, or remove the \
                   attribute."
                  (subject i.name) pname pname pname)
           else (
             match annotated_rest i.name k with
             | Opaque why ->
               add March_errors.Code.cap_host_annotation o i.name
                 (Printf.sprintf
                    "%s is marked `@[net_dest(%s)]`, but it also reaches the network \
                     another way: %s."
                    (subject i.name) pname why)
             | Fixed _ -> ())
       end)
    infos;
  List.sort_uniq compare !out

(* ── The rewrite ──────────────────────────────────────────────────── *)

let rec map_expr (f : Tir.expr -> Tir.expr) (e : Tir.expr) : Tir.expr =
  let e = f e in
  let r = map_expr f in
  match e with
  | Tir.ELet (v, a, b) -> Tir.ELet (v, r a, r b)
  | Tir.ELetRec (fns, b) ->
    Tir.ELetRec
      (List.map (fun (fd : Tir.fn_def) -> { fd with Tir.fn_body = r fd.Tir.fn_body }) fns, r b)
  | Tir.ECase (a, brs, d) ->
    Tir.ECase
      (a, List.map (fun (b : Tir.branch) -> { b with Tir.br_body = r b.Tir.br_body }) brs,
       Option.map r d)
  | Tir.ESeq (a, b) -> Tir.ESeq (r a, r b)
  | _ -> e

let rewrite ~(scopes : (string * H.decl list) list) (m : Tir.tir_module) : Tir.tir_module =
  let entry = if m.Tir.tm_name = "" then "main" else m.Tir.tm_name in
  let defined = Hashtbl.create 256 in
  List.iter (fun (fn : Tir.fn_def) -> Hashtbl.replace defined fn.Tir.fn_name ()) m.Tir.tm_fns;
  let fns =
    List.map
      (fun (fn : Tir.fn_def) ->
         let o = Cap_attrib.owner_of ~entry fn.Tir.fn_name in
         match List.assoc_opt o scopes with
         | None | Some [] -> fn
         | Some ds ->
           let spec = H.encode_spec ds in
           let step (e : Tir.expr) =
             match e with
             | Tir.EApp (v, args)
               when D.redirect_capable v.Tir.v_name
                    && Hashtbl.mem defined (v.Tir.v_name ^ "_scoped") ->
               let v_ty =
                 match v.Tir.v_ty with
                 | Tir.TFn (ps, ret) -> Tir.TFn (ps @ [ Tir.TString ], ret)
                 | t -> t
               in
               Tir.EApp
                 ( { v with Tir.v_name = v.Tir.v_name ^ "_scoped"; v_ty },
                   args @ [ Tir.ALit (March_ast.Ast.LitString spec) ] )
             | _ -> e
           in
           { fn with Tir.fn_body = map_expr step fn.Tir.fn_body })
      m.Tir.tm_fns
  in
  { m with Tir.tm_fns = fns }
