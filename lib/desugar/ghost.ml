(* Ghost code (specs/lang/lemmas.md, "Ghost code"; todo
   2026-11-06-ghost-code, step 6 of the verification ladder).

   Three forms, all proof-only:
   - a ghost parameter, `fn insert(ghost s : Set(Int), t : Tree, x : Int)`;
   - a ghost binding, `ghost let s2 = Set.insert(s, x)`;
   - a ghost function, `ghost fn content(t : Tree) : Set(Int) do … end`
     (stored as the attribute "ghost"; the refinement checker requires it to
     be reflected, which makes it pure, total and terminating).

   The refinement checker reads the program with its ghost code; everything
   after it reads the program without.  [check] enforces what makes that
   sound, noninterference: a ghost value reaches only ghost positions
   (another ghost binding, a ghost argument, a lemma's arguments, a proof
   hint, a ghost function's body, and refinements, which are types and never
   run).  So no runtime branch, return value, closure, pattern match,
   allocation or capability operation can depend on one, directly or through
   a callee.  Ghost code also never observes a linear or affine value:
   erasing the observation would change who consumes it.

   [erase] then removes ghost code before lowering, as [Lemma_erase] removes
   lemmas: ghost parameters and the matching arguments, ghost bindings and
   ghost functions.  It depends only on the syntax, never on a proof verdict
   or the solver.  Calls are resolved without the typechecker, so the rules
   are conservative:
   - a bare call `f(…)` is ghost when it is written in the source file that
     declares ghost `f` (the only place a bare name can see it) and no local
     shadows `f`.  [check_names] then requires that nothing else a bare call
     there could mean shares the name: another declaration of that file, a
     global (a top-level or prelude declaration, a builtin) or a `use` import;
   - a qualified call `M.f(…)` (`M` possibly an `alias`) is ghost only when
     a module of the program named `M` declares ghost `f`.  The stdlib
     declares no ghost code, so `List.map` never matches a user's ghost `map`.

   Not supported yet (each rejected with [ghost_misuse]): ghost parameters
   on impl methods, on local functions and on a function with several
   clauses, pattern parameters or a guard (the desugarer's general path),
   `ghost fn` as an impl method, and a function with ghost parameters used as
   a value rather than called.  A lemma's or ghost function's parameters are
   proof-only already, so `ghost` on one is refused too. *)

open March_ast.Ast
module Err = March_errors.Errors

module SS = Set.Make (String)
module SM = Map.Make (String)

let is_ghost_fn (fd : fn_def) = List.mem "ghost" fd.fn_attrs

let is_ghost_param = function FPNamed { param_lin = Ghost; _ } -> true | _ -> false

(* Positions of a function's ghost parameters (its first clause; the
   desugarer leaves one clause on any function that has them). *)
let ghost_indices (fd : fn_def) : int list =
  match fd.fn_clauses with
  | c :: _ -> List.concat (List.mapi (fun i p -> if is_ghost_param p then [ i ] else []) c.fc_params)
  | [] -> []

let has_ghost_params fd = ghost_indices fd <> []

(* Declarations [erase] removes or rewrites. *)
let is_special fd = is_ghost_fn fd || has_ghost_params fd

let last_segment = Lemma_erase.last_segment

let pat_names p = Lemma_erase.pat_names SS.empty p

let params_names (ps : param list) =
  List.fold_left (fun acc (p : param) -> SS.add p.param_name.txt acc) SS.empty ps

type sigs = {
  ghost_fns : SS.t;              (* `ghost fn` names *)
  ghost_params : int list SM.t;  (* name -> ghost parameter positions *)
  homes : SS.t;                  (* "Module.name" for each ghost declaration *)
  bare_files : SS.t SM.t;        (* name -> files declaring it ghost *)
  aliases : string list SM.t;    (* `alias` short name -> module path *)
  lemmas : SS.t;
  unresolved : SS.t;             (* lemma names a bare call cannot resolve *)
  ghost_files : SS.t;            (* files holding ghost code, set by [erase] *)
}

let home m n = m ^ "." ^ n

let add_file n (fd : fn_def) files =
  SM.update n (fun o -> Some (SS.add fd.fn_name.span.file (Option.value o ~default:SS.empty))) files

let rec collect ~(m : string) (acc : sigs) (decls : decl list) : sigs =
  List.fold_left
    (fun acc d ->
      match d with
      | DFn (fd, _) when Lemma_erase.is_lemma fd ->
        { acc with
          lemmas = SS.add fd.fn_name.txt acc.lemmas;
          homes = SS.add (home m fd.fn_name.txt) acc.homes;
          bare_files = add_file fd.fn_name.txt fd acc.bare_files }
      | DFn (fd, _) when is_ghost_fn fd ->
        { acc with
          ghost_fns = SS.add fd.fn_name.txt acc.ghost_fns;
          homes = SS.add (home m fd.fn_name.txt) acc.homes;
          bare_files = add_file fd.fn_name.txt fd acc.bare_files }
      | DFn (fd, _) when has_ghost_params fd ->
        { acc with
          ghost_params = SM.add fd.fn_name.txt (ghost_indices fd) acc.ghost_params;
          homes = SS.add (home m fd.fn_name.txt) acc.homes;
          bare_files = add_file fd.fn_name.txt fd acc.bare_files }
      | DAlias (a, _) ->
        { acc with aliases = SM.add a.alias_name.txt (List.map (fun (n : name) -> n.txt) a.alias_path) acc.aliases }
      | DMod (n, _, inner, _) -> collect ~m:n.txt acc inner
      | DDescribe (_, inner, _) -> collect ~m acc inner
      | _ -> acc)
    acc decls

