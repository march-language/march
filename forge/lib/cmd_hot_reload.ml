(** forge hot-reload — ed25519 keypair management for forge deploy hot.

    Subcommands:
      forge hot-reload keygen      — generate keypair, save secret, print public key
      forge hot-reload show-pubkey — read saved secret, print public key
*)

let secret_key_path () =
  let home = match Sys.getenv_opt "HOME" with Some h -> h | None -> "." in
  Filename.concat home (Filename.concat ".march" "ed25519_secret.key")

(* Raw base64 decode for 64-byte keys (bypasses the pk_of_base64 32-byte check). *)
let b64_decode_raw (s : string) : bytes option =
  let tbl = Array.make 256 (-1) in
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  |> String.iteri (fun i c -> tbl.(Char.code c) <- i);
  let s = String.map (fun c -> if c = '=' then 'A' else c) s in
  let n = String.length s in
  if n mod 4 <> 0 then None
  else begin
    let out_n = n / 4 * 3 in
    let buf = Bytes.create out_n in
    let ok = ref true in
    for j = 0 to (n/4) - 1 do
      let v i = let x = tbl.(Char.code s.[j*4+i]) in if x < 0 then ok := false; x in
      let b0 = v 0 and b1 = v 1 and b2 = v 2 and b3 = v 3 in
      Bytes.set buf (j*3)   (Char.chr ((b0 lsl 2) lor (b1 lsr 4)));
      Bytes.set buf (j*3+1) (Char.chr (((b1 land 15) lsl 4) lor (b2 lsr 2)));
      Bytes.set buf (j*3+2) (Char.chr (((b2 land 3) lsl 6) lor b3))
    done;
    if not !ok then None else Some buf
  end

let bytes_to_b64 = March_ed25519.Ed25519.pk_to_base64

let read_sk_raw () : (bytes, string) result =
  let path = secret_key_path () in
  if not (Sys.file_exists path) then
    Error (Printf.sprintf "no secret key at %s — run: forge hot-reload keygen" path)
  else begin
    try
      let ic = open_in path in
      let line = input_line ic in
      close_in ic;
      match b64_decode_raw (String.trim line) with
      | None -> Error "secret key file is corrupt (bad base64)"
      | Some b ->
        if Bytes.length b < 64 then Error "secret key is too short (expected 64 bytes)"
        else Ok (Bytes.sub b 0 64)
    with Sys_error m -> Error m
  end

