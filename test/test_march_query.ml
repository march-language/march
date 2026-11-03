(* `march query` (A7, lib/query/query.ml), end to end against the real
   compiler in a fresh project dir with a private HOME, the way test_cas_b7
   drives the CAS.  Every answer is read back as JSON.  The cache queries are
   pinned to what a real compile then does: a why-miss verdict of "post-TIR
   hit" must be followed by a compile that reports "(cached)". *)

let compiler_exe =
  let exe_dir = Filename.dirname Sys.executable_name in
  Filename.concat exe_dir "../bin/main.exe"

let read_file path =
  try
    let ic = open_in_bin path in
    let s = really_input_string ic (in_channel_length ic) in
    close_in ic; s
  with Sys_error _ -> ""

let write_file path s = Out_channel.with_open_bin path (fun oc -> output_string oc s)

let rec rm_rf p =
  match Sys.is_directory p with
  | true ->
    Array.iter (fun c -> rm_rf (Filename.concat p c)) (Sys.readdir p);
    (try Unix.rmdir p with Unix.Unix_error _ -> ())
  | false -> (try Sys.remove p with Sys_error _ -> ())
  | exception Sys_error _ -> ()

let with_project src f =
  let dir = Filename.concat (Filename.get_temp_dir_name ())
      (Printf.sprintf "march_query.%d.%d" (Unix.getpid ())
         (Hashtbl.hash (Unix.gettimeofday ()))) in
  Unix.mkdir dir 0o755;
  Unix.mkdir (Filename.concat dir "home") 0o755;
  Unix.mkdir (Filename.concat dir "home/.cache") 0o755;
  write_file (Filename.concat dir "app.march") src;
  Fun.protect ~finally:(fun () -> rm_rf dir) (fun () -> f dir)

(* Output to files, never a pipe: a piped compile can hang. *)
let run ~dir args =
  let out = Filename.concat dir "q.out" and err = Filename.concat dir "q.err" in
  let cmd = Printf.sprintf "cd %s && env HOME=%s %s %s > %s 2> %s"
      (Filename.quote dir) (Filename.quote (Filename.concat dir "home"))
      (Filename.quote compiler_exe) (String.concat " " (List.map Filename.quote args))
      (Filename.quote out) (Filename.quote err) in
  let rc = Sys.command cmd in
  (rc, read_file out, read_file err)

let query ~dir args =
  let rc, out, err = run ~dir ("query" :: args @ [ "--json" ]) in
  match Yojson.Safe.from_string out with
  | j -> (rc, j)
  | exception _ -> Alcotest.failf "march query %s: not JSON (rc=%d)\nstdout:\n%s\nstderr:\n%s"
                     (String.concat " " args) rc out err

module U = Yojson.Safe.Util

let str j k = U.member k j |> U.to_string
let bool j k = U.member k j |> U.to_bool
let strs j k = U.member k j |> U.to_list |> List.map U.to_string

let contains hay needle =
  let n = String.length hay and m = String.length needle in
  let rec go i = i + m <= n && (String.sub hay i m = needle || go (i + 1)) in
  m = 0 || go 0

let src = {|mod App do
  needs IO.Console
  type Shape = Circle(Float) | Square(Float)

  fn area(s : Shape) : Float do
    match s do
      Circle(r) -> 3.14 *. r *. r
      Square(w) -> w *. w
    end
  end

  fn scale(xs : List(Int), k : Int) : List(Int) do
    List.map(xs, fn x -> x * k)
  end

  fn main(_c : Cap(IO.Console)) do
    println(int_to_string(List.length(scale([1, 2, 3], 2))))
    println(float_to_string(area(Circle(1.0))))
  end
end
|}

let test_fn () =
  with_project src (fun dir ->
      let rc, j = query ~dir [ "fn"; "scale"; "app.march"; "--no-opt" ] in
      Alcotest.(check int) "exit" 0 rc;
      let m = List.hd (U.member "matches" j |> U.to_list) in
      Alcotest.(check string) "name" "scale" (str m "name");
      let events = U.member "events" m |> U.to_list in
      Alcotest.(check string) "first event is lowering"
        "tir-lower" (str (List.hd events) "stage");
      Alcotest.(check bool) "defun rewrote it (the lambda became a closure)" true
        (List.exists (fun e -> str e "stage" = "tir-defun" && str e "event" = "changed") events);
      Alcotest.(check bool) "body is the final one" true (bool m "in_final");
      (* --at picks a stage by substring *)
      let _, j = query ~dir [ "fn"; "scale"; "app.march"; "--no-opt"; "--at"; "lower" ] in
      let m = List.hd (U.member "matches" j |> U.to_list) in
      Alcotest.(check string) "--at lower" "tir-lower" (str m "body_stage");
      (* an unknown name is an error with suggestions *)
      let rc, j = query ~dir [ "fn"; "scal"; "app.march" ] in
      Alcotest.(check int) "unknown name exits 1" 1 rc;
      Alcotest.(check bool) "found false" false (bool j "found");
      Alcotest.(check bool) "suggests scale" true (List.mem "scale" (strs j "suggestions")))

let test_origin_and_edges () =
  with_project src (fun dir ->
      let _, j = query ~dir [ "callees"; "scale"; "app.march"; "--no-opt" ] in
      let apply = List.find (fun n -> contains n "$apply$") (strs j "callees") in
      let rc, o = query ~dir [ "origin"; apply; "app.march"; "--no-opt" ] in
      Alcotest.(check int) "origin exit" 0 rc;
      Alcotest.(check string) "the lambda's host" "scale" (str o "host");
      Alcotest.(check bool) "derived by defun" true
        (List.exists (fun d -> String.starts_with ~prefix:"defun(" d) (strs o "derived"));
      Alcotest.(check bool) "span in app.march" true (contains (str o "span") "app.march:13");
      let _, c = query ~dir [ "callers"; "area"; "app.march"; "--no-opt" ] in
      Alcotest.(check (list string)) "main calls area" [ "main" ] (strs c "callers");
      (* optimised: area is inlined into main, so the answer says where it went *)
      let rc, c = query ~dir [ "callers"; "area"; "app.march" ] in
      Alcotest.(check int) "inlined: exit 1" 1 rc;
      Alcotest.(check bool) "last_seen names a stage" true
        (match U.member "last_seen" c with `String s -> String.starts_with ~prefix:"tir-" s | _ -> false))

let test_repr_and_verify () =
  with_project src (fun dir ->
      let rc, j = query ~dir [ "repr"; "Shape"; "app.march" ] in
      Alcotest.(check int) "repr exit" 0 rc;
      let inst = List.hd (U.member "instances" j |> U.to_list) in
      Alcotest.(check string) "Shape is boxed" "boxed" (str inst "repr");
      Alcotest.(check bool) "and refcounted" true (bool inst "needs_rc");
      let rc, j = query ~dir [ "verify"; "app.march" ] in
      Alcotest.(check int) "verify exit" 0 rc;
      Alcotest.(check int) "no findings" 0 (List.length (U.member "findings" j |> U.to_list));
      Alcotest.(check bool) "checked every stage" true (U.member "stages_checked" j |> U.to_int > 10))

let test_key_and_why_miss () =
  with_project src (fun dir ->
      (* A query may fill the refinement checker's SMT memo (.march/cas/vc,
         as plain --check does) but stores no build state: no artifact, no
         load set, no key record. *)
      let store_files () =
        let rec count p =
          if Sys.is_directory p then Array.fold_left (fun n c -> n + count (Filename.concat p c)) 0 (Sys.readdir p)
          else 1 in
        List.fold_left (fun n sub ->
            let p = Filename.concat dir (".march/cas/" ^ sub) in
            if Sys.file_exists p then n + count p else n)
          0 [ "artifacts-v2"; "loadsets"; "keyrecords" ] in
      (* nothing recorded yet *)
      let _, j = query ~dir [ "why-miss"; "app.march" ] in
      Alcotest.(check bool) "no record" false (bool j "recorded");
      let rc, k = query ~dir [ "key"; "app.march" ] in
      Alcotest.(check int) "key exit" 0 rc;
      Alcotest.(check bool) "O2 is a key input" true (List.mem "O2" (strs k "flags"));
      Alcotest.(check bool) "post-TIR key computed" true (U.member "post_key" k <> `Null);
      Alcotest.(check int) "queries store nothing" 0 (store_files ());
      let compile () =
        let rc, out, err = run ~dir [ "--compile"; "-o"; "app"; "app.march" ] in
        if rc <> 0 then Alcotest.failf "compile failed:\n%s%s" out err;
        out ^ err in
      ignore (compile ());
      let before = store_files () in
      let _, j = query ~dir [ "why-miss"; "app.march" ] in
      Alcotest.(check bool) "recorded" true (bool j "recorded");
      Alcotest.(check bool) "an unchanged build is a source-level hit" true (bool j "source_cached");
      Alcotest.(check int) "why-miss stores nothing" before (store_files ());
      (* a comment edit: the source key moves, the compiled program does not *)
      write_file (Filename.concat dir "app.march")
        (String.concat "\n  -- an edit that changes no code\n" (match String.index_opt src '\n' with
           | Some i -> [ String.sub src 0 i; String.sub src (i + 1) (String.length src - i - 1) ]
           | None -> [ src ]));
      let _, j = query ~dir [ "why-miss"; "app.march" ] in
      Alcotest.(check bool) "source key changed" true (bool j "source_key_changed");
      Alcotest.(check bool) "post-TIR key unchanged" false (bool j "post_key_changed");
      Alcotest.(check bool) "predicts a post-TIR hit" true (bool j "post_cached");
      Alcotest.(check bool) "names the edited file" true
        (List.exists (fun c -> contains (str c "change") "app.march") (U.member "changes" j |> U.to_list));
      (* ...and the real compile agrees *)
      Alcotest.(check bool) "the compile is served from the post-TIR cache" true
        (contains (compile ()) "(cached)");
      (* a flag change is reported as one *)
      let _, j = query ~dir [ "why-miss"; "app.march"; "--opt"; "0" ] in
      let changes = List.map (fun c -> str c "change") (U.member "changes" j |> U.to_list) in
      Alcotest.(check bool) "flag added" true (List.mem "added: O0" changes);
      Alcotest.(check bool) "flag removed" true (List.mem "removed: O2" changes))

let test_usage () =
  let rc, _, err = run ~dir:(Filename.get_temp_dir_name ()) [ "query"; "fn" ] in
  Alcotest.(check int) "missing name exits 2" 2 rc;
  Alcotest.(check bool) "prints usage" true (contains err "usage: march query")

let tests = [
  Alcotest.test_case "fn: stages that changed it, --at, suggestions" `Quick test_fn;
  Alcotest.test_case "origin, callers, callees; an inlined name says where it went" `Quick test_origin_and_edges;
  Alcotest.test_case "repr and verify" `Quick test_repr_and_verify;
  Alcotest.test_case "key and why-miss agree with what the compile then does" `Quick test_key_and_why_miss;
  Alcotest.test_case "usage errors" `Quick test_usage;
]
