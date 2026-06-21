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

(** A config with no overrides for the given app prefix. *)
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

(* ── NAME_ID interning ─────────────────────────────────────────────────────

   The versioned dispatch table is a dense array indexed by NAME_ID. The
   compiler emits `march_dispatch_enter(NAME_ID)` at a boundary→boundary call
   and the runtime populates slot[NAME_ID] with the callee's initial version,
   so the two must agree on the mapping within a build. IDs are assigned in
   sorted-name order so the mapping is a deterministic function of the name set
   (independent of source/iteration order) — NOT a source-order integer that
   shifts when unrelated code is edited. Cross-build reload activation is keyed
   by NAME (string), so dense per-build ids are sufficient. *)
module Name_table = struct
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
