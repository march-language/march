(* Read capabilities from a compiled March binary.  See cap_binary.mli and
   specs/2026-08-03-forge-cap-audit-design.md §4-§5. *)

type build_kind = Dead_stripped | Unstripped | Symbols_removed

type t = {
  caps : string list;
  markers : string list;
  attribution : (string * string) list;
  rt_symbols : string list;
  build : build_kind;
  manifest : string option;
}

let strip_underscore s =
  if String.length s > 0 && s.[0] = '_' then String.sub s 1 (String.length s - 1)
  else s

(* ── symbol channel ─────────────────────────────────────────────────── *)

let read_symbols path : string list =
  let out = Filename.temp_file "capnm" ".txt" in
  let rc =
    Sys.command
      (Printf.sprintf "nm %s > %s 2>/dev/null" (Filename.quote path)
         (Filename.quote out))
  in
  if rc <> 0 then begin
    (try Sys.remove out with Sys_error _ -> ());
    (* nm failed: caller classifies via the other channels *)
    []
  end
  else begin
    let acc = ref [] in
    let ic = open_in out in
    (try
       while true do
         let line = input_line ic in
         match String.rindex_opt line ' ' with
         | Some i ->
             acc := String.sub line (i + 1) (String.length line - i - 1) :: !acc
         | None -> if line <> "" then acc := line :: !acc
       done
     with End_of_file -> ());
    close_in ic;
    (try Sys.remove out with Sys_error _ -> ());
    !acc
  end

(* ── marker channel ─────────────────────────────────────────────────── *)

let marker_prefix = "__march_cap_"

(* Cap paths are mangled dots->underscores at emission; reverse by mangling
   every known lattice path and matching.  Unknown suffixes (a future compiler
   with a new capability) are surfaced verbatim rather than dropped — the
   audit must not silently hide caps it does not recognize. *)
let unmangle_cap suffix =
  let mangle c = String.map (fun ch -> if ch = '.' then '_' else ch) c in
  let known =
    List.map fst March_caps.Cap_lattice.hierarchy
    @ March_caps.Cap_symbols.all_caps
  in
  match List.find_opt (fun c -> mangle c = suffix) known with
  | Some c -> c
  | None -> suffix

let has_prefix p s =
  String.length s >= String.length p && String.sub s 0 (String.length p) = p

let markers_of_symbols syms =
  List.filter_map
    (fun sym ->
      let sym = strip_underscore sym in
      if has_prefix marker_prefix sym then
        Some
          (unmangle_cap
             (String.sub sym
                (String.length marker_prefix)
                (String.length sym - String.length marker_prefix)))
      else None)
    syms
  |> List.sort_uniq String.compare

(* ── attribution channel ────────────────────────────────────────────── *)

(* Per-module attribution markers, [__march_capfrom_<CAP>__<OWNER>].  The
   prefix deliberately shares no prefix with [marker_prefix] (they diverge at
   the 12th character), so [markers_of_symbols] above cannot mistake one of
   these for a flat marker and decode "IO_FileRead__BigLib" as a capability.

   Capability paths never contain "__", so the FIRST "__" in the remainder is
   the separator even when the owner module itself contains one. *)
let attrib_prefix = "__march_capfrom_"

let split_on_double_underscore s =
  let n = String.length s in
  let rec go i =
    if i + 1 >= n then None
    else if s.[i] = '_' && s.[i + 1] = '_' then
      Some (String.sub s 0 i, String.sub s (i + 2) (n - i - 2))
    else go (i + 1)
  in
  go 0

let attribution_of_symbols syms =
  List.filter_map
    (fun sym ->
      let sym = strip_underscore sym in
      if not (has_prefix attrib_prefix sym) then None
      else
        let rest =
          String.sub sym
            (String.length attrib_prefix)
            (String.length sym - String.length attrib_prefix)
        in
        match split_on_double_underscore rest with
        (* The owner is emitted verbatim (dots and all — LLVM global names
           permit them), so it needs no unmangling.  Mangling it would be
           irreversible: a module named My_Mod and a nested module My.Mod
           would share one encoding. *)
        | Some (cap, owner) when owner <> "" -> Some (unmangle_cap cap, owner)
        | _ -> None)
    syms
  |> List.sort_uniq compare

(* ── manifest channel ───────────────────────────────────────────────── *)

let manifest_magic = "MARCHCAP\x01"

let read_file path =
  let ic = open_in_bin path in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic;
  s

(* Locate every MARCHCAP\x01 blob.  Multiplicity is an error: a planted blob
   placed earlier in the file must never shadow the real manifest. *)
