(* Drives a running node's shell listener (runtime/march_shell.c) with signed
   EVALs of hand-written C fragments (test/shell/frag_*.c).

     shell_check keygen <pk-file> <sk-file>
     shell_check run <socket> <program-output> <sk-file> <policy-file> <audit-log> <frag-dir>

   One "ok: ..." / "FAIL: ..." line per check, diffed against a golden.
   The client side (compiling March input into fragments) is not involved:
   this pins the node's half of the protocol. *)

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

let starts_with s p = String.length s >= String.length p && String.sub s 0 (String.length p) = p

let b64_alpha = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

let b64_encode (s : string) : string =
  let n = String.length s in
  let b = Buffer.create (4 * ((n + 2) / 3)) in
  let i = ref 0 in
  while !i < n do
    let c k = if !i + k < n then Char.code s.[!i + k] else 0 in
    let v = (c 0 lsl 16) lor (c 1 lsl 8) lor c 2 in
    Buffer.add_char b b64_alpha.[(v lsr 18) land 63];
    Buffer.add_char b b64_alpha.[(v lsr 12) land 63];
    Buffer.add_char b (if !i + 1 < n then b64_alpha.[(v lsr 6) land 63] else '=');
    Buffer.add_char b (if !i + 2 < n then b64_alpha.[v land 63] else '=');
    i := !i + 3
  done;
  Buffer.contents b

let b64_decode (s : string) : string =
  let v c = match String.index_opt b64_alpha c with Some i -> i | None -> -1 in
  let b = Buffer.create (String.length s) in
  let acc = ref 0 and bits = ref 0 in
  String.iter (fun c ->
      if c <> '=' then begin
        let x = v c in
        if x >= 0 then begin
          acc := (!acc lsl 6) lor x;
          bits := !bits + 6;
          if !bits >= 8 then begin
            bits := !bits - 8;
            Buffer.add_char b (Char.chr ((!acc lsr !bits) land 0xff))
          end
        end
      end) s;
  Buffer.contents b

(* ── connection ── *)

type conn = { fd : Unix.file_descr; buf : Buffer.t }

let connect sock =
  let fd = Unix.socket Unix.PF_UNIX Unix.SOCK_STREAM 0 in
  Unix.setsockopt_float fd Unix.SO_RCVTIMEO 20.;
  Unix.connect fd (Unix.ADDR_UNIX sock);
  { fd; buf = Buffer.create 4096 }

let send c line =
  let s = line ^ "\n" in
  let rec go off = if off < String.length s then go (off + Unix.write_substring c.fd s off (String.length s - off)) in
  go 0

let recv c =
  let chunk = Bytes.create 65536 in
  let rec go () =
    let s = Buffer.contents c.buf in
    match String.index_opt s '\n' with
    | Some i ->
      Buffer.clear c.buf;
      Buffer.add_string c.buf (String.sub s (i + 1) (String.length s - i - 1));
      String.sub s 0 i
    | None ->
      (match Unix.read c.fd chunk 0 (Bytes.length chunk) with
       | 0 -> s
       | n -> Buffer.add_subbytes c.buf chunk 0 n; go ())
  in
  go ()

let ask c line = send c line; recv c

let close c = try Unix.close c.fd with _ -> ()

(* ── signed EVAL ── *)

let now_ms () = int_of_float (Unix.gettimeofday () *. 1000.)
let nonce_n = ref 0
let fresh_nonce () = incr nonce_n; Printf.sprintf "%016x%016x" (now_ms ()) !nonce_n

let eval_line ?(nonce = fresh_nonce ()) ?(timeout_ms = 5000) ?(caps = "-") ~sk ~epoch ~name ~so () =
  let body =
    Printf.sprintf "name:%s epoch:%d nonce:%s not_after_ms:%d timeout_ms:%d caps:%s src_b64:%s so_b64:%s"
      name epoch nonce (now_ms () + 30_000) timeout_ms caps (b64_encode ("source of " ^ name))
      (b64_encode so) in
  let s = March_ed25519.Ed25519.(sig_to_base64 (sign_str ("EVAL " ^ body) sk)) in
  "EVAL " ^ s ^ " " ^ body

let words s = String.split_on_char ' ' s

let field r key =
  List.find_map (fun w ->
      if starts_with w (key ^ ":") then Some (String.sub w (String.length key + 1) (String.length w - String.length key - 1))
      else None) (words r)

let wait_ready file =
  let deadline = Unix.gettimeofday () +. 60. in
  let rec go () =
    let s = try read_file file with Sys_error _ -> "" in
    if contains s "ready\n" then ()
    else if Unix.gettimeofday () > deadline then (prerr_endline ("never ready:\n" ^ s); exit 1)
    else (Unix.sleepf 0.05; go ())
  in
  go ()

let audit_results log =
  (try read_file log with Sys_error _ -> "")
  |> String.split_on_char '\n'
  |> List.filter (fun l -> contains l "\"type\":\"shell\"")
  |> List.map (fun l ->
      match String.index_opt l 'r' with
      | _ ->
        let key = "\"result\":\"" in
        let rec find i = if i + String.length key > String.length l then "" else if String.sub l i (String.length key) = key then
            let j = i + String.length key in
            String.sub l j (String.index_from l j '"' - j) else find (i + 1) in
        find 0)

let run sock prog sk_file policy log frag_dir =
  let sk = Bytes.of_string (read_file sk_file) in
  let so name = read_file (Filename.concat frag_dir (name ^ ".so")) in
  wait_ready prog;
  write_file policy "";
  let c = connect sock in
  check "EVAL before HELLO is refused" (ask c "EVAL x y" = "ERR no_hello") "";
  let hello = ask c "HELLO" in
  let epoch = match field hello "epoch" with Some e -> int_of_string e | None -> -1 in
  check "HELLO answers the epoch and a slot range"
    (starts_with hello "OK " && epoch >= 0 && field hello "slots" <> None) hello;
  let ok_line = eval_line ~sk ~epoch ~name:"__shell_frag_ok" ~so:(so "frag_ok") () in
  let r = ask c ok_line in
  check "a signed fragment runs: its result comes back"
    (starts_with r "OK " && b64_decode (List.nth (words r) 1) = "42") r;
  check "its println is captured, not printed by the node"
    (match field r "out" with Some o -> b64_decode o = "hello from the fragment\n" | None -> false)
    r;
  check "the same line again: replay" (ask c ok_line = "ERR replay") "";
  let _, other = March_ed25519.Ed25519.keygen () in
  check "signed by another key: bad_signature"
    (ask c (eval_line ~sk:other ~epoch ~name:"__shell_frag_ok" ~so:(so "frag_ok") ()) = "ERR bad_signature") "";
  check "a cap the policy does not list: policy"
    (ask c (eval_line ~sk ~epoch ~caps:"IO.NetConnect" ~name:"__shell_frag_ok" ~so:(so "frag_ok") ())
     = "ERR policy IO.NetConnect") "";
  write_file policy "# shell caps\nIO.Console\nIO.NetConnect\n";
  check "listed in the policy: allowed"
    (starts_with (ask c (eval_line ~sk ~epoch ~caps:"IO.Console,IO.NetConnect" ~name:"__shell_frag_ok" ~so:(so "frag_ok") ())) "OK ") "";
  let p = ask c (eval_line ~sk ~epoch ~name:"__shell_frag_panic" ~so:(so "frag_panic") ()) in
  check "a panicking fragment answers PANIC with its message"
    (starts_with p "PANIC " && b64_decode (List.nth (words p) 1) = "fragment panicked") p;
  check "with the output it printed first"
    (match field p "out" with Some o -> b64_decode o = "before " | None -> false) p;
  let t0 = Unix.gettimeofday () in
  let t = ask c (eval_line ~sk ~epoch ~timeout_ms:300 ~name:"__shell_frag_loop" ~so:(so "frag_loop") ()) in
  let dt = Unix.gettimeofday () -. t0 in
  check "a fragment that never returns is cancelled: TIMEOUT" (starts_with t "TIMEOUT out:") t;
  check "within the timeout plus a second" (dt < 1.5) (Printf.sprintf "%.2fs" dt);
  check "the node keeps serving after a panic and a timeout"
    (starts_with (ask c (eval_line ~sk ~epoch ~name:"__shell_frag_ok" ~so:(so "frag_ok") ())) "OK ") "";
  check "an entry the fragment does not define: no_entry"
    (ask c (eval_line ~sk ~epoch ~name:"__shell_nope" ~so:(so "frag_ok") ()) = "ERR no_entry") "";
  check "an EVAL for another epoch: epoch_changed"
    (starts_with (ask c (eval_line ~sk ~epoch:(epoch + 5) ~name:"__shell_frag_ok" ~so:(so "frag_ok") ())) "ERR epoch_changed") "";
  check "an unknown field: bad_args"
    (ask c "EVAL sig name:x colour:red" = "ERR bad_args") "";
  (* Sessions: four at once, the fifth is refused. *)
  let others = List.init 3 (fun _ -> let o = connect sock in ignore (ask o "HELLO"); o) in
  let fifth = connect sock in
  check "a fifth concurrent session: busy" (recv fifth = "ERR busy") "";
  close fifth;
  let ranges = List.map (fun o -> field (ask o "HELLO") "slots") (c :: others) in
  check "each session owns its own slot range"
    (List.length (List.sort_uniq compare ranges) = 4) (String.concat "," (List.map (Option.value ~default:"?") ranges));
  List.iter (fun o -> send o "BYE"; close o) others;
  send c "BYE";
  close c;
  let results = audit_results log in
  let expected = [ "ok"; "replay"; "bad_signature"; "policy"; "ok"; "ok"; "ok"; "ok"; "err_no_entry";
                   "epoch_changed"; "bad_args" ] in
  check "every EVAL is audited, in order" (results = expected) (String.concat "," results);
  check "the audit line carries the source"
    (contains (try read_file log with _ -> "") "\"src\":\"source of __shell_frag_ok\"") "";
  if !failures > 0 then exit 1

let keygen pk_file sk_file =
  let pk, sk = March_ed25519.Ed25519.keygen () in
  write_file pk_file (March_ed25519.Ed25519.pk_to_base64 pk);
  write_file sk_file (Bytes.to_string sk)

let () =
  match Array.to_list Sys.argv |> List.tl with
  | [ "keygen"; pk; sk ] -> keygen pk sk
  | [ "run"; sock; prog; sk; policy; log; frags ] -> run sock prog sk policy log frags
  | _ -> prerr_endline "usage: shell_check keygen|run ..."; exit 2