let save_sk (sk : bytes) : (unit, string) result =
  let path = secret_key_path () in
  let dir = Filename.dirname path in
  (try Unix.mkdir dir 0o700 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
  try
    let oc = open_out path in
    output_string oc (bytes_to_b64 sk);
    output_char oc '\n';
    close_out oc;
    Unix.chmod path 0o600;
    Ok ()
  with Sys_error m -> Error m

let keygen () : (unit, string) result =
  let (pk, sk) = March_ed25519.Ed25519.keygen () in
  match save_sk sk with
  | Error m -> Error m
  | Ok () ->
    let pk_b64 = March_ed25519.Ed25519.pk_to_base64 pk in
    let pk_hex = March_ed25519.Ed25519.pk_to_hex pk in
    Printf.printf "Generated ed25519 keypair.\n";
    Printf.printf "Secret key saved to: %s\n" (secret_key_path ());
    Printf.printf "\nPublic key (base64, for forge.toml [hot-reload]):\n  %s\n" pk_b64;
    Printf.printf "\nPublic key (hex, for --signing-pubkey compiler flag):\n  %s\n" pk_hex;
    Printf.printf "\nAdd to forge.toml:\n";
    Printf.printf "  [hot-reload]\n";
    Printf.printf "  public_key = \"%s\"\n" pk_b64;
    Ok ()

let show_pubkey () : (unit, string) result =
  match read_sk_raw () with
  | Error m -> Error m
  | Ok sk ->
    (* In ed25519, the public key is the last 32 bytes of the 64-byte secret key. *)
    let pk = Bytes.sub sk 32 32 in
    let pk_b64 = March_ed25519.Ed25519.pk_to_base64 pk in
    let pk_hex = March_ed25519.Ed25519.pk_to_hex pk in
    Printf.printf "Public key (base64): %s\n" pk_b64;
    Printf.printf "Public key (hex):    %s\n" pk_hex;
    Ok ()

let run_keygen () = match keygen () with
  | Ok () -> ()
  | Error m -> Printf.eprintf "error: %s\n" m; exit 1

let run_show_pubkey () = match show_pubkey () with
  | Ok () -> ()
  | Error m -> Printf.eprintf "error: %s\n" m; exit 1

(* ─── forge hot-reload init ──────────────────────────────────────────────── *)

(** Analyse git history for recently-modified .march files and suggest which
    modules to exclude from the hot-reload boundary (rarely-changed → safe to
    inline; frequently-changed → keep reloadable). *)
let init ?(lookback_days=90) ?(threshold=3) () : (unit, string) result =
  (* Use git log to collect changed files over the lookback window. *)
  let cmd =
    Printf.sprintf
      "git log --name-only --since=\"%d days ago\" --diff-filter=M \
       --pretty=format: -- '*.march' 2>/dev/null"
      lookback_days
  in
  let ic = Unix.open_process_in cmd in
  let counts : (string, int) Hashtbl.t = Hashtbl.create 32 in
  (try while true do
     let line = String.trim (input_line ic) in
     if line <> "" && Filename.check_suffix line ".march" then begin
       (* Convert path to a module name guess: strip path prefix and .march suffix,
          replace path sep with '.' and capitalise each component. *)
       let base = Filename.basename line in
       let name = Filename.chop_suffix base ".march" in
       (* Capitalise first letter to match March module naming. *)
       let mod_name =
         if name = "" then name
         else String.make 1 (Char.uppercase_ascii name.[0])
              ^ String.sub name 1 (String.length name - 1)
       in
       let prev = try Hashtbl.find counts mod_name with Not_found -> 0 in
       Hashtbl.replace counts mod_name (prev + 1)
     end
   done with End_of_file -> ());
  (match Unix.close_process_in ic with _ -> ());
  (* Sort by commit count. *)
  let entries = Hashtbl.fold (fun k v acc -> (k, v) :: acc) counts [] in
  let sorted = List.sort (fun (_, a) (_, b) -> compare a b) entries in
  let exclude = List.filter (fun (_, n) -> n < threshold) sorted in
  let keep    = List.filter (fun (_, n) -> n >= threshold) sorted in
  Printf.printf "Analyzing git history (last %d days)...\n\n" lookback_days;
  if exclude = [] && keep = [] then begin
    Printf.printf "(No .march files found in git history — nothing to suggest.)\n";
    Ok ()
  end else begin
    if exclude <> [] then begin
      Printf.printf "Modules changed 0-%d times (suggest excluding):\n" (threshold - 1);
      List.iter (fun (name, n) ->
        Printf.printf "  %-40s (%d commit%s)\n" name n (if n = 1 then "" else "s")
      ) exclude;
      Printf.printf "\n"
    end;
    if keep <> [] then begin
      Printf.printf "Modules changed %d+ times (keep reloadable):\n" threshold;
      List.iter (fun (name, n) ->
        Printf.printf "  %-40s (%d commit%s)\n" name n (if n = 1 then "" else "s")
      ) (List.rev keep);   (* show most-changed first *)
      Printf.printf "\n"
    end;
    if exclude <> [] then begin
      Printf.printf "Add to forge.toml:\n";
      Printf.printf "  [hot-reload]\n";
      Printf.printf "  exclude = [%s]\n"
        (String.concat ", "
           (List.map (fun (name, _) -> Printf.sprintf "\"%s\"" name) exclude))
    end;
    Ok ()
  end

let run_init ?(lookback_days=90) ?(threshold=3) () =
  match init ~lookback_days ~threshold () with
  | Ok () -> ()
  | Error m -> Printf.eprintf "error: %s\n" m; exit 1

(* ─── forge hot-reload keygen --rotate ───────────────────────────────────── *)

(** Generate a versioned keypair file (ed25519_secret_v<N>.key) and print
    rotation instructions. *)
let keygen_rotate () : (unit, string) result =
  (* Find the next version number by scanning existing versioned key files. *)
  let home = match Sys.getenv_opt "HOME" with Some h -> h | None -> "." in
  let march_dir = Filename.concat home ".march" in
  let next_ver =
    if not (Sys.file_exists march_dir) then 2
    else begin
      let dir = Unix.opendir march_dir in
      let max_ver = ref 1 in
      (try while true do
         let entry = Unix.readdir dir in
         (* Pattern: ed25519_secret_v<N>.key *)
         let prefix = "ed25519_secret_v" in
         let suffix = ".key" in
         if String.length entry > String.length prefix + String.length suffix
            && String.sub entry 0 (String.length prefix) = prefix then begin
           let mid = String.sub entry (String.length prefix)
                       (String.length entry - String.length prefix
                        - String.length suffix) in
           match int_of_string_opt mid with
           | Some n when n > !max_ver -> max_ver := n
           | _ -> ()
         end
       done with End_of_file -> ());
      Unix.closedir dir;
      !max_ver + 1
    end
  in
  let (pk, sk) = March_ed25519.Ed25519.keygen () in
  let key_path =
    Filename.concat march_dir
      (Printf.sprintf "ed25519_secret_v%d.key" next_ver)
  in
  (* Save the versioned key file. *)
  (try Unix.mkdir march_dir 0o700 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
  (try
    let oc = open_out key_path in
    output_string oc (bytes_to_b64 sk);
    output_char oc '\n';
    close_out oc;
    Unix.chmod key_path 0o600
  with Sys_error m -> failwith m);
  let pk_b64 = March_ed25519.Ed25519.pk_to_base64 pk in
  let pk_hex = March_ed25519.Ed25519.pk_to_hex pk in
  Printf.printf "New keypair generated: %s\n" key_path;
  Printf.printf "New public key (base64): %s\n\n" pk_b64;
  Printf.printf "To complete rotation:\n";
  Printf.printf "  1. Update forge.toml: public_key = \"%s\"\n" pk_b64;
  Printf.printf "  2. Update --signing-pubkey in your build:\n";
  Printf.printf "       forge build --release  (rebuilds with new pubkey)\n";
  Printf.printf "  3. Deploy the new server binary (standard restart)\n";
  Printf.printf "  4. Activate the new key for future deploys:\n";
  Printf.printf "       forge hot-reload use-key %s\n\n" key_path;
  Printf.printf "Public key (hex, for --signing-pubkey flag):\n  %s\n" pk_hex;
  Ok ()

(** Switch `forge deploy hot` to sign with the key at [path]. *)
let use_key (path : string) : (unit, string) result =
  if not (Sys.file_exists path) then
    Error (Printf.sprintf "key file not found: %s" path)
  else begin
    (* Read the key to validate it before symlinking. *)
    match (try let ic = open_in path in
               let line = String.trim (input_line ic) in
               close_in ic;
               b64_decode_raw line
           with Sys_error m -> failwith m) with
    | None -> Error "key file is corrupt (bad base64)"
    | Some b when Bytes.length b < 64 -> Error "key too short (expected 64 bytes)"
    | Some _ ->
      (* Copy to the canonical secret_key_path so subsequent deploys use it. *)
      let dest = secret_key_path () in
      (try
        let ic = open_in_bin path in
        let content = In_channel.input_all ic in
        close_in ic;
        let oc = open_out dest in
        output_string oc content;
        close_out oc;
        Unix.chmod dest 0o600
      with Sys_error m -> failwith m);
      Printf.printf "Active key updated → %s\n" dest;
      Ok ()
  end

let run_keygen_rotate () =
  match keygen_rotate () with
  | Ok () -> ()
  | Error m -> Printf.eprintf "error: %s\n" m; exit 1

let run_use_key path =
  match use_key path with
  | Ok () -> ()
  | Error m -> Printf.eprintf "error: %s\n" m; exit 1
