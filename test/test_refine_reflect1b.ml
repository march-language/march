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
  fn go(xs : List(Int)) : Int do need2(cat(xs, Cons(2, Nil))) end
end
|})
        in
        (* `xs` unknown: the produced `cat(Cons_1(xs), ..)` is undecided, so
           it is not unfolded (phase 4 proves the literal `cat([1], [2])`). *)
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
      | [ "reflect-def"; _; n; h ] when n = name || String.ends_with ~suffix:("." ^ name) n -> Some h
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
        (* Proving it needs `g`'s body too, one decided step deeper (phase 4:
           proved; phase 1 stopped at depth 0 with reflect-fuel).  The query
           ran and keyed on small either way. *)
        expect out1 ~line:6 ~callee:"need_small" "proved";
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

let hcr_src ?(used = true) ~opaque k =
  (* [used]: a caller's precondition needs [inc]'s body, so a stage-2 query
     unfolds it and the slot hash carries its logic hash.  Unused, no proof
     depends on the body and a hot patch may change it. *)
  Printf.sprintf
    {|mod Main do
  needs IO.Console
  %sfn inc(n : Int) : Int do n + %d end
  fn need_big(n : {Int | _ > 1}) : Int do n end
  fn main(_c : Cap(IO.Console)) do
    println("${%s}")
  end
end
|}
    (if opaque then "@[opaque]\n  " else "") k
    (if used then "need_big(inc(1))" else "inc(1)")

