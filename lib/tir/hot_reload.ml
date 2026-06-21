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
