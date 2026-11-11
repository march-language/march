(* Capability checks give the same verdict in every mode
   (specs/plans/2026-11-10-ocap-p3-checks-plan.md, Task 1;
   specs/2026-11-10-object-capability-design.md §15: "The compile-time checks
   run under `march --check`, the interpreter and the REPL, not only
   `--compile`").

   Each fixture is one program (plus, for the REPL, the same declarations as
   prompt input) run through every mode by the real compiler binary, under one
   private HOME for the whole run and a fresh cwd per run, so no cache shared
   with other worktrees or with an earlier run can decide a verdict.  A mode
   must report exactly the fixture's expected capability codes (and exit 1 on
   a reject, 0 on an accept), unless the (fixture, mode) pair is listed in
   [known_gaps].  A listed pair that now agrees is ALSO a failure, so the list
   can only shrink; the phase is done when it is empty. *)

let compiler_exe =
  Filename.concat (Filename.dirname Sys.executable_name) "../bin/main.exe"

type fixture = {
  name : string;
  src : string;  (** the program, an entry module *)
  lib : (string * string) list;  (** files on MARCH_LIB_PATH, (name, text) *)
  repl : string option;  (** REPL input; None = the REPL does not apply *)
  expect : string list;  (** sorted capability codes; [] = accept *)
  skip : (string * string) list;
      (** (mode, reason): a mode the fixture does not apply to *)
  warn_only : bool;  (** [expect] are warnings: the program is accepted *)
}

let fx ?(lib = []) ?repl ?(skip = []) ?(warn_only = false) name expect src =
  { name; src; lib; repl; expect; skip; warn_only }

(* `march check` checks a package: it wraps every file's module as a nested
   module of one synthetic module, so a file's `main` is not the program's
   entry point (no grant to hold it to). *)
let no_entry = [ ("march_check", "march check has no entry point, so no grant") ]

