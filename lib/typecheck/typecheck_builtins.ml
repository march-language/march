(** The built-in world: the type constants, the capability tables, and the
    base environment every March module starts from.

    [t_int] … [t_vault], [span_is_stdlib], [builtin_cap_table], the
    capability-path primitives ([cap_subsumes], [cap_path_of_names],
    [cap_paths_in_surface_ty]), the standard interfaces and impls (§9b — Eq,
    Ord, Show, Hash), [builtin_bindings] (the second-largest definition in the
    checker), [builtin_types], [builtin_ctors] and [base_env].  Lifted
    verbatim out of [Typecheck] (§9/§9b) on 2026-08-26.

    This is the [eval.ml] [base_env] analogue: long, mostly literal, low-risk,
    high volume.  Its only dependencies were four names in the type/env core
    ([fresh_var], [make_env], [add_ctor], [bind_vars]), which is why it could
    not move until Task 6.3 had.

    [open], not [include], for the two core modules: [Typecheck] includes all
    three, and including the same definitions twice is a multiple-definition
    error.

    See specs/plans/2026-08-19-compiler-file-decomposition.md (Phase 6,
    Task 6.4). *)

open Typecheck_types
open Typecheck_env


(* =================================================================
   §9  Built-in types + base environment
   ================================================================= *)

let t_int    = TCon ("Int",    [])
let t_float  = TCon ("Float",  [])
let t_bool   = TCon ("Bool",   [])
let t_string = TCon ("String", [])
let t_unit   = TTuple []
let t_atom   = TCon ("Atom",   [])

let t_list   a     = TCon ("List",   [a])
let t_option a     = TCon ("Option", [a])
let t_result a e   = TCon ("Result", [a; e])
let t_pid    a     = TCon ("Pid",    [a])
let t_vault  v     = TCon ("Vault",  [v])

let _t_list   = t_list
let _t_option = t_option
let _t_result = t_result
let _t_pid    = t_pid

(* =================================================================
   Capability hierarchy for needs / Cap checking.
   Moved to March_caps.Cap_lattice (Phase5C-A.1) — shared with
   March_refinecheck.Cap_infer, which previously carried a verbatim
   duplicate of this table.
   ================================================================= *)

(** Source files loaded as the standard library, set by the driver.

    [prelude.march] is deliberately unwrapped into GLOBAL scope, so its
    declarations are prepended to the ENTRY module's decl list and are
    indistinguishable from the user's own by shape alone. Check 1b dedups its
    body-scan to one (capability, span) pair and keeps the FIRST, so a
    capability prelude also uses got a prelude span — which the driver's
    [is_user_file] filter then discarded, silently.

    Measured: [println] in a plain function body produced NO Check 1b warning
    while [file_exists] in the same module did, purely because prelude calls
    [println] three times and never calls [file_exists]. The diagnostic was
    generated and thrown away. That suppressed Check 1b for every capability
    the standard library happens to use, not just IO.Console.

    Mirrors [Refine_check.stdlib_source_files], which exists for the same
    "whose declaration is this really?" question. *)
let stdlib_source_files : string list ref = ref []

(* When set, [check_module_core] runs the `--check`-side capability ceiling
   ([check_stdlib_mediated_ceiling]): every user module's stdlib-mediated
   capability use must be covered by its own [needs]. Off by default so the
   interpreter/eval/LSP/test paths are unaffected unless they opt in; the
   driver sets it on the `--check`/`--check-json` path (respecting
   `--no-cap-strict`), giving those paths parity with `--compile`'s TIR-side
   ceiling for the common stdlib-mediated route. Deliberately a strict SUBSET
   of the `--compile` ceiling — it under-reports rather than risk breaking a
   build `--compile` accepts. *)
let cap_strict_ceiling : bool ref = ref false

let span_is_stdlib (sp : Ast.span) : bool =
  List.mem sp.Ast.file !stdlib_source_files

(** Maps builtin function names to the IO capability they require.
    Used by the body-scanning pass (Phase 2) to detect missing [needs] declarations. *)
let builtin_cap_table : (string * string) list = [
  (* IO.Console *)
  ("println",               "IO.Console");
  ("print",                 "IO.Console");
  ("print_line",            "IO.Console");
  (* IO.FileRead *)
  ("file_exists",           "IO.FileRead");
  ("file_read",             "IO.FileRead");
  ("file_open",             "IO.FileRead");
  ("file_read_line",        "IO.FileRead");
  ("file_read_chunk",       "IO.FileRead");
  ("file_stat",             "IO.FileRead");
  ("dir_exists",            "IO.FileRead");
  ("dir_list",              "IO.FileRead");
  ("csv_open",              "IO.FileRead");
  ("csv_next_row",          "IO.FileRead");
  (* IO.FileWrite *)
  ("file_write",            "IO.FileWrite");
  ("file_append",           "IO.FileWrite");
  ("file_delete",           "IO.FileWrite");
  ("file_rename",           "IO.FileWrite");
  ("dir_mkdir",             "IO.FileWrite");
  ("dir_mkdir_p",           "IO.FileWrite");
  ("dir_rmdir",             "IO.FileWrite");
  ("dir_rm_rf",             "IO.FileWrite");
  (* IO.FileSystem — needs both read+write *)
  ("file_copy",             "IO.FileSystem");
  (* IO.NetConnect *)
  ("tcp_connect",           "IO.NetConnect");
  ("tcp_send_all",          "IO.NetConnect");
  ("tcp_recv_all",          "IO.NetConnect");
  ("tcp_recv_exact",        "IO.NetConnect");
  ("tcp_recv_http",         "IO.NetConnect");
  ("tcp_recv_http_headers", "IO.NetConnect");
  ("tcp_recv_chunk",        "IO.NetConnect");
  ("tcp_recv_chunk_timeout","IO.NetConnect");
  ("tcp_set_recv_timeout",  "IO.NetConnect");
  ("tcp_recv_chunked_frame","IO.NetConnect");
  ("tcp_recv_timeout",      "IO.NetConnect");
  (* IO.WebSocket — a least-privilege sub-cap of IO.NetConnect; a module that
     only speaks WebSocket can declare `needs IO.WebSocket` instead of the
     broader `needs IO.NetConnect`, mirroring IO.NetConnect.TLS. *)
  ("ws_recv",               "IO.WebSocket");
  ("ws_send",               "IO.WebSocket");
  ("ws_select",             "IO.WebSocket");
  (* IO.Network *)
  ("dns_resolve",           "IO.Network");
  (* IO.NetListen *)
  ("tcp_listen",            "IO.NetListen");
  ("tcp_accept",            "IO.NetListen");
  ("tcp_local_port",        "IO.NetListen");
  ("http_server_listen",    "IO.NetListen");
  ("http_server_spawn_n",   "IO.NetListen");
  ("http_server_wait",      "IO.NetListen");
  (* IO.Process *)
  ("process_env",           "IO.Process");
  ("process_set_env",       "IO.Process");
  ("process_cwd",           "IO.Process");
  ("process_argv",          "IO.Process");
  ("process_pid",           "IO.Process");
  ("process_exit",          "IO.Process");
  ("process_spawn_sync",    "IO.Process");
  ("process_spawn_lines",   "IO.Process");
  ("process_spawn_async",   "IO.Process");
  ("process_read_line",     "IO.Process");
  ("process_write",         "IO.Process");
  ("process_kill_proc",     "IO.Process");
  ("process_wait_proc",     "IO.Process");
  (* IO.Clock *)
  ("unix_time",             "IO.Clock");
  ("unix_time_ms",          "IO.Clock");
  ("uuid_v7",               "IO.Clock");
  (* IO.Random *)
  ("random_bytes",          "IO.Random");
  ("stdlib_random_bytes",   "IO.Random");
  ("uuid_v4",               "IO.Random");
  (* IO.Signal *)
  ("signal_watch",          "IO.Signal");
  ("signal_unwatch",        "IO.Signal");
  ("signal_raise_self",     "IO.Signal");
  (* IO.Spawn *)
  ("task_spawn",            "IO.Spawn");
  ("task_spawn_link",       "IO.Spawn");
  ("task_spawn_steal",      "IO.Spawn");
  ("task_spawn_with_cancel","IO.Spawn");
  ("get_work_pool",         "IO.Spawn");
  (* Vault is IN MEMORY: nothing a read does escapes the process, so a lookup
     carries no ambient authority and needs no capability. What IS authority is
     (a) turning a NAME into a table handle — vault_new/vault_whereis, the
     File.open(path) shape — and (b) mutating state other actors observe.
     Those keep IO.Mut. See lib/caps/cap_symbols.ml for the full note. *)
  (* IO.Mut — shared mutable state via Vault *)
  ("vault_new",             "IO.Mut");
  ("vault_set",             "IO.Mut");
  ("vault_set_ttl",         "IO.Mut");
  ("vault_drop",            "IO.Mut");
  ("vault_update",          "IO.Mut");
  ("vault_put_new",         "IO.Mut");
  ("vault_incr",            "IO.Mut");
  ("vault_push_capped",     "IO.Mut");
  ("vault_ns_set",          "IO.Mut");
  ("vault_ns_get",          "IO.Mut");
  ("vault_ns_drop",         "IO.Mut");
  ("vault_whereis",         "IO.Mut");
  (* IO.NetConnect.TLS — encrypted transport; tls_close/tls_ctx_free are cleanup, no cap *)
  ("tls_client_ctx",        "IO.NetConnect.TLS");
  ("tls_server_ctx",        "IO.NetConnect.TLS");
  ("tls_connect",           "IO.NetConnect.TLS");
  ("tls_accept",            "IO.NetConnect.TLS");
  ("tls_read",              "IO.NetConnect.TLS");
  ("tls_read_timeout",      "IO.NetConnect.TLS");
  ("tls_write",             "IO.NetConnect.TLS");
  ("tls_negotiated_alpn",   "IO.NetConnect.TLS");
  ("tls_peer_cn",           "IO.NetConnect.TLS");
]

(** The names a module DECLARES directly (bare [DFn]s and top-level [DLet]
    [PatVar]s) — exactly the set that wins real name resolution over a global
    builtin of the same bare name at this module's scope (verified:
    interpreted and compiled, a module-level `fn`/`let` of the same name is
    what actually runs, never the builtin).

    Every capability-inference pass below is a raw SYNTACTIC scan
    ([March_ast.Calls.names_and_name_spans]) matching a call's NAME against
    [builtin_cap_table]/a derived banned-set, with no resolution awareness.
    Before this existed, EVERY one of them treated an ordinary function named
    `file_read`, `random_bytes`, `dns_resolve`, … — or a `cap pure`/
    `cap deterministic` module's own same-named helper — as a call to the
    capability-bearing builtin of that name, and (since Check 1b's severity
    flip, 2026-08-06) that is a hard, default-on compile ERROR demanding a
    capability the program never uses (specs/2026-08-09-cap-loose-ends-plan.md,
    Tier 0).

    Deliberately NOT extended to nested-module names (already immune — a
    nested module's qualified TIR/AST name, e.g. "Lib.file_read", never
    string-matches a bare table key) or to a parameter/local `let` shadowing
    a builtin WITHIN a function body (a real, rarer residual gap needing
    actual scope-aware resolution these AST-level passes don't have — filed
    as a follow-up, not blocking this fix).

    ONE shared implementation rather than one per call site: this codebase
    has repeatedly been bitten by near-duplicate capability walks drifting
    apart (the "two-tables-drift" pattern) — [check_module_needs],
    [check_pure_module] and [check_deterministic_module] all consult this,
    rather than each re-deriving its own notion of "locally declared". *)
let locally_declared_names_of (decls : Ast.decl list) : (string, unit) Hashtbl.t =
  let tbl = Hashtbl.create 16 in
  List.iter (function
      (* STDLIB-SPAN declarations must NOT count as "locally declared":
         prelude is unwrapped into the ENTRY module's OWN flat [decls] list
         (see [check_module_needs]'s dedup-first-span comment, and
         [own_caps_of_this_module]'s identical trap), so without this filter
         prelude's `println`/`print`/etc. — sitting in the SAME [decls] this
         function scans for the entry module — were themselves treated as
         "locally declared", shadowing every entry-module call to `println`.
         Measured: a program with NO `needs` at all calling bare `println`
         WRONGLY TYPECHECKED (a corpus regression,
         reject/t40_migrate_state_does_io.march, caught by the corpus sweep
         after the naive first version of this function shipped — the OCaml
         unit tests for the shadowing fix all used the bare, no-stdlib
         [typecheck] helper and could not have caught it). *)
      | Ast.DFn (def, sp) when not (span_is_stdlib sp) ->
        Hashtbl.replace tbl def.Ast.fn_name.Ast.txt ()
      | Ast.DLet (_, b, sp) when not (span_is_stdlib sp) ->
        (match b.Ast.bind_pat with
         | Ast.PatVar n -> Hashtbl.replace tbl n.Ast.txt ()
         | _ -> ())
      | _ -> ())
    decls;
  tbl

(** [cap_subsumes parent child] — true if [parent] is an ancestor of (or equal to) [child].
    E.g., cap_subsumes "IO" "IO.FileRead" = true.
    See [March_caps.Cap_lattice.cap_subsumes]. *)
let cap_subsumes = March_caps.Cap_lattice.cap_subsumes

(** [same_package_namespace a b] — do two module paths belong to the same
    top-level namespace?  ["Conduit.RateLimiter"] and ["Conduit"] do; neither
    shares one with ["Compress.Gzip"].

    Used to decide whether a bare constructor reference is genuinely ambiguous.
    Exact current-module equality is too strict: a package that declares a type
    in `mod Pkg` and matches on its constructors from `mod Pkg.Sub` owns both
    sides, but the two module paths differ, so an unrelated stdlib type sharing
    the constructor name made the package's own code ambiguous against a type
    it never imported.  Measured on conduit, whose `RateLimiterBackend.Custom`
    collided with `Compress.Gzip.Level.Custom`. *)
(* Every module path that could carry the current code's package namespace.
   All three are consulted rather than the first non-empty, because which one
   holds it depends on how the code was reached:
     - a dotted top-level `mod Pkg.Sub` puts the whole path in current_module;
     - a nested `mod Sub` leaves only the bare name there, and the package name
       is in enclosing_package;
     - the multi-file check path wraps everything in a synthetic "LibCheck"
       module, which makes enclosing_package useless but leaves current_module
       correct.
   Consulting only one of them misses whichever shape it does not cover. *)
let local_module_paths env =
  List.filter (fun s -> s <> "")
    [ env.current_module; env.cap_qual_prefix; env.enclosing_package ]

let same_package_namespace (a : string) (b : string) : bool =
  let root p = match String.index_opt p '.' with
    | None -> p
    | Some i -> String.sub p 0 i
  in
  a <> "" && b <> "" && root a = root b

(** [cap_path_of_names names] joins AST name list to dot-string. *)
let cap_path_of_names names =
  String.concat "." (List.map (fun (n : Ast.name) -> n.txt) names)

(** [cap_paths_in_surface_ty ty] returns all Cap(X) paths referenced in [ty].

    Delegates to [Cap_surface_ty.caps_in_ty], which the desugarer's [derive
    Json] rejection uses too.  This was a private copy here until 2026-08-05;
    it now shares one exhaustive implementation, because a capability walk
    maintained in two places drifts, and a drifted capability walk is a silent
    hole rather than a visible bug.

    One behaviour change came with the move: the old copy skipped
    [Tagged(_, _)]'s arguments outright, to avoid mistaking the marker
    argument for a capability.  The shared walk recurses instead.  The marker
    is a nullary constructor whose name is not "Cap", so it still extracts
    nothing — while [Tagged(R, Cap(IO))], which the old copy could not see at
    all, is now found. *)