let find_manifest_offsets data =
  let ml = String.length manifest_magic and dl = String.length data in
  let rec go i acc =
    if i + ml > dl then List.rev acc
    else if String.sub data i ml = manifest_magic then go (i + ml) (i :: acc)
    else go (i + 1) acc
  in
  go 0 []

let manifest_at data off =
  let ml = String.length manifest_magic in
  let p = off + ml in
  if p + 4 > String.length data then Error "manifest: truncated length field"
  else
    let b i = Char.code data.[p + i] in
    let len = b 0 lor (b 1 lsl 8) lor (b 2 lsl 16) lor (b 3 lsl 24) in
    if len < 0 || p + 4 + len > String.length data then
      Error "manifest: length field exceeds file size"
    else Ok (String.sub data (p + 4) len)

(* ── classification ─────────────────────────────────────────────────── *)

let read path : (t, string) result =
  if not (Sys.file_exists path) then Error (Printf.sprintf "%s: no such file" path)
  else
    match read_file path with
    | exception Sys_error e -> Error e
    | data -> (
        let manifests = find_manifest_offsets data in
        match manifests with
        | _ :: _ :: _ ->
            Error
              (Printf.sprintf
                 "%s: %d manifest blobs found — refusing to choose between \
                  them (a planted blob must not shadow the real manifest)"
                 path (List.length manifests))
        | zero_or_one -> (
            let manifest =
              match zero_or_one with
              | [ off ] -> (
                  match manifest_at data off with Ok j -> Some j | Error _ -> None)
              | _ -> None
            in
            let syms = read_symbols path in
            let markers = markers_of_symbols syms in
            let attribution = attribution_of_symbols syms in
            let rt_symbols =
              List.filter_map
                (fun s ->
                  let s' = strip_underscore s in
                  match March_caps.Cap_symbols.cap_of_symbol s' with
                  | Some _ -> Some s'
                  | None -> None)
                syms
              |> List.sort_uniq String.compare
            in
            let all_cap_syms =
              List.sort_uniq String.compare
                (List.map fst March_caps.Cap_symbols.table)
            in
            let n_total = List.length all_cap_syms in
            let n_present =
              List.length (List.filter (fun s -> List.mem s rt_symbols) all_cap_syms)
            in
            (* Classification.  Markers are the only channel we can trust:
               they are emitted from the symbols codegen actually resolved,
               and pinned through dead-strip.  Raw symbol presence cannot
               distinguish "stripped, genuinely uses this" from "linked whole".

               An exact all-symbols-present test is far too brittle — a real
               unstripped artifact measured 79/82 (a forgepm hot-reload .so;
               only IO.Signal absent) and slipped through as Dead_stripped
               with coverage:full.  Use a bulk-presence ratio instead, and
               treat the absence of markers as itself disqualifying. *)
            let bulk_cap_symbols =
              n_total > 0 && n_present * 2 >= n_total (* >= 50% of the table *)
            in
            let build =
              if markers = [] && rt_symbols = [] then Symbols_removed
              else if markers = [] then
                (* No markers: either a pre-marker compiler, a non-March
                   binary, or a .so (carved out of dead-strip).  Whether the
                   symbol set reflects usage is unknowable — never certify. *)
                if bulk_cap_symbols then Unstripped else Symbols_removed
              else if bulk_cap_symbols then Unstripped
              else Dead_stripped
            in
            match build with
            (* caps are reported SPECIFIC, not lattice-normalized.
               normalize collapses IO.NetConnect.TLS/IO.NetListen/
               IO.WebSocket under IO.Network, which for an audit destroys
               exactly the information the reader wants ("does TLS and
               listens on ports" >> "networking"), and orphans the witness
               symbols of every collapsed cap.  Gate checks use
               Cap_lattice.cap_subsumes and work on the specific set. *)
            | Unstripped ->
                (* Reporting the full symbol set as "capabilities" would be
                   the app-invariance failure; report the build kind and no
                   cap list. Markers, if present, are still trustworthy. *)
                Ok { caps = markers; markers; attribution; rt_symbols; build; manifest }
            | Symbols_removed ->
                Ok { caps = []; markers; attribution; rt_symbols; build; manifest }
            | Dead_stripped ->
                let caps =
                  if markers <> [] then markers
                  else
                    List.filter_map March_caps.Cap_symbols.cap_of_symbol
                      rt_symbols
                    |> List.sort_uniq String.compare
                in
                Ok { caps; markers; attribution; rt_symbols; build; manifest }))