(* Pre-existing bugs of `march check`'s synthetic wrapping, filed
   2026-11-10, not this phase's. *)
let mc_nested_path_scope =
  [ ("march_check", "nested-module path scope unchecked: specs/todos/2026-11-10-nested-path-scope-unchecked.md") ]

let mc_inner_unresolved =
  [ ("march_check", "march check: `Unknown module Inner` on a twice-nested call: specs/todos/2026-11-10-march-check-nested-module-resolution.md") ]

(* ── Fixtures: one reject and its accept twin per check ─────────────────── *)

let ceiling_stdlib needs =
  Printf.sprintf
    {|mod Main do
  needs IO.Console, IO.FileRead
  mod Dep do
    needs %s
    fn slurp(p : String) : String do
      match Authority.must(File.read(p)) do
        Ok(s) -> s
        Err(_) -> "none"
      end
    end
  end
  fn main(c : Cap(IO.Console), f : Cap(IO.FileRead)) do
    println(Dep.slurp("/nonexistent/cap_parity"))
  end
end
|}
    needs

let ceiling_stdlib_repl needs =
  Printf.sprintf
    {|mod Dep do
  needs %s
  fn slurp(p : String) : String do
    match Authority.must(File.read(p)) do
      Ok(s) -> s
      Err(_) -> "none"
    end
  end
end
|}
    needs

(* A builtin passed as a value: `--compile`'s ceiling rejects it, the
   typecheck-side subset under `--check` does not (measured 2026-11-10). *)
let ceiling_value needs =
  Printf.sprintf
    {|mod Main do
  needs IO.Console, IO.FileRead
  mod Inner do
    needs %s
    fn apply1(f : (String) -> a, p : String) : a do
      f(p)
    end
    fn go() : () do
      match apply1(file_read, "/nonexistent/cap_parity") do
        Ok(_)  -> Authority.ignore(println("ok"))
        Err(_) -> Authority.ignore(println("e"))
      end
    end
  end
  fn main(_c : Cap(IO.Console), _f : Cap(IO.FileRead)) : () do
    Inner.go()
  end
end
|}
    needs

let fn_bound bound =
  Printf.sprintf
    {|mod Main do
  needs IO.Console
  fn f(s : String) : Unit needs %s do Authority.ignore(println(s)) end
  fn main(c : Cap(IO.Console)) do f("hi") end
end
|}
    bound

let fn_bound_repl bound =
  Printf.sprintf
    {|mod Q do
  needs IO.Console
  fn f(s : String) : Unit needs %s do Authority.ignore(println(s)) end
end
|}
    bound

let main_grant grant =
  Printf.sprintf
    {|mod Main do
  needs IO.Console
  needs IO.FileWrite
  fn greet(name : String) : () do
    match file_write("/nonexistent/cap_parity", name) do
      Ok(_)  -> Authority.ignore(println("hello " ++ name))
      Err(_) -> Authority.ignore(println("hello anyway"))
    end
  end
  fn main(%s) : () do
    greet("march")
  end
end
|}
    grant

let path_scope path =
  Printf.sprintf
    {|mod Main do
  needs IO.Console, IO.FileRead("/nonexistent/cap_parity/")
  fn r() : String do
    match file_read("%s") do
      Ok(s) -> s
      Err(_) -> "none"
    end
  end
  fn main(c : Cap(IO.Console), f : Cap(IO.FileRead)) do println(r()) end
end
|}
    path

let path_scope_repl path =
  Printf.sprintf
    {|mod R do
  needs IO.FileRead("/nonexistent/cap_parity/")
  fn r() : String do
    match file_read("%s") do
      Ok(s) -> s
      Err(_) -> "none"
    end
  end
end
|}
    path

(* Port 9 on loopback refuses at once, so an accepted program's run ends
   quickly with "err" and needs no network. *)
let host_scope_body url =
  Printf.sprintf
    {|  needs IO.NetConnect("127.0.0.1:9")
    fn go(q : String) : String do
      match HttpTransport.simple_get(%s) do
        Ok(_) -> "ok"
        Err(_) -> "err"
      end
    end|}
    url

let host_scope url =
  Printf.sprintf
    {|mod Main do
  needs IO.NetConnect, IO.Console
  mod A do
  %s
  end
  fn main(_n : Cap(IO.NetConnect), _c : Cap(IO.Console)) do
    println(A.go("q"))
  end
end
|}
    (host_scope_body url)

let host_scope_repl url =
  Printf.sprintf "mod A do\n%s\nend\n" (host_scope_body url)

(* A violation in a module loaded from MARCH_LIB_PATH: another file, whose
   module span is not in the entry file's tree. *)
let dep_lib needs =
  [ ( "capdep.march",
      Printf.sprintf
        {|mod CapDep do
  needs %s
  fn slurp(p : String) : String do
    match Authority.must(File.read(p)) do
      Ok(s) -> s
      Err(_) -> "none"
    end
  end
end
|}
        needs ) ]

let dep_main =
  {|mod Main do
  needs IO.Console, IO.FileRead
  fn main(c : Cap(IO.Console), f : Cap(IO.FileRead)) do
    println(CapDep.slurp("/nonexistent/cap_parity"))
  end
end
|}

let unlowerable =
  {|mod Main do
  needs IO.Console
  fn main(c : Cap(IO.Console)) do
    println("before")
    App.stop()
    println("after")
  end
end
|}

let fixtures =
  [
    fx "ceiling_stdlib" [ "cap_ceiling" ] (ceiling_stdlib "IO.Console")
      ~repl:(ceiling_stdlib_repl "IO.Console");
    fx "ceiling_stdlib_ok" [] (ceiling_stdlib "IO.Console, IO.FileRead")
      ~repl:(ceiling_stdlib_repl "IO.Console, IO.FileRead");
    fx "ceiling_value" [ "cap_ceiling" ] (ceiling_value "IO.Console")
      ~skip:mc_inner_unresolved;
    fx "ceiling_value_ok" [] (ceiling_value "IO.Console, IO.FileRead")
      ~skip:mc_inner_unresolved;
    fx "fn_bound" [ "cap_bound" ] (fn_bound "()") ~repl:(fn_bound_repl "()");
    fx "fn_bound_ok" [] (fn_bound "IO.Console") ~repl:(fn_bound_repl "IO.Console");
    (* §21: the REPL runs with full authority, so no grant fixture there. *)
    fx "main_grant" [ "cap_grant_exceeded" ] (main_grant "cap : Cap(IO.Console)")
      ~skip:no_entry;
    fx "main_grant_ok" []
      (main_grant "c : Cap(IO.Console), w : Cap(IO.FileWrite)") ~skip:no_entry;
    fx "path_scope" [ "cap_scope_violation" ]
      (path_scope "/etc/hosts") ~repl:(path_scope_repl "/etc/hosts")
      ~skip:(mc_nested_path_scope
             @ [ ("repl", "a module declared at the prompt is checked as a nested module: specs/todos/2026-11-10-nested-path-scope-unchecked.md") ]);
    fx "path_scope_ok" [] (path_scope "/nonexistent/cap_parity/a.txt")
      ~repl:(path_scope_repl "/nonexistent/cap_parity/a.txt");
    fx "host_scope" [ "cap_host_scope" ]
      (host_scope {|"http://evil.test/" ++ q|})
      ~repl:(host_scope_repl {|"http://evil.test/" ++ q|});
    fx "host_scope_ok" []
      (host_scope {|"http://127.0.0.1:9/" ++ q|})
      ~repl:(host_scope_repl {|"http://127.0.0.1:9/" ++ q|});
    fx "host_unproven" [ "cap_host_unproven" ] (host_scope "q")
      ~repl:(host_scope_repl "q");
    fx "dep_module" [ "cap_ceiling" ] dep_main ~lib:(dep_lib "IO.Console");
    fx "dep_module_ok" [] dep_main ~lib:(dep_lib "IO.Console, IO.FileRead");
    (* An interpreter-only builtin cannot be lowered: the modes that lower on
       demand warn that the TIR checks did not run, and still run it. *)
    fx "unlowerable" [ "cap_unchecked" ] ~warn_only:true unlowerable
      ~skip:[ ("compile", "the compiled backend rejects it (compiled_unsupported)");
              ("jit", "the JIT lowers the program itself and refuses it (an internal-error exit, not this phase's: specs/todos/2026-11-10-jit-ice-on-interpreter-only-builtin.md)") ];
  ]

(* ── Modes ─────────────────────────────────────────────────────────────── *)

let modes =
  [ "compile"; "check"; "check_json"; "emit_core_ast"; "march_check"; "interp";
    "jit"; "repl" ]

(* Pairs that disagree with the fixture's expectation today. Shrinks as the
   phase lands; must be empty when it is done. *)
let known_gaps : (string * string) list =
  [
  ]

let read_file path =
  let ic = open_in_bin path in
  let s = really_input_string ic (in_channel_length ic) in
  close_in ic;
  s

let write_file path text =
  let oc = open_out_bin path in
  output_string oc text;
  close_out oc

let mkdir_p dir =
  ignore (Sys.command (Printf.sprintf "mkdir -p %s" (Filename.quote dir)))

let home =
  lazy
    (let d = Filename.concat (Filename.get_temp_dir_name ())
         (Printf.sprintf "cap_parity_home_%d" (Unix.getpid ())) in
     mkdir_p d;
     d)

let fresh_dir =
  let n = ref 0 in
  fun tag ->
    incr n;
    let d = Filename.concat (Filename.get_temp_dir_name ())
        (Printf.sprintf "cap_parity_%d_%d_%s" (Unix.getpid ()) !n tag) in
    ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote d)));
    mkdir_p d;
    d