let cap_paths_in_surface_ty (ty : Ast.ty) : string list =
  March_caps.Cap_surface_ty.caps_in_ty ty

(* =================================================================
   §9b  Standard interfaces — Eq, Ord, Show, Hash
   These are pre-registered in every module so that builtin types
   (Int, Float, String, Bool) already satisfy the constraints and
   user code can write `impl Eq(MyType)` without re-declaring the
   interface.
   ================================================================= *)

(** Extract the unification-variable id from a fresh TVar. *)
let get_tvar_id = function
  | TVar r -> (match !r with Unbound (id, _) -> id | _ -> 0)
  | _ -> 0

(** Build an [Ast.interface_def] for a builtin interface with a single
    type parameter named "a". [methods] is a list of (method_name, surface_ty). *)
let mk_builtin_iface name methods =
  let mk_n txt = { Ast.txt; span = Ast.dummy_span } in
  let mk_method (mname, mty) =
    { Ast.md_name = mk_n mname; md_ty = mty; md_default = None }
  in
  { Ast.iface_name        = mk_n name;
    iface_param           = mk_n "a";
    iface_superclasses    = [];
    iface_assoc_types     = [];
    iface_methods         = List.map mk_method methods }

let _mk_n txt = { Ast.txt; span = Ast.dummy_span }

