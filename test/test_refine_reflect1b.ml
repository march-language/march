(* Refinement reflection, phase 1b (specs/2026-10-29-refinement-reflection-design.md
   §7.1, §7.2, §9.2, §12 I8/I9; the 1b scope is specs/progress/2026-10-31-reflection-phase1b.md).

   Groups:
   - `reflect-1b`: the cheap gaps phase 1a left (hint text after a stage-2
     re-label, a guard that calls a reflected function, constructor
     ambiguity), the D17 logic hash (in each stage-2 query and in
     `--dump-impl-hashes`), and the hot-reload gate's input (`sound_hcr`);
   - `reflect-parity`: the parity net (§9.2).

   Every case drives the REAL compiler through [Test_refine_unfold]'s helpers
   (a private HOME and a fresh project directory per run). *)

module U = Test_refine_unfold

let gated = U.gated
let run = U.run
let expect = U.expect
let not_proved = U.not_proved
let contains = U.contains
let lines = U.lines

(* The `-- HINT` block of [out] whose text mentions [needle]. *)
let hint_blocks out =
  let ls = String.split_on_char '\n' out in
  let rec go acc cur = function
    | [] -> List.rev (match cur with Some b -> b :: acc | None -> acc)
    | l :: rest ->
      if String.starts_with ~prefix:"-- " l then
        go (match cur with Some b -> b :: acc | None -> acc) (Some l) rest
      else go acc (Option.map (fun b -> b ^ "\n" ^ l) cur) rest
  in
  go [] None ls |> List.filter (fun b -> String.starts_with ~prefix:"-- HINT" b)

let cat = U.cat

