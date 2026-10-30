(* Refinement reflection, phase 0 (specs/2026-10-29-refinement-reflection-design.md
   §10, group `reflect-report`): the §2.1 fixpoint ([Refine_reflect]), read only
   by `--reflect-report`, and the `--refine-report-sites=all` listing (§6.1).

   Every case drives the REAL compiler (`--check --reflect-report`), because
   the inputs the rule reads live in the driver's pipeline: the SCC
   certificates of the refinement walk, the [Division] verdicts of
   [Division_safety], the typechecker's non-exhaustive match spans, and the
   prepended stdlib.  Each asserts the printed row's text, never an exit
   code.  The compiler runs under one private HOME (the shared
   ~/.cache/march carries other worktrees' spans). *)

let z3_available () =
  match March_refine.Solver.create () with
  | None -> false
  | Some s -> March_refine.Solver.close s; true

let gated name f =
  Alcotest.test_case name `Quick (fun () -> if z3_available () then f () else Alcotest.skip ())

let exe () = Filename.concat (Filename.dirname Sys.executable_name) "../bin/main.exe"

let rec remove_tree path =
  if Sys.is_directory path then begin
    Array.iter (fun n -> remove_tree (Filename.concat path n)) (Sys.readdir path);
    Unix.rmdir path
  end
  else Sys.remove path

let home =
  lazy
    (let d = Filename.temp_dir "reflect_home" "" in
     at_exit (fun () -> try remove_tree d with _ -> ());
     d)

(* Run the compiler with [args] on [path]; stdout and stderr together. *)
let run_on args path =
  let out = Filename.temp_file "reflect" ".out" in
  let cmd =
    Printf.sprintf "cd %s && HOME=%s %s %s %s > %s 2>&1"
      (Filename.quote (Filename.dirname path))
      (Filename.quote (Lazy.force home))
      (Filename.quote (exe ())) args (Filename.quote (Filename.basename path)) (Filename.quote out)
  in
  ignore (Test_helpers.Sys.command cmd);
  let s = In_channel.with_open_bin out In_channel.input_all in
  Sys.remove out;
  s

let run ?(args = "--check --reflect-report") src =
  let dir = Filename.temp_dir "reflect" "" in
  Fun.protect ~finally:(fun () -> try remove_tree dir with _ -> ()) (fun () ->
      let f = Filename.concat dir "m.march" in
      Out_channel.with_open_bin f (fun oc -> output_string oc src);
      run_on args f)

let lines s = String.split_on_char '\n' s |> List.filter (( <> ) "")

let contains hay needle =
  let n = String.length needle and h = String.length hay in
  let rec go i = i + n <= h && (String.sub hay i n = needle || go (i + 1)) in
  go 0

(* The (verdict, detail) columns of [name]'s row. *)
let row out name =
  List.find_map
    (fun l ->
      match String.split_on_char '\t' l with
      | [ "reflect"; _; n; v; d ] when n = name -> Some (v, d)
      | _ -> None)
    (lines out)

let expect out name ~verdict ~detail =
  match row out name with
  | Some (v, d) ->
    Alcotest.(check string) (name ^ " verdict") verdict v;
    if not (contains d detail) then
      Alcotest.failf "%s: detail %S does not contain %S" name d detail
  | None -> Alcotest.failf "no row for %s in:\n%s" name out

let reflected out name = expect out name ~verdict:"reflected" ~detail:"unfold"
let blocked out name detail = expect out name ~verdict:"no" ~detail

let cat_rev = {|mod CatRev do
  fn cat(xs : List(Int), ys : List(Int)) : List(Int) do
    match xs do
      Nil -> ys
      Cons(h, t) -> Cons(h, cat(t, ys))
    end
  end

  fn rev(xs : List(Int)) : List(Int) do
    match xs do
      Nil -> Nil
      Cons(h, t) -> cat(rev(t), Cons(h, Nil))
    end
  end
end
|}

let noisy = {|  fn noisy(n : Int) : Int do
    println("hi")
    n
  end
|}

let suite =
  [ gated "report_cat_rev: probe a2's cat and rev are reflected" (fun () ->
        let out = run cat_rev in
        reflected out "cat";
        reflected out "rev");
    gated "report_effect: a println blocks under R3" (fun () ->
        let out = run ("mod Eff do\n  needs IO.Console\n" ^ noisy ^ "end\n") in
        blocked out "noisy" "R3:calls println");
    gated "report_diverge: spin is R2 unproved" (fun () ->
        let out = run "mod Div do\n  fn spin(n : Int) : Int do spin(n) end\nend\n" in
        blocked out "spin" "R2:unproved");
    gated "report_trusted_cert: a trusted metric is R2 trusted" (fun () ->
        let out =
          run
            "mod Tc do\n  @[decreases(n)]\n  @[trusted]\n  fn up(n : Int) : Int do if n > 100 do 0 else up(n + 1) end end\nend\n"
        in
        blocked out "up" "R2:trusted");
    gated "report_trusted_nonrec: @[trusted] blocks with no recursion (R9)" (fun () ->
        let out = run "mod Tn do\n  @[trusted]\n  fn k(n : Int) : {Int | _ > 0} do n end\nend\n" in
        blocked out "k" "R9:@[trusted]");
    gated "report_guarded: a guarded match that can fall through is R5 (probe r2)" (fun () ->
        let out =
          run
            "mod Gd do\n  fn guarded(xs : List(Int)) : Int do\n    match xs do\n      Cons(h, _) when h > 0 -> h\n      Nil -> 0\n    end\n  end\nend\n"
        in
        blocked out "guarded" "R5:guarded match may not match");
    gated "report_domain: a metric on a refined domain is reflected, guarded (probe r1)" (fun () ->
        let out =
          run
            "mod Dom do\n  fn p(n : {Int | _ >= 0}) : Bool do\n    if n >= 0 do true else not(p(n)) end\n  end\nend\n"
        in
        expect out "p" ~verdict:"reflected" ~detail:"guard: n >= 0");
    gated "report_shadow: a user `len` is R11; its caller is R6 (probe r3)" (fun () ->
        let out =
          run
            "mod Sh do\n  fn len(xs : List(Int)) : Int do 7 end\n  fn g(xs : List(Int)) : Int do len(xs) end\nend\n"
        in
        blocked out "len" "R11";
        blocked out "g" "R6:calls len");
    gated "report_eq_effect: `==` over an Eq that prints blocks (C4)" (fun () ->
        let out =
          run
            {|mod Eqe do
  needs IO.Console
  type P = P(Int, Int)
  impl Eq(P) do
    fn eq(a : P, b : P) : Bool do
      println("eq")
      match (a, b) do
        (P(x, _), P(y, _)) -> x == y
      end
    end
  end
  fn same(a : P, b : P) : Bool do a == b end
end
|}
        in
        blocked out "same" "R6:== at P dispatches to impl Eq(P).eq, which calls println");
    gated "report_partial: a missing arm is R5, a panic is R4" (fun () ->
        let out =
          run
            {|mod Part do
  fn hd(xs : List(Int)) : Int do
    match xs do
      Cons(h, _) -> h
    end
  end
  fn safe(n : Int) : Int do if n > 0 do n else panic("neg") end end
end
|}
        in
        blocked out "hd" "R5:non-exhaustive";
        blocked out "safe" "R4:calls panic");
    gated "report_div: a literal divisor passes; an unproved one is R4 (ledger)" (fun () ->
        let out =
          run
            "mod Dv do\n  fn half(n : Int) : Int do n / 2 end\n  fn ratio(a : Int, b : Int) : Int do a / b end\nend\n"
        in
        reflected out "half";
        blocked out "ratio" "R4:division by b not proved");
    gated "report_div: a PROVED Division obligation passes R4" (fun () ->
        let out =
          run
            "mod Dvp do\n  cap no_panic\n  fn ratio(a : Int, b : {Int | _ > 0}) : Int do a / b end\nend\n"
        in
        expect out "ratio" ~verdict:"reflected" ~detail:"guard: b > 0");
    gated "report_fnvalue: function values are R7" (fun () ->
        let out =
          run
            {|mod Fv do
  fn apply(f : Int -> Int, x : Int) : Int do f(x) end
  fn twice(x : Int) : Int do
    let f = fn y -> y + 1
    f(f(x))
  end
  fn h(x : Int) : Option(Int -> Int) do Some(h) end
  fn inc(x : Int) : Int do x + 1 end
  fn h2(x : Int) : Option(Int -> Int) do Some(inc) end
end
|}
        in
        (* A function passing ITSELF is a reference edge, so its SCC is not
           certified: R2 precedes R7. *)
        blocked out "h" "R2:unproved:reference";
        blocked out "apply" "R7:takes a function-typed parameter f";
        blocked out "twice" "R7:contains a lambda";
        blocked out "h2" "R7:names inc as a value");
    gated "report_dispatch: show, interpolation and compare on a user impl are R6" (fun () ->
        let out =
          run
            {|mod Dsp do
  type T = T(Int)
  impl Show(T) do
    fn show(t : T) : String do
      match t do
        T(n) -> int_to_string(n)
      end
    end
  end
  impl Ord(T) do
    fn compare(a : T, b : T) : Int do 0 end
  end
  fn s1(t : T) : String do show(t) end
  fn s2(t : T) : String do "${t}" end
  fn c(a : T, b : T) : Int do compare(a, b) end
end
|}
        in
        blocked out "s1" "R6:dispatches to impl Show(T).show";
        blocked out "s2" "R6:dispatches to impl Show(T).show";
        blocked out "c" "R6:dispatches to impl Ord(T).compare");
    gated "report_chain: the fixpoint names the unreflected callee" (fun () ->
        let out =
          run
            ("mod Ch do\n  needs IO.Console\n" ^ noisy
           ^ "  fn mid(n : Int) : Int do noisy(n) + 1 end\n  fn outer(n : Int) : Int do mid(n) * 2 end\nend\n")
        in
        blocked out "noisy" "R3:calls println";
        blocked out "mid" "R6:calls noisy, which is not reflected";
        blocked out "outer" "R6:calls mid, which is not reflected");
    gated "report_mutual: an SCC is reflected as a whole, or not at all" (fun () ->
        let out =
          run
            {|mod Mu do
  needs IO.Console
  type Nat = Z | S(Nat)
  fn even(n : Nat) : Bool do
    match n do
      Z -> true
      S(m) -> odd(m)
    end
  end
  fn odd(n : Nat) : Bool do
    match n do
      Z -> false
      S(m) -> even(m)
    end
  end
  fn even2(n : Nat) : Bool do
    match n do
      Z -> true
      S(m) -> odd2(m)
    end
  end
  fn odd2(n : Nat) : Bool do
    println("odd")
    match n do
      Z -> false
      S(m) -> even2(m)
    end
  end
end
|}
        in
        reflected out "even";
        reflected out "odd";
        blocked out "odd2" "R3:calls println";
        blocked out "even2" "R6:calls odd2, which is not reflected");
    gated "report_local: a local fn is `outer/go`; a capturing one is R1" (fun () ->
        let out =
          run
            {|mod Lc do
  fn rev2(xs : List(Int)) : List(Int) do
    fn go(ys : List(Int), acc : List(Int)) : List(Int) do
      match ys do
        Nil -> acc
        Cons(h, t) -> go(t, Cons(h, acc))
      end
    end
    go(xs, Nil)
  end
  fn addk(xs : List(Int), k : Int) : List(Int) do
    fn go(ys : List(Int)) : List(Int) do
      match ys do
        Nil -> Nil
        Cons(h, t) -> Cons(h + k, go(t))
      end
    end
    go(xs)
  end
end
|}
        in
        reflected out "rev2/go";
        reflected out "rev2";
        blocked out "addk/go" "R1:captures k";
        blocked out "addk" "R6:calls addk/go, which is not reflected");
    gated "report_sort: a Unit result and an untranslatable refinement are R8" (fun () ->
        let out =
          run
            {|mod So do
  fn inc(n : Int) : Int do n + 1 end
  fn nothing(n : Int) : Unit do () end
  fn idx2(i : {Int | _ < inc(3)}) : Int do i end
end
|}
        in
        reflected out "inc";
        blocked out "nothing" "R8:returns Unit";
        blocked out "idx2" "R8:the refinement of i does not translate (inc is not predicate vocabulary)");
    gated "report: main is R1, and the summary counts rows" (fun () ->
        let out = run "mod Mn do\n  fn one() : Int do 1 end\n  fn main() : Int do one() end\nend\n" in
        reflected out "one";
        blocked out "main" "R1:is `main`";
        Alcotest.(check bool) "summary" true
          (List.exists (fun l -> l = "reflect report: 2 functions, 1 reflected") (lines out)));
    gated "sites_all: probe a1 lists four proved user sites; the summary is unchanged" (fun () ->
        let a1 =
          {|mod A1 do
  fn cat(xs : List(Int), ys : List(Int)) : {List(Int) | len(_) == len(xs) + len(ys)} do
    match xs do
      Nil -> ys
      Cons(h, t) -> Cons(h, cat(t, ys))
    end
  end

  fn rev(xs : List(Int)) : {List(Int) | len(_) == len(xs)} do
    match xs do
      Nil -> Nil
      Cons(h, t) -> cat(rev(t), Cons(h, Nil))
    end
  end

  fn need3(xs : {List(Int) | len(_) == 3}) : Int do 0 end

  fn main() : Unit do
    let a = cat(Cons(1, Nil), Cons(2, Cons(3, Nil)))
    let _ = need3(a)
    let _ = need3(rev(a))
    ()
  end
end
|}
        in
        let all = run ~args:"--check --refine-report --refine-report-sites=all" a1 in
        let user = List.filter (fun l -> contains l "\tuser\t") (lines all) in
        Alcotest.(check int) ("four user sites:\n" ^ String.concat "\n" user) 4 (List.length user);
        List.iter
          (fun l ->
            match String.split_on_char '\t' l with
            | [ "proved"; "user"; _; kind; _; _ ] ->
              if kind <> "precondition" && kind <> "postcondition" then Alcotest.failf "kind %s" kind
            | _ -> Alcotest.failf "not a 6-column proved row: %S" l)
          user;
        (* Every verdict is listed: the stdlib's proved sites too. *)
        Alcotest.(check bool) "stdlib proved rows" true
          (List.exists (fun l -> String.length l > 14 && String.sub l 0 14 = "proved\tstdlib\t") (lines all));
        let plain = run ~args:"--check --refine-report" a1 in
        let summary s = List.filter (fun l -> not (contains l "\tuser\t" || contains l "\tstdlib\t")) (lines s) in
        Alcotest.(check (list string)) "--refine-report summary unchanged" (summary plain) (summary all));
    gated "sites_all: the bare flag still prints only skips, in its own format" (fun () ->
        let src = "mod Rs do\n  fn pos(n : {Int | _ > 0}) : Int do n end\n  fn go(k : Int) : Int do pos(k) end\n  fn ok() : Int do pos(3) end\nend\n" in
        let bare = run ~args:"--check --refine-report-sites" src in
        let all = run ~args:"--check --refine-report-sites=all" src in
        let user s = List.filter (fun l -> contains l "\tuser\t") (lines s) in
        Alcotest.(check bool) "bare: only skips" true
          (List.for_all (fun l -> String.sub l 0 5 = "skip\t") (user bare));
        Alcotest.(check int) "bare: one user skip" 1 (List.length (user bare));
        (* =all: the same skip line, byte for byte, plus the proved one. *)
        Alcotest.(check bool) "=all keeps the skip line" true (List.mem (List.hd (user bare)) (user all));
        Alcotest.(check bool) "=all adds the proved site" true
          (List.exists (fun l -> String.sub l 0 12 = "proved\tuser\t" && contains l "\tprecondition\tpos\t_ > 0") (user all)))
  ]

(* ── The §0 probes, pinned (accept side) ───────────────────────────────────

   test/refine/reflect/<probe>.march and its .expected: the user-code rows of
   `--refine-report-sites=all` and `--reflect-report`, paths reduced to the
   basename.  Phase 1 changes some of these on purpose (a2's postcondition
   proves); the diff is the review artifact.  Regenerate with
   UPDATE_SNAPSHOTS=1. *)

let fixture_dir () =
  let rel = "test/refine/reflect" in
  if Sys.file_exists rel then rel else Filename.concat (Test_helpers.march_project_root ()) rel

(* Run on a COPY under a temp dir: the compiler writes `.march/` beside the
   project it finds, and the source tree is no place for that. *)
let pinned path =
  let src = In_channel.with_open_bin path In_channel.input_all in
  let dir = Filename.temp_dir "reflect_fx" "" in
  Fun.protect ~finally:(fun () -> try remove_tree dir with _ -> ()) (fun () ->
      let f = Filename.concat dir (Filename.basename path) in
      Out_channel.with_open_bin f (fun oc -> output_string oc src);
      let out = run_on "--check --refine-report-sites=all --reflect-report" f in
      let keep l =
        contains l "\tuser\t" || (String.length l > 8 && String.sub l 0 8 = "reflect\t")
      in
      String.concat "\n" (List.filter keep (lines out)) ^ "\n")

let fixture_suite =
  [ gated "the §0 probes keep today's verdicts (test/refine/reflect)" (fun () ->
        let dir = fixture_dir () in
        let files =
          Sys.readdir dir |> Array.to_list
          |> List.filter (fun f -> Filename.check_suffix f ".march")
          |> List.sort compare
        in
        if List.length files < 20 then Alcotest.failf "only %d fixtures under %s" (List.length files) dir;
        let update = Sys.getenv_opt "UPDATE_SNAPSHOTS" = Some "1" in
        let bad = ref [] in
        List.iter
          (fun f ->
            let got = pinned (Filename.concat dir f) in
            let exp_path = Filename.concat dir (Filename.chop_suffix f ".march" ^ ".expected") in
            if update then Out_channel.with_open_bin exp_path (fun oc -> output_string oc got)
            else
              let want =
                if Sys.file_exists exp_path then In_channel.with_open_bin exp_path In_channel.input_all
                else "<missing>"
              in
              if want <> got then bad := Printf.sprintf "%s:\n--- want\n%s--- got\n%s" f want got :: !bad)
          files;
        if !bad <> [] then Alcotest.fail (String.concat "\n" (List.rev !bad))) ]
