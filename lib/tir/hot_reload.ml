(** Hot Code Reload — boundary classification.

    Decides which modules sit on the reloadable boundary. Per
    [specs/hot-code-reload.md] Part 2: app modules under the package's source
    tree are reloadable by default; stdlib, dependencies, and the runtime never
    are; an optional `[hot-reload]` include/exclude list overrides. *)

type config = {
  app_prefix : string;        (** module prefix of the app's own code, e.g. "MyApp" *)
  includes   : string list;   (** extra module prefixes to force-include *)
  excludes   : string list;   (** module prefixes to force-exclude (win over includes) *)
}

(** The owning module of a (possibly qualified) top-level name: everything
    before the last dot, or "" for a bare name like "main". *)
let module_of_name (n : string) : string =
  match String.rindex_opt n '.' with
  | Some i -> String.sub n 0 i
  | None   -> ""

(** A config with no overrides for the given app prefix.
    [app_prefix] is expected to be a non-empty module name (March module names
    start with an uppercase letter); an empty prefix means "no app code is
    reloadable", which is internally consistent but rarely intended. *)
let default_config (app_prefix : string) : config =
  { app_prefix; includes = []; excludes = [] }

(** Is [m] equal to, or a descendant module of, prefix [p]?
    "MyApp" is under "MyApp"; "MyApp.Router" is under "MyApp";
    "MyApplication" is NOT under "MyApp" (a shared string prefix is not a
    module-path prefix — the boundary is "." or end-of-string). *)
let under (p : string) (m : string) : bool =
  String.equal m p
  || (String.length m > String.length p
      && String.equal (String.sub m 0 (String.length p)) p
      && m.[String.length p] = '.')

let under_any (ps : string list) (m : string) : bool =
  List.exists (fun p -> under p m) ps

(** Does the boundary include module [m]?
    Reloadable when it is app code (under [app_prefix]) or force-included,
    AND not force-excluded. Excludes win over includes. *)
let is_reloadable (cfg : config) (m : string) : bool =
  (under cfg.app_prefix m || under_any cfg.includes m)
  && not (under_any cfg.excludes m)

(** Must a direct call from [caller_module] to [callee_module] route through
    the versioned dispatch table (vs. a plain, inlinable direct call)?

    A call dispatches whenever the CALLEE is reloadable, whoever the caller
    is.  Until 2026-09-25 the caller had to be reloadable too (only
    boundary→boundary edges crossed the table, per the first reading of
    specs/hot-code-reload.md Part 2), which pinned every call from
    non-reloadable code into the boundary to the baseline for ever: the
    generated topology `main` and the entry module (never reloadable, see
    [is_entry_fn] in llvm_toplevel.ml), the closures they build, and any
    stdlib code that calls back into the app (Topology.reoffer reopening a
    role with its OLD body after a deploy) all direct-called old code and
    never saw a patch.  Nothing stops a non-reloadable caller from
    dispatching: the table is process-global and a boundary call resolves
    against the running proc's code epoch (march_dispatch_enter_unit), so the
    call gets the code its task was spawned under.  Calls to stdlib/excluded
    modules, and into the runtime, stay direct.  (Intra-SCC calls also stay
    direct; that is an SCC-level decision made by the caller of this
    predicate, not a module-level one.)  [caller_module] is kept in the
    signature so a call site still names both ends of the edge. *)
let needs_dispatch (cfg : config) ~(caller_module : string)
    ~(callee_module : string) : bool =
  ignore caller_module;
  is_reloadable cfg callee_module

(* ── Stdlib actors are not slots (owner decision, 2026-09-30) ──────────────

   An actor's glue functions (`<Actor>_dispatch`, its handlers, spawn,
   on_stop) are BARE-named whatever module declares them, so [is_reloadable]
   cannot see who owns them, and until 2026-09-30 every `*_dispatch` was put
   on the boundary unconditionally: the stdlib's own actors
   (`ClusterNodeActor_dispatch`, which answers SWIM pings, `Endpoint_dispatch`,
   `Writer_dispatch`, `CtlWriter_dispatch`, ...) got dispatch slots, so a
   deploy could activate, pause or migrate them.  They must not: a stdlib
   change comes with a toolchain or language change, which is a restart
   deploy, never a hot patch
   (specs/todos/2026-09-25-hot-deploy-stalls-node-past-swim-timeout.md,
   point 3).

   Whether an actor is the stdlib's is decided by LOADER PROVENANCE, never by
   its name or its file's basename: lowering records every actor fn it
   synthesizes here, keyed by fn name, with whether the declaring [DActor]'s
   span is the stdlib's ([Typecheck_builtins.span_is_stdlib], the one
   predicate the stdlib-only builtin gate and the driver's diagnostic filter
   also use: the file came from the stdlib loader, or lies under the root it
   loaded from).  A user file named `node_queue.march`, or a user actor named
   `Writer`, is the user's, and stays a slot.  If the same bare name is ever
   recorded from both sides, the user's claim wins: a slot too many is
   visible (the deploy can activate it), a slot too few silently pins the
   user's code to the baseline.

   Process-global, reset at the top of [Lower.lower_module] like
   [Handler_owner]; actor glue is monomorphic, so the names survive
   mono/defun unchanged. *)
