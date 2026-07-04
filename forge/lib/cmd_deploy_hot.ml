(** forge deploy hot — CAS-native, ed25519-signed hot code replacement.

    Flow:
      1. Load forge.toml + [hot-reload] config
      2. Build with --compile-so  → <output>.so + <output>.so.hcr_manifest
      3. Open SSH tunnel to the server's Unix socket
      4. VERSIONS — detect crash-restart drift
      5. ABI_QUERY — get current (id, name, impl_hash, sig_hash) per slot
      6. Read manifest — new (name → impl_hash, sig_hash)
      7. Set-diff — find names where new impl_hash ≠ current impl_hash
      8. CAS_CHECK + CAS_PUT the .so artifact  (if any function changed)
      9. Sign + ACTIVATE each changed function
     10. Report
*)

open Unix

(* ─── Manifest parsing ───────────────────────────────────────────────────── *)

type fn_manifest = {
  fn_name      : string;
  fn_impl_hash : string;
  fn_sig_hash  : string;
  fn_callers   : string list;  (* Phase 8: functions that call this one *)
  fn_caps      : string list;  (* Phase 5C: IO-capability authority required (this
                                   function's OWN caps as of the 2026-07-04
                                   granularity revision — no longer an
                                   artifact-wide union) *)
  fn_has_caps  : bool;  (* true iff the manifest FN line carried a `caps=`
                           field at all (even `caps=`, empty). Distinguishes
                           a genuinely pre-Phase-5C legacy manifest (no fn
                           has this field) from a current manifest where a
                           capless function legitimately has fn_caps = []. *)
}

type manifest = {
  cas_hash  : string;
  functions : fn_manifest list;
}