(* [top]: the name of the module whose declarations [decls] are. *)
let sigs_of ~(top : string) (decls : decl list) : sigs =
  collect ~m:top
    { ghost_fns = SS.empty; ghost_params = SM.empty; homes = SS.empty; bare_files = SM.empty;
      aliases = SM.empty; lemmas = SS.empty; unresolved = SS.empty; ghost_files = SS.empty }
    decls

let decl_span = function
  | DFn (_, sp) | DLet (_, _, sp) | DMod (_, _, _, sp) | DDescribe (_, _, sp) | DImpl (_, sp)
  | DInterface (_, sp) | DActor (_, _, _, sp) | DTest (_, sp) | DSetup (_, sp) | DSetupAll (_, sp)
  | DApp (_, sp) | DExtern (_, sp) | DUse (_, sp) | DAlias (_, sp) -> sp
  | _ -> dummy_span

let split_dots (s : string) = String.split_on_char '.' s

(* A callee as (qualifier, name): `f`, `M.f` (one dotted [EVar], as the
   desugarer writes a same-file module path) or a field chain on a module
   name (`List.map`, as the parser writes it). *)
let callee (e : expr) : (string list * string) option =
  let rec path = function
    | ECon (n, [], _) -> Some (split_dots n.txt)
    | EVar n -> Some (split_dots n.txt)
    | EField (b, n, _) -> Option.map (fun p -> p @ [ n.txt ]) (path b)
    | _ -> None
  in
  match path e with
  | Some p when p <> [] ->
    let rev = List.rev p in
    Some (List.rev (List.tl rev), List.hd rev)
  | _ -> None

type kind = [ `Ghost_fn | `Ghost_params of int list | `Lemma | `Other ]

(* What a callee written in [file] names, given the locals in scope. *)
let classify (sigs : sigs) ~(file : string) (locals : SS.t) (e : expr) : kind =
  match callee e with
  | None -> `Other
  | Some ([], n) when SS.mem n locals -> `Other
  | Some (q, n) ->
    let ghost_name = SS.mem n sigs.ghost_fns || SM.mem n sigs.ghost_params in
    let resolved =
      match q with
      | [] -> (match SM.find_opt n sigs.bare_files with Some fs -> SS.mem file fs | None -> false)
      | h :: rest ->
        let q = match SM.find_opt h sigs.aliases with Some p -> p @ rest | None -> q in
        SS.mem (home (List.nth q (List.length q - 1)) n) sigs.homes
    in
    if ghost_name && resolved then
      if SS.mem n sigs.ghost_fns then `Ghost_fn
      else `Ghost_params (SM.find n sigs.ghost_params)
    (* A lemma call, by the same rule: [erase] removes it (it runs nothing),
       so its arguments are a ghost position.  A bare call of a lemma whose
       name something else in its file shares is left to [Lemma_erase], which
       may keep it, arguments and all. *)
    else if SS.mem n sigs.lemmas && resolved && not (q = [] && SS.mem n sigs.unresolved) then `Lemma
    else `Other

(* ------------------------------------------------------------------ *)
(* Noninterference check                                               *)
(* ------------------------------------------------------------------ *)

let report errors code ~span ?hint msg =
  Err.report errors
    { Err.severity = Err.Error; span; message = msg; labels = [];
      notes = (match hint with Some h -> [ h ] | None -> []);
      code; fix = None }

let error errors = report errors Err.Code.ghost_in_runtime
let misuse errors = report errors Err.Code.ghost_misuse

