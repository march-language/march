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
