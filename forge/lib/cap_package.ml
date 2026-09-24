(* Per-package capability sets and version-to-version diffs.
   See cap_package.mli for why this exists alongside the whole-binary audit. *)

type t = { name : string; caps : string list }

type change = Gained of string list | Lost of string list | Unchanged

(* ── computing a package's capability set ──────────────────────────── *)

let read_all path =
  let ic = open_in path in
  let s = really_input_string ic (in_channel_length ic) in
  close_in ic;
  s

(* Minimal extraction of {"caps":["a","b"]} — the payload is emitted by
   `march caps` and is a flat string array, so a full JSON parse would buy
   nothing over scanning quoted runs. *)
let parse_caps_json s =
  match String.index_opt s '[' with
  | None -> []
  | Some lb ->
    let rb = try String.index_from s lb ']' with Not_found -> String.length s in
    let body = String.sub s (lb + 1) (rb - lb - 1) in
    String.split_on_char ',' body
    |> List.filter_map (fun tok ->
           let t = String.trim tok in
           let n = String.length t in
           if n >= 2 && t.[0] = '"' && t.[n - 1] = '"' then
             Some (String.sub t 1 (n - 2))
           else None)

let of_package ~root ~env_prefix =
  let files = Cmd_build.find_march_files (Filename.concat root "lib") in
  if files = [] then Error (Printf.sprintf "%s: no .march files under lib/" root)
  else begin
    let out = Filename.temp_file "cap_pkg" ".json" in
    let err = Filename.temp_file "cap_pkg" ".err" in
    (* [env_prefix] is Cmd_build.lib_path_env's output: a complete shell
       assignment prefix (PATH=... MARCH_LIB_PATH=...), used verbatim exactly
       as Cmd_build.check_all uses it.  Parsing a value out of it is wrong —
       the first `=` belongs to PATH, not MARCH_LIB_PATH, and the paths are
       single-quoted. *)
    let cmd =
      Printf.sprintf "%smarch caps %s > %s 2> %s" env_prefix
        (String.concat " " (List.map Filename.quote files))
        (Filename.quote out) (Filename.quote err)
    in
    let rc = Sys.command cmd in
    let stdout_s = try read_all out with Sys_error _ -> "" in
    let stderr_s = try read_all err with Sys_error _ -> "" in
    (try Sys.remove out with Sys_error _ -> ());
    (try Sys.remove err with Sys_error _ -> ());
    if rc <> 0 then
      (* Never fall back to "no capabilities": an unanalyzable package whose
         set is reported as empty reads as a pure package, which is the
         under-report this whole design exists to avoid. *)
      Error
        (Printf.sprintf "%s: capability set could not be computed (march caps \
                         exited %d)%s"
           (Filename.basename root) rc
           (if String.trim stderr_s = "" then ""
            else "\n" ^ String.trim stderr_s))
    else
      Ok { name = Filename.basename root; caps = parse_caps_json stdout_s }
  end

(* ── the toolchain behind `march caps` ─────────────────────────────── *)

(* Run [cmd] through the shell, returning (exit code, stdout, stderr). *)
let run_capture cmd_body =
  let out = Filename.temp_file "cap_probe" ".out" in
  let err = Filename.temp_file "cap_probe" ".err" in
  let rc =
    Sys.command
      (Printf.sprintf "%s > %s 2> %s" cmd_body (Filename.quote out) (Filename.quote err))
  in
  let o = try read_all out with Sys_error _ -> "" in
  let e = try read_all err with Sys_error _ -> "" in
  (try Sys.remove out with Sys_error _ -> ());
  (try Sys.remove err with Sys_error _ -> ());
  (rc, o, e)

let resolve_march ~toolchain_prefix =
  match run_capture (Printf.sprintf "%ssh -c 'command -v march'" toolchain_prefix) with
  | 0, o, _ when String.trim o <> "" -> Some (String.trim o)
  | _ -> None

let march_version ~toolchain_prefix =
  match run_capture (Printf.sprintf "%smarch --version" toolchain_prefix) with
  | 0, o, _ when String.trim o <> "" -> Some (String.trim o)
  | _ -> None

let realpath p = try Unix.realpath p with Unix.Unix_error _ -> p

let compiler_identity ~toolchain_prefix =
  let parts =
    match resolve_march ~toolchain_prefix with
    | None -> [ "march-unresolved" ]
    | Some p ->
      let real = realpath p in
      let digest = try Digest.to_hex (Digest.file real) with Sys_error _ -> "unreadable" in
      [ p; real; digest ]
  in
  (* The executable's digest alone misses two ways the SAME binary can run a
     different compiler: a wrapper script that execs through
     ~/.march/current (its bytes never change when the active toolchain
     does), and a stdlib picked up from MARCH_STDLIB. *)
  let global = Option.value ~default:"" (try Toolchain.global_version () with _ -> None) in
  let stdlib = Option.value ~default:"" (Sys.getenv_opt "MARCH_STDLIB") in
  Digest.to_hex (Digest.string (String.concat "\x00" (parts @ [ global; stdlib ])))

(* `march caps` first shipped in 0.3.0 (nightly-20260805 for nightlies). *)
let caps_min_version = "0.3.0 (or nightly-20260805)"

let probe_caps_support ~toolchain_prefix =
  let dir = Filename.temp_dir "forge_caps_probe" "" in
  let file = Filename.concat dir "forge_caps_probe.march" in
  let oc = open_out file in
  output_string oc "mod ForgeCapsProbe do\n  fn probe() : Int do 1 end\nend\n";
  close_out oc;
  (* No MARCH_LIB_PATH: the probe must not depend on any package's tree, so
     a failure here is about the compiler, never about a dependency. *)
  let rc, o, e =
    run_capture
      (Printf.sprintf "%sMARCH_LIB_PATH= march caps %s" toolchain_prefix
         (Filename.quote file))
  in
  (try Sys.remove file with Sys_error _ -> ());
  (try Unix.rmdir dir with Unix.Unix_error _ -> ());
  (* Keyed on the contract [of_package] relies on — exit 0 and a JSON object
     with a "caps" field on stdout — not on the wording of an error message.
     A compiler that predates the subcommand takes `caps` as a file name and
     fails; one that supports it answers {"caps":[]} for this module. *)
  let has_caps_json =
    let needle = "\"caps\"" in
    let n = String.length o and m = String.length needle in
    let rec at i = i + m <= n && (String.sub o i m = needle || at (i + 1)) in
    String.contains o '{' && at 0
  in
  if rc = 0 && has_caps_json then Ok ()
  else begin
    let where =
      match resolve_march ~toolchain_prefix with
      | Some p -> p
      | None -> "(no `march` found on PATH)"
    in
    let version =
      match march_version ~toolchain_prefix with
      | Some v -> v
      | None -> "version unknown"
    in
    let detail =
      let s = String.trim (if String.trim e <> "" then e else o) in
      let lines = String.split_on_char '\n' s in
      let first = List.filteri (fun i _ -> i < 3) lines in
      if s = "" then "" else "\n  " ^ String.concat "\n  " first
    in
    Error
      (Printf.sprintf
         "the March toolchain this audit runs does not support `march caps`, \
          which `forge audit --inferred` needs.\n\
          toolchain: %s (%s)\n\
          `march caps` first shipped in march %s. Install a newer toolchain \
          (`forge toolchain install`, then `forge toolchain use`) or update \
          the project's .march-version pin.\n\
          A trivial module run through `march caps` exited %d%s"
         where version caps_min_version rc
         (if detail = "" then " with no output." else ":" ^ detail))
  end

(* ── diffing two versions ──────────────────────────────────────────── *)

(* [covered_by set c] — is [c] already implied by something in [set]?
   Subsumption, not equality: moving from IO.NetConnect to the broader
   IO.Network is a widening, while narrowing to a sub-capability is not. *)
let covered_by set c =
  List.exists (fun s -> March_caps.Cap_lattice.cap_subsumes s c) set

let diff ~old_caps ~new_caps =
  let gained = List.filter (fun c -> not (covered_by old_caps c)) new_caps in
  let lost = List.filter (fun c -> not (covered_by new_caps c)) old_caps in
  match (gained, lost) with
  | [], [] -> [ Unchanged ]
  | g, [] -> [ Gained g ]
  | [], l -> [ Lost l ]
  | g, l -> [ Gained g; Lost l ]

let widens changes =
  List.exists (function Gained (_ :: _) -> true | _ -> false) changes

let format_change ~name ~old_version ~new_version changes =
  if changes = [ Unchanged ] then None
  else begin
    let b = Buffer.create 128 in
    Buffer.add_string b
      (Printf.sprintf "%s %s -> %s\n" name old_version new_version);
    List.iter
      (function
        | Gained (_ :: _ as g) ->
          Buffer.add_string b
            (Printf.sprintf "  caps: + %s\n" (String.concat ", " g))
        | Lost (_ :: _ as l) ->
          Buffer.add_string b
            (Printf.sprintf "  caps: - %s\n" (String.concat ", " l))
        | _ -> ())
      changes;
    Some (Buffer.contents b)
  end