let parse_manifest path : (manifest, string) result =
  try
    let ic = open_in path in
    let cas_hash = ref "" in
    let fns = ref [] in
    (try while true do
       let line = String.trim (input_line ic) in
       if String.length line = 0 || line.[0] = '#' then begin
         (* # cas_hash <hex> *)
         if String.length line > 10 && String.sub line 0 10 = "# cas_hash" then
           cas_hash := String.trim (String.sub line 10 (String.length line - 10))
       end else if String.length line >= 5 && String.sub line 0 5 = "ROOT " then begin
         (* Legacy pre-2026-07-04 manifests may still carry a
            "ROOT cap_root=<hex>" line (whole-artifact union, now retired).
            Recognize and skip it so `String.split_on_char ' '` doesn't
            otherwise fall into the FN-line branches below and fabricate a
            phantom function named "ROOT". *)
         ()
       end else begin
         let has_prefix field prefix =
           let plen = String.length prefix in
           String.length field >= plen && String.sub field 0 plen = prefix
         in
         let parse_callers field =
           if has_prefix field "callers:" then
             let s = String.sub field 8 (String.length field - 8) in
             if s = "" then [] else String.split_on_char ',' s
           else []
         in
         let parse_caps field =
           if has_prefix field "caps=" then
             let s = String.sub field 5 (String.length field - 5) in
             if s = "" then [] else String.split_on_char ',' s
           else []
         in
         (* caps= is not at a fixed field index — it sits after `callers:`
            only when a `callers:` token is present, so scan the trailing
            tokens for whichever one carries the `caps=` prefix instead of
            indexing positionally. *)
         let extract_from_tail tail =
           let callers =
             match List.find_opt (fun f -> has_prefix f "callers:") tail with
             | Some f -> parse_callers f
             | None -> []
           in
           let has_caps = List.exists (fun f -> has_prefix f "caps=") tail in
           let caps =
             match List.find_opt (fun f -> has_prefix f "caps=") tail with
             | Some f -> parse_caps f
             | None -> []
           in
           (callers, caps, has_caps)
         in
         (match String.split_on_char ' ' line with
         | name :: impl_h :: sig_h :: tail when tail <> [] ->
           let (callers, caps, has_caps) = extract_from_tail tail in
           fns := { fn_name = name; fn_impl_hash = impl_h; fn_sig_hash = sig_h;
                    fn_callers = callers; fn_caps = caps; fn_has_caps = has_caps } :: !fns
         | [name; impl_h; sig_h] ->
           fns := { fn_name = name; fn_impl_hash = impl_h; fn_sig_hash = sig_h;
                    fn_callers = []; fn_caps = []; fn_has_caps = false } :: !fns
         | [name; impl_h] ->
           fns := { fn_name = name; fn_impl_hash = impl_h; fn_sig_hash = "";
                    fn_callers = []; fn_caps = []; fn_has_caps = false } :: !fns
         | _ -> ())  (* skip malformed lines *)
       end
     done with End_of_file -> ());
    close_in ic;
    if !cas_hash = "" then Error (path ^ ": missing # cas_hash line")
    else Ok { cas_hash = !cas_hash; functions = List.rev !fns }
  with Sys_error m -> Error m

(** True iff [manifest] is a genuine pre-Phase-5C legacy manifest — i.e. NO
    function line carries a `caps=` field at all. A current manifest always
    has `caps=` on every FN line (possibly `caps=` empty for a capless
    function), so this only fires for manifests written before Phase 5C
    Part A landed. *)
let is_legacy_manifest (m : manifest) : bool =
  not (List.exists (fun fm -> fm.fn_has_caps) m.functions)

(** [fn_cap_root own_caps] — per-function cap_root, matching byte-for-byte the
    server's recompute recipe in runtime/march_reload.c's compute_cap_root:
    split → sort_uniq → march_cap_normalize → join "\n" → blake3. Mirrored
    here as: Cap_lattice.normalize (order-preserving) then List.sort (to
    match the server's sort-before-normalize canonical order) then
    concat "\n" then Blake3.hash_string. *)
let fn_cap_root (own_caps : string list) : string =
  let normalized = March_caps.Cap_lattice.normalize own_caps in
  let sorted = List.sort String.compare normalized in
  March_cas.Blake3.hash_string (String.concat "\n" sorted)

(* ─── Capability monotonicity gate (Phase 5C Part B, Task 4/5) ───────────────

   A hot deploy may narrow the running system's IO-capability authority
   freely, but widening it is blocked unless the operator explicitly
   authorizes the widening with one or more repeatable `--grant-cap <C>`
   flags (Task 5; see `filter_granted_widening` below).

   [compute_cap_widening ~prior ~new_caps] returns the subset of [new_caps]
   not already subsumed by some cap in [prior] — i.e. the caps a hot deploy
   would newly introduce.  Both lists are expected to already be
   [March_caps.Cap_lattice.normalize]d, but this function does not require that. *)
let compute_cap_widening ~(prior : string list) ~(new_caps : string list) : string list =
  List.filter (fun c -> not (List.exists (fun p -> March_caps.Cap_lattice.cap_subsumes p c) prior)) new_caps

(** [compute_cap_narrowing ~prior ~new_caps] — prior caps no longer present in
    the new build.  Log-only: narrowing is always allowed.

    I2 fix: use [Cap_lattice.cap_subsumes] (the same way [compute_cap_widening]
    above already does) rather than exact-match [List.mem].  Both lists are
    normalized (subsumed-duplicate caps already dropped), so an exact-match
    filter misreports narrowing whenever the new build still holds a broader
    cap that covers the prior one — e.g. new build holds [IO] (root), prior
    held [IO.FileRead]: exact match would report [IO.FileRead] as "narrowed
    away" even though [IO] still covers it, so no narrowing actually
    occurred.  A prior cap only counts as genuinely narrowed if nothing in
    [new_caps] subsumes it. *)
let compute_cap_narrowing ~(prior : string list) ~(new_caps : string list) : string list =
  List.filter (fun p -> not (List.exists (fun n -> March_caps.Cap_lattice.cap_subsumes n p) new_caps)) prior

(** [compute_scoped_caps ~to_activate ~prior] — pure factoring of the
    per-function-scoped monotonicity gate (Granularity revision, 2026-07-04).

    Returns [(prior_caps, new_caps)], both normalized, ready to hand to
    [compute_cap_widening] / [compute_cap_narrowing]:

      - [prior = None] (no baseline — first deploy / legacy): returns
        [([], normalize (union of to_activate's own caps))], matching the
        permissive "NOTE" branch in [run].
      - [prior = Some prior_manifest]: for each function being activated,
        look up that SAME function's own caps in the prior baseline by name
        ([] if the function is new relative to the baseline — not present in
        the prior manifest at all), union and normalize across all activated
        functions for [prior_caps]; union and normalize each activated
        function's CURRENT own caps for [new_caps]. This is scoped to
        [to_activate] only — deliberately not the whole-artifact union, which
        is dominated by the linked stdlib and app-invariant, so it can't
        discriminate a real widening. *)
let compute_scoped_caps ~(to_activate : fn_manifest list) ~(prior : manifest option)
  : string list * string list =
  let new_caps =
    March_caps.Cap_lattice.normalize
      (List.concat_map (fun fm -> fm.fn_caps) to_activate)
  in
  match prior with
  | None -> ([], new_caps)
  | Some prior_manifest ->
    let prior_by_name : (string, string list) Hashtbl.t = Hashtbl.create 16 in
    List.iter (fun fm -> Hashtbl.replace prior_by_name fm.fn_name fm.fn_caps)
      prior_manifest.functions;
    let prior_caps =
      March_caps.Cap_lattice.normalize
        (List.concat_map (fun fm ->
             Option.value ~default:[] (Hashtbl.find_opt prior_by_name fm.fn_name))
            to_activate)
    in
    (prior_caps, new_caps)

(* ─── ACTIVATE3 / ACTIVATE4 wire-line builders (Phase 5C Part C, Task C4) ────

   Factored into pure functions (no socket I/O) so the wire shape is
   unit-testable without a live server. Each returns the `signed` message
   (the exact string that gets ed25519-signed) and the `wire_prefix` — the
   unsigned command line MINUS the trailing " <sig_b64> ..." suffix that the
   caller appends once it has computed the signature (avoids duplicating the
   signing step inside this pure helper). Concretely:

     wire_line = wire_prefix ^ " " ^ sig_b64 ^ " " ^ <rest>

   where <rest> is protocol-specific (see each builder). *)

(** ACTIVATE3 (legacy / --no-cap-gate fallback; byte-for-byte unchanged shape).
    Returns [(signed, wire_head)] where:
      signed   = "ACTIVATE3 <name> <impl> <cas> <migrate> epoch:<N> callers:<csv>"
      wire_head = "ACTIVATE3 <name> <impl> <cas>"  (caller appends " <sig_b64> <migrate> epoch:<N> callers:<csv>") *)
let build_activate3_lines ~name ~impl ~cas ~migrate ~epoch ~callers_csv : string * string =
  let signed = Printf.sprintf "ACTIVATE3 %s %s %s %d epoch:%d callers:%s"
    name impl cas migrate epoch callers_csv in
  let wire_head = Printf.sprintf "ACTIVATE3 %s %s %s" name impl cas in
  (signed, wire_head)

(** ACTIVATE4 (Phase 5C Part C): adds cap_root (signed) + caps (unsigned).
    Returns [(signed, wire_head)] where:
      signed    = "ACTIVATE4 <name> <impl> <cas> <migrate> epoch:<N> cap_root:<hex> callers:<csv>"
                  — caps is deliberately NOT in the signed message (see
                  runtime/march_reload.c ACTIVATE4 handler: trust comes from
                  the server recomputing cap_root over the received caps and
                  matching it against this signed value).
      wire_head = "ACTIVATE4 <name> <impl> <cas>"  (caller appends
                  " <sig_b64> <migrate> epoch:<N> cap_root:<hex> caps:<csv> callers:<csv>")
    cap_root and caps both precede callers on the wire (server scans
    `callers:` to end-of-line, so nothing may follow it). *)
let build_activate4_lines ~name ~impl ~cas ~migrate ~epoch ~cap_root ~callers_csv : string * string =
  let signed = Printf.sprintf "ACTIVATE4 %s %s %s %d epoch:%d cap_root:%s callers:%s"
    name impl cas migrate epoch cap_root callers_csv in
  let wire_head = Printf.sprintf "ACTIVATE4 %s %s %s" name impl cas in
  (signed, wire_head)

(** For each widened cap, find a function in [functions] whose [fn_caps]
    contains (or subsumes-would-need) that cap — used to attribute the
    widening to a specific manifest line in the diagnostic.  Picks the first
    function (in manifest name order) that literally lists the cap.

    M5 fix: [functions] arrives here in [manifest.functions]'s order, which
    the manifest-file writer emits via [Hashtbl.iter] (unspecified order) —
    so which function got blamed in the diagnostic could vary build-to-build
    for the exact same source.  Sort by [fn_name] first so the search (and
    thus the diagnostic) is deterministic and reproducible. *)
let attribute_widening (functions : fn_manifest list) (widening : string list) : (string * string) list =
  let sorted_functions =
    List.sort (fun a b -> String.compare a.fn_name b.fn_name) functions in
  List.map (fun cap ->
    let introducer =
      match List.find_opt (fun fm -> List.mem cap fm.fn_caps) sorted_functions with
      | Some fm -> fm.fn_name
      | None -> "?"
    in
    (cap, introducer)
  ) widening

(** [filter_granted_widening ~widening ~grant_caps] — Phase 5C Part B, Task 5.
    Removes from [widening] every cap authorized by some entry in
    [grant_caps], via subsumption (not exact string match): a grant of a
    broader cap (e.g. [IO.FileSystem]) covers a narrower widened cap (e.g.
    [IO.FileWrite]). Grants for caps that aren't actually being widened are
    simply inert — they have no effect and produce no error. *)
let filter_granted_widening ~(widening : string list) ~(grant_caps : string list) : string list =
  List.filter (fun c -> not (List.exists (fun g -> March_caps.Cap_lattice.cap_subsumes g c) grant_caps)) widening

(** Print the "hot deploy would add authority" diagnostic to stderr in the
    fixed shape depended on by tooling/tests:

      error: hot deploy would add authority not held by the running version
        running version caps:  IO.Console, IO.NetConnect
        new version adds:      IO.Process   (from MyApp.Server.handle)
        A hot deploy may only narrow authority. To authorize this widening, re-run with:
            forge deploy hot --grant-cap IO.Process
        The grant is signed and recorded in the audit log.

    Only caps still ungranted (after `filter_granted_widening` has removed
    any covered by `--grant-cap`) are ever passed in via [attributed]. *)
let print_widening_diagnostic ~(prior_caps : string list) ~(attributed : (string * string) list) =
  Printf.eprintf "error: hot deploy would add authority not held by the running version\n";
  Printf.eprintf "  running version caps:  %s\n"
    (if prior_caps = [] then "(none)" else String.concat ", " prior_caps);
  (* M3 fix: the padding width used to be a hardcoded 12, which misaligned
     for caps longer than 12 chars (e.g. "IO.NetConnect.TLS",
     "IO.Foreign.Blocking"). Compute it dynamically from the longest cap name
     actually being printed so alignment holds regardless of cap length. *)
  let pad_width =
    List.fold_left (fun acc (cap, _) -> max acc (String.length cap)) 12 attributed in
  List.iter (fun (cap, fn_name) ->
    Printf.eprintf "  new version adds:      %-*s (from %s)\n" pad_width cap fn_name
  ) attributed;
  Printf.eprintf "  A hot deploy may only narrow authority. To authorize this widening, re-run with:\n";
  List.iter (fun (cap, _) ->
    Printf.eprintf "      forge deploy hot --grant-cap %s\n" cap
  ) attributed

(** After a successful deploy, copy the just-deployed .hcr_manifest over the
    baseline file, so next time's "prior" is this time's "new" — mirrors
    [save_schemas_baseline] exactly. *)
let save_manifest_baseline ~new_manifest_path ~prev_manifest_path =
  if Sys.file_exists new_manifest_path then
    (try
      let ic = open_in new_manifest_path in
      let content = In_channel.input_all ic in
      close_in ic;
      let march_dir = Filename.dirname prev_manifest_path in
      (if not (Sys.file_exists march_dir) then
         try Unix.mkdir march_dir 0o755 with Unix_error _ -> ());
      let oc = open_out prev_manifest_path in
      output_string oc content;
      close_out oc
    with Sys_error _ -> ())

(* ─── Socket I/O ─────────────────────────────────────────────────────────── *)

type conn = {
  fd  : file_descr;
  buf : Buffer.t;
}

let conn_of_fd fd = { fd; buf = Buffer.create 256 }

let send_line conn s =
  let msg = s ^ "\n" in
  let rec loop off remaining =
    if remaining > 0 then
      let n = write conn.fd (Bytes.of_string msg) off remaining in
      loop (off + n) (remaining - n)
  in
  loop 0 (String.length msg)

let recv_line conn =
  let rec loop () =
    match Buffer.contents conn.buf |> String.split_on_char '\n' with
    | line :: rest when String.length line > 0 ->
      let rest_str = String.concat "\n" rest in
      Buffer.clear conn.buf;
      Buffer.add_string conn.buf rest_str;
      line
    | _ ->
      let tmp = Bytes.create 4096 in
      let n = read conn.fd tmp 0 4096 in
      if n = 0 then failwith "connection closed";
      Buffer.add_subbytes conn.buf tmp 0 n;
      loop ()
  in
  loop ()

let send_binary conn data offset len =
  let rec loop off remaining =
    if remaining > 0 then begin
      let n = write conn.fd data off remaining in
      loop (off + n) (remaining - n)
    end
  in
  loop offset len


(* ─── SSH tunnel ─────────────────────────────────────────────────────────── *)

let open_tunnel ~ssh_host ~remote_socket ~local_socket =
  let pid = Unix.create_process "ssh"
    [| "ssh"; "-N"; "-o"; "StrictHostKeyChecking=no"; "-o"; "ExitOnForwardFailure=yes";
       "-L"; Printf.sprintf "%s:%s" local_socket remote_socket;
       ssh_host |]
    Unix.stdin Unix.stdout Unix.stderr
  in
  (* Wait for the tunnel socket to appear (up to 5 seconds). *)
  let ready = ref false in
  for i = 1 to 50 do
    if not !ready then begin
      Unix.sleepf 0.1;
      if Sys.file_exists local_socket then ready := true
      else if i = 50 then
        Printf.eprintf "forge deploy hot: warning: tunnel socket not appearing after 5s\n%!"
    end
  done;
  (pid, local_socket)

let close_tunnel pid local_socket =
  (try Unix.kill pid Sys.sigterm with Unix_error _ -> ());
  (try Unix.waitpid [] pid |> ignore with Unix_error _ -> ());
  (try Sys.remove local_socket with Sys_error _ -> ())

let connect_socket path =
  let fd = Unix.socket Unix.PF_UNIX Unix.SOCK_STREAM 0 in
  let addr = Unix.ADDR_UNIX path in
  Unix.connect fd addr;
  fd

(* ─── Protocol helpers ───────────────────────────────────────────────────── *)

(** Parse ABI_QUERY response lines.
    Each line: SLOT <id> <name> <impl_hash> <sig_hash> *)
type slot = {
  slot_id        : int;
  slot_name      : string;
  slot_impl_hash : string;
  slot_sig_hash  : string;
  slot_callers   : string list;  (* Phase 8: callers recorded at last ACTIVATE *)
}

let parse_abi_query conn =
  let slots = ref [] in
  let parse_slot_callers field =
    if String.length field > 8 && String.sub field 0 8 = "callers:" then
      let s = String.sub field 8 (String.length field - 8) in
      if s = "" then [] else String.split_on_char ',' s
    else []
  in
  let rec loop () =
    let line = recv_line conn in
    if line = "END" then List.rev !slots
    else begin
      (match String.split_on_char ' ' line with
       | "SLOT" :: id_s :: name :: impl_h :: sig_h :: rest ->
         let callers = match rest with
           | [cf] -> parse_slot_callers cf
           | _    -> []
         in
         (match int_of_string_opt id_s with
          | Some id ->
            slots := { slot_id = id; slot_name = name;
                       slot_impl_hash = impl_h; slot_sig_hash = sig_h;
                       slot_callers = callers } :: !slots
          | None -> ())
       | _ -> ());
      loop ()
    end
  in
  loop ()

(** Parse VERSIONS response. Returns list of (name, baseline, current_or_none). *)
type version_entry = {
  ve_name     : string;
  ve_baseline : string;
  ve_current  : string option;  (* Some h when hot ≠ baseline *)
}

let parse_versions conn =
  let entries = ref [] in
  let rec loop () =
    let line = recv_line conn in
    if line = "END" then List.rev !entries
    else begin
      (match String.split_on_char ' ' line with
       | ["VERSION"; name; "baseline"; h] ->
         entries := { ve_name = name; ve_baseline = h; ve_current = None } :: !entries
       | ["VERSION"; name; "hot"; h] ->
         (* Update the last entry with the hot hash *)
         entries := (match !entries with
           | e :: rest when e.ve_name = name -> { e with ve_current = Some h } :: rest
           | _ -> !entries)
       | _ -> ());
      loop ()
    end
  in
  loop ()

(* ─── CAS operations ─────────────────────────────────────────────────────── *)

let cas_check conn hash =
  send_line conn (Printf.sprintf "CAS_CHECK %s" hash);
  let resp = recv_line conn in
  resp = "PRESENT"

let cas_put conn hash path =
  let size = (Unix.stat path).Unix.st_size in
  send_line conn (Printf.sprintf "CAS_PUT %s %d" hash size);
  let resp = recv_line conn in
  if resp <> "READY" then
    failwith (Printf.sprintf "CAS_PUT: server not ready: %s" resp);
  (* Stream the file *)
  let ic = open_in_bin path in
  let buf = Bytes.create 65536 in
  (try while true do
     let n = input ic buf 0 65536 in
     if n = 0 then raise Exit;
     send_binary conn buf 0 n
   done with Exit | End_of_file -> ());
  close_in ic;
  let final = recv_line conn in
  if not (String.length final >= 2 && String.sub final 0 2 = "OK") then
    failwith (Printf.sprintf "CAS_PUT failed: %s" final)

(* ─── Transient socket naming (shared by Phase 7 fan-out and Phase 10 helpers) *)

let _tunnel_counter = ref 0
let fresh_sock prefix =
  incr _tunnel_counter;
  Printf.sprintf "/tmp/%s_%d_%d.sock" prefix (Unix.getpid ()) !_tunnel_counter

(* ─── Phase 10 clustering helpers ────────────────────────────────────────── *)

(** HTTP GET [url] with a [timeout_s]-second limit; returns true iff status 200. *)
let http_health_check ~url ~timeout_s : bool =
  let cmd = Printf.sprintf "curl -sf -o /dev/null --max-time %d %s 2>/dev/null"
    timeout_s (Filename.quote url) in
  Sys.command cmd = 0

(** Open a transient tunnel, send GET_EPOCH to one server, return the epoch (0
    on failure or when server predates Phase 9). *)
let get_epoch_from_server ~ssh_host ~remote_socket : int =
  let local = fresh_sock "march_epoch" in
  let (pid, _) = open_tunnel ~ssh_host ~remote_socket ~local_socket:local in
  let epoch =
    try
      let fd = connect_socket local in
      let conn = conn_of_fd fd in
      send_line conn "GET_EPOCH";
      let resp = recv_line conn in
      Unix.close fd;
      match String.split_on_char ' ' resp with
      | ["EPOCH"; n] -> (match int_of_string_opt n with Some v -> v | None -> 0)
      | _ -> 0
    with _ -> 0
  in
  close_tunnel pid local;
  epoch

(* ─── Main deploy flow ───────────────────────────────────────────────────── *)

(* Check if a symbol is exported from a shared library (for migrate_state presence check). *)
let so_exports_symbol (so_path : string) (sym : string) : bool =
  let cmd = Printf.sprintf "nm -D %s 2>/dev/null | grep -q ' T %s$'"
    (Filename.quote so_path) (Filename.quote sym) in
  Sys.command cmd = 0

let run ~ssh_host ~remote_socket ~signing_pubkey ~sk ~manifest ~so_path
    ?(old_schemas_path="") ?(new_schemas_path="") ?(entry_path="")
    ?(old_manifest_path="") ?(provided_epoch=0) ?(grant_caps=([] : string list))
    ?(no_cap_gate=false) () =
  let local_socket = Printf.sprintf "/tmp/march_deploy_%d.sock" (Unix.getpid ()) in

  (* 1. SSH tunnel *)
  Printf.printf "Connecting to %s via SSH...\n%!" ssh_host;
  let (tunnel_pid, _) = open_tunnel ~ssh_host ~remote_socket ~local_socket in

  let result =
    Fun.protect ~finally:(fun () -> close_tunnel tunnel_pid local_socket) (fun () ->
    (try
      let fd = connect_socket local_socket in
      let conn = conn_of_fd fd in

      (* 2. VERSIONS — active hot-patch check.
         ve_current <> None means this function's running impl_hash differs from
         the compiled-in baseline, i.e. a prior hot deploy is active. This is the
         normal state after any successful deploy; it does NOT indicate crash-restart
         drift (a restart would reset to baseline, making ve_current = None). *)
      send_line conn "VERSIONS";
      let versions = parse_versions conn in
      let patched = List.filter (fun ve -> ve.ve_current <> None) versions in
      if patched <> [] then begin
        Printf.printf "NOTE: %d function(s) have active hot patches (differ from compiled-in baseline):\n"
          (List.length patched);
        List.iter (fun ve ->
          Printf.printf "  %s: baseline=%s, running=%s\n"
            ve.ve_name ve.ve_baseline (Option.value ~default:"?" ve.ve_current)
        ) patched
      end;

      (* 3. ABI_QUERY — current slot state *)
      send_line conn "ABI_QUERY";
      let slots = parse_abi_query conn in
      let slot_map = Hashtbl.create 16 in
      List.iter (fun s -> Hashtbl.replace slot_map s.slot_name s) slots;

      (* Phase 9: GET_EPOCH — assign a monotonic epoch for this deploy batch.
         When provided_epoch > 0 (cluster deploy), the caller already fetched a
         shared epoch from the epoch-master node; skip the round-trip so all
         nodes in the batch share the same epoch.
         Old servers respond ERR unknown_command; fall back to epoch 0 (Phase 8). *)
      let hcr_epoch =
        if provided_epoch > 0 then provided_epoch
        else begin
          send_line conn "GET_EPOCH";
          match String.split_on_char ' ' (recv_line conn) with
          | ["EPOCH"; n] -> (match int_of_string_opt n with Some v -> v | None -> 0)
          | _            -> 0
        end
      in

      (* 4. Set-diff: functions where new impl_hash ≠ current *)
      let not_registered = List.filter (fun fm ->
        not (Hashtbl.mem slot_map fm.fn_name)
      ) manifest.functions in
      if not_registered <> [] then begin
        Printf.printf "NOTE: %d function(s) are new and require a server restart to register:\n"
          (List.length not_registered);
        List.iter (fun fm -> Printf.printf "  %s\n" fm.fn_name) not_registered
      end;
      let to_activate = List.filter (fun fm ->
        match Hashtbl.find_opt slot_map fm.fn_name with
        | None -> false  (* new function — needs restart, not a hot deploy *)
        | Some slot -> slot.slot_impl_hash <> fm.fn_impl_hash
      ) manifest.functions in

      if to_activate = [] then begin
        if not_registered <> [] then
          Printf.printf "No hot-deployable changes detected (new functions require a restart).\n%!"
        else
          Printf.printf "No changes detected — server is already up to date.\n%!";
        Unix.close fd;
        Ok 0
      end else begin
        Printf.printf "Deploying %d changed function(s)...\n%!" (List.length to_activate);

        (* 5. sig_hash safety gate: new sig_hash must match old sig_hash (no ABI breaks).
           Exception: actor dispatch functions whose state schema changed AND whose actor
           exports a __migrate_<Actor> symbol are allowed to have a different sig_hash —
           the state migration path handles the ABI change safely. *)
        let dispatch_suffix = "_dispatch" in
        let has_migrate_exemption (fn_name : string) : bool =
          (* fn_name pattern: "Module.ActorName_dispatch" or "ActorName_dispatch" *)
          let base = match String.rindex_opt fn_name '.' with
            | Some i -> String.sub fn_name (i+1) (String.length fn_name - i - 1)
            | None   -> fn_name
          in
          let dlen = String.length dispatch_suffix in
          if String.length base > dlen &&
             String.sub base (String.length base - dlen) dlen = dispatch_suffix
          then begin
            let actor_name = String.sub base 0 (String.length base - dlen) in
            so_exports_symbol so_path ("__migrate_" ^ actor_name)
          end else false
        in
        let abi_violations = List.filter (fun fm ->
          match Hashtbl.find_opt slot_map fm.fn_name with
          | None -> false
          | Some slot ->
            slot.slot_sig_hash <> "" && fm.fn_sig_hash <> "" &&
            slot.slot_sig_hash <> fm.fn_sig_hash &&
            not (has_migrate_exemption fm.fn_name)
        ) to_activate in
        (* Phase 8 — coordinated upgrade gate.
           For each sig-changed function, check whether all server-recorded callers
           are also being replaced in this deploy.  If the server has no caller data
           for a slot (old server / first deploy), we allow the change conservatively. *)
        let to_activate_set =
          List.fold_left (fun h fm -> Hashtbl.replace h fm.fn_name (); h)
            (Hashtbl.create 8) to_activate
        in
        let missing_callers = List.filter_map (fun fm ->
          match Hashtbl.find_opt slot_map fm.fn_name with
          | None -> None
          | Some slot ->
            let uncovered = List.filter
                (fun c -> not (Hashtbl.mem to_activate_set c))
                slot.slot_callers
            in
            if uncovered = [] then None
            else Some (fm.fn_name, uncovered)
        ) abi_violations in
        if missing_callers <> [] && hcr_epoch = 0 then begin
          (* Phase 8 hard block: Phase 9 not active, so old callers will see the new
             sig immediately.  Require all callers to be in this batch. *)
          Printf.eprintf "error: function signature changed but not all callers are in this deploy:\n\n";
          List.iter (fun (fn_name, callers) ->
            Printf.eprintf "  %s — uncovered caller(s):\n" fn_name;
            List.iter (fun c -> Printf.eprintf "    %s\n" c) callers
          ) missing_callers;
          Printf.eprintf "\nInclude the missing modules in this deploy, or use expand-contract:\n";
          Printf.eprintf "  1. Add B.foo_v2 alongside B.foo, update callers, deploy together\n";
          Printf.eprintf "  2. In a later deploy, remove B.foo\n\n";
          Printf.eprintf "See specs/plans/2026-06-26-hcr-cross-module-versioning.md\n\n";
          Printf.eprintf "error: deploy aborted\n";
          Unix.close fd;
          Error "function signature changed — refusing to deploy"
        end else begin
          (* Phase 9 active (hcr_epoch > 0): missing callers are safe — old callers
             route to the previous ring slot via epoch-tagged dispatch until their
             next deploy.  Emit a warning naming the in-flight callers. *)
          if missing_callers <> [] then begin
            Printf.eprintf "Warning: function signature changed — old callers will continue\n";
            Printf.eprintf "  calling the previous version until they are redeployed:\n";
            List.iter (fun (fn_name, callers) ->
              Printf.eprintf "  %s — old caller(s): %s\n"
                fn_name (String.concat ", " callers)
            ) missing_callers
          end;
          if abi_violations <> [] && missing_callers = [] then
            Printf.printf "Coordinated upgrade: sig_hash changed, all callers covered.\n%!";

          (* Phase 5C Part B, Task 4: capability monotonicity gate.
             Absent baseline (first deploy ever) ⇒ permissive, matching the
             old_schemas_path <> "" precedent above — log a note and proceed. *)
          let prior_manifest_opt =
            if old_manifest_path <> "" && Sys.file_exists old_manifest_path then
              match parse_manifest old_manifest_path with
              | Ok m -> Some m
              | Error _ -> None
            else None
          in
          (* Granularity revision (2026-07-04): scope the monotonicity gate to
             the functions actually being activated (to_activate), not the
             whole-artifact union — the union is dominated by the linked
             stdlib and is app-invariant, so it can't discriminate a real
             widening. For each activated function, compare its new own-caps
             to that SAME function's own-caps in the prior baseline ([] if
             the function is new relative to the baseline). *)
          (match prior_manifest_opt with
          | None ->
            Printf.printf
              "NOTE: no prior capability baseline found — capability widening gate is permissive for this deploy (legacy/first deploy).\n%!"
          | Some _ ->
            let (prior_caps, new_caps) =
              compute_scoped_caps ~to_activate ~prior:prior_manifest_opt
            in
            let widening = compute_cap_widening ~prior:prior_caps ~new_caps in
            let narrowing = compute_cap_narrowing ~prior:prior_caps ~new_caps in
            if narrowing <> [] then
              Printf.printf "NOTE: this deploy narrows capability authority (allowed): %s\n%!"
                (String.concat ", " narrowing);
            if widening <> [] then begin
              (* Phase 5C Part B, Task 5: --grant-cap authorizes specific
                 widenings (subsumption-matched, not exact string match). *)
              let ungranted = filter_granted_widening ~widening ~grant_caps in
              let granted_caps = List.filter (fun c -> not (List.mem c ungranted)) widening in
              List.iter (fun cap ->
                let covering_grant =
                  match List.find_opt (fun g -> March_caps.Cap_lattice.cap_subsumes g cap) grant_caps with
                  | Some g -> g
                  | None -> cap
                in
                Printf.printf "  granted widening: %s (via --grant-cap %s)\n%!" cap covering_grant
              ) granted_caps;
              if ungranted <> [] then begin
                let attributed = attribute_widening to_activate ungranted in
                print_widening_diagnostic ~prior_caps ~attributed;
                Unix.close fd;
                raise (Failure "capability widening — deploy aborted")
              end
            end);

          (* 6. CAS_PUT the .so if not already present *)
          (* NOTE (2026-07-04): the former skew check SHA-256-hashed the .so
             to `manifest.cas_hash`, but cas_hash is the compiler's BLAKE3
             *compilation hash* (blake3 of impl_hash+target+identities+flags,
             March_cas.Cas.compilation_hash), NOT a SHA-256 of the .so bytes — the
             two are different algorithms over different inputs and can never be
             equal, so the check aborted every real deploy. It was dead-broken and
             unexercised since it landed (df4fec3f, ACTIVATE3). Removed here to
             unblock deploys. Proper manifest/binary skew detection needs a real
             content hash recorded in the manifest (e.g. a `# so_blake3 <hex>` line
             written by bin/main.ml after linking, verified here with the same
             blake3) — tracked as a follow-up. Integrity today rests on the
             ed25519 signature over (impl_hash, cas_hash) and the server keying the
             artifact by cas_hash. *)
          let cas_hash = manifest.cas_hash in
          if not (cas_check conn cas_hash) then begin
            Printf.printf "Uploading artifact %s...\n%!" so_path;
            cas_put conn cas_hash so_path;
            Printf.printf "Artifact uploaded.\n%!"
          end else
            Printf.printf "Artifact already on server (cache hit).\n%!";

          (* Phase 5: load actor state schemas for compat checking and migrate_required flag *)
          let old_schemas =
            if old_schemas_path <> "" then Schema_diff.parse_schemas_file old_schemas_path
            else []
          in
          let new_schemas =
            if new_schemas_path <> "" then Schema_diff.parse_schemas_file new_schemas_path
            else []
          in
          let actor_diffs = Schema_diff.diff_schemas old_schemas new_schemas in

          (* Abort if any actor has a compat violation and no migrate_state is present *)
          let compat_errors = List.filter_map (fun d ->
              let compat = match List.assoc_opt d.Schema_diff.actor new_schemas with
                | Some s -> s.Schema_diff.compat | None -> "full" in
              match Schema_diff.check_compat compat d.Schema_diff.changes with
              | Ok () -> None
              | Error msg ->
                let actor_mangled = String.map (fun c -> if c = '.' then '_' else c)
                    d.Schema_diff.actor in
                let migrate_sym = "__migrate_" ^ actor_mangled in
                if so_exports_symbol so_path migrate_sym then None
                else Some (d.Schema_diff.actor, msg)
            ) actor_diffs
          in
          if compat_errors <> [] then begin
            List.iter (fun (actor, msg) ->
              Printf.eprintf "forge deploy hot: actor %s — %s\n" actor msg
            ) compat_errors;
            Printf.eprintf "Provide a migrate_state function or add @compat annotation.\n";
            Unix.close fd;
            raise (Failure "compat violation — deploy aborted")
          end;

          (* Gap #3: migration VC — shell out to march --check-migration. *)
          let march_bin =
            Option.value (Sys.getenv_opt "MARCH_BIN")
              ~default:(Filename.concat (Sys.getcwd ()) "_build/default/bin/main.exe")
          in
          let needs_vc_check =
            List.exists (fun (_, s) -> s.Schema_diff.invariant <> None) new_schemas
          in
          if needs_vc_check && old_schemas_path <> "" && new_schemas_path <> ""
             && entry_path <> "" && Sys.file_exists march_bin then begin
            let cmd = Printf.sprintf "%s --check-migration --prior-schema %s --new-schema %s %s"
                (Filename.quote march_bin)
                (Filename.quote old_schemas_path)
                (Filename.quote new_schemas_path)
                (Filename.quote entry_path)
            in
            (match Unix.system cmd with
            | Unix.WEXITED 0 -> ()
            | Unix.WEXITED _ ->
              Unix.close fd;
              raise (Failure "migration VC failed — deploy aborted")
            | _ ->
              Unix.close fd;
              raise (Failure "march --check-migration abnormal exit — deploy aborted"))
          end;

          (* 7. Sign + ACTIVATE each changed function *)
          let _ = signing_pubkey in  (* public key already embedded in server binary *)
          let activated = ref 0 in
          let failed = ref 0 in

          (* Send BEGIN_BATCH so the server stages activations atomically *)
          send_line conn "BEGIN_BATCH";
          let begin_resp = recv_line conn in
          let batch_mode = String.length begin_resp >= 2 && String.sub begin_resp 0 2 = "OK" in
          if not batch_mode then
            Printf.eprintf
              "  warning: server does not support BEGIN_BATCH — activations are non-atomic\n%!";

          List.iter (fun fm ->
            (* Phase 5: determine migrate_required for actor dispatch functions *)
            let dispatch_suffix = "_dispatch" in
            let dlen = String.length dispatch_suffix in
            let flen = String.length fm.fn_name in
            let migrate_required =
              if flen > dlen && String.sub fm.fn_name (flen - dlen) dlen = dispatch_suffix
              then
                let actor_name = String.sub fm.fn_name 0 (flen - dlen) in
                match List.find_opt (fun d -> d.Schema_diff.actor = actor_name) actor_diffs with
                | None -> 0
                | Some d ->
                  let compat = match List.assoc_opt actor_name new_schemas with
                    | Some s -> s.Schema_diff.compat | None -> "full" in
                  (match Schema_diff.check_compat compat d.Schema_diff.changes with
                  | Ok () ->
                    if Schema_diff.requires_migration d.Schema_diff.changes then 1 else 0
                  | Error _ -> 1)
              else 0
            in
            (* Protocol v3/v4: migrate_required is also signed so it can't be
               forged between the signature and the server.

               Phase 5C Part C, Task C4 (revised 2026-07-04 for granularity):
               emit ACTIVATE4 (cap_root admission) when this manifest carries
               per-fn caps= fields and the operator hasn't forced the legacy
               path with --no-cap-gate. A genuinely pre-Phase-5C legacy
               manifest (no fn line anywhere carries caps=) always falls back
               to ACTIVATE3, since there is no per-fn cap data to admit
               against. Each activated function now sends its OWN cap_root,
               computed from its OWN caps — never the whole-artifact union. *)
            let callers_sorted = List.sort String.compare fm.fn_callers in
            let callers_csv = String.concat "," callers_sorted in
            let epoch_n = if hcr_epoch > 0 then hcr_epoch else 0 in
            let use_activate4 = (not (is_legacy_manifest manifest)) && not no_cap_gate in
            if not use_activate4 && (not (is_legacy_manifest manifest)) && no_cap_gate then
              Printf.printf
                "  NOTE: %s — --no-cap-gate forces legacy ACTIVATE3 (capability admission skipped)\n%!"
                fm.fn_name
            else if not use_activate4 then
              Printf.printf
                "  NOTE: %s — legacy manifest (no caps= fields) — emitting ACTIVATE3\n%!"
                fm.fn_name;
            if use_activate4 then begin
              let fn_caps_sorted = List.sort String.compare fm.fn_caps in
              let caps_csv = String.concat "," fn_caps_sorted in
              let this_cap_root = fn_cap_root fm.fn_caps in
              let (signed, wire_head) =
                build_activate4_lines ~name:fm.fn_name ~impl:fm.fn_impl_hash ~cas:cas_hash
                  ~migrate:migrate_required ~epoch:epoch_n ~cap_root:this_cap_root
                  ~callers_csv
              in
              let sig_bytes = March_ed25519.Ed25519.sign_str signed sk in
              let sig_b64 = March_ed25519.Ed25519.sig_to_base64 sig_bytes in
              let cmd = Printf.sprintf "%s %s %d epoch:%d cap_root:%s caps:%s callers:%s"
                wire_head sig_b64 migrate_required epoch_n this_cap_root caps_csv callers_csv in
              send_line conn cmd;
              let resp = recv_line conn in
              if String.length resp >= 2 && String.sub resp 0 2 = "OK" then begin
                Printf.printf "  activated: %s\n%!" fm.fn_name;
                incr activated
              end else if resp = "ERR unknown_command" then begin
                Printf.eprintf
                  "  FAILED %s: server predates capability admission (Phase 5C); upgrade the server or re-run with --no-cap-gate\n%!"
                  fm.fn_name;
                incr failed
              end else if resp = "ERR cap_tamper" then begin
                Printf.eprintf
                  "  FAILED %s: cap_tamper — server-recomputed cap_root did not match the signed value; deploy rejected\n%!"
                  fm.fn_name;
                incr failed
              end else if String.length resp >= 15 && String.sub resp 0 15 = "ERR cap_policy " then begin
                Printf.eprintf
                  "  FAILED %s: %s — deploy rejected by node capability policy\n%!"
                  fm.fn_name resp;
                incr failed
              end else begin
                Printf.eprintf "  FAILED %s: %s\n%!" fm.fn_name resp;
                incr failed
              end
            end else begin
              let (signed, wire_head) =
                build_activate3_lines ~name:fm.fn_name ~impl:fm.fn_impl_hash ~cas:cas_hash
                  ~migrate:migrate_required ~epoch:epoch_n ~callers_csv
              in
              let sig_bytes = March_ed25519.Ed25519.sign_str signed sk in
              let sig_b64 = March_ed25519.Ed25519.sig_to_base64 sig_bytes in
              let cmd = Printf.sprintf "%s %s %d epoch:%d callers:%s"
                wire_head sig_b64 migrate_required epoch_n callers_csv in
              send_line conn cmd;
              let resp = recv_line conn in
              if String.length resp >= 2 && String.sub resp 0 2 = "OK" then begin
                Printf.printf "  activated: %s\n%!" fm.fn_name;
                incr activated
              end else if resp = "ERR unknown_command" then begin
                Printf.eprintf
                  "  FAILED %s: server predates protocol v3 — restart the server binary\n%!"
                  fm.fn_name;
                incr failed
              end else begin
                Printf.eprintf "  FAILED %s: %s\n%!" fm.fn_name resp;
                incr failed
              end
            end
          ) to_activate;

          (* Commit or rollback the batch *)
          if batch_mode then begin
            if !failed = 0 then begin
              send_line conn "COMMIT_BATCH";
              let commit_resp = recv_line conn in
              let n_expected = List.length to_activate in
              let commit_ok =
                try
                  Scanf.sscanf commit_resp "OK %d" (fun n -> n = n_expected)
                with _ -> false
              in
              if not commit_ok then begin
                Printf.eprintf "  COMMIT_BATCH failed: %s\n%!" commit_resp;
                failed := !activated  (* mark all as failed *)
              end
            end else begin
              send_line conn "ROLLBACK_BATCH";
              ignore (recv_line conn);
              Printf.eprintf
                "  Rolled back: %d function(s) failed, server state unchanged.\n%!" !failed
            end
          end;

          Unix.close fd;

          if !failed = 0 then begin
            Printf.printf "Deploy complete: %d function(s) activated.\n%!" !activated;
            Ok !activated
          end else
            Error (Printf.sprintf "%d function(s) failed to activate" !failed)
        end
      end
    with
    | Failure m -> Error m
    | Unix_error (e, fn, _) ->
      Error (Printf.sprintf "%s: %s" fn (Unix.error_message e))))
  in
  result

(* ─── Status: VERSIONS_DETAIL dashboard ─────────────────────────────────── *)

type detail_slot = {
  ds_id           : int;
  ds_name         : string;
  ds_impl_hash    : string;
  ds_activated_at : int64;   (* Unix ms; 0 = never activated (baseline) *)
  ds_signer       : string;  (* 64-char hex pubkey, or "(none)" if baseline *)
  ds_epoch        : int;     (* Phase 9: deploy epoch; 0 = pre-Phase-9 or baseline *)
}

let parse_versions_detail conn =
  let slots = ref [] in
  let rec loop () =
    let line = recv_line conn in
    if line = "END" then List.rev !slots
    else begin
      (match String.split_on_char ' ' line with
       | "SLOT" :: id_s :: name :: impl_h :: ts_s :: signer :: rest ->
         let epoch = match rest with
           | [ep_s] -> (match int_of_string_opt ep_s with Some v -> v | None -> 0)
           | _ -> 0
         in
         (match int_of_string_opt id_s, Int64.of_string_opt ts_s with
          | Some id, Some ts ->
            slots := { ds_id = id; ds_name = name; ds_impl_hash = impl_h;
                       ds_activated_at = ts; ds_signer = signer;
                       ds_epoch = epoch } :: !slots
          | _ -> ())
       | _ -> ());
      loop ()
    end
  in
  loop ()

let format_elapsed_ms (ts_ms : int64) : string =
  if ts_ms = 0L then "never (baseline)"
  else begin
    let now_ms = Int64.of_float (Unix.gettimeofday () *. 1000.0) in
    let diff_ms = Int64.sub now_ms ts_ms in
    let diff_s = Int64.to_int (Int64.div diff_ms 1000L) in
    if diff_s < 0 then "just now"
    else if diff_s < 60 then Printf.sprintf "%ds ago" diff_s
    else if diff_s < 3600 then Printf.sprintf "%dm ago" (diff_s / 60)
    else if diff_s < 86400 then Printf.sprintf "%dh ago" (diff_s / 3600)
    else Printf.sprintf "%dd ago" (diff_s / 86400)
  end

let run_status ?(env="") () : (unit, string) result =
  match Project.load () with
  | Error m -> Error m
  | Ok proj ->
    match proj.Project.hot_reload with
    | None -> Error "no [hot-reload] section in forge.toml"
    | Some hr ->
      (* Collect the server list to query: env filter → hr_envs → single host *)
      let servers : Project.hot_reload_env list =
        if env <> "" then
          List.filter (fun e -> e.Project.hre_name = env) hr.Project.hr_envs
        else if hr.Project.hr_envs <> [] then hr.Project.hr_envs
        else if hr.Project.hr_ssh_host <> "" then
          [{ Project.hre_name = "default";
             hre_ssh_host = hr.Project.hr_ssh_host;
             hre_socket   = hr.Project.hr_socket;
             hre_public_key = hr.Project.hr_public_key }]
        else []
      in
      if servers = [] then
        Error "[hot-reload] ssh_host is required"
      else begin
        let multi_node = List.length servers > 1 in
        let query_server (srv : Project.hot_reload_env) =
          let local = fresh_sock "march_status" in
          Printf.printf "Connecting to %s...\n%!" srv.Project.hre_ssh_host;
          let (pid, _) = open_tunnel ~ssh_host:srv.Project.hre_ssh_host
                                     ~remote_socket:srv.Project.hre_socket
                                     ~local_socket:local in
          let result =
            try
              let fd = connect_socket local in
              let conn = conn_of_fd fd in
              send_line conn "VERSIONS_DETAIL";
              let slots = parse_versions_detail conn in
              Unix.close fd;
              Ok (srv.Project.hre_name, slots)
            with
            | Failure m -> Error m
            | Unix_error (e, fn, _) ->
              Error (Printf.sprintf "%s: %s" fn (Unix.error_message e))
          in
          close_tunnel pid local;
          result
        in
        let node_results = List.map query_server servers in
        let errors = List.filter_map (function Error m -> Some m | Ok _ -> None) node_results in
        if errors <> [] then
          Error (String.concat "; " errors)
        else begin
          let nodes = List.filter_map (function Ok x -> Some x | Error _ -> None) node_results in
          let all_slots = List.concat_map (fun (_, slots) -> slots) nodes in
          if all_slots = [] then
            Printf.printf "(no registered functions)\n%!"
          else begin
            (* Detect cross-node drift: functions where impl_hash differs between nodes *)
            let drifted = Hashtbl.create 8 in
            if multi_node then begin
              let fn_names = List.sort_uniq compare (List.map (fun ds -> ds.ds_name) all_slots) in
              List.iter (fun fn_name ->
                let hashes = List.filter_map
                  (fun ds -> if ds.ds_name = fn_name then Some ds.ds_impl_hash else None)
                  all_slots in
                let unique = List.sort_uniq compare hashes in
                if List.length unique > 1 then Hashtbl.replace drifted fn_name ()
              ) fn_names
            end;
            let n_drifted = Hashtbl.length drifted in

            let col_node = if multi_node then 12 else 0 in
            let col_fn   = 42 in
            let col_hash = 14 in
            let col_ep   = 6 in
            let col_age  = 18 in
            let sep_w = col_fn + col_hash + col_ep + col_age + 20
                        + (if multi_node then col_node + 2 else 0) in

            if multi_node then
              Printf.printf "%-*s  %-*s  %-*s  %-*s  %-*s  %s\n"
                col_node "Node" col_fn "Function" col_hash "impl_hash"
                col_ep "epoch" col_age "activated" "signer"
            else
              Printf.printf "%-*s  %-*s  %-*s  %-*s  %s\n"
                col_fn "Function" col_hash "impl_hash" col_ep "epoch"
                col_age "activated" "signer";
            Printf.printf "%s\n" (String.make sep_w '-');

            List.iter (fun (node_name, slots) ->
              List.iter (fun ds ->
                let hash_short =
                  if String.length ds.ds_impl_hash >= 8
                  then String.sub ds.ds_impl_hash 0 8 ^ "..."
                  else ds.ds_impl_hash
                in
                let signer_short =
                  if ds.ds_signer = "(none)" then "(baseline)"
                  else if String.length ds.ds_signer >= 8
                       then String.sub ds.ds_signer 0 8 ^ "..."
                  else ds.ds_signer
                in
                let drift_marker =
                  if Hashtbl.mem drifted ds.ds_name then "  ← drift" else ""
                in
                if multi_node then
                  Printf.printf "%-*s  %-*s  %-*s  %-*d  %-*s  %s%s\n"
                    col_node node_name col_fn ds.ds_name
                    col_hash hash_short col_ep ds.ds_epoch
                    col_age (format_elapsed_ms ds.ds_activated_at)
                    signer_short drift_marker
                else
                  Printf.printf "%-*s  %-*s  %-*d  %-*s  %s\n"
                    col_fn ds.ds_name col_hash hash_short col_ep ds.ds_epoch
                    col_age (format_elapsed_ms ds.ds_activated_at) signer_short
              ) slots
            ) nodes;

            if n_drifted > 0 then begin
              Printf.printf "\n%d function(s) show cross-node drift (← marker).\n%!" n_drifted;
              Printf.printf "Run `forge deploy hot --env <name>` to bring nodes into sync.\n%!"
            end
          end;
          Ok ()
        end
      end

(* ─── Build step ─────────────────────────────────────────────────────────── *)

let build_so ~proj ~output : (string * string, string) result =
  let so_path = output ^ ".so" in
  let manifest_path = output ^ ".so.hcr_manifest" in
  let lib_env = Cmd_build.lib_path_env proj in
  let ffi_flags = Cmd_build.ffi_flags_of ~root:proj.Project.root proj in
  let entry = match proj.Project.entrypoint with
    | Some e -> Filename.concat proj.Project.root e
    | None ->
      let src = Filename.concat proj.Project.root "src" in
      Filename.concat src (proj.Project.name ^ ".march")
  in
  let cmd = Printf.sprintf
    "%smarch --compile --compile-so -o %s%s %s"
    lib_env (Filename.quote so_path) ffi_flags (Filename.quote entry)
  in
  let rc = Sys.command cmd in
  if rc <> 0 then Error (Printf.sprintf "build failed (exit %d)" rc)
  else if not (Sys.file_exists manifest_path) then
    Error (Printf.sprintf "no manifest at %s — rebuild with a hot-reload enabled compiler" manifest_path)
  else
    Ok (so_path, manifest_path)

(* ─── Entry point ────────────────────────────────────────────────────────── *)

(** [deploy ~so ~output ()] deploys a hot-reload artifact.
    When [so] is non-empty, it is used as the pre-built .so (the build step is
    skipped).  This allows cross-compiled artifacts (e.g. built in Docker for
    a remote Linux host) to be deployed without a local rebuild. *)
let deploy ?(output="") ?(so="") ?(grant_caps=([] : string list)) ?(no_cap_gate=false) ()
    : (unit, string) result =
  (* Load project *)
  match Project.load () with
  | Error m -> Error m
  | Ok proj ->
    match proj.Project.hot_reload with
    | None -> Error "no [hot-reload] section in forge.toml — add ssh_host, socket, public_key"
    | Some hr ->
      if hr.Project.hr_ssh_host = "" then
        Error "[hot-reload] ssh_host is required"
      else begin
        (* Load signing secret key *)
        match Cmd_hot_reload.read_sk_raw () with
        | Error m -> Error m
        | Ok sk ->
          let (so_path, manifest_path) =
            if so <> "" then
              (* Pre-built artifact supplied: manifest is <so>.hcr_manifest *)
              (so, so ^ ".hcr_manifest")
            else begin
              let out = if output <> "" then output
                else Filename.concat (Filename.concat proj.Project.root ".march")
                       (proj.Project.name ^ "_hot") in
              (out ^ ".so", out ^ ".so.hcr_manifest")
            end
          in
          let result =
            if so <> "" then begin
              (* Skip build — use pre-built .so *)
              if not (Sys.file_exists so_path) then
                Error (Printf.sprintf "pre-built .so not found: %s" so_path)
              else if not (Sys.file_exists manifest_path) then
                Error (Printf.sprintf "manifest not found: %s" manifest_path)
              else
                Ok (so_path, manifest_path)
            end else begin
              Printf.printf "Building hot-reload .so for %s...\n%!" proj.Project.name;
              build_so ~proj ~output:(if output <> "" then output
                else Filename.concat (Filename.concat proj.Project.root ".march")
                       (proj.Project.name ^ "_hot"))
            end
          in
          match result with
          | Error m -> Error m
          | Ok (so_path2, manifest_path2) ->
            (* Parse manifest *)
            match parse_manifest manifest_path2 with
            | Error m -> Error m
            | Ok manifest ->
              let signing_pubkey = Option.value ~default:"" hr.Project.hr_public_key in
              (* Phase 5: compute schema paths for compat checking.
                 new_schemas = <so>.schemas.json; old_schemas = last deployed schemas file.
                 After a successful deploy, write new schemas as the "prev" baseline. *)
              let new_schemas_path = so_path2 ^ ".schemas.json" in
              let prev_schemas_path = Filename.concat
                  (Filename.concat proj.Project.root ".march")
                  (proj.Project.name ^ "_hot.so.schemas.json.prev") in
              (* Phase 5C Part B, Task 4: capability-monotonicity baseline —
                 parallels prev_schemas_path exactly. *)
              let prev_manifest_path = Filename.concat
                  (Filename.concat proj.Project.root ".march")
                  (proj.Project.name ^ "_hot.so.hcr_manifest.prev") in
              let entry_path =
                match proj.Project.entrypoint with
                | Some e -> Filename.concat proj.Project.root e
                | None ->
                  Filename.concat (Filename.concat proj.Project.root "src")
                    (proj.Project.name ^ ".march")
              in
              let result2 =
                run
                  ~ssh_host:hr.Project.hr_ssh_host
                  ~remote_socket:hr.Project.hr_socket
                  ~signing_pubkey
                  ~sk
                  ~manifest
                  ~so_path:so_path2
                  ~old_schemas_path:prev_schemas_path
                  ~new_schemas_path
                  ~entry_path
                  ~old_manifest_path:prev_manifest_path
                  ~grant_caps
                  ~no_cap_gate
                  ()
              in
              (* After successful deploy, save new schemas as the baseline for next time *)
              (match result2 with
              | Ok _ when Sys.file_exists new_schemas_path ->
                (try
                  let ic = open_in new_schemas_path in
                  let content = In_channel.input_all ic in
                  close_in ic;
                  (* Ensure the .march directory exists before writing *)
                  let march_dir = Filename.dirname prev_schemas_path in
                  (if not (Sys.file_exists march_dir) then
                    try Unix.mkdir march_dir 0o755 with Unix_error _ -> ());
                  let oc = open_out prev_schemas_path in
                  output_string oc content;
                  close_out oc
                with Sys_error _ -> ())
              | _ -> ());
              (match result2 with
              | Ok _ -> save_manifest_baseline ~new_manifest_path:manifest_path2 ~prev_manifest_path
              | Error _ -> ());
              result2 |> Result.map ignore
      end

(* ─── Multi-env fan-out (Phase 7) ─────────────────────────────────────────── *)

(** Send PING to one server; returns true if PONG received. *)
let ping_server ~ssh_host ~remote_socket : bool =
  let local = fresh_sock "march_ping" in
  let (pid, _) = open_tunnel ~ssh_host ~remote_socket ~local_socket:local in
  let alive =
    try
      let fd = connect_socket local in
      let conn = conn_of_fd fd in
      send_line conn "PING";
      let r = recv_line conn in
      Unix.close fd;
      r = "PONG"
    with _ -> false
  in
  close_tunnel pid local;
  alive

(** Deploy the given pre-built artifact to one server entry; print status line.
    Pass [~provided_epoch] to use a pre-fetched cluster-wide epoch (Phase 10)
    instead of calling GET_EPOCH on the server. *)
let deploy_one ~(srv : Project.hot_reload_env) ~sk ~manifest ~so_path
    ~old_schemas_path ~new_schemas_path ?(entry_path="") ?(old_manifest_path="")
    ?(provided_epoch=0) ?(grant_caps=([] : string list)) ?(no_cap_gate=false) ()
    : (int, string) result =
  let label = Printf.sprintf "%s [%s]" srv.Project.hre_ssh_host srv.Project.hre_name in
  let pubkey = Option.value ~default:"" srv.Project.hre_public_key in
  Printf.printf "\n── %s\n%!" label;
  run
    ~ssh_host:srv.Project.hre_ssh_host
    ~remote_socket:srv.Project.hre_socket
    ~signing_pubkey:pubkey
    ~sk ~manifest ~so_path ~old_schemas_path ~new_schemas_path ~entry_path
    ~old_manifest_path
    ~provided_epoch
    ~grant_caps
    ~no_cap_gate
    ()

let save_schemas_baseline ~new_schemas_path ~prev_schemas_path =
  if Sys.file_exists new_schemas_path then
    (try
      let ic = open_in new_schemas_path in
      let content = In_channel.input_all ic in
      close_in ic;
      let march_dir = Filename.dirname prev_schemas_path in
      (if not (Sys.file_exists march_dir) then
         try Unix.mkdir march_dir 0o755 with Unix_error _ -> ());
      let oc = open_out prev_schemas_path in
      output_string oc content;
      close_out oc
    with Sys_error _ -> ())

(** [deploy_env ~env ~canary ~timeout_ms ~output ~so ()] deploys to one or more servers.
    - [env]: name of the [[hot-reload.env]] group (empty → use flat [hot-reload] config).
    - [canary]: if > 0, deploy to the first n servers, health-check, then roll out to rest.
    - [timeout_ms]: canary health-check window in milliseconds (default 30 000). *)
let deploy_env ?(output="") ?(so="") ?(env="") ?(canary=0) ?(timeout_ms=30000)
    ?(grant_caps=([] : string list)) ?(no_cap_gate=false) () : (unit, string) result =
  match Project.load () with
  | Error m -> Error m
  | Ok proj ->
    match proj.Project.hot_reload with
    | None -> Error "no [hot-reload] section in forge.toml — add ssh_host, socket, public_key"
    | Some hr ->
      let servers : Project.hot_reload_env list =
        if env = "" then
          if hr.Project.hr_ssh_host = "" then []
          else [{ Project.hre_name = "default";
                  hre_ssh_host = hr.Project.hr_ssh_host;
                  hre_socket = hr.Project.hr_socket;
                  hre_public_key = hr.Project.hr_public_key }]
        else
          List.filter (fun e -> e.Project.hre_name = env) hr.Project.hr_envs
      in
      if servers = [] then
        Error (if env = ""
               then "[hot-reload] ssh_host is required"
               else Printf.sprintf "no servers found for env '%s'" env)
      else begin
        match Cmd_hot_reload.read_sk_raw () with
        | Error m -> Error m
        | Ok sk ->
          let out_prefix =
            if output <> "" then output
            else Filename.concat (Filename.concat proj.Project.root ".march")
                   (proj.Project.name ^ "_hot")
          in
          let (so_path, manifest_path) =
            if so <> "" then (so, so ^ ".hcr_manifest")
            else (out_prefix ^ ".so", out_prefix ^ ".so.hcr_manifest")
          in
          let build_result =
            if so <> "" then begin
              if not (Sys.file_exists so_path) then
                Error (Printf.sprintf "pre-built .so not found: %s" so_path)
              else if not (Sys.file_exists manifest_path) then
                Error (Printf.sprintf "manifest not found: %s" manifest_path)
              else Ok (so_path, manifest_path)
            end else begin
              Printf.printf "Building hot-reload .so for %s...\n%!" proj.Project.name;
              build_so ~proj ~output:out_prefix
            end
          in
          match build_result with
          | Error m -> Error m
          | Ok (so_path2, manifest_path2) ->
            match parse_manifest manifest_path2 with
            | Error m -> Error m
            | Ok manifest ->
              let new_schemas_path = so_path2 ^ ".schemas.json" in
              let prev_schemas_path = out_prefix ^ ".so.schemas.json.prev" in
              (* Phase 5C Part B, Task 4: capability-monotonicity baseline. *)
              let prev_manifest_path = out_prefix ^ ".so.hcr_manifest.prev" in

              let entry_path =
                match proj.Project.entrypoint with
                | Some e -> Filename.concat proj.Project.root e
                | None ->
                  Filename.concat (Filename.concat proj.Project.root "src")
                    (proj.Project.name ^ ".march")
              in
              (* Phase 10: shared epoch — call GET_EPOCH once on the first server
                 so all nodes in this batch get the same epoch N, making epoch a
                 deploy-batch identifier rather than a per-node counter.
                 Single-server deploys skip this and let `run` call GET_EPOCH
                 itself (the old behavior). *)
              let shared_epoch =
                match servers with
                | _ :: _ :: _ ->
                  let first = List.hd servers in
                  let e = get_epoch_from_server
                    ~ssh_host:first.Project.hre_ssh_host
                    ~remote_socket:first.Project.hre_socket in
                  if e > 0 then begin
                    Printf.printf "==> Shared epoch %d (epoch master: %s)\n%!"
                      e first.Project.hre_ssh_host
                  end;
                  e
                | _ -> 0
              in

              let strategy = hr.Project.hr_strategy in
              let health_url = hr.Project.hr_health_check_url in

              (* Simultaneous: deploy to all servers without the rolling stop-on-failure gate.
                 NOTE: List.map is left-to-right sequential in OCaml — this is NOT parallel.
                 The distinction vs rolling is the absence of health-check stops, not concurrency. *)
              let simultaneous_deploy srvs =
                List.map (fun srv ->
                  (srv, deploy_one ~srv ~sk ~manifest ~so_path:so_path2
                          ~old_schemas_path:prev_schemas_path
                          ~new_schemas_path ~entry_path ~old_manifest_path:prev_manifest_path
                          ~provided_epoch:shared_epoch ~grant_caps ~no_cap_gate ())
                ) srvs
              in

              (* Rolling: one server at a time; optional HTTP health-check between. *)
              let rolling_deploy srvs =
                let results = ref [] in
                let stop = ref false in
                List.iter (fun srv ->
                  if not !stop then begin
                    let r = deploy_one ~srv ~sk ~manifest ~so_path:so_path2
                        ~old_schemas_path:prev_schemas_path
                        ~new_schemas_path ~entry_path ~old_manifest_path:prev_manifest_path
                        ~provided_epoch:shared_epoch ~grant_caps ~no_cap_gate () in
                    results := (srv, r) :: !results;
                    (match r with
                    | Error _ -> stop := true
                    | Ok _ ->
                      (match health_url with
                      | Some url ->
                        Printf.printf "  health check %s ... %!" url;
                        if http_health_check ~url ~timeout_s:10 then
                          Printf.printf "ok\n%!"
                        else begin
                          Printf.eprintf "failed!\n%!";
                          Printf.eprintf "  Health check failed after %s — stopping deploy.\n%!"
                            srv.Project.hre_ssh_host;
                          results := (srv, Error "health_check_failed") :: !results;
                          stop := true
                        end
                      | None -> ()))
                  end else
                    Printf.printf "  skipping %s (prior step failed)\n%!"
                      srv.Project.hre_ssh_host
                ) srvs;
                List.rev !results
              in

              let canary_n = if canary > 0 then min canary (List.length servers) else 0 in
              if canary_n > 0 then begin
                (* Canary flow: deploy to first n, health-check via PING, then roll out *)
                let n_total = List.length servers in
                let arr = Array.of_list servers in
                let canary_srvs = Array.to_list (Array.sub arr 0 canary_n) in
                let rest_srvs   = Array.to_list (Array.sub arr canary_n (n_total - canary_n)) in
                Printf.printf "==> Canary: deploying to %d/%d server(s)...\n%!" canary_n n_total;
                let canary_res = simultaneous_deploy canary_srvs in
                let canary_ok = List.for_all (fun (_, r) -> match r with Ok _ -> true | Error _ -> false) canary_res in
                if not canary_ok then
                  Error "canary deploy failed — remaining servers untouched"
                else begin
                  Printf.printf "\n==> Canary live. Monitoring for %.0fs (PING every 2s)...\n%!"
                    (float_of_int timeout_ms /. 1000.0);
                  let deadline = Unix.gettimeofday () +. (float_of_int timeout_ms /. 1000.0) in
                  let failed_host = ref "" in
                  while Unix.gettimeofday () < deadline && !failed_host = "" do
                    let remaining = deadline -. Unix.gettimeofday () in
                    Unix.sleepf (min 2.0 (max 0.0 remaining));
                    List.iter (fun (srv : Project.hot_reload_env) ->
                      if !failed_host = "" then begin
                        let alive = ping_server ~ssh_host:srv.Project.hre_ssh_host
                                                ~remote_socket:srv.Project.hre_socket in
                        if not alive then
                          failed_host := srv.Project.hre_ssh_host
                      end
                    ) canary_srvs
                  done;
                  if !failed_host <> "" then
                    Error (Printf.sprintf "canary health check failed: %s stopped responding — remaining servers untouched" !failed_host)
                  else begin
                    Printf.printf "\n==> Canary healthy. Rolling out to %d remaining server(s)...\n%!" (List.length rest_srvs);
                    let rest_res = simultaneous_deploy rest_srvs in
                    let failed = List.filter_map (fun (srv, r) -> match r with
                        | Error m -> Some (srv.Project.hre_ssh_host, m) | Ok _ -> None) rest_res in
                    if failed = [] then begin
                      save_schemas_baseline ~new_schemas_path ~prev_schemas_path;
                      save_manifest_baseline ~new_manifest_path:manifest_path2 ~prev_manifest_path;
                      Ok ()
                    end else
                      Error (Printf.sprintf "%d server(s) failed during rollout" (List.length failed))
                  end
                end
              end else if strategy = "simultaneous" then begin
                (* Simultaneous fan-out to all servers *)
                if List.length servers > 1 then
                  Printf.printf "==> Deploying to %d server(s) simultaneously (env: %s)...\n%!"
                    (List.length servers) env;
                let results = simultaneous_deploy servers in
                let failed = List.filter_map (fun (srv, r) -> match r with
                    | Error m -> Some (srv.Project.hre_ssh_host, m) | Ok _ -> None) results in
                if failed = [] then begin
                  save_schemas_baseline ~new_schemas_path ~prev_schemas_path;
                  save_manifest_baseline ~new_manifest_path:manifest_path2 ~prev_manifest_path;
                  Ok ()
                end else begin
                  Printf.eprintf "\nFailed servers:\n";
                  List.iter (fun (host, m) -> Printf.eprintf "  %s: %s\n" host m) failed;
                  Error (Printf.sprintf "%d/%d server(s) failed" (List.length failed) (List.length servers))
                end
              end else begin
                (* Rolling deploy (default): one server at a time with health check *)
                if List.length servers > 1 then
                  Printf.printf "==> Rolling deploy to %d server(s) (env: %s)%s...\n%!"
                    (List.length servers) env
                    (match health_url with Some u -> Printf.sprintf " with health check %s" u | None -> "");
                let results = rolling_deploy servers in
                let failed = List.filter_map (fun (srv, r) -> match r with
                    | Error m -> Some (srv.Project.hre_ssh_host, m) | Ok _ -> None) results in
                if failed = [] then begin
                  (* Only advance the schema baseline when all servers succeeded. *)
                  save_schemas_baseline ~new_schemas_path ~prev_schemas_path;
                  save_manifest_baseline ~new_manifest_path:manifest_path2 ~prev_manifest_path;
                  Ok ()
                end else begin
                  Printf.eprintf "\nFailed servers:\n";
                  List.iter (fun (host, m) -> Printf.eprintf "  %s: %s\n" host m) failed;
                  Error (Printf.sprintf "%d/%d server(s) failed" (List.length failed) (List.length servers))
                end
              end
      end