(** Pre-declared standard interfaces.  These are injected into every
    module's initial environment so users can write impls for them. *)
let builtin_interfaces : (string * Ast.interface_def) list =
  let av       = Ast.TyVar  { txt = "a";      span = Ast.dummy_span } in
  let bool_t   = Ast.TyCon  ({ txt = "Bool";   span = Ast.dummy_span }, []) in
  let int_t    = Ast.TyCon  ({ txt = "Int";    span = Ast.dummy_span }, []) in
  let string_t = Ast.TyCon  ({ txt = "String"; span = Ast.dummy_span }, []) in
  [
    ("Eq",   mk_builtin_iface "Eq" [
       ("eq",      Ast.TyArrow (av, Ast.TyArrow (av, bool_t)));
     ]);
    ("Ord",  mk_builtin_iface "Ord" [
       ("compare", Ast.TyArrow (av, Ast.TyArrow (av, int_t)));
     ]);
    ("Show", mk_builtin_iface "Show" [
       ("show",    Ast.TyArrow (av, string_t));
     ]);
    ("Hash", mk_builtin_iface "Hash" [
       ("hash",    Ast.TyArrow (av, int_t));
     ]);
  ]

(** Concrete type implementations for the standard interfaces.
    These ensure that Int/Float/String/Bool satisfy Eq, Ord, Show, Hash
    out of the box. *)
let builtin_impls : (string * ty) list =
  [ (* Eq *)
    ("Eq",   t_int);   ("Eq",   t_float); ("Eq",   t_string);
    ("Eq",   t_bool);  ("Eq",   t_unit);  ("Eq",   t_atom);
    (* Ord *)
    ("Ord",  t_int);   ("Ord",  t_float); ("Ord",  t_string);
    (* Show — Atom included so `show(:tag)` / `show` on an Atom-typed value
       typechecks (compiled backend lowers it to Show$Atom.show; the
       interpreter renders VAtom a as ":" ^ a).  Without this, a direct
       `show(a)` on a concretely-Atom-typed `a` failed with "Atom does not
       implement interface Show" in BOTH modes even though `println(a)`
       worked via the generic prelude path. *)
    ("Show", t_int);   ("Show", t_float); ("Show", t_string);
    ("Show", t_bool);  ("Show", t_unit);  ("Show", t_atom);
    (* Hash *)
    ("Hash", t_int);   ("Hash", t_float); ("Hash", t_string);
    ("Hash", t_bool);
  ]

(** Build a scheme [∀a. CInterface(iface, a) => mk_ty(a)] for a builtin
    interface method binding. *)
let mk_iface_method_scheme iface_name mk_ty =
  let a = fresh_var 0 in
  Poly ([get_tvar_id a], [CInterface (iface_name, a)], mk_ty a)

(** Method bindings for the standard interfaces.  These are added to
    every module's initial [vars] so that [eq], [compare], [show],
    and [hash] resolve as polymorphic functions at call sites.
    Both unqualified (eq) and qualified (Eq.eq) forms are registered
    so that [Eq.eq(x, y)] resolves via the EField module-path lookup. *)
let builtin_interface_bindings : (string * scheme) list =
  [ ("eq",      mk_iface_method_scheme "Eq"   (fun a -> TArrow (a, TArrow (a, t_bool))));
    ("compare", mk_iface_method_scheme "Ord"  (fun a -> TArrow (a, TArrow (a, t_int))));
    ("show",    mk_iface_method_scheme "Show" (fun a -> TArrow (a, t_string)));
    ("hash",    mk_iface_method_scheme "Hash" (fun a -> TArrow (a, t_int)));
    (* Qualified forms: Eq.eq, Ord.compare, Show.show, Hash.hash *)
    ("Eq.eq",      mk_iface_method_scheme "Eq"   (fun a -> TArrow (a, TArrow (a, t_bool))));
    ("Ord.compare",mk_iface_method_scheme "Ord"  (fun a -> TArrow (a, TArrow (a, t_int))));
    ("Show.show",  mk_iface_method_scheme "Show" (fun a -> TArrow (a, t_string)));
    ("Hash.hash",  mk_iface_method_scheme "Hash" (fun a -> TArrow (a, t_int)));
  ]

(** Built-in binary operator schemes.
    We use level-0 fresh vars for polymorphic ops — they will be
    properly instantiated each time [instantiate] is called. *)
let builtin_bindings : (string * scheme) list =
  (* Extract the id from a fresh TVar (always succeeds for fresh vars) *)
  let get_id = function
    | TVar r -> (match !r with Unbound (id, _) -> id | _ -> 0)
    | _ -> 0
  in
  (* ∀a. f(a) — unconstrained polymorphism *)
  let poly1 f =
    let a = fresh_var 0 in
    Poly ([get_id a], [], f a)
  in
  (* ∀a:Num. f(a) — a must be Int or Float *)
  let poly1_num f =
    let a = fresh_var 0 in
    Poly ([get_id a], [CNum a], f a)
  in
  (* ∀a:Ord. f(a) — a must be Int, Float, or String (legacy COrd path) *)
  let _poly1_ord f =
    let a = fresh_var 0 in
    Poly ([get_id a], [COrd a], f a)
  in
  (* ∀a:Iface. f(a) — a must implement the named interface *)
  let poly1_iface iname f =
    let a = fresh_var 0 in
    Poly ([get_id a], [CInterface (iname, a)], f a)
  in
  (* ∀a b. f(a, b) — two unconstrained type variables *)
  let poly2 f =
    let a = fresh_var 0 in
    let b = fresh_var 0 in
    Poly ([get_id a; get_id b], [], f a b)
  in
  (* ∀a b c. f(a, b, c) — three unconstrained type variables.  Underscored:
     no builtin needs three free vars since the vault_* group was retyped
     against [Vault(v)] (2026-08-14).  Kept because it is the obvious partner
     to poly1/poly2 for the next builtin that does. *)
  let _poly3 f =
    let a = fresh_var 0 in
    let b = fresh_var 0 in
    let c = fresh_var 0 in
    Poly ([get_id a; get_id b; get_id c], [], f a b c)
  in
  [
    (* Arithmetic: Num-constrained so they work on Int and Float *)
    ("+",  poly1_num (fun a -> TArrow (a, TArrow (a, a))));
    ("-",  poly1_num (fun a -> TArrow (a, TArrow (a, a))));
    ("*",  poly1_num (fun a -> TArrow (a, TArrow (a, a))));
    ("/",  poly1_num (fun a -> TArrow (a, TArrow (a, a))));
    ("%",  Mono (TArrow (t_int,    TArrow (t_int,    t_int))));
    ("negate", poly1_num (fun a -> TArrow (a, a)));
    (* Float-specific operators — always monomorphic *)
    ("+.", Mono (TArrow (t_float, TArrow (t_float, t_float))));
    ("-.", Mono (TArrow (t_float, TArrow (t_float, t_float))));
    ("*.", Mono (TArrow (t_float, TArrow (t_float, t_float))));
    ("/.", Mono (TArrow (t_float, TArrow (t_float, t_float))));
    (* Ordering comparisons: Ord interface-constrained (Int, Float, String) *)
    ("<",  poly1_iface "Ord" (fun a -> TArrow (a, TArrow (a, t_bool))));
    (">",  poly1_iface "Ord" (fun a -> TArrow (a, TArrow (a, t_bool))));
    ("<=", poly1_iface "Ord" (fun a -> TArrow (a, TArrow (a, t_bool))));
    (">=", poly1_iface "Ord" (fun a -> TArrow (a, TArrow (a, t_bool))));
    ("&&", Mono (TArrow (t_bool,   TArrow (t_bool,   t_bool))));
    ("||", Mono (TArrow (t_bool,   TArrow (t_bool,   t_bool))));
    (* Equality: Eq interface-constrained *)
    ("==", poly1_iface "Eq" (fun a -> TArrow (a, TArrow (a, t_bool))));
    ("!=", poly1_iface "Eq" (fun a -> TArrow (a, TArrow (a, t_bool))));
    ("++",             Mono (TArrow (t_string, TArrow (t_string, t_string))));
    ("print",          Mono (TArrow (t_string, t_unit)));
    ("println",        Mono (TArrow (t_string, t_unit)));
    (* print_line: a String and its newline in ONE write.  `println` is the
       polymorphic prelude wrapper and cannot be this — a module-level `fn`
       shadows the builtin of the same name, so [Prelude.println] was reaching
       the backend as two separate `print` calls and never touched
       `march_println` at all.  This is the name the wrapper's body calls to
       get there.  See stdlib/prelude.march. *)
    ("print_line",     Mono (TArrow (t_string, t_unit)));
    ("print_int",      Mono (TArrow (t_int,    t_unit)));
    ("print_float",    Mono (TArrow (t_float,  t_unit)));
    (* Tap bus: ∀a. a -> a  (sends value to tap bus, returns it unchanged) *)
    ("tap",            poly1 (fun a -> TArrow (a, a)));
    (* Property-testing primitive: ∀a. (Bool -> a) -> Result(a, String).
       Runs the thunk (a 1-arg lambda whose argument is ignored — used
       because the typechecker doesn't handle `() -> a` well in argument
       position), catching any runtime failure (assert, panic, match
       failure, division by zero, etc.) and returning Err(msg) on failure
       or Ok(result) on success. Call as `__try_call(fn _ -> body)`.
       The thunk must return Bool (not a generic `a`): the C runtime stores
       the Ok field in the uniform low-bit-tagged immediate representation,
       which would corrupt a heap pointer.  See __try_call in
       runtime/march_runtime.c. *)
    ("__try_call",     Mono
        (TArrow (TArrow (t_bool, t_bool), t_result t_bool t_string)));
    (* Value-carrying try: ∀a. (Bool -> a) -> Result(a, String).  Unlike
       __try_call, the thunk's result type is the type variable `a`, so the
       compiled thunk returns its value in the uniform representation (heap
       pointers raw, immediates low-bit-tagged).  __try_call_val stores that
       uniform value into the Ok field as-is — exactly how __try_call already
       stores the heap march_string into its Err field — so a heap result
       (e.g. a nested Result) round-trips without corruption.  Used by
       Depot.Transaction.run to guard a callback that returns Result(v, String).
       See __try_call_val in runtime/march_runtime.c. *)
    ("__try_call_val", poly1 (fun a ->
        TArrow (TArrow (t_bool, a), t_result a t_string)));
    ("int_to_string",  Mono (TArrow (t_int,    t_string)));
    ("float_to_string",Mono (TArrow (t_float,  t_string)));
    ("bool_to_string", Mono (TArrow (t_bool,   t_string)));
    ("string_to_int",   Mono (TArrow (t_string, t_option t_int)));
    ("string_to_float", Mono (TArrow (t_string, t_option t_float)));
    ("string_length",   Mono (TArrow (t_string, t_int)));
    ("string_to_codepoints",  Mono (TArrow (t_string, t_list t_int)));
    ("string_from_codepoint", Mono (TArrow (t_int, t_option t_string)));
    ("string_concat",  Mono (TArrow (t_string, TArrow (t_string, t_string))));
    ("read_line",      Mono (TArrow (t_unit,   t_string)));
    ("read_byte",      Mono (TArrow (t_unit,   t_int)));
    (* Signal.watch(code, handler): register a deferred handler for an OS
       signal; signal_unwatch(code) removes it. See stdlib/signal.march. *)
    ("signal_watch",   Mono (TArrow (t_int, TArrow (TArrow (t_unit, t_unit), t_unit))));
    ("signal_unwatch", Mono (TArrow (t_int, t_unit)));
    ("signal_raise_self", Mono (TArrow (t_int, t_unit)));
    ("not",            Mono (TArrow (t_bool,   t_bool)));
    (* List helpers: ∀a. ... *)
    ("head",   poly1 (fun a -> TArrow (t_list a, a)));
    ("tail",   poly1 (fun a -> TArrow (t_list a, t_list a)));
    ("is_nil", poly1 (fun a -> TArrow (t_list a, t_bool)));
    (* Generic to_string: ∀a. a -> String *)
    ("to_string", poly1 (fun a -> TArrow (a, t_string)));
    (* Record introspection builtins: ∀a b. fully polymorphic — runtime checks type *)
    ("record_keys",      poly1 (fun a -> TArrow (a, t_list t_string)));
    ("record_values",    poly2 (fun a b -> TArrow (a, t_list b)));
    ("record_entries",   poly2 (fun a b -> TArrow (a, t_list (TTuple [t_string; b]))));
    ("record_get",       poly2 (fun a b -> TArrow (a, TArrow (t_string, t_option b))));
    ("record_put",       poly2 (fun a b -> TArrow (a, TArrow (t_string, TArrow (b, a)))));
    ("record_has_key",   poly1 (fun a -> TArrow (a, TArrow (t_string, t_bool))));
    ("record_from_list", poly2 (fun a b -> TArrow (t_list (TTuple [t_string; a]), b)));
    (* Vault (in-memory key-value table) — raw C-runtime entry points backing
       the typed wrapper module [stdlib/vault.march] (`Vault.new`, `Vault.get`,
       …). The table handle is [Vault(v)], phantom in its ELEMENT type: the
       same [v] appears in [vault_set]'s value, [vault_get]'s result and
       [vault_update]'s function, so a table written at [Int] cannot be read
       at [Pid(_)]. Keys stay per-operation generic ([k]) because
       [vault_key_cstr] stringifies them — see the [Vault] entry in
       [builtin_types] for why there is no key parameter.

       [vault_ns_*] take a NAMESPACE STRING rather than a handle, so there is
       no handle to carry [v] and they remain erased. That is the module's one
       remaining untyped door and stdlib/vault.march says so at the call site.

       Needed so a BARE call to one of these resolves at all. Before this they
       were simply UNBOUND — every call site (including inside
       [stdlib/vault.march] and [stdlib/config.march] themselves) hit "I
       cannot find `vault_get`", tolerated for years only because a
       diagnostic whose span lands in a stdlib file never reaches CLI output
       (see [bin/main.ml]'s `is_user_file` filter) and [TError] unifies
       permissively downstream. Surfaced by the vault-read capability test in
       test/test_caps.ml, which typechecks a bare `vault_get`/`vault_set`
       call directly (no stdlib loaded) and got "I cannot find" for BOTH,
       masking the real capability check either way.

       Return shapes mirror the actual [VBuiltin] cases in lib/eval/eval.ml. *)
    ("vault_new",          poly1 (fun v -> TArrow (t_string, t_vault v)));
    ("vault_whereis",      poly1 (fun v -> TArrow (t_string, t_option (t_vault v))));
    ("vault_set",          poly2 (fun k v -> TArrow (t_vault v, TArrow (k, TArrow (v, t_unit)))));
    ("vault_set_ttl",      poly2 (fun k v -> TArrow (t_vault v, TArrow (k, TArrow (v, TArrow (t_int, t_unit))))));
    ("vault_get",          poly2 (fun k v -> TArrow (t_vault v, TArrow (k, t_option v))));
    ("vault_drop",         poly2 (fun k v -> TArrow (t_vault v, TArrow (k, t_unit))));
    ("vault_update",       poly2 (fun k v -> TArrow (t_vault v, TArrow (k, TArrow (TArrow (v, v), t_unit)))));
    ("vault_put_new",      poly2 (fun k v -> TArrow (t_vault v, TArrow (k, TArrow (v, TArrow (t_int, t_bool))))));
    (* [incr] and [push_capped] pin the element type the way the C runtime
       actually treats it: [march_vault_incr] reads/writes an Int cell, and
       [march_vault_push_capped] a List cell. Typing them against a table of
       any [v] would keep exactly the erasure this parameter exists to remove. *)
    ("vault_incr",         poly1 (fun k -> TArrow (t_vault t_int, TArrow (k, TArrow (t_int, t_int)))));
    ("vault_push_capped",  poly2 (fun k e -> TArrow (t_vault (t_list e), TArrow (k, TArrow (e, TArrow (t_int, t_unit))))));
    (* Keys come back STRINGIFIED — [vault_keys] returns what
       [vault_key_cstr] wrote, never the original key value, so [List(String)]
       is the honest type. The old [t -> List(k)] let `Vault.keys(t)` be read
       back at the caller's key type, a second erasure in the same module. *)
    ("vault_keys",         poly1 (fun v -> TArrow (t_vault v, t_list t_string)));
    ("vault_size",         poly1 (fun v -> TArrow (t_vault v, t_int)));
    ("vault_ns_set",       poly2 (fun k v -> TArrow (t_string, TArrow (k, TArrow (v, t_unit)))));
    ("vault_ns_get",       poly2 (fun k v -> TArrow (t_string, TArrow (k, t_option v))));
    ("vault_ns_drop",      poly1 (fun k -> TArrow (t_string, TArrow (k, t_unit))));
    (* Generic to_json/from_json: fully polymorphic — runtime dispatches via impl_tbl.
       ∀a b. a -> b  — this avoids shadowing when multiple types derive Json. *)
    ("to_json",   poly2 (fun a b -> TArrow (a, b)));
    ("from_json",  poly2 (fun a b -> TArrow (a, b)));
    (* from_json_events: same rationale as from_json above (Task 7 / Phase
       B) -- a second, event-consuming decoder derived per record type,
       bound as a plain (non-impl_tbl-dispatched) name per derive so
       multiple types deriving Json in one module can each define it
       without colliding with the polymorphic scheme registered here. *)
    ("from_json_events", poly2 (fun a b -> TArrow (a, b)));
    (* Actor/respond: ∀a. a -> Unit *)
    ("respond", poly1 (fun a -> TArrow (a, t_unit)));
    (* Actor builtins *)
    ("kill",     poly1 (fun a -> TArrow (TCon ("Pid", [a]), t_unit)));
    ("is_alive", poly1 (fun a -> TArrow (TCon ("Pid", [a]), t_bool)));
    ("actor_get_int", poly1 (fun a -> TArrow (TCon ("Pid", [a]), TArrow (t_int, t_int))));
    (* Int primitives *)
    ("int_abs",         Mono (TArrow (t_int,   t_int)));
    ("int_pow",         Mono (TArrow (t_int,   TArrow (t_int, t_int))));
    ("int_div",         Mono (TArrow (t_int,   TArrow (t_int, t_int))));
    ("int_mod",         Mono (TArrow (t_int,   TArrow (t_int, t_int))));
    ("int_div_euclid",  Mono (TArrow (t_int,   TArrow (t_int, t_int))));
    ("int_mod_euclid",  Mono (TArrow (t_int,   TArrow (t_int, t_int))));
    ("int_to_float",    Mono (TArrow (t_int,   t_float)));
    ("int_max_value",   Mono (TArrow (t_unit,  t_int)));
    ("int_min_value",   Mono (TArrow (t_unit,  t_int)));
    (* Int bitwise primitives *)
    ("int_and",         Mono (TArrow (t_int,   TArrow (t_int, t_int))));
    ("int_or",          Mono (TArrow (t_int,   TArrow (t_int, t_int))));
    ("int_xor",         Mono (TArrow (t_int,   TArrow (t_int, t_int))));
    ("int_not",         Mono (TArrow (t_int,   t_int)));
    ("int_shl",         Mono (TArrow (t_int,   TArrow (t_int, t_int))));
    ("int_shr",         Mono (TArrow (t_int,   TArrow (t_int, t_int))));
    ("int_popcount",    Mono (TArrow (t_int,   t_int)));
    (* Float primitives *)
    ("float_abs",       Mono (TArrow (t_float, t_float)));
    ("float_floor",     Mono (TArrow (t_float, t_int)));
    ("float_ceil",      Mono (TArrow (t_float, t_int)));
    ("float_round",     Mono (TArrow (t_float, t_int)));
    ("float_truncate",  Mono (TArrow (t_float, t_int)));
    ("float_to_int",    Mono (TArrow (t_float, t_int)));
    ("float_is_nan",    Mono (TArrow (t_float, t_bool)));
    ("float_is_infinite",Mono (TArrow (t_float, t_bool)));
    ("float_infinity",  Mono (TArrow (t_unit,  t_float)));
    ("float_neg_infinity",Mono (TArrow (t_unit, t_float)));
    ("float_nan",       Mono (TArrow (t_unit,  t_float)));
    ("float_epsilon",   Mono (TArrow (t_unit,  t_float)));
    ("unix_time",       Mono (TArrow (t_unit,  t_float)));
    ("unix_time_ms",    Mono (TArrow (t_unit,  t_int)));
    (* peak_rss_bytes: process self-inspection (peak resident set size, in
       bytes, on both platforms). Deliberately NOT in the capability table
       below — it performs no IO and observes nothing outside this process,
       so unlike unix_time (gated to IO.Clock right next to this entry) it
       needs no capability grant. Don't "fix" that by copying unix_time's
       cap-table entry. *)
    ("peak_rss_bytes",  Mono (TArrow (t_unit,  t_int)));
    (* live_allocs: net count of live March heap objects (march_alloc minus
       free-on-rc-zero). Same ambient, non-capability-gated rationale as
       peak_rss_bytes directly above — it reads one process-local counter and
       observes nothing outside this process. Unlike peak_rss_bytes it is
       exact and platform-independent (a plain atomic counter, no getrusage,
       no allocator or OS accounting in the path), which is why the RSS leak
       probes now assert on it instead. *)
    ("live_allocs",     Mono (TArrow (t_unit,  t_int)));
    ("uuid_v7",         Mono (TArrow (t_unit,  t_string)));
    ("uuid_v7_at",      Mono (TArrow (t_int,   t_string)));
    ("float_from_string",Mono (TArrow (t_string, t_option t_float)));
    ("float_to_string", Mono (TArrow (t_float,  t_string)));
    (* Math primitives *)
    ("math_sqrt",   Mono (TArrow (t_float, t_float)));
    ("math_cbrt",   Mono (TArrow (t_float, t_float)));
    ("math_pow",    Mono (TArrow (t_float, TArrow (t_float, t_float))));
    ("math_exp",    Mono (TArrow (t_float, t_float)));
    ("math_exp2",   Mono (TArrow (t_float, t_float)));
    ("math_log",    Mono (TArrow (t_float, t_float)));
    ("math_log2",   Mono (TArrow (t_float, t_float)));
    ("math_log10",  Mono (TArrow (t_float, t_float)));
    ("math_sin",    Mono (TArrow (t_float, t_float)));
    ("math_cos",    Mono (TArrow (t_float, t_float)));
    ("math_tan",    Mono (TArrow (t_float, t_float)));
    ("math_asin",   Mono (TArrow (t_float, t_float)));
    ("math_acos",   Mono (TArrow (t_float, t_float)));
    ("math_atan",   Mono (TArrow (t_float, t_float)));
    ("math_atan2",  Mono (TArrow (t_float, TArrow (t_float, t_float))));
    ("math_sinh",   Mono (TArrow (t_float, t_float)));
    ("math_cosh",   Mono (TArrow (t_float, t_float)));
    ("math_tanh",   Mono (TArrow (t_float, t_float)));
    (* String primitives *)
    ("string_is_empty",     Mono (TArrow (t_string, t_bool)));
    ("string_slice",        Mono (TArrow (t_string, TArrow (t_int, TArrow (t_int, t_string)))));
    ("string_contains",     Mono (TArrow (t_string, TArrow (t_string, t_bool))));
    ("string_starts_with",  Mono (TArrow (t_string, TArrow (t_string, t_bool))));
    ("string_ends_with",    Mono (TArrow (t_string, TArrow (t_string, t_bool))));
    ("string_index_of",     Mono (TArrow (t_string, TArrow (t_string, t_option t_int))));
    ("string_index_of_from", Mono (TArrow (t_string, TArrow (t_string, TArrow (t_int, t_option t_int)))));
    ("string_replace",      Mono (TArrow (t_string, TArrow (t_string, TArrow (t_string, t_string)))));
    ("string_replace_all",  Mono (TArrow (t_string, TArrow (t_string, TArrow (t_string, t_string)))));
    ("string_split",        Mono (TArrow (t_string, TArrow (t_string, t_list t_string))));
    ("string_concat3",      Mono (TArrow (t_string, TArrow (t_string, TArrow (t_string, t_string)))));
    ("string_join",         Mono (TArrow (t_list t_string, TArrow (t_string, t_string))));
    ("string_trim",         Mono (TArrow (t_string, t_string)));
    ("string_trim_start",   Mono (TArrow (t_string, t_string)));
    ("string_trim_end",     Mono (TArrow (t_string, t_string)));
    ("string_to_uppercase", Mono (TArrow (t_string, t_string)));
    ("string_to_lowercase", Mono (TArrow (t_string, t_string)));
    ("string_chars",        Mono (TArrow (t_string, t_list t_string)));
    ("string_from_chars",   Mono (TArrow (t_list t_string, t_string)));
    ("string_repeat",       Mono (TArrow (t_string, TArrow (t_int, t_string))));
    ("string_reverse",      Mono (TArrow (t_string, t_string)));
    ("string_pad_left",     Mono (TArrow (t_string, TArrow (t_int, TArrow (t_string, t_string)))));
    ("string_pad_right",    Mono (TArrow (t_string, TArrow (t_int, TArrow (t_string, t_string)))));
    ("string_byte_length",  Mono (TArrow (t_string, t_int)));
    ("string_byte_at",      Mono (TArrow (t_string, TArrow (t_int, t_int))));
    ("string_split_first",   Mono (TArrow (t_string, TArrow (t_string, t_option (TTuple [t_string; t_string])))));
    ("string_grapheme_count",Mono (TArrow (t_string, t_int)));
    (* Char primitives — in March, a "char" is a single-char String *)
    ("char_is_alpha",        Mono (TArrow (t_string, t_bool)));
    ("char_is_digit",        Mono (TArrow (t_string, t_bool)));
    ("char_is_alphanumeric", Mono (TArrow (t_string, t_bool)));
    ("char_is_whitespace",   Mono (TArrow (t_string, t_bool)));
    ("char_is_uppercase",    Mono (TArrow (t_string, t_bool)));
    ("char_is_lowercase",    Mono (TArrow (t_string, t_bool)));
    ("char_to_uppercase",    Mono (TArrow (t_string, t_string)));
    ("char_to_lowercase",    Mono (TArrow (t_string, t_string)));
    ("char_to_int",          Mono (TArrow (t_string, t_int)));
    ("char_from_int",        Mono (TArrow (t_int, t_string)));
    (* Comparison primitives *)
    ("compare_int",    Mono (TArrow (t_int,    TArrow (t_int,    t_int))));
    ("compare_float",  Mono (TArrow (t_float,  TArrow (t_float,  t_int))));
    ("compare_string", Mono (TArrow (t_string, TArrow (t_string, t_int))));
    (* Diverging primitives *)
    ("panic",       poly1 (fun a -> TArrow (t_string, a)));
    ("panic_",      poly1 (fun a -> TArrow (t_string, a)));
    ("todo_",       poly1 (fun a -> TArrow (t_string, a)));
    ("unreachable_",poly1 (fun a -> TArrow (t_unit,   a)));
    (* Task builtins — thunks use fn x -> expr (single Int param, ignored).
       task_spawn calls the thunk with 0, wraps result in Task(a). *)
    ("task_spawn",         poly1 (fun a -> TArrow (TArrow (t_int, a), TCon ("Task", [a]))));
    ("task_await",         poly1 (fun a -> TArrow (TCon ("Task", [a]), t_result a t_string)));
    ("task_await_unwrap",  poly1 (fun a -> TArrow (TCon ("Task", [a]), a)));
    ("task_yield",         Mono (TArrow (t_unit, t_unit)));
    ("task_spawn_steal",   poly1 (fun a -> TArrow (TCon ("WorkPool", []), TArrow (TArrow (t_int, a), TCon ("Task", [a])))));
    ("task_reductions",    Mono (TArrow (t_unit, t_int)));
    (* Zero-arg: pmap_threshold() parses as EApp(f,[]); infer_app returns the
       declared type directly, so declare as Mono Int (not TArrow unit Int). *)
    ("pmap_threshold",     Mono t_int);
    ("get_work_pool",      Mono (TCon ("WorkPool", [])));
    (* Capability builtins.  root_cap is a bare value (use `root_cap`, never
       `root_cap()`) — see [noncallable_builtin_values]. *)
    ("root_cap",   Mono (TCon ("Cap", [TCon ("IO", [])])));
    (* R4a (2026-08-06): source is [Cap(a)], not [Cap(IO)], so attenuation can
       CHAIN — a holder of [Cap(IO.FileSystem)] can hand out
       [Cap(IO.FileRead)].  Before this, the argument was literally the root,
       so only [main] could attenuate and least-privilege threading was
       unwritable past the first hop.
       The monotonicity that the old argument type enforced structurally (a
       widen simply failed to unify) now lives in [check_cap_narrow_sites].
       That is weaker IN KIND — an application site the sweep does not record
       is a silently permitted widen — which is why every site is recorded at
       one place below and why reject/t153-t155 are the load-bearing witnesses
       rather than decorative ones. *)
    ("cap_narrow", poly2 (fun a b -> TArrow (TCon ("Cap", [a]), TCon ("Cap", [b]))));
    (* mint_cap: the gated proof-cap mint. Same scheme as cap_narrow
       (Cap(IO) -> Cap(a)); the GATE (declaring-module + public fn, proof-cap
       target only) is enforced in the EApp special-case, not the scheme.
       Runtime-erased: aliases cap_narrow in eval/defun/llvm (caps compile to
       null/VUnit). *)
    ("mint_cap",   poly1 (fun a -> TArrow (TCon ("Cap", [TCon ("IO", [])]), TCon ("Cap", [a]))));
    (* cap_impl: attach a runtime DICTIONARY to a capability that declared one
       (`proof cap Live with Ops`).  The scheme is deliberately loose in the
       dictionary position — the dictionary's type is checked against the
       capability's declared `with` type by [check_cap_impl_sites], because the
       result cap is not pinned until later unification (typically the
       enclosing fn's return annotation), exactly as for [mint_cap].  The GATE
       (declaring-module + public fn; IO caps refused outside a --test build)
       lives in that sweep too, not in this scheme. *)
    ("cap_impl",   poly2 (fun a b ->
       TArrow (TCon ("Cap", [a]), TArrow (b, TCon ("Cap", [a])))));
    (* cap_dict: read a capability's dictionary back.  [Option], not the bare
       dictionary: [None] is "no dictionary — ambient/default implementation",
       which is every capability that has ever existed, so the read is total and
       the default path stays visible in the source.  The scheme here is only
       for bare references; an APPLICATION is typed by the [cap_dict] arm in
       [infer_expr], which resolves the result from the capability's declared
       `with` type and therefore needs the argument's type known at the site. *)
    ("cap_dict",   poly2 (fun a b -> TArrow (TCon ("Cap", [a]), t_option b)));
    (* cap_ops_empty: the all-None dictionary for a capability — the base a
       mock overrides one field of, `{ cap_ops_empty(c) with print_line: ... }`.
       March records unify EXACTLY (no width subtyping), so without a base every
       mock would have to spell out every operation of the capability.  Typed by
       the [cap_ops_empty] arm in [infer_expr], which resolves the record from
       the capability. *)
    ("cap_ops_empty", poly2 (fun a b -> TArrow (TCon ("Cap", [a]), b)));
    (* Phase 1: Monitor/link builtins *)
    ("monitor",      poly2 (fun a b -> TArrow (TCon ("Pid", [a]), TArrow (TCon ("Pid", [b]), t_int))));
    ("demonitor",    Mono (TArrow (t_int, t_unit)));
    ("mailbox_size", poly1 (fun a -> TArrow (TCon ("Pid", [a]), t_int)));
    (* Task 6: scheduler observability — raw stat read by index. *)
    ("sched_stat",   Mono (TArrow (t_int, t_int)));
    (* Task 9: bind a mailbox capacity + overflow policy to an actor. *)
    ("actor_set_mailbox_limit", poly1 (fun a -> TArrow (TCon ("Pid", [a]), TArrow (t_int, TArrow (t_int, t_unit)))));
    (* Phase 4: Actor state introspection — reads a named field from actor state *)
    ("get_actor_field", poly2 (fun a b -> TArrow (TCon ("Pid", [a]), TArrow (t_string, t_option b))));
    (* Phase 4: Flush the async message queue — runs all pending handlers *)
    ("run_until_idle", Mono (TArrow (t_unit, t_unit)));
    (* Phase 6a: Register a cleanup resource with an actor — called on kill/crash *)
    ("register_resource", poly1 (fun a -> TArrow (TCon ("Pid", [a]),
        TArrow (t_string, TArrow (TArrow (t_unit, t_unit), t_unit)))));
    (* Phase 6b: Register a linear value with an actor; Drop impl resolved at runtime *)
    ("own", poly2 (fun a b -> TArrow (TCon ("Pid", [a]), TArrow (b, t_unit))));
    (* Named registry (Task 4): register/unregister/whereis/registered over the
       runtime-owned name table. No capability — the runtime owns the table,
       so no March-level naming call happens. Arg order matches monitor/kill
       (pid first). *)
    ("actor_register",   poly1 (fun a -> TArrow (TCon ("Pid", [a]), TArrow (t_string, t_bool))));
    ("actor_unregister", Mono (TArrow (t_string, t_bool)));
    ("actor_whereis",    poly1 (fun a -> TArrow (t_string, TCon ("Option", [TCon ("Pid", [a])]))));
    ("actor_registered", Mono (TArrow (t_unit, TCon ("List", [t_string]))));
    (* Phase 3: Epoch-based capability builtins *)
    (* [ActorCap], NOT [Cap] (2026-08-06).  These are process capabilities —
       a revocable, epoch-checked reference to a live actor, represented at run
       time as [VCap (pid, epoch)] and consumed by [send_checked] /
       [revoke_cap] / [is_cap_valid].  An IO capability is a different thing
       entirely: [VUnit], fully erased, governed by [needs] and the lattice.

       They shared the [Cap] constructor until 2026-08-06 and therefore
       UNIFIED, which meant [get_cap]'s unconstrained [a] could bind to [IO]
       and hand a module the root capability it was never granted — defeating
       R2 in two lines with no actor declared.  See the R8 audit
       (specs/2026-08-06-r8-runtime-hatch-audit.md) and reject/t158.

       Splitting the constructor rather than sweeping [get_cap]'s sites is
       deliberate: a sweep patches one symptom, while the conflation would keep
       producing them for every future builtin returning [Cap(a)].

       A consequence worth naming: [ActorCap] is invisible to [needs], because
       [Cap_surface_ty.caps_in_ty] matches [Cap].  That is correct — a process
       capability is not IO authority and never should have required a
       declaration. *)
    ("get_cap",      poly1 (fun a -> TArrow (TCon ("Pid", [a]), TCon ("Option", [TCon ("ActorCap", [a])]))));
    (* [ActorCap]'s parameter is the actor's STATE type (it flows from
       get_cap : Pid(a) -> Option(ActorCap(a)) and, since spawn returns
       Pid[state], is the concrete state record); the MESSAGE argument is an
       unrelated constructor type — a distinct variable.  Tying both to `a`
       only ever typechecked while spawn yielded Pid[<fresh>]. *)
    ("send_checked", poly2 (fun a b -> TArrow (TCon ("ActorCap", [a]), TArrow (b, t_atom))));
    ("revoke_cap",   poly1 (fun a -> TArrow (TCon ("ActorCap", [a]), t_atom)));
    ("is_cap_valid", poly1 (fun a -> TArrow (TCon ("ActorCap", [a]), t_bool)));
    (* Utility: convert Int to Pid (unsafe but needed for supervisor state fields) *)
    ("pid_of_int",   poly1 (fun a -> TArrow (t_int, TCon ("Pid", [a]))));
    (* Phase 5: task_spawn_link — like task_spawn but links to spawner *)
    ("task_spawn_link", poly1 (fun a -> TArrow (TArrow (t_int, a), TCon ("Task", [a]))));
    (* Phase 5B: cancellation token builtins.
       task_cancel_token_new() is zero-arg: EApp(f,[]) → infer_app returns type
       directly (see infer_app: | [], t -> t), so declare as Mono CancelToken,
       not as TArrow(t_unit, CancelToken). *)
    ("task_cancel_token_new",  Mono (TCon ("CancelToken", [])));
    ("task_cancel",            Mono (TArrow (TCon ("CancelToken", []), t_unit)));
    ("task_is_cancelled",      Mono (TArrow (TCon ("CancelToken", []), t_bool)));
    ("task_spawn_with_cancel", poly1 (fun a ->
        TArrow (TArrow (t_int, a),
        TArrow (TCon ("CancelToken", []),
                TCon ("Task", [a])))));
    ("task_cancel_by_id",      poly1 (fun a -> TArrow (TCon ("Task", [a]), t_unit)));
    (* File I/O builtins.
       All of these fail with a concrete `File.FileError` value at runtime
       (see eval.ml's file_error_of_unix/file_error_of_sys) — never an
       arbitrary caller-chosen type — so the error type is Mono, not a
       polymorphic `e`.  Registering it as poly1 previously let a caller
       declare an incompatible Result(_, T) and typecheck with zero errors,
       then panic the moment the bound error value was used as T. *)
    ("file_exists",     Mono (TArrow (t_string, t_bool)));
    ("file_read",       Mono (TArrow (t_string, t_result t_string (TCon ("FileError", [])))));
    ("file_write",      Mono (TArrow (t_string, TArrow (t_string, t_result t_unit (TCon ("FileError", []))))));
    ("file_append",     Mono (TArrow (t_string, TArrow (t_string, t_result t_unit (TCon ("FileError", []))))));
    ("file_delete",     Mono (TArrow (t_string, t_result t_unit (TCon ("FileError", [])))));
    ("file_copy",       Mono (TArrow (t_string, TArrow (t_string, t_result t_unit (TCon ("FileError", []))))));
    ("file_rename",     Mono (TArrow (t_string, TArrow (t_string, t_result t_unit (TCon ("FileError", []))))));
    ("file_stat",       Mono (TArrow (t_string, t_result (TCon ("FileStat", [])) (TCon ("FileError", [])))));
    ("file_open",       Mono (TArrow (t_string, t_result t_int (TCon ("FileError", [])))));
    ("file_read_line",  Mono (TArrow (t_int, t_option t_string)));
    ("file_read_chunk", Mono (TArrow (t_int, TArrow (t_int, t_option t_string))));
    ("file_close",      Mono (TArrow (t_int, t_unit)));
    (* Structured cleanup: try_finally(action: () -> a, cleanup: () -> b) : a *)
    ("try_finally",
      poly2 (fun a b -> TArrow (TArrow (t_int, a),
                                TArrow (TArrow (t_int, b), a))));
    (* CSV builtins — csv_next_row returns CsvRow (declared in csv.march).
       The TIR registers user ptypes under their module-qualified name
       ("Csv.CsvRow"), so this MUST match that qualification: a bare
       "CsvRow" here makes Repr.niche_repr_of_concrete's find_variant miss
       the type definition and silently fall back to Boxed, even though
       CsvRow is niche-shaped (CsvEof nullary + Row single-payload). Under
       Boxed the compiled match reads a heap object's tag byte, but the C
       runtime returns raw NULL for EOF (a Niche-only convention) — so every
       row is misread against an uninitialized tag. *)
    (* csv_open's error is always a concrete Csv.CsvError value at runtime
       (see eval.ml's csv_open_impl) — Mono, not a polymorphic `e`. CsvError
       isn't niche-shaped (both variants carry a payload) so, unlike CsvRow
       above, the bare name is fine here. *)
    ("csv_open",     Mono (TArrow (t_string, TArrow (t_string, TArrow (t_atom, t_result t_int (TCon ("CsvError", [])))))));
    ("csv_next_row", Mono (TArrow (t_int, TCon ("Csv.CsvRow", []))));
    ("csv_close",    Mono (TArrow (t_int, t_atom)));
    (* TCP/HTTP transport builtins *)
    (* tcp_listen(port): binds+listens on port, returns Ok(listen_fd) or Err(reason) *)
    ("tcp_listen",              Mono (TArrow (t_int, t_result t_int t_string)));
    (* tcp_accept(listen_fd): blocks until a client connects, returns Ok(client_fd) or Err *)
    ("tcp_accept",              Mono (TArrow (t_int, t_result t_int t_string)));
    (* tcp_local_port(fd): the local (bound) port of a socket — the OS-assigned
       one when listened on port 0. Returns Ok(port) or Err(reason). *)
    ("tcp_local_port",          Mono (TArrow (t_int, t_result t_int t_string)));
    (* tcp_connect/send_all/recv_all always fail with a String reason (see
       eval.ml and runtime/march_http.c) — Mono, matching tcp_listen/tcp_accept
       above rather than leaving the error type unconstrained. *)
    ("tcp_connect",             Mono (TArrow (t_string, TArrow (t_int, t_result t_int t_string))));
    ("tcp_send_all",            Mono (TArrow (t_int, TArrow (t_string, t_result t_unit t_string))));
    ("tcp_recv_all",            Mono (TArrow (t_int, TArrow (t_int, TArrow (t_int, t_result t_string t_string)))));
    ("tcp_close",               Mono (TArrow (t_int, t_unit)));
    (* tcp_peer_addr(fd): numeric IP of the connected peer; "" when unavailable *)
    ("tcp_peer_addr",           Mono (TArrow (t_int, t_string)));
    ("dns_resolve",             Mono (TArrow (t_string, t_result (t_list t_string) t_string)));
    (* tcp_recv_exact(fd, n): reads exactly n bytes, returns Result(Bytes, String) *)
    ("tcp_recv_exact",          Mono (TArrow (t_int, TArrow (t_int, t_result (TCon ("Bytes", [])) t_string))));
    (* md5(s): returns 32-char lowercase hex digest *)
    ("md5",                     Mono (TArrow (t_string, t_string)));
    ("tcp_recv_http",           Mono (TArrow (t_int, TArrow (t_int, t_result t_string t_string))));
    ("tcp_recv_http_headers",   Mono (TArrow (t_int, t_result (TTuple [t_string; t_int; t_bool]) t_string)));
    ("tcp_recv_chunk",          Mono (TArrow (t_int, TArrow (t_int, t_result t_string t_string))));
    (* tcp_recv_chunk_timeout(fd, max_bytes, timeout_ms): one chunk, bounded by a
       per-call deadline.  Err("recv: timed out") when the peer stays silent. *)
    ("tcp_recv_chunk_timeout",  Mono (TArrow (t_int, TArrow (t_int, TArrow (t_int, t_result t_string t_string)))));
    (* tcp_set_recv_timeout(fd, timeout_ms): SO_RCVTIMEO on fd, so later reads —
       including reads made through OpenSSL — fail instead of hanging. *)
    ("tcp_set_recv_timeout",    Mono (TArrow (t_int, TArrow (t_int, t_result t_unit t_string))));
    ("tcp_recv_chunked_frame",  Mono (TArrow (t_int, t_result t_string t_string)));
    (* Ok(None) is the cap expiring: the absence of an event, not an error. *)
    ("tcp_recv_timeout",        Mono (TArrow (t_int, TArrow (t_int, TArrow (t_int, t_result (t_option t_string) t_string)))));
    (* http_serialize_request(method, host, path, query_opt, headers, body) -> String *)
    ("http_serialize_request",  Mono (TArrow (t_string, TArrow (t_string, TArrow (t_string,
        TArrow (t_option t_string, TArrow (t_list (TCon ("Header", [])), TArrow (t_string, t_string))))))));
    ("http_parse_response",     Mono (TArrow (t_string,
        t_result (TTuple [t_int; t_list (TCon ("Header", [])); t_string]) t_string)));
    (* http_fetch / http_fetch_available: JS-only fetch path used by
       HttpTransport.request (stdlib/http_transport.march).  On native builds
       http_fetch_available() always returns false (see runtime/march_http.c),
       so http_fetch itself is never actually invoked — the tcp_* socket path
       handles the request instead.  Both are registered here (Bool / a
       concrete Result(String,String)) so the call sites get a real static
       type instead of falling through llvm_emit's generic erased-type path,
       which expects a different (boxed) representation than a raw Bool. *)
    ("http_fetch_available",    Mono t_bool);
    ("http_fetch",              Mono (TArrow (t_string, TArrow (t_string,
        TArrow (t_string, TArrow (t_string, t_result t_string t_string))))));
    (* http_server_listen(port, max_conns, idle_timeout, pipeline_fn) *)
    ("http_server_listen",      poly1 (fun a -> TArrow (t_int, TArrow (t_int, TArrow (t_int, TArrow (TArrow (a, a), t_unit))))));
    (* http_server_spawn_n(port, n, max_conns, idle_timeout, pipeline_fn) -> Int (pid) *)
    ("http_server_spawn_n",     poly1 (fun a -> TArrow (t_int, TArrow (t_int, TArrow (t_int, TArrow (t_int, TArrow (TArrow (a, a), t_int)))))));
    ("http_server_wait",        Mono (TArrow (t_int, t_unit)));
    (* WebSocket builtins — WsFrame and SelectResult declared in websocket.march *)
    ("ws_recv",   Mono (TArrow (t_int, TCon ("WsFrame", []))));
    ("ws_send",   Mono (TArrow (t_int, TArrow (TCon ("WsFrame", []), t_unit))));
    ("ws_select", Mono (TArrow (t_int, TArrow (t_int, TArrow (t_int, TCon ("SelectResult", []))))));
    (* Dir I/O builtins — same FileError-vs-poly1 gap as the File builtins
       above (see eval.ml's dir_list/dir_mkdir/dir_mkdir_p/dir_rmdir/dir_rm_rf). *)
    ("dir_exists",      Mono (TArrow (t_string, t_bool)));
    ("dir_list",        Mono (TArrow (t_string, t_result (t_list t_string) (TCon ("FileError", [])))));
    ("dir_mkdir",       Mono (TArrow (t_string, t_result t_unit (TCon ("FileError", [])))));
    ("dir_mkdir_p",     Mono (TArrow (t_string, t_result t_unit (TCon ("FileError", [])))));
    ("dir_rmdir",       Mono (TArrow (t_string, t_result t_unit (TCon ("FileError", [])))));
    ("dir_rm_rf",       Mono (TArrow (t_string, t_result t_unit (TCon ("FileError", [])))));
    (* String extra builtins *)
    ("string_last_index_of", Mono (TArrow (t_string, TArrow (t_string, t_option t_int))));
    (* App/Supervisor builtins *)
    ("worker",          poly1 (fun a -> TArrow (a, TCon ("ChildSpec", []))));
    ("Supervisor.spec", Mono (TArrow (t_atom, TArrow (t_list (TCon ("ChildSpec", [])),
                                                       TCon ("SupervisorSpec", [])))));
    (* Dynamic supervisor builtins *)
    ("dynamic_supervisor", Mono (TArrow (t_atom, TArrow (t_atom, TCon ("ChildSpec", [])))));
    ("Supervisor.start_child",
     poly1 (fun a -> TArrow (t_atom, TArrow (TCon ("ChildSpec", []),
                                             t_result (TCon ("Pid", [a])) t_string))));
    ("Supervisor.stop_child",
     Mono (TArrow (t_atom, TArrow (t_int, t_result t_unit t_string))));
    ("Supervisor.which_children",
     Mono (TArrow (t_atom, t_list t_unit)));   (* simplified; full type is List({pid,...}) *)
    ("Supervisor.count_children",
     Mono (TArrow (t_atom, TCon ("SupervisorSpec", []))));  (* simplified return type *)
    ("App.stop",        Mono (TArrow (t_unit, t_unit)));
    (* Session-typed channel builtins — Chan.send/recv/close are special-cased in
       infer_expr for proper session type advancement. These entries just put the
       names in scope; the real typing is done in the Chan.* EApp branches. *)
    ("Chan.new",    poly2 (fun a b -> TArrow (t_string, TTuple [a; b])));
    ("Chan.send",   poly2 (fun a b -> TArrow (a, TArrow (t_unit, b))));
    ("Chan.recv",   poly1 (fun a -> TArrow (t_unit, a)));
    ("Chan.close",  Mono (TArrow (t_unit, t_unit)));
    ("Chan.choose", poly2 (fun a b -> TArrow (a, TArrow (t_atom, b))));
    ("Chan.offer",  poly1 (fun a -> TArrow (a, TTuple [t_atom; a])));
    (* Byte builtins *)
    ("byte_to_char", Mono (TArrow (t_int, t_string)));
    (* Actor message-passing builtins *)
    ("actor_cast",  poly2 (fun a b -> TArrow (a, TArrow (b, t_unit))));
    ("actor_call",
      let pid_a = fresh_var 0 in
      let msg_b = fresh_var 0 in
      let ret_c = fresh_var 0 in
      Poly ([get_id pid_a; get_id msg_b; get_id ret_c], [],
        TArrow (pid_a, TArrow (msg_b, TArrow (t_int, t_result ret_c t_string)))));
    ("actor_reply", poly2 (fun a b -> TArrow (a, TArrow (b, t_unit))));
    (* actor_send_after/actor_cancel_timer (specs/progress/2026-08-12-language-
       level-timers.md): schedule msg for delivery to pid after delay_ms
       milliseconds, returning an opaque TimerRef; actor_cancel_timer(ref)
       cancels a still-pending one. Named with the "actor_" raw-builtin
       prefix (like actor_cast/actor_call/actor_reply, all wrapped by clean
       Actor.* names in stdlib/actor.march) rather than left bare like
       self/spawn/send: a bare `send_after`/`cancel_timer` March-level
       wrapper of the SAME name recursing into itself instead of reaching
       the builtin is exactly the documented System.mem_peak_bytes/
       peak_rss_bytes pitfall (stdlib/system.march) — March has no way to
       call a shadowed global from inside a same-named local fn. `a` (the
       pid slot) is left just as unconstrained as actor_cast's — self()
       returns Int, a real spawn() Pid(a) is a distinct heap type, and both
       already flow through actor_cast's identically-unconstrained first
       parameter. TimerRef carries no type parameter (not CancelToken(a)-
       shaped): a timer is not associated with any particular actor's state
       type. *)
    ("actor_send_after", poly2 (fun a b ->
        TArrow (a, TArrow (b, TArrow (t_int, TCon ("TimerRef", []))))));
    ("actor_cancel_timer", Mono (TArrow (TCon ("TimerRef", []), t_unit)));
    (* Logger builtins — 0-arg variants typed as Mono(result) so foo() works *)
    ("logger_set_level",   Mono (TArrow (t_int, t_unit)));
    ("logger_get_level",   Mono t_int);
    ("logger_add_context", Mono (TArrow (t_string, TArrow (t_string, t_unit))));
    ("logger_clear_context", Mono t_unit);
    ("logger_get_context", Mono (t_list (TTuple [t_string; t_string])));
    ("logger_write",       Mono (TArrow (t_string, TArrow (t_string,
        TArrow (t_list (TTuple [t_string; t_string]),
        TArrow (t_list (TTuple [t_string; t_string]), t_unit))))));
    (* Logger v2: structured field stack.  LogValue and LogField are
       declared in stdlib/logger.march; the builtins are typed
       polymorphic on those constructors and the typechecker
       reconciles them at the call site. *)
    ("logger_add_field",     poly1 (fun a -> TArrow (t_string, TArrow (a, t_unit))));
    ("logger_field_count",   Mono t_int);
    ("logger_pop_to_depth",  Mono (TArrow (t_int, t_unit)));
    ("logger_get_fields",    poly1 (fun a -> a));
    (* Logger v2 appender pipeline.  Polymorphic so the LogEntry /
       Appender constructor types declared in stdlib/logger.march
       unify at the call site. *)
    ("logger_register_appender",
       poly1 (fun a -> TArrow (t_string, TArrow (a, t_unit))));
    ("logger_remove_appender",   Mono (TArrow (t_string, t_unit)));
    ("logger_clear_appenders",   Mono t_unit);
    ("logger_appender_names",    Mono (t_list t_string));
    ("logger_dispatch",
       poly1 (fun a -> TArrow (t_string, TArrow (t_string,
              TArrow (t_string, TArrow (a, t_unit))))));
    ("logger_set_module_level",
       Mono (TArrow (t_string, TArrow (t_int, t_unit))));
    ("logger_clear_module_level", Mono (TArrow (t_string, t_unit)));
    ("logger_module_level",       Mono (TArrow (t_string, t_int)));
    (* Process builtins — 0-arg variants typed as Mono(result) *)
    ("process_env",        Mono (TArrow (t_string, t_option t_string)));
    ("process_set_env",    Mono (TArrow (t_string, TArrow (t_string, t_unit))));
    ("process_cwd",        Mono t_string);
    ("process_exit",       Mono (TArrow (t_int, t_unit)));
    ("process_argv",       Mono (t_list t_string));
    ("process_pid",        Mono t_int);
    (* process_spawn_sync/lines/async always fail with a String reason (see
       eval.ml and runtime/march_runtime.c) — the error type is Mono, not a
       polymorphic `e`.  process_spawn_lines keeps its Seq element type `a`
       polymorphic since that's a generic Seq, unrelated to the error slot. *)
    ("process_spawn_sync", Mono
        (TArrow (t_string, TArrow (t_list t_string,
          t_result (TCon ("ProcessResult", [])) t_string))));
    ("process_spawn_lines", poly1 (fun a ->
        TArrow (t_string, TArrow (t_list t_string,
          t_result (TCon ("Seq", [a])) t_string))));
    (* Async (non-blocking) process spawn *)
    ("process_spawn_async", Mono
        (TArrow (t_string, TArrow (t_list t_string,
          t_result (TCon ("LiveProcess", [])) t_string))));
    ("process_read_line", Mono
        (TArrow (TCon ("LiveProcess", []), t_option t_string)));
    ("process_write", Mono
        (TArrow (TCon ("LiveProcess", []), TArrow (t_string, t_unit))));
    ("process_kill_proc", Mono
        (TArrow (TCon ("LiveProcess", []), t_unit)));
    ("process_wait_proc", Mono
        (TArrow (TCon ("LiveProcess", []), t_int)));
    (* Actor self/receive builtins — 0-arg: foo() parses as EApp(f,[])
       so infer_app returns the type directly without unwrapping TArrow *)
    ("self",    Mono t_int);
    ("receive", poly1 (fun a -> a));
    (* Crypto / encoding builtins *)
    ("sha256",          Mono (TArrow (TCon ("Bytes", []), TCon ("Bytes", []))));
    (* hmac_sha256(key, msg): String-domain HMAC. Canonical signature matches
       the native runtime (march_hmac_sha256 reads march_string args) and the
       eval builtin — both return Result(Bytes, String). *)
    ("hmac_sha256",     Mono (TArrow (t_string, TArrow (t_string,
        TCon ("Result", [TCon ("Bytes", []); t_string])))));
    (* hmac_sha256_bytes(key, msg): Bytes-domain HMAC, bare Bytes result *)
    ("hmac_sha256_bytes", Mono (TArrow (TCon ("Bytes", []), TArrow (TCon ("Bytes", []),
        TCon ("Bytes", [])))));
    ("pbkdf2_sha256",   Mono (TArrow (t_string, TArrow (TCon ("Bytes", []),
        TArrow (t_int, TArrow (t_int,
        TCon ("Result", [TCon ("Bytes", []); t_string])))))));
    ("base64_encode",   Mono (TArrow (TCon ("Bytes", []), t_string)));
    ("base64_decode",   Mono (TArrow (t_string,
        TCon ("Result", [TCon ("Bytes", []); t_string]))));
    ("random_bytes",    Mono (TArrow (t_int, TCon ("Bytes", []))));
    (* Bytes <-> NativeU8Arr bridge: pure data movement, not a capability. *)
    ("bytes_to_u8_arr", Mono (TArrow (TCon ("Bytes", []), TCon ("NativeU8Arr", []))));
    ("u8_arr_to_bytes", Mono (TArrow (TCon ("NativeU8Arr", []), TCon ("Bytes", []))));
    (* stdlib_* variants — used by module wrappers that shadow the base names.
       stdlib_base64_encode accepts String only at the type-checker level;
       callers should convert Bytes to String with bytes_to_string first. *)
    ("stdlib_sha256",         Mono (TArrow (t_string, t_string)));
    ("stdlib_random_bytes",   Mono (TArrow (t_int, TCon ("Bytes", []))));
    ("stdlib_base64_encode",  Mono (TArrow (t_string, t_string)));
    ("stdlib_base64_decode",  Mono (TArrow (t_string,
        TCon ("Result", [TCon ("Bytes", []); t_string]))));
    ("stdlib_hmac_sha256",    Mono (TArrow (t_string, TArrow (t_string,
        TCon ("Result", [TCon ("Bytes", []); t_string])))));
    (* Compress builtins — gzip, deflate, zstd, brotli C-level shims.
       Called directly by stdlib/compress.march and any code that needs
       compression without `import Compress` (not in stdlib_file_list). *)
    ("stdlib_gzip_encode",    Mono (TArrow (TCon ("Bytes", []), TArrow (t_int,
        TCon ("Result", [TCon ("Bytes", []); t_string])))));
    ("stdlib_gzip_decode",    Mono (TArrow (TCon ("Bytes", []),
        TCon ("Result", [TCon ("Bytes", []); t_string]))));
    ("stdlib_deflate_encode", Mono (TArrow (TCon ("Bytes", []),
        TCon ("Result", [TCon ("Bytes", []); t_string]))));
    ("stdlib_deflate_decode", Mono (TArrow (TCon ("Bytes", []),
        TCon ("Result", [TCon ("Bytes", []); t_string]))));
    ("stdlib_zstd_encode",    Mono (TArrow (TCon ("Bytes", []), TArrow (t_int,
        TCon ("Result", [TCon ("Bytes", []); t_string])))));
    ("stdlib_zstd_decode",    Mono (TArrow (TCon ("Bytes", []),
        TCon ("Result", [TCon ("Bytes", []); t_string]))));
    ("stdlib_brotli_encode",  Mono (TArrow (TCon ("Bytes", []), TArrow (t_int,
        TCon ("Result", [TCon ("Bytes", []); t_string])))));
    ("stdlib_brotli_decode",  Mono (TArrow (TCon ("Bytes", []),
        TCon ("Result", [TCon ("Bytes", []); t_string]))));
    (* NativeArray builtins — flat OCaml arrays for fast numeric loops (P10).
       NativeIntArr / NativeFloatArr are opaque types (0-arity constructors).
       These builtins are interpreter-path only; compiled mode support is
       tracked in specs/optimizations.md P10 Phase 2. *)
    (* Int array *)
    ("native_int_arr_make",
       Mono (TArrow (t_int, TArrow (t_int, TCon ("NativeIntArr", [])))));
    ("native_int_arr_length",
       Mono (TArrow (TCon ("NativeIntArr", []), t_int)));
    ("native_int_arr_get",
       Mono (TArrow (TCon ("NativeIntArr", []), TArrow (t_int, t_int))));
    ("native_int_arr_set",
       Mono (TArrow (TCon ("NativeIntArr", []),
             TArrow (t_int, TArrow (t_int, TCon ("NativeIntArr", []))))));
    ("native_int_arr_sum",
       Mono (TArrow (TCon ("NativeIntArr", []), t_int)));
    ("native_int_arr_min",
       Mono (TArrow (TCon ("NativeIntArr", []), t_int)));
    ("native_int_arr_max",
       Mono (TArrow (TCon ("NativeIntArr", []), t_int)));
    ("native_int_arr_sumsq_dev",
       Mono (TArrow (TCon ("NativeIntArr", []), TArrow (t_float, t_float))));
    ("native_int_arr_map",
       Mono (TArrow (TCon ("NativeIntArr", []),
             TArrow (TArrow (t_int, t_int), TCon ("NativeIntArr", [])))));
    ("native_int_arr_map2",
       Mono (TArrow (TCon ("NativeIntArr", []),
             TArrow (TCon ("NativeIntArr", []),
             TArrow (TArrow (t_int, TArrow (t_int, t_int)), TCon ("NativeIntArr", []))))));
    ("native_int_arr_to_float_arr",
       Mono (TArrow (TCon ("NativeIntArr", []), TCon ("NativeFloatArr", []))));
    ("native_int_arr_fold",
       poly1 (fun a ->
         TArrow (a, TArrow (TCon ("NativeIntArr", []),
                   TArrow (TArrow (a, TArrow (t_int, a)), a)))));
    ("native_int_arr_from_list",
       Mono (TArrow (t_list t_int, TCon ("NativeIntArr", []))));
    ("native_int_arr_to_list",
       Mono (TArrow (TCon ("NativeIntArr", []), t_list t_int)));
    (* Float array *)
    ("native_float_arr_make",
       Mono (TArrow (t_int, TArrow (t_float, TCon ("NativeFloatArr", [])))));
    ("native_float_arr_length",
       Mono (TArrow (TCon ("NativeFloatArr", []), t_int)));
    ("native_float_arr_get",
       Mono (TArrow (TCon ("NativeFloatArr", []), TArrow (t_int, t_float))));
    ("native_float_arr_set",
       Mono (TArrow (TCon ("NativeFloatArr", []),
             TArrow (t_int, TArrow (t_float, TCon ("NativeFloatArr", []))))));
    ("native_float_arr_sum",
       Mono (TArrow (TCon ("NativeFloatArr", []), t_float)));
    ("native_float_arr_min",
       Mono (TArrow (TCon ("NativeFloatArr", []), t_float)));
    ("native_float_arr_max",
       Mono (TArrow (TCon ("NativeFloatArr", []), t_float)));
    ("native_float_arr_sumsq_dev",
       Mono (TArrow (TCon ("NativeFloatArr", []), TArrow (t_float, t_float))));
    ("native_float_arr_map",
       Mono (TArrow (TCon ("NativeFloatArr", []),
             TArrow (TArrow (t_float, t_float), TCon ("NativeFloatArr", [])))));
    ("native_float_arr_map2",
       Mono (TArrow (TCon ("NativeFloatArr", []),
             TArrow (TCon ("NativeFloatArr", []),
             TArrow (TArrow (t_float, TArrow (t_float, t_float)), TCon ("NativeFloatArr", []))))));
    ("native_float_arr_fold",
       poly1 (fun a ->
         TArrow (a, TArrow (TCon ("NativeFloatArr", []),
                   TArrow (TArrow (a, TArrow (t_float, a)), a)))));
    ("native_float_arr_from_list",
       Mono (TArrow (t_list t_float, TCon ("NativeFloatArr", []))));
    ("native_float_arr_to_list",
       Mono (TArrow (TCon ("NativeFloatArr", []), t_list t_float)));
    ("native_int_arr_filter_mask",
       Mono (TArrow (TCon ("NativeIntArr", []),
             TArrow (TCon ("TypedArray", [t_bool]), TCon ("NativeIntArr", [])))));
    ("native_float_arr_filter_mask",
       Mono (TArrow (TCon ("NativeFloatArr", []),
             TArrow (TCon ("TypedArray", [t_bool]), TCon ("NativeFloatArr", [])))));
    (* Narrow-width NativeArray families — f32/i32/u8 (P10 narrow types).
       Opaque 0-arity types, same shape as NativeIntArr/NativeFloatArr above.
       No min / max / sumsq_dev / filter_mask for these widths -- only the
       9-op family + fold + conversions. *)
    (* f32 *)
    ("native_f32_arr_make",
       Mono (TArrow (t_int, TArrow (t_float, TCon ("NativeF32Arr", [])))));
    ("native_f32_arr_length",
       Mono (TArrow (TCon ("NativeF32Arr", []), t_int)));
    ("native_f32_arr_get",
       Mono (TArrow (TCon ("NativeF32Arr", []), TArrow (t_int, t_float))));
    ("native_f32_arr_set",
       Mono (TArrow (TCon ("NativeF32Arr", []),
             TArrow (t_int, TArrow (t_float, TCon ("NativeF32Arr", []))))));
    ("native_f32_arr_sum",
       Mono (TArrow (TCon ("NativeF32Arr", []), t_float)));
    ("native_f32_arr_map",
       Mono (TArrow (TCon ("NativeF32Arr", []),
             TArrow (TArrow (t_float, t_float), TCon ("NativeF32Arr", [])))));
    ("native_f32_arr_map2",
       Mono (TArrow (TCon ("NativeF32Arr", []),
             TArrow (TCon ("NativeF32Arr", []),
             TArrow (TArrow (t_float, TArrow (t_float, t_float)), TCon ("NativeF32Arr", []))))));
    ("native_f32_arr_fold",
       poly1 (fun a ->
         TArrow (a, TArrow (TCon ("NativeF32Arr", []),
                   TArrow (TArrow (a, TArrow (t_float, a)), a)))));
    ("native_f32_arr_from_list",
       Mono (TArrow (t_list t_float, TCon ("NativeF32Arr", []))));
    ("native_f32_arr_to_list",
       Mono (TArrow (TCon ("NativeF32Arr", []), t_list t_float)));
    (* i32 *)
    ("native_i32_arr_make",
       Mono (TArrow (t_int, TArrow (t_int, TCon ("NativeI32Arr", [])))));
    ("native_i32_arr_length",
       Mono (TArrow (TCon ("NativeI32Arr", []), t_int)));
    ("native_i32_arr_get",
       Mono (TArrow (TCon ("NativeI32Arr", []), TArrow (t_int, t_int))));
    ("native_i32_arr_set",
       Mono (TArrow (TCon ("NativeI32Arr", []),
             TArrow (t_int, TArrow (t_int, TCon ("NativeI32Arr", []))))));
    ("native_i32_arr_sum",
       Mono (TArrow (TCon ("NativeI32Arr", []), t_int)));
    ("native_i32_arr_map",
       Mono (TArrow (TCon ("NativeI32Arr", []),
             TArrow (TArrow (t_int, t_int), TCon ("NativeI32Arr", [])))));
    ("native_i32_arr_map2",
       Mono (TArrow (TCon ("NativeI32Arr", []),
             TArrow (TCon ("NativeI32Arr", []),
             TArrow (TArrow (t_int, TArrow (t_int, t_int)), TCon ("NativeI32Arr", []))))));
    ("native_i32_arr_fold",
       poly1 (fun a ->
         TArrow (a, TArrow (TCon ("NativeI32Arr", []),
                   TArrow (TArrow (a, TArrow (t_int, a)), a)))));
    ("native_i32_arr_from_list",
       Mono (TArrow (t_list t_int, TCon ("NativeI32Arr", []))));
    ("native_i32_arr_to_list",
       Mono (TArrow (TCon ("NativeI32Arr", []), t_list t_int)));
    (* u8 *)
    ("native_u8_arr_make",
       Mono (TArrow (t_int, TArrow (t_int, TCon ("NativeU8Arr", [])))));
    ("native_u8_arr_length",
       Mono (TArrow (TCon ("NativeU8Arr", []), t_int)));
    ("native_u8_arr_get",
       Mono (TArrow (TCon ("NativeU8Arr", []), TArrow (t_int, t_int))));
    ("native_u8_arr_set",
       Mono (TArrow (TCon ("NativeU8Arr", []),
             TArrow (t_int, TArrow (t_int, TCon ("NativeU8Arr", []))))));
    ("native_u8_arr_sum",
       Mono (TArrow (TCon ("NativeU8Arr", []), t_int)));
    ("native_u8_arr_map",
       Mono (TArrow (TCon ("NativeU8Arr", []),
             TArrow (TArrow (t_int, t_int), TCon ("NativeU8Arr", [])))));
    ("native_u8_arr_map2",
       Mono (TArrow (TCon ("NativeU8Arr", []),
             TArrow (TCon ("NativeU8Arr", []),
             TArrow (TArrow (t_int, TArrow (t_int, t_int)), TCon ("NativeU8Arr", []))))));
    ("native_u8_arr_fold",
       poly1 (fun a ->
         TArrow (a, TArrow (TCon ("NativeU8Arr", []),
                   TArrow (TArrow (a, TArrow (t_int, a)), a)))));
    ("native_u8_arr_from_list",
       Mono (TArrow (t_list t_int, TCon ("NativeU8Arr", []))));
    ("native_u8_arr_to_list",
       Mono (TArrow (TCon ("NativeU8Arr", []), t_list t_int)));
    (* Conversions *)
    ("native_float_to_f32_arr",
       Mono (TArrow (TCon ("NativeFloatArr", []), TCon ("NativeF32Arr", []))));
    ("native_f32_to_float_arr",
       Mono (TArrow (TCon ("NativeF32Arr", []), TCon ("NativeFloatArr", []))));
    ("native_int_to_i32_arr",
       Mono (TArrow (TCon ("NativeIntArr", []), TCon ("NativeI32Arr", []))));
    ("native_i32_to_int_arr",
       Mono (TArrow (TCon ("NativeI32Arr", []), TCon ("NativeIntArr", []))));
    ("native_int_to_u8_arr",
       Mono (TArrow (TCon ("NativeIntArr", []), TCon ("NativeU8Arr", []))));
    ("native_u8_to_int_arr",
       Mono (TArrow (TCon ("NativeU8Arr", []), TCon ("NativeIntArr", []))));
    ("native_i32_to_f32_arr",
       Mono (TArrow (TCon ("NativeI32Arr", []), TCon ("NativeF32Arr", []))));
    ("native_u8_to_f32_arr",
       Mono (TArrow (TCon ("NativeU8Arr", []), TCon ("NativeF32Arr", []))));
    (* TypedArray builtins — contiguous native arrays for columnar DataFrame storage *)
    ("typed_array_create",   poly1 (fun a ->
        TArrow (t_int, TArrow (a, TCon ("TypedArray", [a])))));
    ("typed_array_get",      poly1 (fun a ->
        TArrow (TCon ("TypedArray", [a]), TArrow (t_int, a))));
    ("typed_array_set",      poly1 (fun a ->
        TArrow (TCon ("TypedArray", [a]), TArrow (t_int, TArrow (a, TCon ("TypedArray", [a]))))));
    ("typed_array_length",   poly1 (fun a ->
        TArrow (TCon ("TypedArray", [a]), t_int)));
    ("typed_array_slice",    poly1 (fun a ->
        TArrow (TCon ("TypedArray", [a]), TArrow (t_int, TArrow (t_int, TCon ("TypedArray", [a]))))));
    ("typed_array_map",      poly2 (fun a b ->
        TArrow (TCon ("TypedArray", [a]), TArrow (TArrow (a, b), TCon ("TypedArray", [b])))));
    ("typed_array_filter",   poly1 (fun a ->
        TArrow (TCon ("TypedArray", [a]), TArrow (TCon ("TypedArray", [t_bool]), TCon ("TypedArray", [a])))));
    ("typed_array_fold",     poly2 (fun a b ->
        TArrow (TCon ("TypedArray", [a]), TArrow (b, TArrow (TArrow (b, TArrow (a, b)), b)))));
    ("typed_array_from_list", poly1 (fun a ->
        TArrow (t_list a, TCon ("TypedArray", [a]))));
    ("typed_array_to_list",  poly1 (fun a ->
        TArrow (TCon ("TypedArray", [a]), t_list a)));
    (* RingBuf builtins — mutable fixed-capacity circular buffer.
       RingBuf(a) is a non-sendable type: the typechecker rejects it in send() payloads. *)
    ("ring_buf_make",        poly1 (fun a ->
        TArrow (t_int, TCon ("RingBuf", [a]))));
    ("ring_buf_push",        poly1 (fun a ->
        TArrow (TCon ("RingBuf", [a]), TArrow (a, t_unit))));
    ("ring_buf_pop",         poly1 (fun a ->
        TArrow (TCon ("RingBuf", [a]), t_option a)));
    ("ring_buf_get",         poly1 (fun a ->
        TArrow (TCon ("RingBuf", [a]), TArrow (t_int, t_option a))));
    ("ring_buf_peek_oldest", poly1 (fun a ->
        TArrow (TCon ("RingBuf", [a]), t_option a)));
    ("ring_buf_peek_newest", poly1 (fun a ->
        TArrow (TCon ("RingBuf", [a]), t_option a)));
    ("ring_buf_size",        poly1 (fun a ->
        TArrow (TCon ("RingBuf", [a]), t_int)));
    ("ring_buf_cap",         poly1 (fun a ->
        TArrow (TCon ("RingBuf", [a]), t_int)));
    ("ring_buf_clear",       poly1 (fun a ->
        TArrow (TCon ("RingBuf", [a]), t_unit)));
    ("ring_buf_to_list",     poly1 (fun a ->
        TArrow (TCon ("RingBuf", [a]), t_list a)));
    (* TLS builtins — tls_client_ctx, tls_server_ctx, etc.  All fail with a
       String reason (see runtime/march_tls.c's make_err) — Mono, not a
       polymorphic `e`. *)
    ("tls_client_ctx",       Mono
        (TArrow (t_string, TArrow (t_list t_string, TArrow (t_int, TArrow (t_int,
          t_result t_int t_string))))));
    ("tls_server_ctx",       Mono
        (TArrow (t_string, TArrow (t_string, TArrow (t_string, TArrow (t_list t_string,
          TArrow (t_int, t_result t_int t_string)))))));
    ("tls_connect",          Mono
        (TArrow (t_int, TArrow (t_int, TArrow (t_string, t_result t_int t_string)))));
    ("tls_accept",           Mono
        (TArrow (t_int, TArrow (t_int, t_result t_int t_string))));
    ("tls_read",             Mono
        (TArrow (t_int, TArrow (t_int, t_result t_string t_string))));
    ("tls_read_timeout",     Mono
        (TArrow (t_int, TArrow (t_int, TArrow (t_int, t_result (t_option t_string) t_string)))));
    ("tls_write",            Mono
        (TArrow (t_int, TArrow (t_string, t_result t_int t_string))));
    ("tls_close",            Mono (TArrow (t_int, t_unit)));
    ("tls_ctx_free",         Mono (TArrow (t_int, t_unit)));
    ("tls_negotiated_alpn",  Mono (TArrow (t_int, t_option t_string)));
    ("tls_peer_cn",          Mono (TArrow (t_int, t_option t_string)));
    (* HTML template builtins — generated by ~H sigil desugar *)
    (* html_auto_escape: ∀a. a -> String
       Accepts any value: Html.Safe, IOList, String, or other (escaped).
       The desugar emits html_auto_escape(x) for each ${x} in ~H sigils. *)
    ("html_auto_escape",   poly1 (fun a -> TArrow (a, t_string)));
    (* html_escape_ctx: ∀a. Int -> a -> String
       The escaper id is chosen at COMPILE time from the parse context
       (lib/ctxesc/automaton.ml) and arrives as a literal. The value stays
       polymorphic so the desugarer need not know the hole's type, but
       llvm_emit normalises it to a String before the call — the runtime must
       never dispatch on a heap tag. See the "Carried over from Task 0" note in
       specs/plans/2026-08-05-contextual-autoescaping.md. *)
    ("html_escape_ctx",    poly1 (fun a -> TArrow (t_int, TArrow (a, t_string))));
    (* iolist_hash_fnv1a: IOList -> String
       FNV-1a 64-bit hash over segments, returns 16-char hex string.
       Used by IOList.hash and Html.content_hash for ETag generation. *)
    ("iolist_hash_fnv1a",  Mono (TArrow (TCon ("IOList", []), t_string)));
    (* Distributed OTP L4 — function-by-identity remote registry.
       remote_ref_hashes(module, fn) returns (sig_hash, impl_hash) from the CAS
       pipeline (compiled path) or deterministic FNV-1a hashes (eval path).
       remote_register_stub(impl_hash, sig_hash, stub) enrolls a marshalling stub
       in the C-level registry; stub type is unconstrained (poly) so the caller
       can pass any function value. Returns 0 on success, -1 on failure.
       remote_count() returns the number of enrolled remote targets (testing). *)
    ("remote_ref_hashes",    Mono (TArrow (t_string, TArrow (t_string, TTuple [t_string; t_string]))));
    ("remote_register_stub", poly1 (fun a -> TArrow (t_string, TArrow (t_string, TArrow (a, t_int)))));
    ("remote_count",         Mono t_int);
    (* Compiler-emitted enroll/stub dispatch builtins (L4).
       remote_check(impl_hash, sig_hash): 0=not enrolled, 1=sig match, 2=TypeMismatch.
       remote_invoke(impl_hash, args): calls the enrolled stub or None if not found. *)
    ("remote_check",  Mono (TArrow (t_string, TArrow (t_string, t_int))));
    ("remote_invoke", Mono (TArrow (t_string, TArrow (TCon ("List", [t_int]),
                        TCon ("Option", [TCon ("Result", [TCon ("List", [t_int]); t_string])])))));
    (* Simd -- explicit 128-bit SIMD vector types (F32x4/F64x2/I32x4/I64x2/U8x16).
       127 builtins per the op grid in
       docs/superpowers/plans/2026-08-10-simd-vector-types.md (Global Constraints).
       Interpreter-path only here; compiled (LLVM) support is a later task.
       simd_<t>_<op> naming; stdlib Simd module wraps as <op>_<t> with refinement-typed
       lane indices. *)
    (* f32x4 *)
    ("simd_f32x4_splat", Mono (TArrow (t_float, TCon ("F32x4", []))));
    ("simd_f32x4_make", Mono (TArrow (t_float, TArrow (t_float, TArrow (t_float, TArrow (t_float, TCon ("F32x4", [])))))));
    ("simd_f32x4_extract", Mono (TArrow (TCon ("F32x4", []), TArrow (t_int, t_float))));
    ("simd_f32x4_replace", Mono (TArrow (TCon ("F32x4", []), TArrow (t_int, TArrow (t_float, TCon ("F32x4", []))))));
    ("simd_f32x4_load", Mono (TArrow (TCon ("NativeF32Arr", []), TArrow (t_int, TCon ("F32x4", [])))));
    ("simd_f32x4_store", Mono (TArrow (TCon ("NativeF32Arr", []), TArrow (t_int, TArrow (TCon ("F32x4", []), TCon ("NativeF32Arr", []))))));
    ("simd_f32x4_eq", Mono (TArrow (TCon ("F32x4", []), TArrow (TCon ("F32x4", []), TCon ("F32x4", [])))));
    ("simd_f32x4_lt", Mono (TArrow (TCon ("F32x4", []), TArrow (TCon ("F32x4", []), TCon ("F32x4", [])))));
    ("simd_f32x4_gt", Mono (TArrow (TCon ("F32x4", []), TArrow (TCon ("F32x4", []), TCon ("F32x4", [])))));
    ("simd_f32x4_and", Mono (TArrow (TCon ("F32x4", []), TArrow (TCon ("F32x4", []), TCon ("F32x4", [])))));
    ("simd_f32x4_or", Mono (TArrow (TCon ("F32x4", []), TArrow (TCon ("F32x4", []), TCon ("F32x4", [])))));
    ("simd_f32x4_xor", Mono (TArrow (TCon ("F32x4", []), TArrow (TCon ("F32x4", []), TCon ("F32x4", [])))));
    ("simd_f32x4_not", Mono (TArrow (TCon ("F32x4", []), TCon ("F32x4", []))));
    ("simd_f32x4_select", Mono (TArrow (TCon ("F32x4", []), TArrow (TCon ("F32x4", []), TArrow (TCon ("F32x4", []), TCon ("F32x4", []))))));
    ("simd_f32x4_any", Mono (TArrow (TCon ("F32x4", []), t_bool)));
    ("simd_f32x4_all", Mono (TArrow (TCon ("F32x4", []), t_bool)));
    ("simd_f32x4_first_set", Mono (TArrow (TCon ("F32x4", []), t_int)));
    ("simd_f32x4_add", Mono (TArrow (TCon ("F32x4", []), TArrow (TCon ("F32x4", []), TCon ("F32x4", [])))));
    ("simd_f32x4_sub", Mono (TArrow (TCon ("F32x4", []), TArrow (TCon ("F32x4", []), TCon ("F32x4", [])))));
    ("simd_f32x4_mul", Mono (TArrow (TCon ("F32x4", []), TArrow (TCon ("F32x4", []), TCon ("F32x4", [])))));
    ("simd_f32x4_div", Mono (TArrow (TCon ("F32x4", []), TArrow (TCon ("F32x4", []), TCon ("F32x4", [])))));
    ("simd_f32x4_min", Mono (TArrow (TCon ("F32x4", []), TArrow (TCon ("F32x4", []), TCon ("F32x4", [])))));
    ("simd_f32x4_max", Mono (TArrow (TCon ("F32x4", []), TArrow (TCon ("F32x4", []), TCon ("F32x4", [])))));
    ("simd_f32x4_fma", Mono (TArrow (TCon ("F32x4", []), TArrow (TCon ("F32x4", []), TArrow (TCon ("F32x4", []), TCon ("F32x4", []))))));
    ("simd_f32x4_sqrt", Mono (TArrow (TCon ("F32x4", []), TCon ("F32x4", []))));
    ("simd_f32x4_sum", Mono (TArrow (TCon ("F32x4", []), t_float)));
    ("simd_f32x4_hmin", Mono (TArrow (TCon ("F32x4", []), t_float)));
    ("simd_f32x4_hmax", Mono (TArrow (TCon ("F32x4", []), t_float)));
    (* f64x2 *)
    ("simd_f64x2_splat", Mono (TArrow (t_float, TCon ("F64x2", []))));
    ("simd_f64x2_make", Mono (TArrow (t_float, TArrow (t_float, TCon ("F64x2", [])))));
    ("simd_f64x2_extract", Mono (TArrow (TCon ("F64x2", []), TArrow (t_int, t_float))));
    ("simd_f64x2_replace", Mono (TArrow (TCon ("F64x2", []), TArrow (t_int, TArrow (t_float, TCon ("F64x2", []))))));
    ("simd_f64x2_load", Mono (TArrow (TCon ("NativeFloatArr", []), TArrow (t_int, TCon ("F64x2", [])))));
    ("simd_f64x2_store", Mono (TArrow (TCon ("NativeFloatArr", []), TArrow (t_int, TArrow (TCon ("F64x2", []), TCon ("NativeFloatArr", []))))));
    ("simd_f64x2_eq", Mono (TArrow (TCon ("F64x2", []), TArrow (TCon ("F64x2", []), TCon ("F64x2", [])))));
    ("simd_f64x2_lt", Mono (TArrow (TCon ("F64x2", []), TArrow (TCon ("F64x2", []), TCon ("F64x2", [])))));
    ("simd_f64x2_gt", Mono (TArrow (TCon ("F64x2", []), TArrow (TCon ("F64x2", []), TCon ("F64x2", [])))));
    ("simd_f64x2_and", Mono (TArrow (TCon ("F64x2", []), TArrow (TCon ("F64x2", []), TCon ("F64x2", [])))));
    ("simd_f64x2_or", Mono (TArrow (TCon ("F64x2", []), TArrow (TCon ("F64x2", []), TCon ("F64x2", [])))));
    ("simd_f64x2_xor", Mono (TArrow (TCon ("F64x2", []), TArrow (TCon ("F64x2", []), TCon ("F64x2", [])))));
    ("simd_f64x2_not", Mono (TArrow (TCon ("F64x2", []), TCon ("F64x2", []))));
    ("simd_f64x2_select", Mono (TArrow (TCon ("F64x2", []), TArrow (TCon ("F64x2", []), TArrow (TCon ("F64x2", []), TCon ("F64x2", []))))));
    ("simd_f64x2_any", Mono (TArrow (TCon ("F64x2", []), t_bool)));
    ("simd_f64x2_all", Mono (TArrow (TCon ("F64x2", []), t_bool)));
    ("simd_f64x2_first_set", Mono (TArrow (TCon ("F64x2", []), t_int)));
    ("simd_f64x2_add", Mono (TArrow (TCon ("F64x2", []), TArrow (TCon ("F64x2", []), TCon ("F64x2", [])))));
    ("simd_f64x2_sub", Mono (TArrow (TCon ("F64x2", []), TArrow (TCon ("F64x2", []), TCon ("F64x2", [])))));
    ("simd_f64x2_mul", Mono (TArrow (TCon ("F64x2", []), TArrow (TCon ("F64x2", []), TCon ("F64x2", [])))));
    ("simd_f64x2_div", Mono (TArrow (TCon ("F64x2", []), TArrow (TCon ("F64x2", []), TCon ("F64x2", [])))));
    ("simd_f64x2_min", Mono (TArrow (TCon ("F64x2", []), TArrow (TCon ("F64x2", []), TCon ("F64x2", [])))));
    ("simd_f64x2_max", Mono (TArrow (TCon ("F64x2", []), TArrow (TCon ("F64x2", []), TCon ("F64x2", [])))));
    ("simd_f64x2_fma", Mono (TArrow (TCon ("F64x2", []), TArrow (TCon ("F64x2", []), TArrow (TCon ("F64x2", []), TCon ("F64x2", []))))));
    ("simd_f64x2_sqrt", Mono (TArrow (TCon ("F64x2", []), TCon ("F64x2", []))));
    ("simd_f64x2_sum", Mono (TArrow (TCon ("F64x2", []), t_float)));
    ("simd_f64x2_hmin", Mono (TArrow (TCon ("F64x2", []), t_float)));
    ("simd_f64x2_hmax", Mono (TArrow (TCon ("F64x2", []), t_float)));
    (* i32x4 *)
    ("simd_i32x4_splat", Mono (TArrow (t_int, TCon ("I32x4", []))));
    ("simd_i32x4_make", Mono (TArrow (t_int, TArrow (t_int, TArrow (t_int, TArrow (t_int, TCon ("I32x4", [])))))));
    ("simd_i32x4_extract", Mono (TArrow (TCon ("I32x4", []), TArrow (t_int, t_int))));
    ("simd_i32x4_replace", Mono (TArrow (TCon ("I32x4", []), TArrow (t_int, TArrow (t_int, TCon ("I32x4", []))))));
    ("simd_i32x4_load", Mono (TArrow (TCon ("NativeI32Arr", []), TArrow (t_int, TCon ("I32x4", [])))));
    ("simd_i32x4_store", Mono (TArrow (TCon ("NativeI32Arr", []), TArrow (t_int, TArrow (TCon ("I32x4", []), TCon ("NativeI32Arr", []))))));
    ("simd_i32x4_eq", Mono (TArrow (TCon ("I32x4", []), TArrow (TCon ("I32x4", []), TCon ("I32x4", [])))));
    ("simd_i32x4_lt", Mono (TArrow (TCon ("I32x4", []), TArrow (TCon ("I32x4", []), TCon ("I32x4", [])))));
    ("simd_i32x4_gt", Mono (TArrow (TCon ("I32x4", []), TArrow (TCon ("I32x4", []), TCon ("I32x4", [])))));
    ("simd_i32x4_and", Mono (TArrow (TCon ("I32x4", []), TArrow (TCon ("I32x4", []), TCon ("I32x4", [])))));
    ("simd_i32x4_or", Mono (TArrow (TCon ("I32x4", []), TArrow (TCon ("I32x4", []), TCon ("I32x4", [])))));
    ("simd_i32x4_xor", Mono (TArrow (TCon ("I32x4", []), TArrow (TCon ("I32x4", []), TCon ("I32x4", [])))));
    ("simd_i32x4_not", Mono (TArrow (TCon ("I32x4", []), TCon ("I32x4", []))));
    ("simd_i32x4_select", Mono (TArrow (TCon ("I32x4", []), TArrow (TCon ("I32x4", []), TArrow (TCon ("I32x4", []), TCon ("I32x4", []))))));
    ("simd_i32x4_any", Mono (TArrow (TCon ("I32x4", []), t_bool)));
    ("simd_i32x4_all", Mono (TArrow (TCon ("I32x4", []), t_bool)));
    ("simd_i32x4_first_set", Mono (TArrow (TCon ("I32x4", []), t_int)));
    ("simd_i32x4_add", Mono (TArrow (TCon ("I32x4", []), TArrow (TCon ("I32x4", []), TCon ("I32x4", [])))));
    ("simd_i32x4_sub", Mono (TArrow (TCon ("I32x4", []), TArrow (TCon ("I32x4", []), TCon ("I32x4", [])))));
    ("simd_i32x4_mul", Mono (TArrow (TCon ("I32x4", []), TArrow (TCon ("I32x4", []), TCon ("I32x4", [])))));
    ("simd_i32x4_min", Mono (TArrow (TCon ("I32x4", []), TArrow (TCon ("I32x4", []), TCon ("I32x4", [])))));
    ("simd_i32x4_max", Mono (TArrow (TCon ("I32x4", []), TArrow (TCon ("I32x4", []), TCon ("I32x4", [])))));
    ("simd_i32x4_shl", Mono (TArrow (TCon ("I32x4", []), TArrow (t_int, TCon ("I32x4", [])))));
    ("simd_i32x4_shr", Mono (TArrow (TCon ("I32x4", []), TArrow (t_int, TCon ("I32x4", [])))));
    ("simd_i32x4_sum", Mono (TArrow (TCon ("I32x4", []), t_int)));
    ("simd_i32x4_hmin", Mono (TArrow (TCon ("I32x4", []), t_int)));
    ("simd_i32x4_hmax", Mono (TArrow (TCon ("I32x4", []), t_int)));
    (* i64x2 *)
    ("simd_i64x2_splat", Mono (TArrow (t_int, TCon ("I64x2", []))));
    ("simd_i64x2_make", Mono (TArrow (t_int, TArrow (t_int, TCon ("I64x2", [])))));
    ("simd_i64x2_extract", Mono (TArrow (TCon ("I64x2", []), TArrow (t_int, t_int))));
    ("simd_i64x2_replace", Mono (TArrow (TCon ("I64x2", []), TArrow (t_int, TArrow (t_int, TCon ("I64x2", []))))));
    ("simd_i64x2_load", Mono (TArrow (TCon ("NativeIntArr", []), TArrow (t_int, TCon ("I64x2", [])))));
    ("simd_i64x2_store", Mono (TArrow (TCon ("NativeIntArr", []), TArrow (t_int, TArrow (TCon ("I64x2", []), TCon ("NativeIntArr", []))))));
    ("simd_i64x2_eq", Mono (TArrow (TCon ("I64x2", []), TArrow (TCon ("I64x2", []), TCon ("I64x2", [])))));
    ("simd_i64x2_lt", Mono (TArrow (TCon ("I64x2", []), TArrow (TCon ("I64x2", []), TCon ("I64x2", [])))));
    ("simd_i64x2_gt", Mono (TArrow (TCon ("I64x2", []), TArrow (TCon ("I64x2", []), TCon ("I64x2", [])))));
    ("simd_i64x2_and", Mono (TArrow (TCon ("I64x2", []), TArrow (TCon ("I64x2", []), TCon ("I64x2", [])))));
    ("simd_i64x2_or", Mono (TArrow (TCon ("I64x2", []), TArrow (TCon ("I64x2", []), TCon ("I64x2", [])))));
    ("simd_i64x2_xor", Mono (TArrow (TCon ("I64x2", []), TArrow (TCon ("I64x2", []), TCon ("I64x2", [])))));
    ("simd_i64x2_not", Mono (TArrow (TCon ("I64x2", []), TCon ("I64x2", []))));
    ("simd_i64x2_select", Mono (TArrow (TCon ("I64x2", []), TArrow (TCon ("I64x2", []), TArrow (TCon ("I64x2", []), TCon ("I64x2", []))))));
    ("simd_i64x2_any", Mono (TArrow (TCon ("I64x2", []), t_bool)));
    ("simd_i64x2_all", Mono (TArrow (TCon ("I64x2", []), t_bool)));
    ("simd_i64x2_first_set", Mono (TArrow (TCon ("I64x2", []), t_int)));
    ("simd_i64x2_add", Mono (TArrow (TCon ("I64x2", []), TArrow (TCon ("I64x2", []), TCon ("I64x2", [])))));
    ("simd_i64x2_sub", Mono (TArrow (TCon ("I64x2", []), TArrow (TCon ("I64x2", []), TCon ("I64x2", [])))));
    ("simd_i64x2_mul", Mono (TArrow (TCon ("I64x2", []), TArrow (TCon ("I64x2", []), TCon ("I64x2", [])))));
    ("simd_i64x2_min", Mono (TArrow (TCon ("I64x2", []), TArrow (TCon ("I64x2", []), TCon ("I64x2", [])))));
    ("simd_i64x2_max", Mono (TArrow (TCon ("I64x2", []), TArrow (TCon ("I64x2", []), TCon ("I64x2", [])))));
    ("simd_i64x2_shl", Mono (TArrow (TCon ("I64x2", []), TArrow (t_int, TCon ("I64x2", [])))));
    ("simd_i64x2_shr", Mono (TArrow (TCon ("I64x2", []), TArrow (t_int, TCon ("I64x2", [])))));
    ("simd_i64x2_sum", Mono (TArrow (TCon ("I64x2", []), t_int)));
    ("simd_i64x2_hmin", Mono (TArrow (TCon ("I64x2", []), t_int)));
    ("simd_i64x2_hmax", Mono (TArrow (TCon ("I64x2", []), t_int)));
    (* u8x16 *)
    ("simd_u8x16_splat", Mono (TArrow (t_int, TCon ("U8x16", []))));
    ("simd_u8x16_make", Mono (TArrow (t_int, TArrow (t_int, TArrow (t_int, TArrow (t_int, TArrow (t_int, TArrow (t_int, TArrow (t_int, TArrow (t_int, TArrow (t_int, TArrow (t_int, TArrow (t_int, TArrow (t_int, TArrow (t_int, TArrow (t_int, TArrow (t_int, TArrow (t_int, TCon ("U8x16", [])))))))))))))))))));
    ("simd_u8x16_extract", Mono (TArrow (TCon ("U8x16", []), TArrow (t_int, t_int))));
    ("simd_u8x16_replace", Mono (TArrow (TCon ("U8x16", []), TArrow (t_int, TArrow (t_int, TCon ("U8x16", []))))));
    ("simd_u8x16_load", Mono (TArrow (TCon ("NativeU8Arr", []), TArrow (t_int, TCon ("U8x16", [])))));
    ("simd_u8x16_store", Mono (TArrow (TCon ("NativeU8Arr", []), TArrow (t_int, TArrow (TCon ("U8x16", []), TCon ("NativeU8Arr", []))))));
    ("simd_u8x16_eq", Mono (TArrow (TCon ("U8x16", []), TArrow (TCon ("U8x16", []), TCon ("U8x16", [])))));
    ("simd_u8x16_lt", Mono (TArrow (TCon ("U8x16", []), TArrow (TCon ("U8x16", []), TCon ("U8x16", [])))));
    ("simd_u8x16_gt", Mono (TArrow (TCon ("U8x16", []), TArrow (TCon ("U8x16", []), TCon ("U8x16", [])))));
    ("simd_u8x16_and", Mono (TArrow (TCon ("U8x16", []), TArrow (TCon ("U8x16", []), TCon ("U8x16", [])))));
    ("simd_u8x16_or", Mono (TArrow (TCon ("U8x16", []), TArrow (TCon ("U8x16", []), TCon ("U8x16", [])))));
    ("simd_u8x16_xor", Mono (TArrow (TCon ("U8x16", []), TArrow (TCon ("U8x16", []), TCon ("U8x16", [])))));
    ("simd_u8x16_not", Mono (TArrow (TCon ("U8x16", []), TCon ("U8x16", []))));
    ("simd_u8x16_select", Mono (TArrow (TCon ("U8x16", []), TArrow (TCon ("U8x16", []), TArrow (TCon ("U8x16", []), TCon ("U8x16", []))))));
    ("simd_u8x16_any", Mono (TArrow (TCon ("U8x16", []), t_bool)));
    ("simd_u8x16_all", Mono (TArrow (TCon ("U8x16", []), t_bool)));
    ("simd_u8x16_first_set", Mono (TArrow (TCon ("U8x16", []), t_int)));
  ]

(** Builtins declared with a bare (non-[TArrow]) scheme that must NOT be
    called with [()] — unlike [pmap_threshold], [get_work_pool],
    [task_cancel_token_new], the [logger_*]/[process_*] readers, [self], and
    [remote_count] (all genuinely invoked as [name()], exactly like a
    zero-param user [fn] — see the [pmap_threshold] comment above), [root_cap]
    is a plain ambient value: reference it bare ([let c = root_cap]).
    [infer_app]'s [| [], t -> t] base case cannot tell these apart from its
    types alone (both look like "call site with 0 args, callee type is
    non-arrow"), so [Ast.EApp]'s handler special-cases names in this set. *)
(* Shared source of truth for [Modules.Prelude_collision.check]'s two
   builtin-name inputs, used by every caller (bin/main.ml, the LSP's
   lsp/lib/analysis.ml) so they can never independently drift from what the
   typechecker itself treats as a builtin — see
   specs/plans/2026-08-13-prelude-entry-fn-name-collision.md §4.1/§4.2.
   [prelude_collision_builtin_names] excludes qualified forms (containing
   '.'): a user's bare top-level [fn] can never be named with a dot, so they
   could never collide with one anyway. *)
let prelude_collision_builtin_names : string list =
  List.filter_map (fun (name, _) -> if String.contains name '.' then None else Some name)
    builtin_bindings

(* [show]/[eq]/[compare]/[hash] are NOT in the list above — they are
   structural interface methods with their OWN type-directed dispatch
   ([builtin_interface_bindings]), and a bare top-level [fn] of the right
   ARITY legitimately participates in it (regression-tested by
   test/native/iface_method_collision.march). Only a WRONG-arity same-name
   function is a genuine collision — see Prelude_collision's doc comment. *)
let prelude_collision_iface_arities : (string * int) list =
  [ ("eq", 2); ("compare", 2); ("show", 1); ("hash", 1) ]

let noncallable_builtin_values = StringSet.of_list [ "root_cap" ]

let builtin_types : (string * int) list =
  [ ("Int",    0); ("Float",  0); ("Bool",  0); ("String", 0);
    ("Char",   0); ("Byte",   0); ("Atom",  0); ("Unit",   0);
    ("List",   1); ("Option", 1); ("Array", 1); ("Set",    1); ("Seq",    1);
    ("TypedArray", 1);
    ("Result", 2); ("Map",    2);
    ("Pid",    1); ("Cap",    1); ("Future",1); ("Stream", 1);
    ("ActorCap", 1);
    ("Task",   1); ("WorkPool", 0); ("Node",   0);
    (* Vault(v) — ETS-like table handle, phantom in its ELEMENT type.
       ONE parameter, not the Vault(k, v) the design note sketched: keys are
       stringified by [vault_key_cstr] before they ever reach the table, so a
       key-type parameter buys no memory safety (a wrong-typed key is a silent
       MISS, never a value read at the wrong type) and costs real
       expressiveness — stdlib/config.march deliberately keys ONE table with
       both 2-tuples and 3-tuples, which no single [k] can describe. The value
       parameter is the one that closes the read-it-back-as-a-Pid hole. *)
    ("Vault",  1);
    ("ChildSpec", 0); ("SupervisorSpec", 0);
    ("Vector", 2); ("Matrix", 3); ("NDArray", 2);
    (* Tagged(X, T) — specialization tag constructor: phantom policy/width tags *)
    ("Tagged", 2);
    (* Alloc and Panic — future capability roots excluded from realtime contexts *)
    ("Alloc", 0); ("Panic", 0);
    (* Capability token types — used as arguments to Cap(X).
       Mirrors the full 18-entry hierarchy in lib/caps/cap_lattice.ml. *)
    ("IO",            0); ("IO.Console",    0); ("IO.FileSystem", 0);
    ("IO.FileRead",   0); ("IO.FileWrite",  0); ("IO.Network",    0);
    ("IO.NetConnect", 0); ("IO.NetListen",  0); ("IO.Process",    0);
    ("IO.Clock",      0); ("IO.Random",     0); ("IO.Database",   0);
    ("IO.Signal",     0);
    ("IO.Spawn",      0); ("IO.Mut",        0); ("IO.Telemetry",  0);
    ("IO.Foreign",    0); ("IO.Foreign.Blocking", 0); ("IO.NetConnect.TLS", 0);
    ("IO.WebSocket",  0);
    (* RingBuf — mutable fixed-capacity circular buffer (non-sendable) *)
    ("RingBuf",       1);
    (* NativeArray opaque types — flat numeric arrays (P10) *)
    ("NativeIntArr",   0); ("NativeFloatArr", 0);
    ("NativeF32Arr",   0); ("NativeI32Arr",   0); ("NativeU8Arr", 0);
    (* Simd — explicit 128-bit SIMD vector types (F32x4/F64x2/I32x4/I64x2/U8x16).
       All arity 0, sendable (NOT added to non_sendable_types below). *)
    ("F32x4", 0); ("F64x2", 0); ("I32x4", 0); ("I64x2", 0); ("U8x16", 0);
    (* Runtime-originated local-monitor signal. These names are reserved by
       the compiled ABI; source declarations with the same exact shape (the
       native conformance fixture and, later, the actor stdlib surface) refine
       the same nominal entries rather than inventing per-module wire tags. *)
    ("DownReason", 0); ("Down", 1); ]

(** Built-in constructor table for Option, Result, and List, which are
    pre-registered types.  User-declared types are added via [DType].
    Each constructor is registered under both its bare name ("Some") and its
    type-qualified name ("Option.Some") so that users can write either form. *)
let builtin_ctors : (string * ctor_info) list =
  let mk_var s = Ast.TyVar { txt = s; span = Ast.dummy_span } in
  let mk_ty name args = Ast.TyCon ({ txt = name; span = Ast.dummy_span }, args) in
  let mk_list_ty s = Ast.TyCon ({ txt = "List"; span = Ast.dummy_span }, [mk_var s]) in
  let some_ci  = { ci_type = "Option"; ci_params = ["a"];      ci_arg_tys = [mk_var "a"]; ci_module = ""; ci_vis = Ast.Public; ci_is_actor_msg = false } in
  let none_ci  = { ci_type = "Option"; ci_params = ["a"];      ci_arg_tys = []; ci_module = ""; ci_vis = Ast.Public; ci_is_actor_msg = false } in
  let ok_ci    = { ci_type = "Result"; ci_params = ["a"; "e"]; ci_arg_tys = [mk_var "a"]; ci_module = ""; ci_vis = Ast.Public; ci_is_actor_msg = false } in
  let err_ci   = { ci_type = "Result"; ci_params = ["a"; "e"]; ci_arg_tys = [mk_var "e"]; ci_module = ""; ci_vis = Ast.Public; ci_is_actor_msg = false } in
  let nil_ci   = { ci_type = "List";   ci_params = ["a"];      ci_arg_tys = []; ci_module = ""; ci_vis = Ast.Public; ci_is_actor_msg = false } in
  let cons_ci  = { ci_type = "List";   ci_params = ["a"];
                   ci_arg_tys = [mk_var "a"; mk_list_ty "a"]; ci_module = ""; ci_vis = Ast.Public; ci_is_actor_msg = false } in
  let normal_ci = { ci_type = "DownReason"; ci_params = []; ci_arg_tys = [];
                    ci_module = ""; ci_vis = Ast.Public; ci_is_actor_msg = false } in
  let killed_ci = { normal_ci with ci_type = "DownReason" } in
  let crash_ci = { normal_ci with ci_arg_tys = [mk_ty "String" []] } in
  let down_ci = { ci_type = "Down"; ci_params = ["a"];
                  ci_arg_tys = [mk_ty "Int" [];
                                mk_ty "Pid" [mk_var "a"];
                                mk_ty "DownReason" []];
                  ci_module = ""; ci_vis = Ast.Public; ci_is_actor_msg = false } in
  [ ("Some",        some_ci);  ("Option.Some", some_ci);
    ("None",        none_ci);  ("Option.None", none_ci);
    ("Ok",          ok_ci);    ("Result.Ok",   ok_ci);
    ("Err",         err_ci);   ("Result.Err",  err_ci);
    ("Nil",         nil_ci);   ("List.Nil",    nil_ci);
    ("Cons",        cons_ci);  ("List.Cons",   cons_ci);
    ("Normal",      normal_ci); ("DownReason.Normal", normal_ci);
    ("Killed",      killed_ci); ("DownReason.Killed", killed_ci);
    ("Crash",       crash_ci);  ("DownReason.Crash",  crash_ci);
    ("Down",        down_ci);   ("Down.Down",         down_ci);
  ]

let base_env errors type_map =
  let env = make_env errors type_map in
  let env = bind_vars builtin_bindings env in
  let env = bind_vars builtin_interface_bindings env in
  { env with
    types      = List.fold_left (fun m (k, v) -> StrMap.add k v m) StrMap.empty builtin_types;
    ctors      = List.fold_left (fun m (k, v) -> add_ctor k v m) StrMap.empty builtin_ctors;
    interfaces = List.fold_left (fun m (k, v) -> StrMap.add k v m) StrMap.empty builtin_interfaces;
    impls      = List.fold_left (fun m (k, v) ->
                   let lst = Option.value ~default:[] (StrMap.find_opt k m) in
                   (* Built-ins carry [dummy_span]; the coherence check reads it
                      to phrase a user-impl-over-builtin conflict specially. *)
                   StrMap.add k ((v, Ast.dummy_span, None) :: lst) m) StrMap.empty builtin_impls;
  }