let stdlib_actor_fns : (string, unit) Hashtbl.t = Hashtbl.create 64
let user_actor_fns : (string, unit) Hashtbl.t = Hashtbl.create 16

let reset_actor_provenance () =
  Hashtbl.reset stdlib_actor_fns;
  Hashtbl.reset user_actor_fns

(** Record the fns lowering synthesized for one [DActor]; [~stdlib] is that
    declaration's provenance. *)
let note_actor_fns ~(stdlib : bool) (fn_names : string list) : unit =
  let tbl = if stdlib then stdlib_actor_fns else user_actor_fns in
  List.iter (fun n -> Hashtbl.replace tbl n ()) fn_names

(** Was [n] synthesized for an actor the standard library declares (and for
    no user actor)? *)
let is_stdlib_actor_fn (n : string) : bool =
  Hashtbl.mem stdlib_actor_fns n && not (Hashtbl.mem user_actor_fns n)

(** Is [n] an actor dispatch fn that gets a hot-reload slot: every
    `*_dispatch` except the stdlib's.  The ONE predicate for "this actor is
    on the boundary": the reload name table ([Llvm_toplevel.emit_module]'s
    [hr_names]), the patch `.so`'s default-visibility exemptions
    ([Llvm_toplevel]'s [vis_prefix], [Llvm_tco]'s [wrap_vis]) and the slot
    hash fold in bin/main.ml all go through it, so they cannot disagree. *)
let is_slot_actor_dispatch (n : string) : bool =
  Tir_names.is_actor_dispatch_fn n && not (is_stdlib_actor_fn n)

(* ── NAME_ID interning ─────────────────────────────────────────────────────

   The versioned dispatch table is a dense array indexed by NAME_ID. The
   compiler emits `march_dispatch_enter(NAME_ID)` at a boundary→boundary call
   and the runtime populates slot[NAME_ID] with the callee's initial version,
   so the two must agree on the mapping within a build. IDs are assigned in
   sorted-name order so the mapping is a deterministic function of the name set
   (independent of source/iteration order) — NOT a source-order integer that
   shifts when unrelated code is edited. Cross-build reload activation is keyed
   by NAME (string), so dense per-build ids are sufficient. *)
module Name_table : sig
  type t
  val build   : string list -> t
  val id_of   : t -> string -> int option
  val name_of : t -> int -> string option
  val count   : t -> int
  val names   : t -> string list
end = struct
  type t = {
    by_id   : string array;            (* id → name, sorted *)
    by_name : (string, int) Hashtbl.t; (* name → id *)
  }

  let build (names : string list) : t =
    let sorted = List.sort_uniq String.compare names in
    let by_id = Array.of_list sorted in
    let by_name = Hashtbl.create (Array.length by_id) in
    Array.iteri (fun id name -> Hashtbl.replace by_name name id) by_id;
    { by_id; by_name }

  let id_of (t : t) (name : string) : int option = Hashtbl.find_opt t.by_name name

  let name_of (t : t) (id : int) : string option =
    if id >= 0 && id < Array.length t.by_id then Some t.by_id.(id) else None

  let count (t : t) : int = Array.length t.by_id
  let names (t : t) : string list = Array.to_list t.by_id
end