let hcr =
  [ Alcotest.test_case "sound_hcr: a body edit to a reflected function a proof used changes its slot hash; to an unused or @[opaque] one, not" `Slow
      (fun () ->
        let v ?used ~opaque k = hcr_manifest_line (hcr_src ?used ~opaque k) "inc" in
        let sig_of fs = List.nth fs 2 in
        let r1 = v ~opaque:false 1 and r2 = v ~opaque:false 2 in
        Alcotest.(check (option string)) "same type signature" (field "tsig=" r1) (field "tsig=" r2);
        (match field "logic=" r1, field "logic=" r2 with
         | Some a, Some b -> if a = b then Alcotest.fail "the logic hash must change with the body"
         | _ -> Alcotest.failf "a proof-used reflected function's line carries logic=: %s" (String.concat " " r1));
        if sig_of r1 = sig_of r2 then
          Alcotest.fail "a proof-used reflected body edit must change the slot sig_hash (forge then refuses it)";
        let u1 = v ~used:false ~opaque:false 1 and u2 = v ~used:false ~opaque:false 2 in
        if field "logic=" u1 <> None then
          Alcotest.failf "a reflected function no proof used has no logic=: %s" (String.concat " " u1);
        Alcotest.(check string) "an unused reflected body edit keeps the slot sig_hash" (sig_of u1) (sig_of u2);
        if List.nth u1 1 = List.nth u2 1 then Alcotest.fail "the unused edit did change the impl_hash";
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
         | Some (_, d) ->
           if not (contains d "4611686018427387903") then Alcotest.failf "inc's overflow input: %s" d;
           (* review round 1: an overflow? row says how many inputs agreed *)
           if not (contains d "inputs compared") then Alcotest.failf "inc's overflow? row carries the compared count: %s" d
         | None -> ());
        Alcotest.(check string) "half: the evaluator's own 63-bit limit is not overflow?" "agree" (parity_status out "half");
        Alcotest.(check string) "area over a user type" "agree" (parity_status out "area");
        Alcotest.(check string) "get_or over Option" "agree" (parity_status out "get_or");
        Alcotest.(check string) "a refined parameter: only inputs inside pre_f" "agree" (parity_status out "pos_only");
        if parity_row out "guarded" <> None then Alcotest.fail "guarded is R5-blocked, so it is not in the net");
    gated "parity: a logic side that fails on every input is not-compared, not overflow? (review round 1)" (fun () ->
        (* k compares Floats with the opaque Float `==` (D9), which the
           evaluator does not model; f calls it, so f's logic side fails on
           every input while the interpreter overflows at the maximum Int.
           Zero inputs compared: no evidence either way. *)
        let src =
          {|mod P3 do
  fn k(n : Int) : Int do
    if 2.0 == 2.0 do n + 1 else n - 1 end
  end
  fn f(n : Int) : Int do k(n) + n end
end
|}
        in
        let out = run ~args:"--check --reflect-parity" src in
        Alcotest.(check string) "f" "not-compared" (parity_status out "f");
        Alcotest.(check string) "k (reflected, the opaque Float ==)" "not-compared" (parity_status out "k"));
    gated "parity: a reflected function with no logic definition is listed, not dropped (review round 1)" (fun () ->
        let src =
          {|mod P1 do
  fn f(n : Int, x : Float) : Int do
    if x == x do n + 1 else n end
  end
  type Bx = { v : Int }
  type By = { v : Int }
  fn g(n : Int) : Int do
    let b = { v: n }
    b.v + 1
  end
end
|}
        in
        let out = run ~args:"--check --reflect-parity" src in
        Alcotest.(check string) "f" "not-compared" (parity_status out "f");
        (match parity_row out "g" with
         | Some (st, d) ->
           Alcotest.(check string) "g" "not-compared" st;
           if not (contains d "no logic definition") then Alcotest.failf "g's reason: %s" d
         | None -> Alcotest.failf "no parity row for g:\n%s" out);
        (match summary out with
         | Some l -> if not (contains l "2 functions") then Alcotest.failf "summary: %s" l
         | None -> Alcotest.failf "no summary:\n%s" out);
        (* review round 2: a run that compared no input is not green *)
        if not (contains out "parity: NOTHING COMPARED") then
          Alcotest.failf "a run with no compared input says so:\n%s" out;
        if contains (run ~args:"--check --reflect-parity" parity_src) "NOTHING COMPARED" then
          Alcotest.fail "the parity program compares inputs");
    (* §3.2: a tuple or record drawn as an input is a tuple or record to the
       interpreter, and a tuple or record result is read back as one. *)
    gated "parity: functions over tuples and records agree" (fun () ->
        let src =
          {|mod PT do
  type Pt = { x : Int, y : Int }
  fn sw(t : (Int, Int)) : Int do match t do (a, b) -> a - b end end
  fn fst2(t : (Int, Bool)) : Int do
    let (a, _) = t
    a
  end
  fn swp(t : (Int, Int)) : (Int, Int) do match t do (a, b) -> (b, a) end end
  fn px(p : Pt) : Int do p.x - p.y end
  fn bump(p : Pt) : Pt do { p with x: p.y } end
  fn sx(p : Pt) : Int do
    let { x, y } = p
    x - 2 * y
  end
end
|}
        in
        let out = run ~args:"--check --reflect-parity" src in
        List.iter
          (fun f -> Alcotest.(check string) f "agree" (parity_status out f))
          [ "sw"; "fst2"; "swp"; "px"; "bump"; "sx" ]);
    gated "parity RED: an arms-swapped term_of_body is a mismatch" (fun () ->
        let out = run ~env:"MARCH_REFLECT_PERTURB=swap-arms" ~args:"--check --reflect-parity" parity_src in
        Alcotest.(check string) "absv" "MISMATCH" (parity_status out "absv");
        Alcotest.(check string) "get_or" "MISMATCH" (parity_status out "get_or");
        if not (contains out "parity: RED") then Alcotest.failf "the net must report RED:\n%s" out);
    gated "parity RED: a guarded match R5 wrongly admits panics in the interpreter: RED, not not-compared" (fun () ->
        let out = run ~env:"MARCH_REFLECT_PERTURB=r5-guarded" ~args:"--check --reflect-parity" parity_src in
        Alcotest.(check string) "guarded" "INTERPRETER-FAILURE" (parity_status out "guarded");
        if not (contains out "parity: RED") then Alcotest.failf "the net must report RED:\n%s" out) ]

(* ── The constructor registry, keyed by (datatype, constructor) ──────────
   (specs/progress/2026-11-02-reflection-ctor-registry-by-datatype.md).  A
   constructor name two datatypes declare gets one SMT constructor per
   datatype, `<datatype sort>$<Ctor>`; a source `Some` is resolved by the
   type the checker knows for it, and declines when that type does not pin
   one datatype. *)

let ctor_src =
  {|mod M do
  fn need(x : {Int | _ == 100}) : Int do x end
  mod U do
    type Mb = Some(Int) | None
    fn val(x : Mb) : Int do
      match x do
        Some(n) -> n + 2
        None -> 0
      end
    end
    fn b() : Int do need(val(Some(98))) end
    fn b2() : Int do need(val(Some(97))) end
  end
  fn wrap(n : Int) : Option(Int) do Some(n) end
  fn get(x : Option(Int)) : Int do
    match x do
      Some(n) -> n
      None -> 0
    end
  end
  fn a() : Int do need(get(wrap(100))) end
  fn c() : Int do need(get(Some(100))) end
  fn d() : Int do need(get(Some(98))) end
end
|}

(* Every `declare-datatypes` of an `M_Option` instance in [qs], as (instance
   suffix, the payload field's declared sort). *)
let option_decls qs =
  let re = Str.regexp {|((M_Option\([^ ]*\) 0)) ((([^()]*None) ([^ ]*Some ([^ ]*Some_0 \([^()]*\))))))|} in
  List.concat_map
    (fun q ->
      let rec go pos acc =
        match Str.search_forward re q pos with
        | exception Not_found -> List.rev acc
        | i -> go (i + 1) ((Str.matched_group 1 q, Str.matched_group 2 q) :: acc)
      in
      go 0 [])
    qs

let ctor_registry =
  [ gated "ctor (a): a user Some(Int) leaves Option's sorts alone, and Option functions are reflected" (fun () ->
        let out, qs = run_logged ~args:"--check --refine-report-sites=all" ctor_src in
        expect out ~line:21 ~callee:"need" "proved" ~uses:"wrap";
        expect out ~line:22 ~callee:"need" "proved" ~uses:"get";
        let ds = option_decls qs in
        if ds = [] then Alcotest.failf "no Option datatype declaration in the z3 log (vacuous)";
        List.iter
          (fun (suffix, field) ->
            let want = if suffix = "" then "Elem" else if suffix = "$Int" then "Int" else String.sub suffix 1 (String.length suffix - 1) in
            if field <> want then
              Alcotest.failf "M_Option%s declares Some's payload as %s (want %s): the user type lent its fields"
                suffix field want)
          ds);
    gated "ctor (b): one program matching on a user Some and Option's Some resolves each to its own type" (fun () ->
        let out = run ctor_src in
        expect out ~line:11 ~callee:"need" "proved" ~uses:"val";
        expect out ~line:22 ~callee:"need" "proved" ~uses:"get");
    gated "ctor (d): a violation through colliding constructor names is still a violation" (fun () ->
        let out = run ctor_src in
        (* U.val(Some(97)) is 99 and get(Some(98)) is 98 at run time. *)
        expect out ~line:12 ~callee:"need" "violated";
        expect out ~line:23 ~callee:"need" "violated");
    gated "ctor (c): a type name two modules declare does not pin a datatype: declined, not guessed" (fun () ->
        (* Both modules declare `type T` with a `K`; whichever datatype a
           guess picked, one of the two calls would be decided wrongly. *)
        let out =
          run
            {|mod M do
  mod A do
    type T = K(Int) | Z
    fn f(x : T) : Int do
      match x do
        K(n) -> n + 1
        Z -> 0
      end
    end
  end
  mod B do
    type T = Z | K(Int)
    fn f(x : T) : Int do
      match x do
        K(n) -> n * 2
        Z -> 0
      end
    end
  end
  fn need6(x : {Int | _ == 6}) : Int do x end
  fn a() : Int do need6(B.f(B.K(3))) end
  fn b() : Int do need6(A.f(A.K(3))) end
end
|}
        in
        (* B.f(B.K(3)) is 6 and A.f(A.K(3)) is 4 at run time: a proof of
           either line, or a violation of line 21, is a guess. *)
        not_proved out ~line:21 ~callee:"need6";
        not_proved out ~line:22 ~callee:"need6";
        (match U.rows out ~line:21 ~callee:"need6" with
         | rs when List.exists (fun (v, _) -> v = "violated") rs ->
           Alcotest.failf "line 21 (true at run time) reported violated:\n%s" out
         | _ -> ()));
    gated "ctor: a library module declaring Some(Int), reached directly and by `alias`, lends Option nothing" (fun () ->
        (* L.val(L.Some(98)) is 100 and V.val(V.Some(99)) is 101 at run time.
           A library function is not unfolded today (so neither is proved);
           what must hold is that no guess decides either, and that Option's
           own sites are decided at Option's sorts. *)
        let out =
          U.run_lib
            ~lib:[ ("l.march", "mod L do\n  type Mb = Some(Int) | None\n  fn val(x : Mb) : Int do\n    match x do\n      Some(n) -> n + 2\n      None -> 0\n    end\n  end\nend\n") ]
            {|mod M do
  fn need(x : {Int | _ == 100}) : Int do x end
  fn get(x : Option(Int)) : Int do
    match x do
      Some(n) -> n
      None -> 0
    end
  end
  alias L as V
  fn a() : Int do need(get(Some(100))) end
  fn b() : Int do need(get(Some(99))) end
  fn c() : Int do need(L.val(L.Some(98))) end
  fn d() : Int do need(V.val(V.Some(98))) end
  fn e() : Int do need(V.val(V.Some(99))) end
end
|}
        in
        expect ~file:"m.march" out ~line:10 ~callee:"need" "proved" ~uses:"get";
        expect ~file:"m.march" out ~line:11 ~callee:"need" "violated";
        List.iter
          (fun line ->
            match U.rows ~file:"m.march" out ~line ~callee:"need" with
            | [] -> Alcotest.failf "no need row at line %d:\n%s" line out
            | rs ->
              let bad = if line = 14 then "proved" else "violated" in
              if List.exists (fun (v, _) -> v = bad) rs then
                Alcotest.failf "line %d must not be %s:\n%s" line bad out)
          [ 12; 13; 14 ]);
    gated "ctor: a nested module named like a stdlib module, declaring Some, does not lend its fields" (fun () ->
        (* `mod Option` inside the entry collides with nothing the checker
           keys on, but its `Some(Int)` collides with Option's `Some(a)`. *)
        let out =
          run
            {|mod M do
  fn need(x : {Int | _ == 100}) : Int do x end
  mod Option do
    type Mb = Some(Int) | None
    fn val(x : Mb) : Int do
      match x do
        Some(n) -> n + 2
        None -> 0
      end
    end
  end
  fn get(x : Option(Int)) : Int do
    match x do
      Some(n) -> n
      None -> 0
    end
  end
  fn a() : Int do need(get(Some(98))) end
  fn b() : Int do need(Option.val(Option.Some(98))) end
end
|}
        in
        (* get(Some(98)) is 98; Option.val(Option.Some(98)) is 100 (not
           unfolded today: a module named `Option` is not resolved). *)
        expect out ~line:18 ~callee:"need" "violated";
        (match U.rows out ~line:19 ~callee:"need" with
         | rs when List.exists (fun (v, _) -> v = "violated") rs ->
           Alcotest.failf "line 19 (true at run time) reported violated:\n%s" out
         | _ -> ()));
    gated "ctor: a predicate tester on a colliding name resolves by the argument's type" (fun () ->
        let out =
          run
            {|mod M do
  mod U do
    type Mb = Some(Int) | None
  end
  fn need_some(x : {Option(Int) | is_Some(_)}) : Int do 0 end
  fn a() : Int do need_some(Some(1)) end
  fn b() : Int do need_some(None) end
end
|}
        in
        expect out ~line:6 ~callee:"need_some" "proved";
        expect out ~line:7 ~callee:"need_some" "violated") ]

(* ── Review round 1 of the constructor registry (c87e66495) ─────────────── *)

(* C1: `W1`'s field is declared `Tq`, a type name two modules declare; the
   field's datatype must not be taken from the name's preferred declarant.
   At run time B.c4(B.W1(B.Z)) passes 0 to need1. *)
let c1_src =
  {|mod M do
  fn need1(x : {Int | _ == 1}) : Int do x end
  mod A do
    type Tq = K(Int)
  end
  mod B do
    type Tq = K(Int) | Z
    type W = W1(Tq)
    fn g(w : W) : Int do
      match w do
        W1(K(n)) -> 1
        W1(_) -> 0
      end
    end
    fn c4(w : W) : Int do need1(g(w)) end
  end
end
|}

(* C2: a nested user type named like a built-in.  [ty] is the user type's
   declaration, [tester]/[bad] a tester and a built-in value it is false of. *)
let c2_src ~decl ~ty ~tester ~bad =
  Printf.sprintf
    {|mod M do
  mod A do
    %s
  end
  fn need(x : {%s | %s(_)}) : Int do 0 end
  fn mk(n : Int) : %s do %s end
  fn b(y : %s) : Int do need(y) end
  fn c() : Int do need(mk(0)) end
end
|}
    decl ty tester ty bad ty

let c2_case name ~decl ~ty ~tester ~bad =
  gated ("ctor review C2: a nested `" ^ name ^ "` does not replace the built-in") (fun () ->
      let out = run (c2_src ~decl ~ty ~tester ~bad) in
      (* mk(0) is the built-in's other constructor; y is anything. *)
      not_proved out ~line:7 ~callee:"need";
      not_proved out ~line:8 ~callee:"need")

let ctor_review =
  [ gated "ctor review C1: a nested pattern does not resolve through a field type two modules declare" (fun () ->
        let out = run c1_src in
        not_proved out ~line:15 ~callee:"need1");
    gated "ctor review I1: the parity net does not report a C1-shaped function as agreeing" (fun () ->
        let out = run ~args:"--check --reflect-parity" c1_src in
        match parity_row out "B.g" with
        | Some ("agree", _) -> Alcotest.failf "B.g reported agreeing on a model that cannot build W1(Z):\n%s" out
        | _ -> ());
    gated "ctor review I1: the parity generator draws nothing from a field type two modules declare" (fun () ->
        (* `h`'s body is translated (it resolves no `Tq` constructor), so only
           the generator stands between it and a draw of `W1` built from the
           wrong `Tq`. *)
        let src =
          {|mod M do
  mod A do
    type Tq = K(Int)
  end
  mod B do
    type Tq = K(Int) | Z
    type W = W1(Tq)
    fn h(w : W) : Int do
      match w do
        W1(_) -> 0
      end
    end
  end
end
|}
        in
        let out = run ~args:"--check --reflect-parity" src in
        match parity_row out "B.h" with
        | Some ("not-compared", d) when contains d "generator" -> ()
        | r ->
          Alcotest.failf "B.h must be not-compared for want of a generator, got %s:\n%s"
            (match r with Some (st, d) -> st ^ " " ^ d | None -> "no row") out);
    c2_case "type Option(a) = Some(a)" ~decl:"type Option(a) = Some(a)" ~ty:"Option(Int)" ~tester:"is_Some" ~bad:"None";
    c2_case "type Result(a, e) = Ok(a)" ~decl:"type Result(a, e) = Ok(a)" ~ty:"Result(Int, Int)" ~tester:"is_Ok"
      ~bad:"Err(0)";
    c2_case "type List(a) = Cons(a, List(a))" ~decl:"type List(a) = Cons(a, List(a))" ~ty:"List(Int)"
      ~tester:"is_Cons" ~bad:"Nil";
    gated "ctor review C2: a TOP-LEVEL `type Option` does not replace the built-in either" (fun () ->
        let out =
          run
            {|mod M do
  type Option(a) = Some(a)
  fn need(x : {Option(Int) | is_Some(_)}) : Int do 0 end
  fn b(y : Option(Int)) : Int do need(y) end
end
|}
        in
        not_proved out ~line:4 ~callee:"need") ]

(* ── Review round 2 (of c87e66495 + 037744add) ─────────────────────────────
   The typechecker treats two types of one short name as ONE type (A.Tq and
   B.Tq unify; `todo 2026-11-02-typecheck-conflates-same-short-named-types`),
   so a constructor only A.Tq declares can be matched against a B.Tq value.
   Each program below proved a call that is violated at run time. *)
let ctor_review2 =
  [ gated "ctor review2 c1: a nested pattern `W1(KA(n))` on a field type two modules declare" (fun () ->
        let out =
          run
            {|mod M do
  fn need1(x : {Int | _ == 1}) : Int do x end
  mod A do
    type Tq = KA(Int)
  end
  mod B do
    type Tq = K(Int) | Z
    type W = W1(Tq)
    fn g(w : W) : Int do
      match w do
        W1(KA(n)) -> 1
        W1(_) -> 0
      end
    end
    fn c4(w : W) : Int do need1(g(w)) end
    fn c5() : Int do need1(g(W1(Z))) end
  end
end
|}
        in
        not_proved out ~line:15 ~callee:"need1");
    gated "ctor review2 c2: a `match` arm's exclusion through a type name two modules declare" (fun () ->
        let out =
          run
            {|mod M do
  needs IO
  fn need1(x : {Int | _ == 1}) : Int do x end
  mod A do
    type Tq = KA(Int)
  end
  mod B do
    type Tq = K(Int) | Z
    fn f(x : Tq) : Int do
      match x do
        KA(_) -> 1
        _ -> need1(0)
      end
    end
    fn f2(x : Tq) : Int do
      match x do
        KA(n) -> need1(n)
        _ -> 1
      end
    end
  end
  fn main(cap : Cap(IO)) : Unit do
    println(int_to_string(B.f(B.Z)))
  end
end
|}
        in
        not_proved out ~line:12 ~callee:"need1");
    gated "ctor review2 c3: a top-level user `type Option` beside the built-in: `_` arm" (fun () ->
        let out =
          run
            {|mod M do
  needs IO
  fn need1(x : {Int | _ == 1}) : Int do x end
  type Option(a) = Only(a)
  fn f(x : Option(Int)) : Int do
    match x do
      Only(_) -> 1
      _ -> need1(0)
    end
  end
  fn main(cap : Cap(IO)) : Unit do
    println(int_to_string(f(None)))
  end
end
|}
        in
        not_proved out ~line:8 ~callee:"need1");
    gated "ctor review2 c4: a call-site tester on a value of a type name two modules declare" (fun () ->
        let out =
          run
            {|mod M do
  needs IO
  mod A do
    type Tq = KA(Int)
  end
  mod B do
    type Tq = K(Int) | Z
    fn need_ka(x : {Tq | is_KA(_)}) : Int do
      match x do
        KA(_) -> 1
        _ -> 0
      end
    end
    fn c(x : Tq) : Int do need_ka(x) end
    fn d() : Int do need_ka(Z) end
  end
  fn main(cap : Cap(IO)) : Unit do
    println(int_to_string(B.c(B.Z)))
  end
end
|}
        in
        not_proved out ~line:14 ~callee:"B.need_ka");
    gated "ctor review2 c5: a user `type DownReason` beside the built-in/stdlib one" (fun () ->
        let out =
          run
            {|mod M do
  needs IO
  fn need1(x : {Int | _ == 1}) : Int do x end
  type DownReason = OnlyR(Int)
  fn f(x : DownReason) : Int do
    match x do
      OnlyR(_) -> 1
      _ -> need1(0)
    end
  end
  fn main(cap : Cap(IO)) : Unit do
    println(int_to_string(f(DownReason.Killed)))
  end
end
|}
        in
        not_proved out ~line:8 ~callee:"need1");
    gated "ctor review2: a program with no short-name conflation keeps its proofs" (fun () ->
        let out = run ctor_src in
        expect out ~line:11 ~callee:"need" "proved" ~uses:"val";
        expect out ~line:21 ~callee:"need" "proved" ~uses:"wrap";
        expect out ~line:22 ~callee:"need" "proved" ~uses:"get";
        expect out ~line:23 ~callee:"need" "violated") ]

(* ── Review round 3 ────────────────────────────────────────────────────────
   Declarants the earlier rounds missed: a second declaration at the SAME
   module path (the typechecker merges both), a type the typechecker
   synthesises (an actor's `<Actor>_Msg`), and a tester on a value whose
   known type is not a registered variant.  Each program proved a call that
   is violated at run time. *)
let ctor_review3 =
  [ gated "ctor review3 h5: a second `type Zq` in the same module is a second declarant" (fun () ->
        let out =
          run
            {|mod M do
  needs IO
  fn need1(x : {Int | _ == 1}) : Int do x end
  type Zq = Pz | Qz
  fn mk() : Zq do Pz end
  type Zq = Rz(Int) | Sz
  fn f(t : Zq, n : Int) : Int do
    match t do
      Rz(_) -> 1
      Sz -> 1
      _ -> need1(n)
    end
  end
  fn main(cap : Cap(IO)) : Unit do
    println(int_to_string(f(mk(), 0)))
  end
end
|}
        in
        not_proved out ~line:11 ~callee:"need1");
    gated "ctor review3 h6: a second `type Zq` in a reopened `mod A` is a second declarant" (fun () ->
        let out =
          run
            {|mod M do
  needs IO
  fn need1(x : {Int | _ == 1}) : Int do x end
  mod A do
    type Zq = Pz | Qz
    fn mk() : Zq do Pz end
  end
  mod A do
    type Zq = Rz(Int)
    fn f(t : Zq, n : Int) : Int do
      match t do
        Rz(_) -> 1
        _ -> need1(n)
      end
    end
  end
  fn main(cap : Cap(IO)) : Unit do
    println(int_to_string(A.f(A.mk(), 0)))
  end
end
|}
        in
        not_proved out ~line:13 ~callee:"need1");
    gated "ctor review3 m1: a user `mod Membership` declaring the stdlib's `MemberStatus` path again" (fun () ->
        let out =
          run
            {|mod M do
  needs IO
  fn need1(x : {Int | _ == 1}) : Int do x end
  mod Membership do
    type MemberStatus = Gone(Int)
    fn f(t : MemberStatus, n : Int) : Int do
      match t do
        Gone(_) -> 1
        _ -> need1(n)
      end
    end
  end
  fn main(cap : Cap(IO)) : Unit do
    println(int_to_string(Membership.f(Alive, 0)))
  end
end
|}
        in
        not_proved out ~line:9 ~callee:"need1");
    gated "ctor review3 ac1: a user `type Counter_Msg` beside actor Counter's message type" (fun () ->
        let out =
          run
            {|mod M do
  needs IO
  fn need1(x : {Int | _ == 1}) : Int do x end
  actor Counter do
    state { v : Int }
    init { v: 0 }
    on Inc() do { state with v: state.v + 1 } end
  end
  type Counter_Msg = Rz(Int)
  fn f(t : Counter_Msg, n : Int) : Int do
    match t do
      Rz(_) -> 1
      _ -> need1(n)
    end
  end
  fn main(cap : Cap(IO)) : Unit do
    println(int_to_string(f(Inc(), 0)))
  end
end
|}
        in
        not_proved out ~line:13 ~callee:"need1");
    gated "ctor review3 t1: a tester on a value whose known type is not a variant (`Int`)" (fun () ->
        let out =
          run
            {|mod M do
  needs IO
  type Zq = Rz(Int)
  fn need(x : {a | is_Rz(_)}) : Int do 1 end
  fn c(y : Option(Int)) : Int do need(y) end
  fn needi(x : {Int | is_Rz(_)}) : Int do 1 end
  fn d(n : Int) : Int do needi(n) end
  fn e() : Int do need(None) end
  fn main(cap : Cap(IO)) : Unit do
    println(int_to_string(c(None)))
  end
end
|}
        in
        not_proved out ~line:7 ~callee:"needi");
    gated "ctor review3: the renamed control (no conflation) keeps its proofs" (fun () ->
        let out =
          run
            {|mod M do
  type Stazus = Active(Int) | Gone
  fn need(x : {Stazus | is_Active(_)}) : Int do 1 end
  fn a() : Int do need(Active(1)) end
  fn b() : Int do need(Gone) end
  fn c(s : Stazus) : Int do
    match s do
      Active(_) -> need(s)
      Gone -> 0
    end
  end
end
|}
        in
        expect out ~line:4 ~callee:"need" "proved";
        expect out ~line:5 ~callee:"need" "violated";
        expect out ~line:8 ~callee:"need" "proved") ]

(* ── Review round 4 ────────────────────────────────────────────────────────
   A qualified type name (`Counter.Msg`, the actor message alias) resolved by
   its last segment, a tester on an actual whose type is a type variable,
   typechecker-made types outside the built-in type table (`CancelToken`,
   `TimerRef`), and a measure applied to an actual of another type.  Each
   program proved a call that is violated at run time (or ill-typed for the
   measure). *)
let ctor_review4 =
  [ gated "ctor review4 msg3: `Counter.Msg` is the actor's message type, not an unrelated `U.Msg`" (fun () ->
        let out =
          run
            {|mod M do
  needs IO
  mod U do
    type Msg = Zap(Int)
  end
  actor Counter do
    state { v : Int }
    init { v: 0 }
    on Inc() do { state with v: state.v + 1 } end
  end
  fn need(m : Counter.Msg, n : {Int | is_Zap(m)}) : Int do n end
  fn c(m : Counter.Msg) : Int do need(m, 1) end
  fn d() : Int do need(Inc(), 1) end
  fn main(cap : Cap(IO)) : Unit do
    println(int_to_string(c(Inc())))
  end
end
|}
        in
        not_proved out ~line:12 ~callee:"need");
    gated "ctor review4 msg2: `Counter.Msg` in a refined parameter's own base type" (fun () ->
        let out =
          run
            {|mod M do
  needs IO
  mod U do
    type Msg = Zap(Int)
  end
  actor Counter do
    state { v : Int }
    init { v: 0 }
    on Inc() do { state with v: state.v + 1 } end
  end
  fn need(x : {Counter.Msg | is_Zap(_)}, n : {Int | _ > 0}) : Int do n end
  fn c(m : Counter.Msg) : Int do need(m, 1) end
  fn main(cap : Cap(IO)) : Unit do
    println(int_to_string(c(Inc())))
  end
end
|}
        in
        (* Line 12's `_ > 0` on `n` is a legitimate proof; the `is_Zap` one
           on `x` must not be. *)
        List.iter
          (fun l ->
            if contains l "is_Zap" && String.starts_with ~prefix:"proved" l then
              Alcotest.failf "is_Zap(_) proved for a Counter.Msg value:\n%s" out)
          (lines out));
    gated "ctor review4 tv2: a tester on an actual whose type is a type variable" (fun () ->
        let out =
          run
            {|mod M do
  needs IO
  type Zq = Rz(Int)
  fn need(m : a, n : {Int | is_Rz(m)}) : Int do n end
  fn c(y : b) : Int do need(y, 1) end
  fn d(y : Option(Int)) : Int do need(y, 1) end
  fn e() : Int do need(None, 1) end
  fn f() : Int do need(5, 1) end
  fn main(cap : Cap(IO)) : Unit do
    println(int_to_string(c(None)))
  end
end
|}
        in
        not_proved out ~line:5 ~callee:"need");
    gated "ctor review4 ct1: a user `type CancelToken` beside the typechecker's own" (fun () ->
        let out =
          run
            {|mod M do
  needs IO
  type CancelToken = Tok(Int)
  fn need(m : CancelToken, n : {Int | is_Tok(m)}) : Int do n end
  fn c(t : CancelToken) : Int do need(t, 1) end
  fn main(cap : Cap(IO)) : Unit do
    let t = task_cancel_token_new()
    println(int_to_string(c(t)))
  end
end
|}
        in
        not_proved out ~line:5 ~callee:"need");
    gated "ctor review4 ct3: a nested pattern over a user `CancelToken`" (fun () ->
        let out =
          run
            {|mod M do
  needs IO
  type CancelToken = Tok(Int)
  fn need1(x : {Int | _ == 1}) : Int do
    println("need1 got " ++ int_to_string(x))
    x
  end
  fn g(o : Option(CancelToken)) : Int do
    match o do
      Some(Tok(_)) -> 1
      _ -> 0
    end
  end
  fn c(o : Option(CancelToken)) : Int do need1(g(o)) end
  fn c2(o : Option(CancelToken)) : Int do match o do
      Some(_) -> need1(g(o))
      None -> 1
    end
  end
  fn main(cap : Cap(IO)) : Unit do
    let t = task_cancel_token_new()
    println(int_to_string(c2(Some(t))))
  end
end
|}
        in
        not_proved out ~line:16 ~callee:"need1");
    gated "ctor review4 tr1: a user `type TimerRef` beside the typechecker's own" (fun () ->
        let out =
          run
            {|mod M do
  needs IO
  type TimerRef = Tm(Int)
  fn need(m : TimerRef, n : {Int | is_Tm(m)}) : Int do n end
  fn c(t : TimerRef) : Int do need(t, 1) end
end
|}
        in
        not_proved out ~line:5 ~callee:"need");
    gated "ctor review4 ms1: a measure applied to an actual not of its datatype" (fun () ->
        let out =
          run
            {|mod M do
  needs IO
  type Zq = Rz(Int) | Qz
  @[measure]
  fn cnt(t : Zq) : Int do
    match t do
      Rz(_) -> 1
      Qz -> 1
    end
  end
  fn need(m : a, n : {Int | cnt(m) > 0}) : Int do n end
  fn c(y : b) : Int do need(y, 1) end
  fn d(y : Option(Int)) : Int do need(y, 1) end
  fn d2(y : Int) : Int do need(y, 1) end
  fn e() : Int do need(None, 1) end
  fn main(cap : Cap(IO)) : Unit do
    println(int_to_string(c(None)))
  end
end
|}
        in
        not_proved out ~line:12 ~callee:"need";
        not_proved out ~line:13 ~callee:"need";
        not_proved out ~line:14 ~callee:"need");
    gated "ctor review4 control ct1c: no conflation, the proof stays" (fun () ->
        let out =
          run
            {|mod M do
  needs IO
  type CancelTokn = Tok(Int)
  fn need(m : CancelTokn, n : {Int | is_Tok(m)}) : Int do n end
  fn c(t : CancelTokn) : Int do need(t, 1) end
  fn main(cap : Cap(IO)) : Unit do
    let t = Tok(3)
    println(int_to_string(c(t)))
  end
end
|}
        in
        expect out ~line:5 ~callee:"need" "proved");
    gated "ctor review4 control msg1c: no conflation, the proof stays" (fun () ->
        let out =
          run
            {|mod M do
  needs IO
  mod U do
    type Msg = Zap(Int)
  end
  actor Counter do
    state { v : Int }
    init { v: 0 }
    on Inc() do { state with v: state.v + 1 } end
  end
  fn need(x : {U.Msg | is_Zap(_)}) : Int do 1 end
  fn c(m : U.Msg) : Int do need(m) end
  fn d() : Int do need(U.Zap(1)) end
  fn main(cap : Cap(IO)) : Unit do
    println(int_to_string(c(U.Zap(2))))
  end
end
|}
        in
        expect out ~line:12 ~callee:"need" "proved") ]

(* Review round 4, C3: every type a built-in signature names is a built-in
   type name the refinement checker counts as a declarant.  The list is
   derived from the signatures; this pins that the derivation reaches names
   that appear ONLY there. *)
(* ── Review round 5 (of 8312dbc6a) ───────────────────────────────────────────
   A builtin whose signature names a type QUALIFIED (`csv_next_row : Int ->
   Csv.CsvRow`) is canonicalized to the bare `CsvRow` by the typechecker at
   every use, so its result unifies with any user `type CsvRow`.  The checker
   dropped dotted builtin names, so under an entry module named `Csv` (which
   strips the stdlib's own `CsvRow` declaration) the user type had one
   declarant and its constructors resolved: `is_Zap(r)` was proved for a row
   the builtin returned. *)
let ctor_review5 =
  [ gated "ctor review5 csv2: a user `CsvRow` under an entry `mod Csv` is conflated with the builtin's `Csv.CsvRow`" (fun () ->
        let out =
          run
            {|mod Csv do
  needs IO, IO.FileRead
  type CsvRow = Zap | Zip
  fn need(r : CsvRow, n : {Int | is_Zap(r)}) : Int do
    match r do
      Zap -> n
      _ -> 0 - 99
    end
  end
  fn go(h : Int) : Int do
    let r = csv_next_row(h)
    match r do
      Zip -> 0
      _ -> need(r, 7)
    end
  end
end
|}
        in
        not_proved out ~line:14 ~callee:"need") ]

let builtin_names_cover_signatures =
  [ Alcotest.test_case "builtin_type_names covers types named only in builtin signatures" `Quick (fun () ->
        let names = March_typecheck.Typecheck_builtins.builtin_type_names in
        List.iter
          (fun n ->
            if not (List.mem n names) then
              Alcotest.failf "%s (named by a builtin signature) is missing from builtin_type_names" n)
          [ "CancelToken"; "TimerRef"; "DownReason"; "Option"; "Int" ]) ]

