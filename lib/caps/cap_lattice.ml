(* =================================================================
   Capability hierarchy for needs / Cap checking.
   Each entry: (cap_path, parent_path option).
   Paths are dot-joined strings, e.g. "IO.FileRead".
   FFI caps like "LibC" are valid but not in this table — they are
   their own roots and have no subtyping relationship.

   Shared between March_typecheck.Typecheck (body-scan Phase 2) and
   March_refinecheck.Cap_infer (capability-inference hints) — both need
   the identical subsumption rule, so it lives here as a single source
   of truth (factored out in Phase5C-A.1; previously duplicated verbatim
   in both files).
   ================================================================= *)

let hierarchy : (string * string option) list = [
  ("IO",            None);
  ("IO.Console",    Some "IO");
  ("IO.FileSystem", Some "IO");
  ("IO.FileRead",   Some "IO.FileSystem");
  ("IO.FileWrite",  Some "IO.FileSystem");
  ("IO.Network",    Some "IO");
  ("IO.NetConnect", Some "IO.Network");
  ("IO.NetListen",  Some "IO.Network");
  ("IO.Process",    Some "IO");
  ("IO.Clock",      Some "IO");
  ("IO.Random",     Some "IO");
  ("IO.Signal",     Some "IO");
  ("IO.Database",   Some "IO.NetConnect");
  ("IO.Spawn",      Some "IO");
  ("IO.Mut",        Some "IO");
  ("IO.Telemetry",  Some "IO");
  ("IO.NetConnect.TLS", Some "IO.NetConnect");
  ("IO.WebSocket",       Some "IO.NetConnect");
  ("IO.Foreign",         Some "IO");
  ("IO.Foreign.Blocking", Some "IO.Foreign");
]

(** [cap_ancestors cap] returns [cap] and all its ancestors, most-specific first.
    E.g., "IO.FileRead" → ["IO.FileRead"; "IO.FileSystem"; "IO"].
    FFI caps not in the table return just themselves. *)
let cap_ancestors cap =
  let rec go c acc =
    let acc' = c :: acc in
    match List.assoc_opt c hierarchy with
    | Some (Some parent) -> go parent acc'
    | _ -> acc'
  in
  List.rev (go cap [])

(** [cap_subsumes parent child] — true if [parent] is an ancestor of (or equal to) [child].
    E.g., cap_subsumes "IO" "IO.FileRead" = true. *)
let cap_subsumes parent child =
  List.mem parent (cap_ancestors child)

(** [normalize caps] drops any cap subsumed by another cap already in the
    list, preserving the relative order of the caps that remain.  E.g.
    ["IO"; "IO.FileRead"] -> ["IO"]; ["IO.FileRead"; "IO"] -> ["IO"]. *)
let normalize caps =
  (* DEDUPLICATE FIRST.  A capability closure is a SET; this used to return a
     bag, and the difference was not cosmetic.

     [Typecheck.record_fn_caps] folds a function's newly-seen caps into the ones
     already recorded — [normalize (module_wide_caps @ own_caps @ prior)] — and
     stores the result back.  Because the filter below only drops a cap that a
     DIFFERENT cap subsumes ([other <> c]), two equal entries never eliminate
     each other, so every repeat call appended another copy of the module's
     declared caps and the stored list grew without bound.  With the filter at
     O(n^2) in that list, a long-lived typechecker env degraded quadratically.

     That is invisible in a one-shot CLI run (one module, one call) and severe
     wherever an env is REUSED across many module checks: the property suite
     typechecks ~1800 generated modules against one cached stdlib seed env,
     where it cost 1s -> 168s for a single property group.  The LSP and
     `forge build` (which typechecks each library file as its own entry) reuse
     envs the same way.

     Deduping bounds the list by the size of the lattice regardless of how many
     times a function is recorded.  Order of survivors is unchanged: the first
     occurrence of each cap is kept, which is what the [.mli] promises. *)
  let seen = Hashtbl.create 16 in
  let uniq =
    List.filter (fun c ->
      if Hashtbl.mem seen c then false else (Hashtbl.add seen c (); true)) caps
  in
  List.filter (fun c ->
    not (List.exists (fun other -> other <> c && cap_subsumes other c) uniq)
  ) uniq

(* Levenshtein distance, iterative two-row form. *)
let edit_distance a b =
  let la = String.length a and lb = String.length b in
  if la = 0 then lb else if lb = 0 then la
  else begin
    let prev = Array.init (lb + 1) (fun j -> j) in
    let cur  = Array.make (lb + 1) 0 in
    for i = 1 to la do
      cur.(0) <- i;
      for j = 1 to lb do
        let cost = if a.[i - 1] = b.[j - 1] then 0 else 1 in
        cur.(j) <- min (min (cur.(j - 1) + 1) (prev.(j) + 1)) (prev.(j - 1) + cost)
      done;
      Array.blit cur 0 prev 0 (lb + 1)
    done;
    prev.(lb)
  end

let known_caps = List.map fst hierarchy

let leaf c =
  match String.rindex_opt c '.' with
  | Some i -> String.sub c (i + 1) (String.length c - i - 1)
  | None -> c

(** [suggest_cap cap] is [None] when [cap] is a legal capability path, and
    [Some known] naming the closest known capability when it is not.

    A path rooted at [IO] must appear in [hierarchy] — that lattice is closed.
    Any other root is an FFI/proof capability (see the header comment) and is
    legal, INCLUDING a dotted one like [Db.Migrated] or [MyLib.Clock] — a
    dotted non-[IO] path is never mistaken for a mistyped [IO] capability,
    because it is unambiguously its own namespaced root.

    The leaf-collision rule (a leaf matching a known capability's leaf
    case-insensitively is rejected in favor of the known capability) applies
    ONLY to a bare, single-segment name: that's the `needs Network` case, a
    real capability written without its `IO.` path. Gating it on "no dot"
    keeps it from misfiring on a legitimate dotted FFI root whose last
    segment happens to coincide with an IO leaf (e.g. [MyLib.Clock],
    [Vendor.Random] — these must stay legal, exactly like [Db.Migrated]). *)
let suggest_cap cap =
  if List.mem cap known_caps then None
  else begin
    let lower s = String.lowercase_ascii s in
    let is_io_rooted =
      cap = "IO" || (String.length cap > 3 && String.sub cap 0 3 = "IO.")
    in
    let is_dotted = String.contains cap '.' in
    let leaf_match =
      if is_dotted && not is_io_rooted then None
      else List.find_opt (fun k -> lower (leaf k) = lower (leaf cap)) known_caps
    in
    match leaf_match with
    | Some k -> Some k
    | None ->
      if not is_io_rooted then None   (* an FFI/proof root; legal *)
      else
        let scored =
          List.map (fun k -> (edit_distance (lower cap) (lower k), k)) known_caps
        in
        match List.sort compare scored with
        | (d, k) :: _ when d <= 3 -> Some k
        | _ -> Some "IO"
  end
