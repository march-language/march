(** A4: [--bisect-pass] and [--reduce].

    Both drive THIS compiler as a subprocess ([Sys.executable_name]), so a
    probe is exactly a user's build: same flags, same CAS (keyed on the
    disabled-pass set, see {!March_tir.Pass_switch.cas_tag}), same runtime.

    [--bisect-pass FILE]: which optional TIR passes make the compiled program
    wrong?  The reference is the interpreter's output (stdout and exit code),
    or with [--expect OUT] the contents of OUT (stdout only).  It checks that
    the default build is wrong and that disabling every optional pass makes
    it right, then shrinks that disabled set greedily, in pipeline order, to
    a 1-minimal one: every pass left in it is needed.

    [--reduce FILE --oracle CMD]: delta debugging.  CMD is run through
    [/bin/sh -c] with the candidate's path in place of [{}] (or appended);
    exit 0 means "still interesting".  It removes whole declarations first
    (outermost level first, re-parsing between levels), then single lines,
    and writes the smallest interesting program to [FILE.reduced.march]. *)

let exe () =
  let e = Sys.executable_name in
  if Filename.is_relative e then Filename.concat (Sys.getcwd ()) e else e

let tmp_dir prefix =
  let d = Filename.concat (Filename.get_temp_dir_name ())
      (Printf.sprintf "%s-%d-%d" prefix (Unix.getpid ()) (Random.bits ())) in
  Unix.mkdir d 0o700; d

let read_file p =
  let ic = open_in_bin p in
  Fun.protect ~finally:(fun () -> close_in ic) (fun () ->
      really_input_string ic (in_channel_length ic))

let write_file p s =
  let oc = open_out_bin p in
  Fun.protect ~finally:(fun () -> close_out oc) (fun () -> output_string oc s)

let timeout_s () =
  match Option.bind (Sys.getenv_opt "MARCH_BISECT_TIMEOUT") float_of_string_opt with
  | Some t when t > 0. -> t | _ -> 60.

(** Run [argv] with stdout (and stderr, when [merge]) captured.  Returns the
    output and a status: the exit code, 128+signal, or [-1] on timeout.
    Plain [Unix.create_process]: no shell, so no quoting to get wrong. *)
let run ?(merge = false) ?(timeout = timeout_s ()) (argv : string array) : string * int =
  let out = Filename.temp_file "march-probe" ".out" in
  let fd = Unix.openfile out [ Unix.O_WRONLY; Unix.O_TRUNC; Unix.O_CREAT ] 0o600 in
  let devnull = Unix.openfile "/dev/null" [ Unix.O_RDWR ] 0 in
  let pid = Unix.create_process argv.(0) argv devnull fd (if merge then fd else devnull) in
  Unix.close fd; Unix.close devnull;
  let deadline = Unix.gettimeofday () +. timeout in
  let rec wait () =
    match Unix.waitpid [ Unix.WNOHANG ] pid with
    | 0, _ ->
      if Unix.gettimeofday () > deadline then begin
        (try Unix.kill pid Sys.sigterm with Unix.Unix_error _ -> ());
        Unix.sleepf 2.;
        (match Unix.waitpid [ Unix.WNOHANG ] pid with
         | 0, _ -> (try Unix.kill pid Sys.sigkill with Unix.Unix_error _ -> ());
           ignore (Unix.waitpid [] pid)
         | _ -> ());
        -1
      end else (Unix.sleepf 0.02; wait ())
    | _, Unix.WEXITED c -> c
    | _, (Unix.WSIGNALED s | Unix.WSTOPPED s) -> 128 + abs s
  in
  let status = wait () in
  let s = try read_file out with Sys_error _ -> "" in
  (try Sys.remove out with Sys_error _ -> ());
  (s, status)

let status_str = function
  | -1 -> "timed out"
  | c when c > 128 -> Printf.sprintf "killed by signal %d" (c - 128)
  | c -> Printf.sprintf "exit %d" c

let first_lines n s =
  let ls = String.split_on_char '\n' s in
  String.concat "\n" (List.filteri (fun i _ -> i < n) ls)

(* ── --bisect-pass ──────────────────────────────────────────────────── *)

type outcome = Ran of string * int | Build_failed of string

