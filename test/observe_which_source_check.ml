(* Observe R10: WHICH and SOURCE across a real hot deploy.

     observe_which_source_check <march-exe> <v1.march> <v2.march>

   Builds test/native/observe_which_source_v1.march as a --hot-reload node with
   a fresh deploy key, and _v2 as a --compile-so patch, starts the node, and
   checks what it says about Billing.price before and after
   `Cmd_deploy_hot.run` (what `forge deploy hot` runs) switches it to the
   patch: WHICH's hash and SOURCE's text, the signature and policy gates, the
   names that must not reach a path, the CAS_PUT kind:source guards, and the
   audit log.

   The node's HOME is not the builder's: the baseline's source reaches it by a
   copy (a node built on the machine it runs on), and the patch's only through
   the deploy's upload.  The program asks for its own source through
   Recon.source until the policy lets it, which covers the in-process path.

   One "ok: ..." / "FAIL: ..." line per check, diffed against a golden. *)

open Yojson.Safe.Util

(* [member] that reads a missing object (an error reply's data) as null. *)
let member k j = match j with `Assoc _ -> member k j | _ -> `Null

let failures = ref 0
let check name ok detail =
  if ok then Printf.printf "ok: %s\n%!" name
  else begin incr failures; Printf.printf "FAIL: %s (%s)\n%!" name detail end

let read_file f =
  let ic = open_in_bin f in
  Fun.protect ~finally:(fun () -> close_in ic)
    (fun () -> really_input_string ic (in_channel_length ic))

let write_file f s =
  let oc = open_out_bin f in
  output_string oc s;
  close_out oc

let contains s sub =
  let n = String.length s and m = String.length sub in
  let rec go i = i + m <= n && (String.sub s i m = sub || go (i + 1)) in
  go 0

let now_ms () = int_of_float (Unix.gettimeofday () *. 1000.)

let sh fmt = Printf.ksprintf (fun c -> Sys.command c) fmt

(* One line out, everything the socket sends back until it closes. *)
let raw_exchange sock line =
  let fd = Unix.socket Unix.PF_UNIX Unix.SOCK_STREAM 0 in
  Fun.protect ~finally:(fun () -> Unix.close fd) (fun () ->
      Unix.setsockopt_float fd Unix.SO_RCVTIMEO 15.;
      Unix.connect fd (Unix.ADDR_UNIX sock);
      let req = line ^ "\n" in
      ignore (Unix.write_substring fd req 0 (String.length req));
      let buf = Buffer.create 4096 and chunk = Bytes.create 65536 in
      let rec loop () =
        match Unix.read fd chunk 0 (Bytes.length chunk) with
        | 0 -> ()
        | n -> Buffer.add_subbytes buf chunk 0 n; loop ()
        | exception Unix.Unix_error (Unix.ECONNRESET, _, _) -> ()
      in
      loop ();
      String.trim (Buffer.contents buf))

let query sock line = Yojson.Safe.from_string (raw_exchange sock line)
let error j = member "error" j |> to_string_option
let data j = member "data" j

(* Reload-socket verbs answer one line (CAS_PUT's body is not sent here:
   every case below is refused before READY, or never reaches it). *)
let reload sock line =
  let fd = Unix.socket Unix.PF_UNIX Unix.SOCK_STREAM 0 in
  Fun.protect ~finally:(fun () -> Unix.close fd) (fun () ->
      Unix.setsockopt_float fd Unix.SO_RCVTIMEO 15.;
      Unix.connect fd (Unix.ADDR_UNIX sock);
      let req = line ^ "\n" in
      ignore (Unix.write_substring fd req 0 (String.length req));
      let buf = Buffer.create 64 and one = Bytes.create 1 in
      let rec loop () =
        match Unix.read fd one 0 1 with
        | 0 -> ()
        | _ -> if Bytes.get one 0 <> '\n' then (Buffer.add_bytes buf one; loop ())
        | exception Unix.Unix_error _ -> ()
      in
      loop ();
      String.trim (Buffer.contents buf))

let nonce_counter = ref 0
let fresh_nonce () =
  incr nonce_counter;
  Printf.sprintf "%016x%016x" (now_ms ()) !nonce_counter

let sign sk verb fields =
  let nonce = fresh_nonce () in
  let body = String.concat " "
      (Printf.sprintf "nonce:%s" nonce :: Printf.sprintf "not_after_ms:%d" (now_ms () + 30_000) :: fields) in
  let s = March_ed25519.Ed25519.(sig_to_base64 (sign_str (verb ^ " " ^ body) sk)) in
  Printf.sprintf "%s %s %s" verb s body

let wait_line file text =
  let deadline = Unix.gettimeofday () +. 90. in
  let rec go () =
    let s = try read_file file with Sys_error _ -> "" in
    if contains s text then s
    else if Unix.gettimeofday () > deadline then (prerr_endline ("never printed " ^ text ^ ":\n" ^ s); exit 1)
    else (Unix.sleepf 0.05; go ())
  in
  go ()

let audit_lines log =
  (try read_file log with Sys_error _ -> "")
  |> String.split_on_char '\n'
  |> List.filter (fun l -> l <> "")
  |> List.map Yojson.Safe.from_string
  |> List.filter (fun j -> member "type" j = `String "debug" && member "verb" j = `String "SOURCE")

let () =
  match Array.to_list Sys.argv |> List.tl with
  | [ march; v1; v2 ] ->
    let march = if Filename.is_relative march then Filename.concat (Sys.getcwd ()) march else march in
    let tmp = Printf.sprintf "/tmp/ws%d" (Unix.getpid ()) in
    let home = tmp ^ "/home" and node_home = tmp ^ "/nodehome" in
    ignore (sh "rm -rf %s && mkdir -p %s/p1 %s/p2 %s %s" tmp tmp tmp home node_home);
    let policy = tmp ^ "/policy" and log = tmp ^ "/audit" in
    write_file policy "";
    let pk, sk = March_ed25519.Ed25519.keygen () in
    let pk_b64 = March_ed25519.Ed25519.pk_to_base64 pk in
    Unix.putenv "HOME" home;
    (* The operator's policy file, which `forge deploy hot` reads to decide
       whether to upload source and the node reads to decide whether to serve it. *)
    Unix.putenv "MARCH_DEBUG_POLICY" policy;

    (* The node: built here, its source kept in the builder's CAS. *)
    ignore (sh "cp %s %s/p1/app.march && cp %s %s/p2/app.march" v1 tmp v2 tmp);
    let build dir flags out =
      let rc = sh "cd %s && %s --compile --hot-reload Main %s -o %s app.march > build.log 2>&1" dir march flags out in
      if rc <> 0 then (prerr_endline (read_file (dir ^ "/build.log")); exit 1) in
    build (tmp ^ "/p1") ("--signing-pubkey " ^ pk_b64) "node.bin";
    (* The baseline's source goes to the node's machine, as it would with a build on the node. *)
    ignore (sh "mkdir -p %s/.march/cas && cp -R %s/.march/cas/sources %s/.march/cas/" node_home home node_home);
    build (tmp ^ "/p2") "--compile-so" "v2.so";
    check "the patch build wrote a manifest" (Sys.file_exists (tmp ^ "/p2/v2.so.hcr_manifest")) "no manifest";

    let reload_sock = tmp ^ "/n.sock" in
    let sock = reload_sock ^ ".observe" in
    let out = tmp ^ "/node.out" in
    let inherited = Unix.environment () |> Array.to_list
                    |> List.filter (fun e -> not (String.length e >= 5 && String.sub e 0 5 = "HOME=")) in
    let env = Array.append (Array.of_list inherited)
        [| "HOME=" ^ node_home; "MARCH_HOT_RELOAD_SOCKET=" ^ reload_sock;
           "MARCH_DEBUG_POLICY=" ^ policy; "MARCH_AUDIT_LOG=" ^ log |] in
    let out_fd = Unix.openfile out [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC ] 0o644 in
    let node = Unix.create_process_env (tmp ^ "/p1/node.bin") [| tmp ^ "/p1/node.bin" |] env
        Unix.stdin out_fd out_fd in
    Unix.close out_fd;
    let finish () =
      (try Unix.kill node Sys.sigterm with Unix.Unix_error _ -> ());
      (try ignore (Unix.waitpid [] node) with Unix.Unix_error _ -> ());
      ignore (sh "rm -rf %s" tmp);
      if !failures > 0 then exit 1 in
    let banner = wait_line out "ready" in

    let price = "Billing.price" and label = "Billing.label" in
    let which n = query sock ("WHICH " ^ n) in
    let source ?(extra = []) n = query sock (sign sk "SOURCE" (("name:" ^ n) :: extra)) in
    let hash_of j =
      match data j with
      | `Assoc _ as d -> member "impl_hash" d |> to_string_option |> Option.value ~default:""
      | _ -> "" in

    (* -- the verbs and their tiers -- *)
    let verbs = query sock "HELP" |> data |> member "verbs" |> to_list in
    let tier v = List.find_map (fun e ->
        if member "name" e = `String v then to_string_option (member "tier" e) else None) verbs in
    check "HELP: WHICH is observe tier, SOURCE debug tier"
      (tier "WHICH" = Some "observe" && tier "SOURCE" = Some "debug")
      (Option.value ~default:"-" (tier "WHICH") ^ "/" ^ Option.value ~default:"-" (tier "SOURCE"));

    (* -- WHICH before the deploy -- *)
    let w1 = which price in
    let h1 = hash_of w1 in
    check "WHICH: a 64-hex impl_hash" (String.length h1 = 64) (Yojson.Safe.to_string w1);
    check "WHICH: the baseline is running (not patched, activated_at 0)"
      (data w1 |> member "patched" = `Bool false
       && data w1 |> member "baseline_hash" = `String h1
       && data w1 |> member "activated_at_ms" = `Int 0)
      (Yojson.Safe.to_string w1);
    let hl1 = hash_of (which label) in
    check "WHICH: a different function has its own hash" (String.length hl1 = 64 && hl1 <> h1) hl1;
    check "WHICH of a name that is not a slot: not_found" (error (which "Billing.nothing") = Some "not_found") "";
    check "WHICH with no name: bad_args" (error (query sock "WHICH") = Some "bad_args") "";
    check "WHICH with a path in the name: bad_args"
      (error (which "../../etc/passwd") = Some "bad_args") "";
    check "the program saw the same hash in-process (Recon.which)"
      (contains banner ("which " ^ h1 ^ " patched=no")) banner;
    check "Recon.which of a name that is not a slot: not_found"
      (contains banner "which nothing: not_found") banner;

    (* -- SOURCE: the gates -- *)
    let r = source price in
    check "SOURCE with no policy entry: policy" (error r = Some "policy") (Yojson.Safe.to_string r);
    let _, other = March_ed25519.Ed25519.keygen () in
    let r = query sock (sign other "SOURCE" [ "name:" ^ price ]) in
    check "SOURCE signed by another key: bad_signature" (error r = Some "bad_signature") (Yojson.Safe.to_string r);
    let r = query sock ("SOURCE AAAA nonce:" ^ fresh_nonce () ^ " not_after_ms:" ^ string_of_int (now_ms () + 30000)
                        ^ " name:" ^ price) in
    check "SOURCE with a garbage signature: bad_signature" (error r = Some "bad_signature") (Yojson.Safe.to_string r);
    let r = query sock ("SOURCE local name:" ^ price) in
    check "SOURCE 'local' on the socket is not a way past the signature: refused"
      (error r = Some "bad_args") (Yojson.Safe.to_string r);
    let signed = sign sk "SOURCE" [ "name:" ^ price ] in
    let tampered = Str.global_replace (Str.regexp_string price) label signed in
    let r = query sock tampered in
    check "SOURCE with its name changed after signing: bad_signature"
      (error r = Some "bad_signature") (Yojson.Safe.to_string r);

    write_file policy "# debug verbs this node allows\nSOURCE\n";

    (* -- SOURCE before the deploy: the old body -- *)
    let s1 = source price in
    let text1 = data s1 |> member "source" |> to_string_option |> Option.value ~default:"" in
    check "SOURCE: the baseline's body"
      (error s1 = None && contains text1 "qty * 10" && not (contains text1 "qty * 12")
       && data s1 |> member "impl_hash" = `String h1)
      (Yojson.Safe.to_string s1);
    check "SOURCE: the declaration only, not its neighbours"
      (contains text1 "fn price(" && not (contains text1 "fn label(")) text1;
    let ls = source label in
    check "SOURCE: another function's own text"
      (match data ls |> member "source" with
       | `String t -> contains t "fn label(" && not (contains t "fn price(")
       | _ -> false) (Yojson.Safe.to_string ls);
    let line = sign sk "SOURCE" [ "name:" ^ price ] in
    ignore (query sock line);
    check "SOURCE: the same signed request again: replay" (error (query sock line) = Some "replay") "";
    check "SOURCE of a name that is not a slot: not_found"
      (error (source "Billing.nothing") = Some "not_found") "";
    check "SOURCE of a path: bad_args" (error (source "../../etc/passwd") = Some "bad_args") "";
    check "SOURCE of an absolute path: bad_args" (error (source "/etc/passwd") = Some "bad_args") "";
    check "SOURCE with no name: bad_args" (error (query sock (sign sk "SOURCE" [])) = Some "bad_args") "";
    check "SOURCE with a second name: bad_args"
      (error (source ~extra:[ "name:" ^ label ] price) = Some "bad_args") "";
    check "SOURCE with another argument: bad_args"
      (error (source ~extra:[ "pid:1" ] price) = Some "bad_args") "";
    let in_proc = wait_line out "source done" in
    check "Recon.source in-process, once the policy allows it: the baseline's body"
      (contains in_proc "in-process source: fn price(" && contains in_proc "qty * 10") in_proc;

    (* -- CAS_PUT kind:source: what the reload socket refuses -- *)
    let zero = String.make 64 '0' in
    check "CAS_PUT kind:source: an upper-case hash is refused"
      (reload reload_sock ("CAS_PUT " ^ String.uppercase_ascii (String.make 64 'a') ^ " 5 kind:source") = "ERR bad_format") "";
    check "CAS_PUT kind:source: a short hash is refused"
      (reload reload_sock "CAS_PUT abc 5 kind:source" = "ERR bad_format") "";
    check "CAS_PUT kind:source: a text over the limit is refused"
      (reload reload_sock ("CAS_PUT " ^ zero ^ " 262145 kind:source") = "ERR bad_format") "";
    check "CAS_PUT kind:source: an empty text is refused"
      (reload reload_sock ("CAS_PUT " ^ zero ^ " 0 kind:source") = "ERR bad_format") "";
    check "CAS_PUT kind:source stored nothing as an artifact"
      (reload reload_sock ("CAS_CHECK " ^ zero) = "MISSING") "";

    (* -- The hot deploy: what `forge deploy hot` runs -- *)
    Unix.chdir (tmp ^ "/p2");
    let so = tmp ^ "/p2/v2.so" in
    let deployed =
      match March_forge.Cmd_deploy_hot.parse_manifest (so ^ ".hcr_manifest") with
      | Error m -> prerr_endline ("manifest: " ^ m); Error m
      | Ok manifest ->
        flush stdout;
        let saved = Unix.dup Unix.stdout in
        let log_fd = Unix.openfile (tmp ^ "/deploy.log") [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC ] 0o644 in
        Unix.dup2 log_fd Unix.stdout;
        let r =
          try
            March_forge.Cmd_deploy_hot.run ~tunnel:false ~ssh_host:"local" ~remote_socket:reload_sock
              ~signing_pubkey:pk_b64 ~sk ~manifest ~so_path:so ~old_schemas_path:""
              ~new_schemas_path:(so ^ ".schemas.json") ~old_manifest_path:"" ~grant_caps:[] ()
          with Failure m -> Error m | Unix.Unix_error (e, _, _) -> Error (Unix.error_message e) in
        flush stdout;
        Unix.dup2 saved Unix.stdout;
        Unix.close saved; Unix.close log_fd;
        r in
    let deploy_log = try read_file (tmp ^ "/deploy.log") with Sys_error _ -> "" in
    check "the deploy activated one function"
      (match deployed with Ok 1 -> true | _ -> false)
      (match deployed with Ok n -> string_of_int n ^ "\n" ^ deploy_log | Error m -> m ^ "\n" ^ deploy_log);
    check "the deploy uploaded source for the policy that allows it"
      (contains deploy_log "Uploaded source of 2 function version(s)")
      (String.sub deploy_log 0 (min 400 (String.length deploy_log)));

    (* -- After: the new body and hash -- *)
    let w2 = which price in
    let h2 = hash_of w2 in
    check "WHICH after the deploy: a new hash, patched, the baseline remembered"
      (String.length h2 = 64 && h2 <> h1
       && data w2 |> member "patched" = `Bool true
       && data w2 |> member "baseline_hash" = `String h1)
      (Yojson.Safe.to_string w2);
    check "WHICH after the deploy: activated_at is set"
      (match data w2 |> member "activated_at_ms" with `Int t -> t > 0 | _ -> false) (Yojson.Safe.to_string w2);
    check "WHICH after the deploy: the untouched function keeps its hash" (hash_of (which label) = hl1) "";
    let s2 = source price in
    let text2 = data s2 |> member "source" |> to_string_option |> Option.value ~default:"" in
    check "SOURCE after the deploy: the new body"
      (error s2 = None && contains text2 "qty * 12 + 1" && not (contains text2 "qty * 10")
       && data s2 |> member "impl_hash" = `String h2)
      (Yojson.Safe.to_string s2);
    check "the new text reached the node's own store (uploaded, not shared)"
      (Sys.file_exists (Printf.sprintf "%s/.march/cas/sources/%s/%s" node_home (String.sub h2 0 2)
                          (String.sub h2 2 62))) "";
    check "SOURCE of the function the deploy did not touch: still its own text"
      (match data (source label) |> member "source" with
       | `String t -> contains t "fn label(" | _ -> false) "";
    ignore reload;

    (* -- Policy edit applies at once -- *)
    write_file policy "STATE\n";
    check "SOURCE once the policy drops it: policy" (error (source price) = Some "policy") "";
    check "WHICH needs no policy" (error (which price) = None) "";

    (* -- The audit log: every SOURCE attempt, the name it asked for -- *)
    let lines = audit_lines log in
    let signed_lines = List.filter (fun j -> member "signer" j <> `String "in-process") lines in
    let results = List.map (fun j -> to_string (member "result" j)) signed_lines in
    let expected = [ "policy"; "bad_signature"; "bad_signature"; "bad_args"; "bad_signature";
                     "ok"; "ok"; "ok"; "replay"; "not_found"; "bad_args"; "bad_args"; "bad_args";
                     "bad_args"; "bad_args"; "ok"; "ok"; "policy" ] in
    check "every signed SOURCE attempt is audited, in order"
      (results = expected) (String.concat "," results);
    check "audit lines for an accepted SOURCE name the function"
      (List.exists (fun j -> member "result" j = `String "ok" && member "name" j = `String price) signed_lines) "";
    let local_ok = List.filter (fun j -> member "signer" j = `String "in-process"
                                          && member "result" j = `String "ok") lines in
    check "the in-process Recon.source is audited, as in-process" (List.length local_ok = 1)
      (string_of_int (List.length local_ok));
    finish ()
  | _ -> prerr_endline "usage: observe_which_source_check <march-exe> <v1.march> <v2.march>"; exit 2