(* Lexical scope during the walk.  [ghost]: ghost locals; [local]: every
   other local (it shadows a ghost function's bare name); [lin]: locals
   bound `linear` or `affine`. *)
type scope = { ghost : SS.t; local : SS.t; lin : SS.t }

let empty_scope = { ghost = SS.empty; local = SS.empty; lin = SS.empty }

let bind_runtime ?(lin = false) sc names =
  { ghost = SS.diff sc.ghost names;
    local = SS.union sc.local names;
    lin = (if lin then SS.union sc.lin names else SS.diff sc.lin names) }

let bind_ghost sc names = { ghost = SS.union sc.ghost names; local = SS.diff sc.local names; lin = SS.diff sc.lin names }

let locals_of sc = SS.union sc.local sc.ghost

type ctx = { errors : Err.ctx; sigs : sigs; is_linear : span -> bool; file : string }

let ghost_hint =
  "Ghost values exist only for proofs and are erased before the program runs. \
   Use them in refinements, lemma arguments, ghost arguments, `ghost let` and proof hints."

let rec children (e : expr) : expr list =
  match e with
  | ELit _ | EVar _ | EHole _ | EResultRef _ | EDbg (None, _) -> []
  | EApp (f, args, _) -> f :: args
  | ECon (_, args, _) | ETuple (args, _) | EAtom (_, args, _) | EBlock (args, _) -> args
  | ELam (_, b, _) | ELetFn (_, _, _, b, _) -> [ b ]
  | ELet (b, _) -> [ b.bind_expr ]
  | ELetQ (_, a, b, _) | ELetStar (_, a, b, _) | EPipe (a, b, _) | ESend (a, b, _) -> [ a; b ]
  | EMatch (s, brs, _) -> s :: List.concat_map (fun br -> br.branch_body :: Option.to_list br.branch_guard) brs
  | ERecord (fs, _) -> List.map snd fs
  | ERecordUpdate (b, fs, _) -> b :: List.map snd fs
  | EField (x, _, _) | EAnnot (x, _, _) | ESpawn (x, _) | EAssert (x, _) | ESigil (_, x, _) | EDbg (Some x, _) -> [ x ]
  | EIf (c, t, f, _) -> [ c; t; f ]
  | ECond (arms, _) -> List.concat_map (fun (c, b) -> [ c; b ]) arms
  | ERefineMsg (x, _, _) -> [ x ]
  | EProof (p, _) -> proof_children p

(* Ghost position: nothing here runs.  What remains is that no runtime
   linear value is observed.  (A binder inside the ghost expression that
   reuses a linear local's name is still refused: conservative.) *)
and ghost_expr cx sc (e : expr) : unit =
  match e with
  | EVar n when SS.mem n.txt sc.lin || cx.is_linear n.span ->
    misuse cx.errors ~span:n.span
      ~hint:"Erasing the ghost code would change who consumes it; describe the value with a \
             measure in a refinement instead."
      (Printf.sprintf "`%s` is linear, and ghost code cannot use it." n.txt)
  | _ -> List.iter (ghost_expr cx sc) (children e)

let head_span = function EVar n -> n.span | EField (_, _, sp) -> sp | ECon (n, _, _) -> n.span | _ -> dummy_span

let value_use cx sc (e : expr) (span : span) (shown : string) =
  match classify cx.sigs ~file:cx.file (locals_of sc) e with
  | `Ghost_fn ->
    error cx.errors ~span ~hint:ghost_hint
      (Printf.sprintf "`%s` is a ghost function: it is never compiled, so only proofs can call it." shown)
  | `Ghost_params _ ->
    misuse cx.errors ~span
      ~hint:"Call it directly; passing it as a value would need its ghost arguments at runtime."
      (Printf.sprintf "`%s` has ghost parameters, so it can only be called directly." shown)
  | `Lemma | `Other -> ()

(* Runtime position.  Returns the scope a statement leaves for the
   statements after it in a block. *)
let rec runtime_expr cx sc (e : expr) : unit = ignore (runtime_stmt cx sc e)

and runtime_stmt cx sc (e : expr) : scope =
  let rt = runtime_expr cx sc in
  match e with
  | EVar n when SS.mem n.txt sc.ghost ->
    error cx.errors ~span:n.span ~hint:ghost_hint
      (Printf.sprintf "`%s` is ghost, so the running program cannot use it." n.txt);
    sc
  | EVar n ->
    value_use cx sc e n.span n.txt;
    sc
  | EField (_, n, sp) when callee e <> None ->
    value_use cx sc e sp n.txt;
    List.iter rt (children e);
    sc
  | EApp (head, args, _) ->
    (match classify cx.sigs ~file:cx.file (locals_of sc) head with
     | `Lemma -> List.iter (ghost_expr cx sc) args
     | `Ghost_fn ->
       let shown = match callee head with Some (_, n) -> n | None -> "this" in
       error cx.errors ~span:(head_span head) ~hint:ghost_hint
         (Printf.sprintf "`%s` is a ghost function: it is never compiled, so only proofs can call it." shown)
     | `Ghost_params ix -> List.iteri (fun i a -> if List.mem i ix then ghost_expr cx sc a else rt a) args
     | `Other ->
       rt head;
       List.iter rt args);
    sc
  | ELet (b, _) when b.bind_lin = Ghost ->
    ghost_expr cx sc b.bind_expr;
    bind_ghost sc (pat_names b.bind_pat)
  | ELet (b, _) ->
    rt b.bind_expr;
    bind_runtime ~lin:(b.bind_lin = Linear || b.bind_lin = Affine) sc (pat_names b.bind_pat)
  | EBlock (es, _) ->
    ignore (List.fold_left (fun sc e -> runtime_stmt cx sc e) sc es);
    sc
  | ELam (ps, body, _) ->
    runtime_expr cx (bind_runtime sc (params_names ps)) body;
    sc
  | ELetFn (n, ps, _, body, _) ->
    List.iter
      (fun (p : param) ->
        if p.param_lin = Ghost then
          misuse cx.errors ~span:p.param_name.span
            ~hint:"Move the function to the module level, where ghost parameters are erased."
            "Ghost parameters are supported on module-level `fn` declarations, not on local functions.")
      ps;
    let sc' = bind_runtime sc (SS.singleton n.txt) in
    runtime_expr cx (bind_runtime sc' (params_names ps)) body;
    sc'
  | ELetQ (p, a, b, _) | ELetStar (p, a, b, _) ->
    rt a;
    runtime_expr cx (bind_runtime sc (pat_names p)) b;
    sc
  | EMatch (s, brs, _) ->
    rt s;
    List.iter
      (fun br ->
        let sc' = bind_runtime sc (pat_names br.branch_pat) in
        Option.iter (runtime_expr cx sc') br.branch_guard;
        runtime_expr cx sc' br.branch_body)
      brs;
    sc
  (* A `with fuel` body is ordinary code; the other proof statements are
     ghost. *)
  | EProof (PWithFuel (f, _, body), _) ->
    ghost_expr cx sc f;
    ignore (List.fold_left (fun sc e -> runtime_stmt cx sc e) sc body);
    sc
  | EProof (p, _) ->
    List.iter (ghost_expr cx sc) (proof_children p);
    sc
  | _ ->
    List.iter rt (children e);
    sc

let check_impl_method cx (fd : fn_def) =
  List.iter
    (fun (c : fn_clause) ->
      List.iter
        (function
          | FPNamed ({ param_lin = Ghost; _ } as p) ->
            misuse cx.errors ~span:p.param_name.span
              ~hint:"Move the proof-only argument to a top-level `fn`, or describe it with a measure."
              "Ghost parameters are supported on `fn` declarations, not on impl methods."
          | _ -> ())
        c.fc_params)
    fd.fn_clauses;
  if is_ghost_fn fd then misuse cx.errors ~span:fd.fn_name.span "An impl method cannot be a `ghost fn`."

let check_fn cx (fd : fn_def) =
  if Lemma_erase.is_lemma fd || is_ghost_fn fd then begin
    (* Every parameter of a lemma or ghost function is already proof-only;
       `ghost` there would only make its calls' arguments disagree with its
       parameters once a call is kept ([Lemma_erase] may keep one). *)
    List.iter
      (fun (c : fn_clause) ->
        List.iter
          (function
            | FPNamed ({ param_lin = Ghost; _ } as p) ->
              misuse cx.errors ~span:p.param_name.span
                ~hint:"Drop the `ghost`: nothing a lemma or ghost function takes reaches the running program."
                (Printf.sprintf "`%s` is a parameter of %s, which is proof-only already." p.param_name.txt
                   (if is_ghost_fn fd then "a ghost function" else "a lemma"))
            | _ -> ())
          c.fc_params)
      fd.fn_clauses;
    (* Proof-only throughout; reflection decides what the body may do. *)
    List.iter (fun (c : fn_clause) -> ghost_expr cx empty_scope c.fc_body) fd.fn_clauses
  end
  else
    List.iter
      (fun (c : fn_clause) ->
        let sc =
          List.fold_left
            (fun sc -> function
              | FPNamed ({ param_lin = Ghost; _ } as p) ->
                (match p.param_ty with
                 | Some (TyLinear ((Linear | Affine), _)) ->
                   misuse cx.errors ~span:p.param_name.span
                     (Printf.sprintf "Ghost parameter `%s` cannot have a linear or affine type." p.param_name.txt)
                 | _ -> ());
                bind_ghost sc (SS.singleton p.param_name.txt)
              | FPNamed p | FPDefault (p, _) ->
                bind_runtime ~lin:(p.param_lin = Linear || p.param_lin = Affine) sc (SS.singleton p.param_name.txt)
              | FPPat p -> bind_runtime sc (pat_names p))
            empty_scope c.fc_params
        in
        List.iter (function FPDefault (_, d) -> runtime_expr cx sc d | _ -> ()) c.fc_params;
        Option.iter (runtime_expr cx sc) c.fc_guard;
        runtime_expr cx sc c.fc_body)
      fd.fn_clauses

let rec check_decls cx (decls : decl list) =
  List.iter
    (fun d ->
      let cx = { cx with file = (decl_span d).file } in
      let rt = runtime_expr cx empty_scope in
      match d with
      | DFn (fd, _) -> check_fn cx fd
      | DLet (_, b, _) -> rt b.bind_expr
      | DMod (_, _, inner, _) | DDescribe (_, inner, _) -> check_decls cx inner
      | DImpl (idef, _) ->
        List.iter
          (fun (_, fd) ->
            check_impl_method cx fd;
            check_fn cx fd)
          idef.impl_methods
      | DInterface (idef, _) -> List.iter (fun m -> Option.iter rt m.md_default) idef.iface_methods
      | DActor (_, _, a, _) ->
        let handler (h : actor_handler) = runtime_expr cx (bind_runtime empty_scope (params_names h.ah_params)) h.ah_body in
        let init_sc = bind_runtime empty_scope (params_names a.actor_init_params) in
        runtime_expr cx init_sc a.actor_init;
        List.iter handler a.actor_handlers;
        Option.iter handler a.actor_on_stop;
        (* A supervised child's `init` arguments run in the spawn glue. *)
        Option.iter
          (fun (sv : supervise_config) ->
            List.iter (fun (f : supervise_field) -> List.iter (runtime_expr cx init_sc) f.sf_init_args) sv.sc_fields)
          a.actor_supervise
      | DTest (t, _) -> rt t.test_body
      | DSetup (e, _) | DSetupAll (e, _) -> rt e
      | DApp (a, _) ->
        rt a.app_body;
        Option.iter rt a.app_on_start;
        Option.iter rt a.app_on_stop
      | _ -> ())
    decls

(* Every name a declaration binds, ghost declarations excepted: what a bare
   call by that name could also mean.  [deep]: into nested modules, those of
   [file] only ([None]: the top level alone, every file's globals). *)
let rec decl_names ?(file : string option) (acc : SS.t) (decls : decl list) : SS.t =
  let decl_names = decl_names ?file in
  List.fold_left
    (fun acc d ->
      match d with
      | d when (match file with Some f -> (decl_span d).file <> f | None -> false) -> acc
      | DFn (fd, _) when is_special fd || Lemma_erase.is_lemma fd -> acc
      | DFn (fd, _) -> SS.add fd.fn_name.txt acc
      | DLet (_, b, _) -> Lemma_erase.pat_names acc b.bind_pat
      | DMod (_, _, inner, _) | DDescribe (_, inner, _) -> if file = None then acc else decl_names acc inner
      | DImpl (idef, _) -> List.fold_left (fun acc (n, _) -> SS.add n.txt acc) acc idef.impl_methods
      | DInterface (idef, _) -> List.fold_left (fun acc (m : method_decl) -> SS.add m.md_name.txt acc) acc idef.iface_methods
      | DExtern (ext, _) -> List.fold_left (fun acc (f : extern_fn) -> SS.add f.ef_name.txt acc) acc ext.ext_fns
      | _ -> acc)
    acc decls

let rec module_names (acc : SS.t) (decls : decl list) : SS.t =
  List.fold_left
    (fun acc -> function
      | DMod (n, _, inner, _) -> module_names (SS.add n.txt acc) inner
      | DDescribe (_, inner, _) -> module_names acc inner
      | _ -> acc)
    acc decls

(* Names a `use` makes callable bare.  [exports] lists a module's public
   names when the program does not hold its declarations (a stdlib module);
   [None] for a wildcard import means the names cannot be known. *)
let rec imported_names ~(exports : string -> string list option) ~(own : SS.t) (decls : decl list) :
    SS.t * (string * span) list =
  List.fold_left
    (fun (names, unknown) d ->
      match d with
      | DUse (u, sp) -> (
        let path = String.concat "." (List.map (fun (n : name) -> n.txt) u.use_path) in
        let last = match List.rev u.use_path with n :: _ -> n.txt | [] -> "" in
        match u.use_sel with
        | UseNames ns -> (List.fold_left (fun acc (n : name) -> SS.add n.txt acc) names ns, unknown)
        | UseSingle -> (names, unknown)
        | (UseAll | UseExcept _) when SS.mem last own -> (names, unknown)
        | UseAll | UseExcept _ -> (
          match exports path with
          | Some ns -> (List.fold_left (fun acc n -> SS.add n acc) names ns, unknown)
          | None -> (names, (path, sp) :: unknown)))
      | DMod (_, _, inner, _) | DDescribe (_, inner, _) ->
        let n, u = imported_names ~exports ~own inner in
        (SS.union names n, u @ unknown)
      | _ -> (names, unknown))
    (SS.empty, []) decls

(* Whether a bare call of [fd]'s name, in [fd]'s file, could mean something
   else: another declaration of that file, a global (a top-level or prelude
   declaration, a builtin) or a `use` import.  [unknown]: wildcard imports
   whose names cannot be listed. *)
let collisions ~(reserved : string -> bool) ~(exports : string -> string list option) ~(globals : string -> bool)
    (decls : decl list) : (fn_def -> bool) * (string * span) list =
  let own = module_names SS.empty decls in
  let imported, unknown = imported_names ~exports ~own decls in
  let top = SS.union (decl_names SS.empty decls) imported in
  let per_file = Hashtbl.create 4 in
  let file_names f =
    match Hashtbl.find_opt per_file f with
    | Some ns -> ns
    | None ->
      let ns = decl_names ~file:f SS.empty decls in
      Hashtbl.replace per_file f ns;
      ns
  in
  let collides (fd : fn_def) =
    let n = fd.fn_name.txt in
    SS.mem n top || SS.mem n (file_names fd.fn_name.span.file) || globals n || reserved n
  in
  (collides, unknown)

let rec fold_fns f acc (decls : decl list) =
  List.fold_left
    (fun acc -> function
      | DFn (fd, _) -> f acc fd
      | DMod (_, _, inner, _) | DDescribe (_, inner, _) -> fold_fns f acc inner
      | _ -> acc)
    acc decls

(* Two ghost declarations of one name must agree on their ghost signature,
   and a ghost name must be resolvable ([collisions]).  Returns [sigs] with
   the lemmas whose bare calls cannot be resolved. *)
let check_names errors ~reserved ~exports ~globals (sigs : sigs) (decls : decl list) : sigs =
  let collides, unknown = collisions ~reserved ~exports ~globals decls in
  let shapes = Hashtbl.create 8 in
  fold_fns
    (fun sigs fd ->
      let n = fd.fn_name.txt in
      if Lemma_erase.is_lemma fd then
        if collides fd || unknown <> [] then { sigs with unresolved = SS.add n sigs.unresolved } else sigs
      else if is_special fd then begin
        let shape = (is_ghost_fn fd, ghost_indices fd) in
        (match Hashtbl.find_opt shapes n with
         | Some s when s <> shape ->
           misuse errors ~span:fd.fn_name.span
             (Printf.sprintf "Another declaration named `%s` has different ghost parameters." n)
         | _ -> Hashtbl.replace shapes n shape);
        (if collides fd then
           misuse errors ~span:fd.fn_name.span
             ~hint:"Give it a name no other function, value or builtin visible here has."
             (Printf.sprintf
                "`%s` is ghost code, but another declaration visible here is also named `%s`, \
                 so its calls cannot be told apart and erased." n n)
         else
           match unknown with
           | (path, _) :: _ ->
             misuse errors ~span:fd.fn_name.span
               ~hint:(Printf.sprintf "Import the names you need, `use %s.{…}`." path)
               (Printf.sprintf "`use %s.*` may also bring in a `%s`, so calls to ghost `%s` cannot be resolved."
                  path n n)
           | [] -> ());
        sigs
      end
      else sigs)
    sigs decls

let uses_ghost_let (decls : decl list) : bool =
  let found = ref false in
  let rec ex e =
    if not !found then
      match e with
      | ELet (b, _) when b.bind_lin = Ghost -> found := true
      | ELetFn (_, ps, _, _, _) when List.exists (fun (p : param) -> p.param_lin = Ghost) ps -> found := true
      | _ -> List.iter ex (children e)
  in
  (* A ghost parameter where [collect] does not record one (a lemma's, a
     ghost function's) is still ghost syntax the check must see. *)
  let fn (fd : fn_def) =
    if List.exists (fun (c : fn_clause) -> List.exists is_ghost_param c.fc_params) fd.fn_clauses then found := true;
    List.iter (fun (c : fn_clause) -> ex c.fc_body) fd.fn_clauses
  in
  let rec go decls =
    List.iter
      (function
        | DFn (fd, _) -> fn fd
        | DLet (_, b, _) -> ex b.bind_expr
        | DMod (_, _, inner, _) | DDescribe (_, inner, _) -> go inner
        | DImpl (idef, _) -> List.iter (fun (_, f) -> fn f) idef.impl_methods
        | DInterface (idef, _) -> List.iter (fun (m : method_decl) -> Option.iter ex m.md_default) idef.iface_methods
        | DActor (_, _, a, _) ->
          ex a.actor_init;
          List.iter (fun (h : actor_handler) -> ex h.ah_body) a.actor_handlers;
          Option.iter (fun (h : actor_handler) -> ex h.ah_body) a.actor_on_stop
        | DTest (t, _) -> ex t.test_body
        | DSetup (e, _) | DSetupAll (e, _) -> ex e
        | DApp (a, _) ->
          ex a.app_body;
          Option.iter ex a.app_on_start;
          Option.iter ex a.app_on_stop
        | _ -> ())
      decls
  in
  go decls;
  !found

(* A ghost parameter or `ghost fn` where none is supported (an impl method):
   reported by [check_impl_method], so the walk must run. *)
let rec ghost_in_impls (decls : decl list) =
  List.exists
    (function
      | DImpl (idef, _) -> List.exists (fun (_, fd) -> is_special fd) idef.impl_methods
      | DMod (_, _, inner, _) | DDescribe (_, inner, _) -> ghost_in_impls inner
      | _ -> false)
    decls

let no_ghost_code sigs decls =
  SS.is_empty sigs.ghost_fns && SM.is_empty sigs.ghost_params && not (uses_ghost_let decls)
  && not (ghost_in_impls decls)

let no_exports _ = None

(* The typechecker's entry point: every diagnostic about ghost code.  A
   program without ghost code costs one scan. *)
let check ?(is_linear = fun _ -> false) ?(reserved = fun _ -> false) ?(exports = no_exports)
    ?(globals = fun _ -> false) ~(top : string) (errors : Err.ctx) (decls : decl list) : unit =
  let sigs = sigs_of ~top decls in
  if not (no_ghost_code sigs decls) then begin
    let sigs = check_names errors ~reserved ~exports ~globals sigs decls in
    check_decls { errors; sigs; is_linear; file = "" } decls
  end

(* ------------------------------------------------------------------ *)
(* Erasure                                                             *)
(* ------------------------------------------------------------------ *)

exception Not_erasable of span * string

(* [locals]: names bound in scope, which shadow a ghost function's bare
   name. *)
let rec erase_expr (sigs : sigs) ~(file : string) (locals : SS.t) (e : expr) : expr =
  let ex = erase_expr sigs ~file locals in
  let under names = erase_expr sigs ~file (SS.union locals names) in
  let erase_expr sigs locals e = erase_expr sigs ~file locals e in
  match e with
  | EApp (head, args, sp) -> (
    match classify sigs ~file locals head with
    | `Ghost_params ix -> EApp (ex head, List.filteri (fun i _ -> not (List.mem i ix)) args |> List.map ex, sp)
    (* A lemma runs nothing; the typechecker recorded `Unit` at the call. *)
    | `Lemma -> ETuple ([], sp)
    | _ -> EApp (ex head, List.map ex args, sp))
  | EBlock (es, sp) ->
    let _, rev =
      List.fold_left
        (fun (locals, acc) e ->
          match e with
          | ELet (b, _) when b.bind_lin = Ghost -> (locals, acc)
          | ELet (b, lsp) ->
            let b' = { b with bind_expr = erase_expr sigs locals b.bind_expr } in
            (SS.union locals (pat_names b.bind_pat), ELet (b', lsp) :: acc)
          | ELetFn (n, _, _, _, _) ->
            let locals = SS.add n.txt locals in
            (locals, erase_expr sigs locals e :: acc)
          | e -> (locals, erase_expr sigs locals e :: acc))
        (locals, []) es
    in
    (* An erased lemma call (here or by [Lemma_erase]) is `()`: as a
       statement, not the block's value, it is dropped, so a backend that
       emits unit statements (the JS one) sees the program without it. *)
    let stmts =
      match rev with
      | last :: before when SS.mem file sigs.ghost_files ->
        last :: List.filter (function ETuple ([], _) -> false | _ -> true) before
      | _ -> rev
    in
    EBlock (List.rev stmts, sp)
  | ELam (ps, body, sp) -> ELam (ps, under (params_names ps) body, sp)
  | ELet (b, sp) -> ELet ({ b with bind_expr = ex b.bind_expr }, sp)
  | ELetFn (n, ps, ret, body, sp) -> ELetFn (n, ps, ret, under (SS.add n.txt (params_names ps)) body, sp)
  | ELetQ (p, a, b, sp) -> ELetQ (p, ex a, under (pat_names p) b, sp)
  | ELetStar (p, a, b, sp) -> ELetStar (p, ex a, under (pat_names p) b, sp)
  | EMatch (s, brs, sp) ->
    EMatch
      ( ex s,
        List.map
          (fun br ->
            let names = pat_names br.branch_pat in
            { br with branch_body = under names br.branch_body; branch_guard = Option.map (under names) br.branch_guard })
          brs,
        sp )
  | ECon (n, args, sp) -> ECon (n, List.map ex args, sp)
  | ETuple (es, sp) -> ETuple (List.map ex es, sp)
  | ERecord (fs, sp) -> ERecord (List.map (fun (n, x) -> (n, ex x)) fs, sp)
  | ERecordUpdate (b, fs, sp) -> ERecordUpdate (ex b, List.map (fun (n, x) -> (n, ex x)) fs, sp)
  | EField (x, n, sp) -> EField (ex x, n, sp)
  | EIf (c, t, f, sp) -> EIf (ex c, ex t, ex f, sp)
  | ECond (arms, sp) -> ECond (List.map (fun (c, b) -> (ex c, ex b)) arms, sp)
  | EPipe (l, r, sp) -> EPipe (ex l, ex r, sp)
  | EAnnot (x, t, sp) -> EAnnot (ex x, t, sp)
  | EDbg (Some x, sp) -> EDbg (Some (ex x), sp)
  | ESend (c, m, sp) -> ESend (ex c, ex m, sp)
  | ESpawn (x, sp) -> ESpawn (ex x, sp)
  | EAssert (x, sp) -> EAssert (ex x, sp)
  | EAtom (a, args, sp) -> EAtom (a, List.map ex args, sp)
  | ESigil (s, x, sp) -> ESigil (s, ex x, sp)
  | ERefineMsg (x, msg, sp) -> ERefineMsg (ex x, msg, sp)
  | EProof (p, sp) -> EProof (map_proof ex p, sp)
  | ELit _ | EVar _ | EHole _ | EResultRef _ | EDbg (None, _) -> e

let erase_fn sigs ~file (fd : fn_def) : fn_def =
  let erase_expr sigs locals e = erase_expr sigs ~file locals e in
  { fd with
    fn_clauses =
      List.map
        (fun (c : fn_clause) ->
          let locals =
            List.fold_left
              (fun acc -> function
                | FPNamed p | FPDefault (p, _) -> SS.add p.param_name.txt acc
                | FPPat p -> SS.union (pat_names p) acc)
              SS.empty c.fc_params
          in
          { c with
            fc_params =
              List.filter_map
                (function
                  | p when is_ghost_param p -> None
                  | FPDefault (p, d) -> Some (FPDefault (p, erase_expr sigs SS.empty d))
                  | p -> Some p)
                c.fc_params;
            fc_body = erase_expr sigs locals c.fc_body;
            fc_guard = Option.map (erase_expr sigs locals) c.fc_guard })
        fd.fn_clauses }

let rec erase_decls sigs (decls : decl list) : decl list =
  List.filter_map
    (fun d ->
      let file = (decl_span d).file in
      let erase_fn = erase_fn ~file in
      let erase_expr sigs locals e = erase_expr sigs ~file locals e in
      let ex = erase_expr sigs SS.empty in
      let handler (h : actor_handler) = { h with ah_body = erase_expr sigs (params_names h.ah_params) h.ah_body } in
      match d with
      | DFn (fd, _) when is_ghost_fn fd -> None
      | DFn (fd, sp) -> Some (DFn (erase_fn sigs fd, sp))
      | DLet (v, b, sp) -> Some (DLet (v, { b with bind_expr = ex b.bind_expr }, sp))
      | DMod (n, v, inner, sp) -> Some (DMod (n, v, erase_decls sigs inner, sp))
      | DDescribe (s, inner, sp) -> Some (DDescribe (s, erase_decls sigs inner, sp))
      | DImpl (idef, sp) ->
        Some (DImpl ({ idef with impl_methods = List.map (fun (n, f) -> (n, erase_fn sigs f)) idef.impl_methods }, sp))
      | DInterface (idef, sp) ->
        Some
          (DInterface
             ({ idef with iface_methods = List.map (fun m -> { m with md_default = Option.map ex m.md_default }) idef.iface_methods },
              sp))
      | DActor (v, n, a, sp) ->
        Some
          (DActor
             ( v, n,
               { a with
                 actor_init = erase_expr sigs (params_names a.actor_init_params) a.actor_init;
                 actor_handlers = List.map handler a.actor_handlers;
                 actor_on_stop = Option.map handler a.actor_on_stop;
                 actor_supervise =
                   Option.map
                     (fun (sv : supervise_config) ->
                       { sv with
                         sc_fields =
                           List.map
                             (fun (f : supervise_field) ->
                               { f with
                                 sf_init_args =
                                   List.map (erase_expr sigs (params_names a.actor_init_params)) f.sf_init_args })
                             sv.sc_fields })
                     a.actor_supervise },
               sp ))
      | DTest (t, sp) -> Some (DTest ({ t with test_body = ex t.test_body }, sp))
      | DSetup (e, sp) -> Some (DSetup (ex e, sp))
      | DSetupAll (e, sp) -> Some (DSetupAll (ex e, sp))
      | DApp (a, sp) ->
        Some
          (DApp
             ({ a with app_body = ex a.app_body; app_on_start = Option.map ex a.app_on_start; app_on_stop = Option.map ex a.app_on_stop },
              sp))
      | _ -> Some d)
    decls

(* Remove ghost code from [decls], which [Lemma_erase] has already run over.
   [whole] is the whole program before erasure (for resolution), [top] the
   name of the module whose declarations [decls] are.  Raises [Not_erasable]
   when the program breaks a rule [check] enforces (a check seeded without
   the stdlib does not see a collision there), and for a ghost argument of a
   lemma call [Lemma_erase] could not resolve, which would stay in the
   running program. *)
let erase ?(reserved = fun _ -> false) ?(exports = no_exports) ?(globals = fun _ -> false) ~(top : string)
    ~(whole : decl list) (decls : decl list) : decl list =
  let sigs = sigs_of ~top whole in
  if no_ghost_code sigs whole then decls
  else begin
    let errors = Err.create () in
    let first () =
      match List.find_opt (fun (d : Err.diagnostic) -> d.Err.severity = Err.Error) errors.Err.diagnostics with
      | Some d -> raise (Not_erasable (d.Err.span, d.Err.message))
      | None -> ()
    in
    let sigs = check_names errors ~reserved ~exports ~globals sigs whole in
    first ();
    check_decls { errors; sigs; is_linear = (fun _ -> false); file = "" } whole;
    first ();
    (* Only a file with ghost code is touched beyond the ghost code itself
       (its erased lemma calls' `()` statements): every other file reaches
       lowering exactly as [Lemma_erase] left it. *)
    let rec files acc ds =
      List.fold_left
        (fun acc d ->
          match d with
          | DMod (_, _, inner, _) | DDescribe (_, inner, _) -> files acc inner
          | DFn (fd, _) when is_special fd -> SS.add (decl_span d).file acc
          | d when uses_ghost_let [ d ] -> SS.add (decl_span d).file acc
          | _ -> acc)
        acc ds
    in
    let sigs = { sigs with ghost_files = files SS.empty whole } in
    (* A lemma whose calls this removed is now referenced by nothing. *)
    let out = erase_decls sigs decls in
    Lemma_erase.drop_unreferenced out out
  end