let bisect ~(file : string) ~(expect : string option) ~(extra : string list) : int =
  let exe = exe () in
  (* each probe states its own disabled set; an inherited one would leak
     into the "all passes on" probe *)
  Unix.putenv "MARCH_DISABLE_PASS" "";
  let dir = tmp_dir "march-bisect" in
  let reference, compare_code =
    match expect with
    | Some p -> (read_file p, None)
    | None ->
      let out, code = run (Array.of_list ((exe :: extra) @ [ file ])) in
      Printf.eprintf "reference (interpreter): %s, %d byte(s) of output\n%!"
        (status_str code) (String.length out);
      (out, Some code)
  in
  let n = ref 0 in
  let build disabled =
    incr n;
    let bin = Filename.concat dir (Printf.sprintf "probe%d" !n) in
    let flags = match disabled with
      | [] -> [] | ps -> [ "--disable-pass"; String.concat "," ps ] in
    let log, code =
      run ~merge:true (Array.of_list ((exe :: "--compile" :: flags) @ extra @ [ "-o"; bin; file ])) in
    if code <> 0 || not (Sys.file_exists bin) then Build_failed log
    else begin
      let out, code = run [| bin |] in
      (try Sys.remove bin with Sys_error _ -> ());
      Ran (out, code)
    end
  in
  let good = function
    | Build_failed _ -> false
    | Ran (out, code) ->
      out = reference && (match compare_code with Some c -> c = code | None -> true)
  in
  let describe = function
    | Build_failed log -> "the build failed:\n" ^ first_lines 12 log
    | Ran (out, code) ->
      Printf.sprintf "%s, output %s" (status_str code)
        (if out = reference then "matches" else
           Printf.sprintf "differs (%d byte(s); first line: %S)" (String.length out)
             (first_lines 1 out))
  in
  let probe disabled =
    let o = build disabled in
    Printf.eprintf "  [%s] %s\n%!"
      (match disabled with [] -> "all passes on" | ps -> "off: " ^ String.concat "," ps)
      (if good o then "GOOD" else "BAD: " ^ describe o);
    o
  in
  (* the whole-loop switch [opt] is redundant with its members *)
  let candidates = List.filter (fun p -> p <> "opt") March_tir.Pass_switch.names in
  let base = probe [] in
  if good base then begin
    print_endline "bisect-pass: the default compiled build already matches the reference; nothing to bisect.";
    0
  end else
    let all = probe candidates in
    if not (good all) then begin
      print_endline "bisect-pass: still wrong with every optional pass disabled, so no optional \
                     pass is the cause.  Try `scripts/triage.sh FILE` (mandatory passes, \
                     codegen, runtime).";
      1
    end else begin
      let set = List.fold_left (fun set p ->
          let without = List.filter (( <> ) p) set in
          if good (probe without) then without else set) candidates candidates in
      Printf.printf "bisect-pass: the compiled program is right only with %s disabled:\n"
        (if List.length set = 1 then "this pass" else "all of these passes");
      List.iter (fun p ->
          Printf.printf "  %-24s %s\n" p (List.assoc p March_tir.Pass_switch.known)) set;
      Printf.printf "Each one is needed: re-enabling any of them makes it wrong again.\n\
                     Reproduce: march --compile --disable-pass %s %s\n"
        (String.concat "," set) file;
      (try Sys.rmdir dir with Sys_error _ -> ());
      1
    end

(* ── --reduce ───────────────────────────────────────────────────────── *)

let oracle_cmd oracle path =
  let q = Filename.quote path in
  let re = Str.regexp_string "{}" in
  if (try ignore (Str.search_forward re oracle 0); true with Not_found -> false)
  then Str.global_replace re q oracle
  else oracle ^ " " ^ q

(** [lines] with the 0-based indices in [drop] removed. *)
let keep_lines lines drop =
  List.filteri (fun i _ -> not (Hashtbl.mem drop i)) lines

(** Classic ddmin over [units] (each a list of line indices): the smallest
    subset of [units] to DELETE is not what ddmin finds; it finds a 1-minimal
    set to KEEP.  [test kept] is the oracle on the program keeping [kept]. *)