(* Capability codes in a run's output: `[cap_x]` in rendered text, or
   `"code":"cap_x"` in JSON. *)
let codes_of (out : string) : string list =
  let found = ref [] in
  let scan re =
    let rec go pos =
      match Str.search_forward re out pos with
      | p ->
        found := Str.matched_group 1 out :: !found;
        go (p + 1)
      | exception Not_found -> ()
    in
    go 0
  in
  scan (Str.regexp {|\[\(cap_[a-z_]+\)\]|});
  scan (Str.regexp {|"code":"\(cap_[a-z_]+\)|});
  List.sort_uniq compare !found

(* The output file of the last [run_mode], quoted in a mismatch: a mode that
   prints an unrelated error (the REPL exits 0 whatever happens) shows up as
   "accept []", and only its output says why. *)
let last_out = ref ""

let output_excerpt () =
  let lines =
    try String.split_on_char '\n' (read_file !last_out) with _ -> [ "(no output file)" ] in
  let rec take n = function
    | [] -> []
    | _ when n = 0 -> [ "    ..." ]
    | l :: rest -> ("    " ^ l) :: take (n - 1) rest
  in
  String.concat "\n" (take 25 lines)

(* Runs [f] in [mode]: (rejected, codes). [None] when the mode does not
   apply to the fixture. *)
let run_mode (f : fixture) (mode : string) : (bool * string list) option =
  if List.mem_assoc mode f.skip then None else
  let dir = fresh_dir (f.name ^ "_" ^ mode) in
  let lib_env =
    if f.lib = [] then ""
    else begin
      let lib = Filename.concat dir "lib" in
      mkdir_p lib;
      List.iter (fun (n, t) -> write_file (Filename.concat lib n) t) f.lib;
      Printf.sprintf "MARCH_LIB_PATH=%s " (Filename.quote lib)
    end
  in
  let src = Filename.concat dir "main.march" in
  write_file src f.src;
  let out = Filename.concat dir "out.txt" in
  last_out := out;
  let exe = Filename.quote compiler_exe in
  let run args stdin =
    Sys.command
      (Printf.sprintf "cd %s && HOME=%s MARCH_CAP_TRACE=1 %s%s %s > %s 2>&1 < %s"
         (Filename.quote dir) (Filename.quote (Lazy.force home)) lib_env exe args
         (Filename.quote out) stdin)
  in
  let q = Filename.quote src in
  let result rc = Some (rc <> 0, codes_of (read_file out)) in
  match mode with
  | "compile" -> result (run ("--compile -o " ^ Filename.quote (Filename.concat dir "a.out") ^ " " ^ q) "/dev/null")
  | "check" -> result (run ("--check " ^ q) "/dev/null")
  | "check_json" ->
    (* --check-json exits 0 whatever it prints: the verdict is an error-
       severity diagnostic in the stream. *)
    let _ = run ("--check-json " ^ q) "/dev/null" in
    let text = read_file out in
    let rejected =
      match Str.search_forward (Str.regexp_string {|"severity":"error"|}) text 0 with
      | _ -> true
      | exception Not_found -> false
    in
    Some (rejected, codes_of text)
  | "emit_core_ast" ->
    (* The JSON (verdict + diagnostics) goes to stdout. *)
    let _ = run ("--emit-core-ast " ^ q) "/dev/null" in
    let text = read_file out in
    let rejected =
      match Str.search_forward (Str.regexp {|"verdict": *"reject"|}) text 0 with
      | _ -> true
      | exception Not_found -> false
    in
    Some (rejected, codes_of text)
  | "march_check" -> result (run ("check " ^ q) "/dev/null")
  | "interp" -> result (run q "/dev/null")
  | "jit" -> result (run ("--jit " ^ q) "/dev/null")
  | "repl" ->
    (match f.repl with
     | None -> None
     | Some input ->
       let inp = Filename.concat dir "repl.txt" in
       write_file inp (input ^ ":quit\n");
       (* MARCH_CAP_TRACE: the check's decision points, quoted in a
          mismatch (Linux x86_64 CI accepts three fixtures silently). *)
       let _ = run "repl" (Filename.quote inp) in
       (* The REPL exits 0 whatever happened: a capability error is a
          rejection of the declaration. *)
       let codes = codes_of (read_file out) in
       Some (codes <> [], codes))
  | m -> Alcotest.failf "unknown mode %s" m

let agrees (f : fixture) (rejected, codes) =
  codes = f.expect && rejected = (f.expect <> [] && not f.warn_only)

(* CAP_PARITY_ONLY=fn_bound,host_scope limits a run to those fixtures (the
   edit loop; the full run gates). *)
let selected (f : fixture) =
  match Sys.getenv_opt "CAP_PARITY_ONLY" with
  | None | Some "" -> true
  | Some l -> List.mem f.name (String.split_on_char ',' l)

let test_modes_agree () =
  if not (Sys.file_exists compiler_exe) then
    Alcotest.failf "compiler not found at %s" compiler_exe;
  let problems = ref [] in
  List.iter
    (fun f ->
       List.iter
         (fun mode ->
            match run_mode f mode with
            | None -> ()
            | Some ((rejected, codes) as got) ->
              let gap = List.mem (f.name, mode) known_gaps in
              let ok = agrees f got in
              if ok && gap then
                problems :=
                  Printf.sprintf "%s/%s now agrees: remove it from known_gaps"
                    f.name mode
                  :: !problems
              else if (not ok) && not gap then
                problems :=
                  (Printf.sprintf "%s/%s: expected %s [%s], got %s [%s]" f.name
                    mode
                    (if f.expect = [] || f.warn_only then "accept" else "reject")
                    (String.concat " " f.expect)
                    (if rejected then "reject" else "accept")
                    (String.concat " " codes)
                  ^ "\n  output:\n" ^ output_excerpt ())
                  :: !problems)
         modes)
    (List.filter selected fixtures);
  match List.rev !problems with
  | [] -> ()
  | ps -> Alcotest.failf "capability mode parity:\n%s" (String.concat "\n" ps)

(* Every capability code is classified: either some fixture above expects
   it, so every mode is held to it, or it is listed here with the reason it
   needs no parity fixture.  A new static check (the narrow-capability
   scopes, restrict, grants) fails this until it gets a fixture. *)
let not_static =
  [
    ("cap_bound_needs", "declaration check inside the typechecker every mode runs; test/test_cap_fn_bounds.ml");
    ("cap_bound_iface", "declaration check inside the typechecker every mode runs; test/test_cap_fn_bounds.ml");
    ("cap_deserialize", "typechecker check on Cap values in serialized types");
    ("cap_dict_misuse", "proof-capability dictionaries, not IO authority");
    ("cap_dict_type", "proof-capability dictionaries, not IO authority");
    ("cap_grant", "typechecker: main declares no grant; test/errors/cap_grant_*");
    ("cap_host_annotation", "@[net_dest] well-formedness, reported with cap_host_unproven's check");
    ("cap_impl_invalid", "cap_impl declaration check inside the typechecker");
    ("cap_mismatch", "Cap(X) argument type check inside the typechecker");
    ("cap_narrow_invalid", "cap_narrow call check inside the typechecker");
    ("cap_needs", "the body-scan check inside the typechecker every mode runs; test/errors/cap_needs_*");
    ("cap_result_unhandled", "a type mismatch reported by the typechecker every mode runs; test/errors/cap_result_unhandled_*");
    ("cap_root_broad", "lint on a broad root capability; typechecker");
    ("cap_widen", "Cap widening check inside the typechecker");
  ]

let test_every_cap_code_is_classified () =
  let expected = List.concat_map (fun f -> f.expect) fixtures in
  let unclassified =
    List.filter
      (fun c ->
         String.length c > 4 && String.sub c 0 4 = "cap_"
         && (not (List.mem c expected))
         && not (List.mem_assoc c not_static))
      March_errors.Code.all
  in
  Alcotest.(check (list string))
    "cap_* codes with neither a parity fixture nor a not_static reason" []
    unclassified

let tests =
  [
    Alcotest.test_case "every cap code is classified" `Quick
      test_every_cap_code_is_classified;
    Alcotest.test_case "capability checks agree across modes" `Slow
      test_modes_agree;
  ]
