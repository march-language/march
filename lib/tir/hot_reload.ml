(** Hot Code Reload — boundary classification.

    Decides which modules sit on the reloadable boundary. Per
    [specs/hot-code-reload.md] Part 2: app modules under the package's source
    tree are reloadable by default; stdlib, dependencies, and the runtime never
    are; an optional `[hot-reload]` include/exclude list overrides. *)

type config = {
  app_prefix : string;        (** module prefix of the app's own code, e.g. "MyApp" *)
  includes   : string list;   (** extra module prefixes to force-include *)
  excludes   : string list;   (** module prefixes to force-exclude (win over includes) *)
  entry_top_level : bool;
  (** The entry file's own top-level functions are on the boundary: the
      prefix names the entry module, whose name lowering strips (see
      [is_entry_file_slot]).  Set by the driver, like [includes]. *)
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
  { app_prefix; includes = []; excludes = []; entry_top_level = false }

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
    generated topology `main` (never reloadable, see [is_program_entry]
    below), the closures it builds, and any
    stdlib code that calls back into the app (Topology.reoffer reopening a
    role with its OLD body after a deploy) all direct-called old code and
    never saw a patch.  Nothing stops a non-reloadable caller from
    dispatching: the table is process-global and a boundary call resolves
    against the running proc's code epoch (march_dispatch_enter_unit), so the
    call gets the code its task was spawned under.  Calls to stdlib/excluded
    modules, and into the runtime, stay direct.  (A self-call stays direct
    too, decided by the call site in llvm_emit_call.ml, not here: until
    2026-10-01 this comment said intra-SCC calls did, but nothing
    implemented it; mutual recursion between two slots dispatches.)
    [caller_module] is kept in the signature so a call site still names both
    ends of the edge. *)
let needs_dispatch (cfg : config) ~(caller_module : string)
    ~(callee_module : string) : bool =
  ignore caller_module;
  is_reloadable cfg callee_module

(** The file name the driver parses the control plane's wiring under
    (bin/topology_gen.ml): protocols, leader, Agent and control API spliced
    into a topology app's entry module when it has a [control] section.  Its
    actors (CtlRespawner) are infrastructure like the stdlib's: the control
    plane is what drives a deploy, and a deploy must not swap or migrate the
    thing doing the deploy; a change to it ships with the toolchain, which
    is a restart.  [Lower] records them with the stdlib's. *)
let control_wiring_file = "<control>"

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

(* ── The entry file's top-level functions (2026-10-01) ─────────────────────

   Lowering strips the entry module's name from every declaration of the
   entry file, so `fn serve_one` at the top of `mod UpgradeApp` is the TIR fn
   `serve_one`, module "", and [is_reloadable] never matches it: until
   2026-10-01 a role body, hook or helper written there could never be hot
   deployed, and `forge deploy hot` said "no changes" for it.  A bare name
   alone cannot say where a function came from (the prelude, lifted lambdas
   and join points, actor glue and the generated topology code are all bare
   too), so lowering records the entry file's own top-level fns here, by
   LOADER PROVENANCE like [note_actor_fns]: a [DFn] at the top of the module
   lowering was handed whose span lies in the entry file.  Excluded there:
   `main` (see [is_program_entry]) and the compiler's `__`-named fns.  Code
   spliced into the entry module by the driver (the generated topology
   `main`, the control plane's wiring) is parsed from `<topology>` and
   `<control>`, not the entry file, so it is never recorded: the control
   plane is the thing that runs a deploy, and a deploy must not swap it
   (the same reasoning that keeps stdlib actors off, above).

   A polymorphic entry fn's specializations (`foo$Int`) are not recorded:
   they are bare non-slots, folded into their slotted callers' hashes and
   delivered inside those callers' patches, like lifted lambdas.

   Process-global, reset at the top of [Lower.lower_module]. *)
let entry_file_fns : (string, unit) Hashtbl.t = Hashtbl.create 64

let reset_entry_file_fns () = Hashtbl.reset entry_file_fns

let note_entry_file_fn (n : string) : unit = Hashtbl.replace entry_file_fns n ()

(** A program entry point, never a slot: the running green thread's root
    frame is `main`/`<Mod>.main` (emitted as @march_main), and in the
    hot-reload layout the app's own `main` (HotEntry.main -> App.main) is
    permanently on the stack too; swapping either while live corrupts the
    allocator.  Every fn named `main`, bare or `.main`-suffixed. *)
let is_program_entry (n : string) : bool =
  String.equal n "main"
  || (String.length n > 5
      && String.equal (String.sub n (String.length n - 5) 5) ".main")

(** Is [n] one of the entry file's own top-level functions, on the boundary
    because [cfg]'s prefix names the entry module? *)
let is_entry_file_slot (cfg : config) (n : string) : bool =
  cfg.entry_top_level
  && Hashtbl.mem entry_file_fns n
  && not (under_any cfg.excludes cfg.app_prefix)

(** Does a call to the module function [n] route through the dispatch
    table?  [needs_dispatch] by its module, or one of the entry file's own
    top-level fns (bare-named, so its module says nothing). *)
let needs_dispatch_to (cfg : config) (n : string) : bool =
  is_reloadable cfg (module_of_name n) || is_entry_file_slot cfg n

(** THE slot predicate: does module function [n] get a hot-reload dispatch
    slot?  App code (under the prefix or an include), the entry file's own
    top-level fns, and every non-stdlib actor's `<Actor>_dispatch`; never a
    program entry.  The reload name table ([Llvm_toplevel.emit_module]'s
    [hr_names]) and the driver's slot-hash fold both go through it. *)
let is_slot_fn (cfg : config) (n : string) : bool =
  not (is_program_entry n)
  && (is_reloadable cfg (module_of_name n)
      || is_slot_actor_dispatch n
      || is_entry_file_slot cfg n)

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