let ddmin (units : 'a list) (test : 'a list -> bool) : 'a list =
  let split l n =
    let len = List.length l in
    let size = max 1 ((len + n - 1) / n) in
    let rec go acc cur k = function
      | [] -> List.rev (if cur = [] then acc else List.rev cur :: acc)
      | x :: xs ->
        if k = size then go (List.rev cur :: acc) [ x ] 1 xs else go acc (x :: cur) (k + 1) xs
    in
    go [] [] 0 l
  in
  let rec loop c n =
    if List.length c <= 1 then c
    else
      let parts = split c n in
      let complement i = List.concat (List.filteri (fun j _ -> j <> i) parts) in
      match List.find_opt (fun p -> test p) parts with
      | Some p -> loop p 2
      | None ->
        let rec try_compl i =
          if i >= List.length parts then None
          else let c' = complement i in
            if test c' then Some c' else try_compl (i + 1)
        in
        match try_compl 0 with
        | Some c' -> loop c' (max (n - 1) 2)
        | None ->
          if n >= List.length c then c else loop c (min (List.length c) (2 * n))
  in
  if test [] then [] else loop units 2

let reduce ~(file : string) ~(oracle : string) : int =
  let dir = tmp_dir "march-reduce" in
  let cand = Filename.concat dir (Filename.basename file) in
  let calls = ref 0 in
  let interesting text =
    incr calls;
    write_file cand text;
    let _, code = run [| "/bin/sh"; "-c"; oracle_cmd oracle cand |] in
    code = 0
  in
  let text0 = read_file file in
  if not (interesting text0) then begin
    Printf.eprintf "reduce: the oracle does not accept the original program (it must exit 0 on it)\n";
    2
  end else begin
    let lines_of t = String.split_on_char '\n' t in
    let cur = ref (lines_of text0) in
    let render ls = String.concat "\n" ls in
    (* Phase 1: declarations, level by level.  A unit is the 0-based line
       range of one declaration; nested modules are units at their level
       and their members become units at the next. *)
    let decl_units (ls : string list) (depth : int) : (int * int) list =
      match March_parser.Parse.module_ ~filename:file (render ls) with
      | Error _ -> []
      | Ok m ->
        let rec at d (decls : March_ast.Ast.decl list) =
          List.concat_map (fun dcl ->
              let sp = March_tir.Lower_decls.decl_span dcl in
              let unit = (sp.March_ast.Ast.start_line - 1, sp.March_ast.Ast.end_line - 1) in
              match dcl with
              | March_ast.Ast.DMod (_, _, inner, _) ->
                if d = depth then [ unit ] else at (d + 1) inner
              | _ -> if d = depth then [ unit ] else [])
            decls
        in
        List.filter (fun (a, b) -> a >= 0 && b >= a) (at 0 m.March_ast.Ast.mod_decls)
    in
    let reduce_units (units : (int * int) list) =
      if units <> [] then begin
        let ls = !cur in
        let program kept =
          let drop = Hashtbl.create 64 in
          List.iter (fun (a, b) ->
              if not (List.mem (a, b) kept) then
                for i = a to b do Hashtbl.replace drop i () done) units;
          keep_lines ls drop
        in
        let kept = ddmin units (fun kept -> interesting (render (program kept))) in
        cur := program kept
      end
    in
    let rec levels depth =
      let units = decl_units !cur depth in
      if units <> [] && depth < 8 then begin
        let before = List.length !cur in
        reduce_units units;
        Printf.eprintf "reduce: declarations at depth %d: %d -> %d line(s)\n%!"
          depth before (List.length !cur);
        levels (depth + 1)
      end
    in
    levels 0;
    (* Phase 2: single lines. *)
    let ls = !cur in
    let idx = List.mapi (fun i _ -> i) ls in
    let kept = ddmin idx (fun kept ->
        interesting (render (List.filteri (fun i _ -> List.mem i kept) ls))) in
    cur := List.filteri (fun i _ -> List.mem i kept) ls;
    let out = Filename.remove_extension file ^ ".reduced.march" in
    let final = render !cur in
    (* the last oracle call may have been a rejected candidate *)
    if not (interesting final) then begin
      Printf.eprintf "reduce: internal error, the final candidate is not interesting\n";
      2
    end else begin
      write_file out final;
      Printf.printf "reduce: %d -> %d line(s) in %d oracle call(s); wrote %s\n"
        (List.length (lines_of text0)) (List.length !cur) !calls out;
      (try Sys.remove cand; Sys.rmdir dir with Sys_error _ -> ());
      0
    end
  end
