(** Process-lifetime memo of the typed stdlib (and stdlib+deps) environment.

    Phase 1 memoized the *parse/desugar* of stdlib; this memoizes its
    *typecheck* — the dominant per-keystroke LSP cost. Previously [analyse]
    re-ran the whole-module typechecker over [stdlib @ deps @ user] on every
    edit. Here the invariant prefix is checked once into a base [env], and
    only the user file's decls are layered on top per edit (via
    [Tc.check_module_with_env_full], the same incremental path the REPL JIT
    uses). Keyed by the CAS compiler-identity discipline so a rebuilt compiler
    busts the cache. *)

module Tc = March_typecheck.Typecheck
module Err = March_errors.Errors
module Ast = March_ast.Ast

let dummy_name : Ast.name = { Ast.txt = ""; span = Ast.dummy_span }

let wrap_module (decls : Ast.decl list) : Ast.module_ =
  { Ast.mod_name = dummy_name; mod_decls = decls }

(* Compiler identity also covers stdlib content via Stdlib_cache's own key;
   stdlib decls are physically stable per process, so a single key suffices. *)
let key () = Lazy.force March_cas.Cas.compiler_identity

(* ── stdlib base env ─────────────────────────────────────────────────────── *)

let cache : (string, Tc.env) Hashtbl.t = Hashtbl.create 1

let base_env () : Tc.env =
  let k = key () in
  match Hashtbl.find_opt cache k with
  | Some env -> env
  | None ->
    let stdlib_decls = Stdlib_cache.load () in
    let (_errs, _tm, env) = Tc.check_module_full (wrap_module stdlib_decls) in
    Hashtbl.replace cache k env;
    env

(* Derive a per-analysis env: reuse the (immutable StrMap) stdlib bindings but
   give fresh mutable state so layering user decls cannot mutate the shared
   base. [type_map] is COPIED so stdlib span->type entries survive for
   cross-stdlib hover. Mutable fields per typecheck.ml:359-391:
   errors, type_map, pending_constraints, import_tracker. *)
let derive (base : Tc.env) : Tc.env =
  { base with
    Tc.errors           = Err.create ();
    type_map            = Hashtbl.copy base.Tc.type_map;
    pending_constraints = ref [];
    import_tracker      = ref [] }

(* ── stdlib + deps env ───────────────────────────────────────────────────── *)

let deps_cache : (string, Tc.env) Hashtbl.t = Hashtbl.create 8

(* Content key for a set of resolved dependency decls. Decls contain no
   closures, so structural marshalling is a sound content fingerprint. *)
let deps_key (deps : Ast.decl list) : string =
  let payload = try Marshal.to_string deps [Marshal.No_sharing] with _ -> "" in
  March_cas.Blake3.hash_string (key () ^ "\x00" ^ payload)

(* stdlib + deps env, memoized by dep content. Returns [base] unchanged when
   there are no deps. The cached env still has shared mutable state — callers
   must [derive] it before layering the user file. *)
let deps_env (base : Tc.env) ~(deps : Ast.decl list) : Tc.env =
  if deps = [] then base
  else
    let k = deps_key deps in
    match Hashtbl.find_opt deps_cache k with
    | Some env -> env
    | None ->
      let scratch = derive base in
      let (_e, _tm, env) = Tc.check_module_with_env_full scratch (wrap_module deps) in
      Hashtbl.replace deps_cache k env;
      env

(* Drop the deps layer (e.g. a dependency changed on disk). The stdlib base
   env is unaffected. *)
let clear_deps () = Hashtbl.clear deps_cache