(* `uses:` when a stage-2 proof's unsat core names no unfolding (congruence
   alone, I8): the definitions that query assumed, not every unfolding the
   whole stage-2 run made (todo 2026-10-31-reflection-encoder-gaps, "`uses:`
   over-approximation").  Driven at [Obligation.record], where the query's
   core and assumptions meet. *)
let uses_query_frontier =
  let module O = March_refinecheck.Obligation in
  let module R = March_refine.Refine in
  let ob callee =
    { O.span = March_ast.Ast.dummy_span; callee; predicate = "_ == a"; verdict = O.Proved
    ; kind = O.Precondition; inst = None }
  in
  [ Alcotest.test_case "an empty core reports the query's own frontier" `Quick (fun () ->
        O.with_scratch (fun () ->
            R.last_core := [];
            R.last_assumed := [ "|$ru_1:f|"; "|$ru_2:f|" ];
            let o = ob "need_eq_a" in
            O.record o;
            Alcotest.(check (list string)) "uses" [ "f" ] (O.uses_of o)));
    Alcotest.test_case "a core naming an unfolding still wins over the query's frontier" `Quick (fun () ->
        O.with_scratch (fun () ->
            R.last_core := [ "$ru_2:g" ];
            R.last_assumed := [ "|$ru_1:f|"; "|$ru_2:g|" ];
            let o = ob "need_eq_b" in
            O.record o;
            Alcotest.(check (list string)) "uses" [ "g" ] (O.uses_of o)));
    Alcotest.test_case "a stage-1 proof (no assumptions) records no uses" `Quick (fun () ->
        O.with_scratch (fun () ->
            R.last_core := [];
            R.last_assumed := [];
            let o = ob "need_eq_c" in
            O.record o;
            Alcotest.(check (list string)) "uses" [] (O.uses_of o))) ]