let gaps =
  [ gated "5a: a hint stage 2 re-labels reflect-fuel names the new reason" (fun () ->
        let out =
          run ~args:"--check --refine-report-sites=all"
            ("mod N do\n" ^ cat
           ^ {|  fn need2(xs : {List(Int) | len(_) == 2}) : Int do 0 end
  fn go() : Int do need2(cat(Cons(1, Nil), Cons(2, Nil))) end
end
|})
        in
        expect out ~line:9 ~callee:"need2" "skip:reflect-fuel";
        match List.filter (fun b -> contains b "`need2` was NOT verified") (hint_blocks out) with
        | [] -> Alcotest.failf "no refinement_unverified hint for need2:\n%s" out
        | b :: _ ->
          if not (contains b "may need more unfolding of `cat`") then
            Alcotest.failf "the hint must name the reflect-fuel reason:\n%s" b;
          if contains b "solver-undecided" then
            Alcotest.failf "the hint still names stage 1's reason:\n%s" b);
    gated "5c: a parameter refinement calling a reflected function is not R8-blocked" (fun () ->
        let src =
          {|mod P do
  fn is_small(n : Int) : Bool do n < 10 end
  fn f(n : {Int | is_small(_)}) : Int do n + 1 end
  fn need_eq(a : Int, b : {Int | _ == a}) : Int do b end
  fn b(n : Int) : Int do
    if is_small(n) do need_eq(n + 1, f(n)) else 0 end
  end
end
|}
        in
        let rep = run ~args:"--check --reflect-report" src in
        if not (List.exists (fun l -> contains l "\tf\treflected") (lines rep)) then
          Alcotest.failf "f must be reflected (its guard calls the reflected is_small):\n%s" rep;
        let out = run src in
        expect out ~line:6 ~callee:"need_eq" "proved" ~uses:"f");
    gated "5c REJECT: a guard calling a function that is not reflected blocks the function" (fun () ->
        let rep =
          run ~args:"--check --reflect-report"
            {|mod P do
  needs IO.Console
  fn noisy(n : Int) : Bool do
    println("x")
    n < 10
  end
  fn f(n : {Int | noisy(_)}) : Int do n + 1 end
end
|}
        in
        match List.find_opt (fun l -> contains l "\tf\t") (lines rep) with
        | None -> Alcotest.failf "no report row for f:\n%s" rep
        | Some l -> if contains l "\treflected\t" then Alcotest.failf "f must not be reflected: %s" l);
    gated "5c REJECT: a guard call two declarations could supply is not resolved" (fun () ->
        (* The entry's nested `mod X` and the library `X` both supply `X.small`
           (the second review's C-A shape): the guard has no single meaning. *)
        let out =
          U.run_lib ~args:"--check --reflect-report"
            ~lib:[ ("x.march", "mod X do\n  fn small(n : Int) : Bool do n < 10 end\nend\n") ]
            {|mod M do
  mod X do
    fn small(n : Int) : Bool do n < 100 end
  end
  fn f(n : {Int | X.small(_)}) : Int do n + 1 end
  fn g(n : Int) : Int do X.small(n) end
end
|}
        in
        match List.find_opt (fun l -> contains l "\tf\t" && contains l "m.march") (lines out) with
        | None -> Alcotest.failf "no report row for f:\n%s" out
        | Some l -> if contains l "\treflected\t" then Alcotest.failf "f must not be reflected: %s" l);
    gated "5b REJECT: a constructor two modules declare is not guessed" (fun () ->
        (* `K` is declared by A.T and B.U; fb(B.K(5)) is 10 at run time. *)
        let out =
          run
            {|mod M do
  mod A do
    type T = K(Int) | Z
    fn fa(x : T) : Int do
      match x do
        K(n) -> n + 1
        Z -> 0
      end
    end
  end
  mod B do
    type U = Z | K(Int)
    fn fb(x : U) : Int do
      match x do
        K(n) -> n * 2
        Z -> 0
      end
    end
  end
  fn need6(x : {Int | _ == 6}) : Int do x end
  fn a() : Int do need6(B.fb(B.K(5))) end
  fn b() : Int do need6(A.fa(A.K(5))) end
end
|}
        in
        not_proved out ~line:21 ~callee:"need6");
    gated "5b REJECT: a user Some/None does not lend its fields to Option" (fun () ->
        (* The phase-1a review's ctor2.march, with false obligations: at run
           time o(Some(98)) is 99 and val(Some(101)) is 101. *)
        let out =
          run
            {|mod M do
  fn need(x : {Int | _ == 100}) : Int do x end
  mod U do
    type Mb = Some(Int) | None
    fn val(x : Mb) : Int do
      match x do
        Some(n) -> n
        None -> 0
      end
    end
    fn b() : Int do need(val(Some(101))) end
  end
  fn o(x : Option(Int)) : Int do
    match x do
      Some(n) -> n + 1
      None -> 0
    end
  end
  fn a() : Int do need(o(Some(98))) end
end
|}
        in
        not_proved out ~line:11 ~callee:"need";
        not_proved out ~line:19 ~callee:"need") ]

(* ── D17: the logic hash (§7.1, I8) ─────────────────────────────────────── *)

(* The `reflect-def` hash of [name] in a `--reflect-deps` run. *)
let def_hash out name =
  List.find_map
    (fun l ->
      match String.split_on_char '\t' l with
      | [ "reflect-def"; _; n; h ] when n = name -> Some h
      | _ -> None)
    (lines out)

let def_hash_exn out name =
  match def_hash out name with Some h -> h | None -> Alcotest.failf "no reflect-def line for %s:\n%s" name out

(* Run [src] with the z3 log on; (output, sent query blocks). *)
let run_logged ?(env = "") ?(args = "--check --refine-report-sites=all --reflect-deps") src =
  let lg = Filename.temp_file "d17" ".log" in
  Sys.remove lg;
  let out = run ~env:(env ^ " MARCH_REFINE_Z3_LOG=" ^ Filename.quote lg) ~args src in
  let qs = U.queries_of_log lg in
  (try Sys.remove lg with Sys_error _ -> ());
  (out, qs)

let guard_src =
  {|mod G do
  fn is_small(n : Int) : Bool do n < 10 end
  fn need_small(n : {Int | _ < 10}) : Int do n end
  fn f(n : Int) : Int do
    if is_small(n) do need_small(n) else 0 end
  end
end
|}

let eq_src ~derived ~shift =
  (if shift then "-- a comment line that moves every position below it\n" else "")
  ^ {|mod E do
  fn same(a : P, b : P) : Bool do a == b end
  fn self_same(x : P) : Bool do same(x, x) end
  type P = P(Int, Int)
|}
  ^ (if derived then "  derive Eq for P\n"
     else
       {|  impl Eq(P) do
    fn eq(a : P, b : P) : Bool do
      match (a, b) do
        (P(x, _), P(y, _)) -> x == y
      end
    end
  end
|})
  ^ "end\n"

let d17 =
  [ gated "d17_line: a stage-2 query names each frontier definition's logic hash" (fun () ->
        let out, qs = run_logged guard_src in
        expect out ~line:5 ~callee:"need_small" "proved" ~uses:"is_small";
        let h = def_hash_exn out "is_small" in
        let s2 = List.filter (fun q -> contains q "|$ru_") qs in
        if s2 = [] then Alcotest.failf "no stage-2 query was sent:\n%s" out;
        if not (List.exists (fun q -> contains q ("|r:user:is_small#m.march:2:5| blake3=" ^ h)) s2) then
          Alcotest.failf "no stage-2 query carries `; reflect … blake3=%s`:\n%s" h (List.hd s2);
        List.iter
          (fun q -> if contains q "; reflect " then Alcotest.failf "a stage-1 query carries a D17 line:\n%s" q)
          (List.filter (fun q -> not (contains q "|$ru_")) qs));
    gated "d17_eq_status: a type's Eq derivation changes the hash; moving lines does not" (fun () ->
        let h_der = def_hash_exn (run ~args:"--check --reflect-deps" (eq_src ~derived:true ~shift:false)) "same" in
        let h_shift = def_hash_exn (run ~args:"--check --reflect-deps" (eq_src ~derived:true ~shift:true)) "same" in
        let h_hand = def_hash_exn (run ~args:"--check --reflect-deps" (eq_src ~derived:false ~shift:false)) "same" in
        Alcotest.(check string) "a line inserted above moves no hash" h_der h_shift;
        if h_der = h_hand then
          Alcotest.failf "derive Eq -> impl Eq must change same's logic hash (both %s)" h_der);
    gated "sound_cache (second half): a change that only removes reflectability changes the D17 line" (fun () ->
        (* `small`'s own text is the same in both versions; only its callee
           `g` gains an effect, so `small` stops being reflected. *)
        let src noisy =
          Printf.sprintf
            {|mod Sc do
  needs IO.Console
  fn small(n : Int) : Bool do g(n) end
  fn need_small(n : {Int | _ < 10}) : Int do n end
  fn f(n : Int) : Int do
    if small(n) do need_small(n) else 0 end
  end
  fn g(n : Int) : Bool do
    %s
    n < 10
  end
end
|}
            (if noisy then "println(\"g\")" else "let _k = 0")
        in
        let out1, qs1 = run_logged (src false) and out2, qs2 = run_logged (src true) in
        let line_for qs = List.exists (fun q -> contains q "; reflect |r:user:small#") qs in
        if def_hash out1 "small" = None then Alcotest.failf "small must be reflected before the edit:\n%s" out1;
        if not (line_for qs1) then Alcotest.fail "before: no D17 line for small";
        if def_hash out2 "small" <> None then Alcotest.failf "small must not be reflected after the edit:\n%s" out2;
        if line_for qs2 then Alcotest.fail "after: a D17 line still names small";
        (* Proving it needs `g`'s body too (depth 1): reflect-fuel, but the
           query ran and keyed on small. *)
        expect out1 ~line:6 ~callee:"need_small" "skip:reflect-fuel";
        not_proved out2 ~line:6 ~callee:"need_small") ]

(* ── I9: hot code reload (§7.2) ─────────────────────────────────────────── *)

(* Build [src] as a hot-reload patch; the manifest line of [fn] as fields. *)
let hcr_manifest_line src fn =
  let dir = Filename.temp_dir "hcr1b" "" in
  Fun.protect ~finally:(fun () -> try U.remove_tree dir with _ -> ()) (fun () ->
      Out_channel.with_open_bin (Filename.concat dir "m.march") (fun oc -> output_string oc src);
      let out = U.run_in ~dir "--compile --hot-reload Main --compile-so -o m.so" "m.march" in
      let mf = Filename.concat dir "m.so.hcr_manifest" in
      if not (Sys.file_exists mf) then Alcotest.failf "no manifest written:\n%s" out;
      let text = In_channel.with_open_bin mf In_channel.input_all in
      match List.find_opt (fun l -> String.starts_with ~prefix:(fn ^ " ") l) (lines text) with
      | Some l -> String.split_on_char ' ' l
      | None -> Alcotest.failf "no manifest line for %s:\n%s" fn text)

let field p fs = List.find_map (fun f -> if String.starts_with ~prefix:p f then Some (String.sub f (String.length p) (String.length f - String.length p)) else None) fs

let hcr_src ~opaque k =
  Printf.sprintf
    {|mod Main do
  needs IO.Console
  %sfn inc(n : Int) : Int do n + %d end
  fn main(_c : Cap(IO.Console)) do
    println("${inc(1)}")
  end
end
|}
    (if opaque then "@[opaque]\n  " else "") k

let hcr =
  [ Alcotest.test_case "sound_hcr: a body edit to a reflected function changes its slot hash; to an @[opaque] one, not" `Slow
      (fun () ->
        let v ~opaque k = hcr_manifest_line (hcr_src ~opaque k) "inc" in
        let sig_of fs = List.nth fs 2 in
        let r1 = v ~opaque:false 1 and r2 = v ~opaque:false 2 in
        Alcotest.(check (option string)) "same type signature" (field "tsig=" r1) (field "tsig=" r2);
        (match field "logic=" r1, field "logic=" r2 with
         | Some a, Some b -> if a = b then Alcotest.fail "the logic hash must change with the body"
         | _ -> Alcotest.failf "a reflected function's line carries logic=: %s" (String.concat " " r1));
        if sig_of r1 = sig_of r2 then
          Alcotest.fail "a reflected body edit must change the slot sig_hash (forge then refuses it)";
        let o1 = v ~opaque:true 1 and o2 = v ~opaque:true 2 in
        if field "logic=" o1 <> None then Alcotest.failf "an @[opaque] function has no logic=: %s" (String.concat " " o1);
        Alcotest.(check string) "an @[opaque] body edit keeps the slot sig_hash" (sig_of o1) (sig_of o2);
        if List.nth o1 1 = List.nth o2 1 then Alcotest.fail "the opaque edit did change the impl_hash");
    gated "dump_impl_hashes: the fourth column is the logic hash, `-` when not reflected" (fun () ->
        let dump src =
          let dir = Filename.temp_dir "dump1b" "" in
          Fun.protect ~finally:(fun () -> try U.remove_tree dir with _ -> ()) (fun () ->
              Out_channel.with_open_bin (Filename.concat dir "m.march") (fun oc -> output_string oc src);
              ignore (U.run_in ~dir "--emit-llvm --hot-reload Main --dump-impl-hashes" "m.march");
              let text = In_channel.with_open_bin (Filename.concat dir "m.hashes") In_channel.input_all in
              List.filter_map
                (fun l -> match String.split_on_char '\t' l with [ n; _; _; lg ] -> Some (n, lg) | _ -> None)
                (lines text))
        in
        let d1 = dump (hcr_src ~opaque:false 1) and d2 = dump (hcr_src ~opaque:false 2) in
        let o1 = dump (hcr_src ~opaque:true 1) in
        let col d n = match List.assoc_opt n d with Some c -> c | None -> Alcotest.failf "no row for %s" n in
        if String.length (col d1 "inc") <> 64 then Alcotest.failf "inc's logic column: %s" (col d1 "inc");
        if col d1 "inc" = col d2 "inc" then Alcotest.fail "the logic column must follow the body";
        Alcotest.(check string) "main is not reflected" "-" (col d1 "main");
        Alcotest.(check string) "an @[opaque] function is not reflected" "-" (col o1 "inc")) ]

(* ── §9.2: the parity net (group reflect-parity) ───────────────────────── *)

let parity_src = {|mod Par do
  type Shape = Sq(Int) | Rect(Int, Int) | Dot
  fn inc(n : Int) : Int do n + 1 end
  fn absv(n : Int) : Int do if n < 0 do 0 - n else n end end
  fn is_small(n : Int) : Bool do n < 10 end
  fn sign(n : Int) : Int do
    if n > 0 do 1 else if n < 0 do -1 else 0 end end
  end
  fn half(n : Int) : Int do n / 2 end
  fn rem3(n : Int) : Int do n % 3 end
  fn area(s : Shape) : Int do
    match s do
      Sq(a) -> a * a
      Rect(w, h) -> w * h
      Dot -> 0
    end
  end
  fn len2(xs : List(Int)) : Int do
    match xs do
      Nil -> 0
      Cons(_, t) -> 1 + len2(t)
    end
  end
  fn first_or(xs : List(Int), d : Int) : Int do
    match xs do
      Nil -> d
      Cons(h, _) -> h
    end
  end
  fn get_or(o : Option(Int), d : Int) : Int do
    match o do
      Some(x) -> x
      None -> d
    end
  end
  fn guarded(xs : List(Int)) : Int do
    match xs do
      Cons(h, _) when h > 0 -> h
      Nil -> 0
    end
  end
  fn pos_only(n : {Int | _ > 0}) : Int do n - 1 end
end
|}

(* (status, detail) of [name]'s parity row. *)
let parity_row out name =
  List.find_map
    (fun l ->
      match String.split_on_char '\t' l with
      | [ "parity"; _; n; st; d ] when n = name -> Some (st, d)
      | _ -> None)
    (lines out)

let parity_status out name =
  match parity_row out name with Some (st, _) -> st | None -> Alcotest.failf "no parity row for %s:\n%s" name out

let summary out = List.find_opt (fun l -> String.starts_with ~prefix:"parity: " l) (lines out)

let fixtures () =
  match U.fixtures_dir () with
  | None -> []
  | Some d ->
    Sys.readdir d |> Array.to_list |> List.filter (fun f -> Filename.check_suffix f ".march") |> List.sort compare
    |> List.map (fun f -> (f, In_channel.with_open_bin (Filename.concat d f) In_channel.input_all))

let parity =
  [ gated "parity: 0 mismatches and 0 interpreter failures on every phase fixture and the parity program" (fun () ->
        let compared = ref 0 in
        List.iter
          (fun (f, src) ->
            let out = run ~args:"--check --reflect-parity" src in
            (match summary out with
             | None -> Alcotest.failf "%s: no parity summary:\n%s" f out
             | Some s ->
               if not (contains s " 0 mismatch, 0 interpreter failure") then Alcotest.failf "%s: %s\n%s" f s out);
            List.iter (fun l -> if contains l "\tagree\t" then incr compared) (lines out))
          (("parity_program", parity_src) :: fixtures ());
        if !compared < 20 then Alcotest.failf "only %d functions compared: the net is vacuous" !compared);
    gated "parity: boundary Ints are overflow?, never a mismatch (D8)" (fun () ->
        let out = run ~args:"--check --reflect-parity" parity_src in
        Alcotest.(check string) "inc at the maximum Int" "overflow?" (parity_status out "inc");
        (match parity_row out "inc" with
         | Some (_, d) -> if not (contains d "4611686018427387903") then Alcotest.failf "inc's overflow input: %s" d
         | None -> ());
        Alcotest.(check string) "half: the evaluator's own 63-bit limit is not overflow?" "agree" (parity_status out "half");
        Alcotest.(check string) "area over a user type" "agree" (parity_status out "area");
        Alcotest.(check string) "get_or over Option" "agree" (parity_status out "get_or");
        Alcotest.(check string) "a refined parameter: only inputs inside pre_f" "agree" (parity_status out "pos_only");
        if parity_row out "guarded" <> None then Alcotest.fail "guarded is R5-blocked, so it is not in the net");
    gated "parity RED: an arms-swapped term_of_body is a mismatch" (fun () ->
        let out = run ~env:"MARCH_REFLECT_PERTURB=swap-arms" ~args:"--check --reflect-parity" parity_src in
        Alcotest.(check string) "absv" "MISMATCH" (parity_status out "absv");
        Alcotest.(check string) "get_or" "MISMATCH" (parity_status out "get_or");
        if not (contains out "parity: RED") then Alcotest.failf "the net must report RED:\n%s" out);
    gated "parity RED: a guarded match R5 wrongly admits panics in the interpreter: RED, not not-compared" (fun () ->
        let out = run ~env:"MARCH_REFLECT_PERTURB=r5-guarded" ~args:"--check --reflect-parity" parity_src in
        Alcotest.(check string) "guarded" "INTERPRETER-FAILURE" (parity_status out "guarded");
        if not (contains out "parity: RED") then Alcotest.failf "the net must report RED:\n%s" out) ]
