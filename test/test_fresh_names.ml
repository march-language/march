(* Function-local fresh names (specs/progress/2026-11-26-function-local-fresh-counters.md).

   The names lowering, TRMC and the authority-capture pass mint for a
   function's temporaries ($t7, $f3, $guard2, $p1, $trmc4, $auth_cap1) are
   numbered per top-level function.  They used to come from module-wide
   counters, so a function's emitted text depended on every function lowered
   before it: lowering one more function, or the same functions in another
   order, renumbered the rest of the program.

   What is pinned here, each RED before the change (the authority pass's
   half is in test/test_auth_rt.ml):
   1. a function's TIR straight out of lowering, and after TRMC, is the same
      text whether or not another (live) function is declared before it;
   2. its LLVM definition is identical when a function nothing calls is
      declared before it (lowered, then pruned before Mono), and the whole
      `.ll` the compiler writes is byte-identical;
   3. no two compiler-minted binders of one function share a name, with
      module-level lets folded into the functions that use them: the names of
      two scopes that end up in one body must still be distinct;
   4. the order Perceus releases sibling fields in does not move with the
      numbering (it sorted names as strings: [$f10] before [$f9]). *)

open Test_helpers

let starts_with pre s =
  String.length s >= String.length pre && String.sub s 0 (String.length pre) = pre

(* [target] uses every kind of lowering temp: call temporaries, constructor
   field binders, a guard, a lambda with a tuple-pattern parameter, a local
   named fn, and a modulo-cons recursion for TRMC. *)
let target_src = {|
  type IntList = INil | ICons(Int, IntList)

  fn bump(xs : IntList, k : Int) : IntList do
    match xs do
    INil -> INil
    ICons(h, t) -> ICons(h * 2 + k, bump(t, k))
    end
  end

  fn target(xs : IntList, k : Int) : Int do
    fn go(ys : IntList, acc : Int) : Int do
      match ys do
      INil -> acc
      ICons(h, t) when h > k -> go(t, acc + h * 2)
      ICons(h, t) -> go(t, acc + h)
      end
    end
    let pair = fn (a, b) -> a * k + b
    let ys = bump(xs, pair(k, 1))
    go(ys, pair(2, 3)) + go(bump(ys, k + 1), 0)
  end
|}

(* An unrelated function that mints plenty of names of every kind. *)
let extra_src = {|
  fn extra(xs : IntList, n : Int) : IntList do
    let f = fn (a, b) -> a + b + n
    match xs do
    INil -> ICons(f(n, 1), INil)
    ICons(h, t) when h > f(n, 2) -> ICons(h - f(1, 2), extra(t, n + 1))
    ICons(h, t) -> ICons(f(h, n) * f(n, h), extra(t, f(3, 4)))
    end
  end
|}

let main_plain = {|
  fn main() : Int do
    target(ICons(1, ICons(2, INil)), 3)
  end
|}

(* [extra] is called: it survives to the emitter. *)
let main_live = {|
  fn main() : Int do
    match extra(ICons(4, INil), 5) do
    INil -> 0
    ICons(h, _) -> h + target(ICons(1, ICons(2, INil)), 3)
    end
  end
|}

let program parts = "mod Test do\n" ^ String.concat "\n" parts ^ "\nend"

(* [without_extra] (below) puts blank lines where [extra] goes, so every
   function keeps its source line: the line is in a function's emitted text
   (overflow sites). *)
(* The type declaration stays first; [extra] goes between it and [bump]. *)
let split_target =
  let marker = "  fn bump" in
  let i =
    let n = String.length marker and h = String.length target_src in
    let rec go i = if i + n > h then failwith "marker" else
        if String.sub target_src i n = marker then i else go (i + 1) in
    go 0 in
  (String.sub target_src 0 i, String.sub target_src i (String.length target_src - i))
let with_extra main =
  let (types, fns) = split_target in
  program [ types; extra_src; fns; main ]
let without_extra =
  let (types, fns) = split_target in
  let blank = String.map (fun c -> if c = '\n' then c else ' ') extra_src in
  program [ types; blank; fns; main_plain ]

let lower src =
  let m = parse_and_desugar src in
  let (_, type_map) = March_typecheck.Typecheck.check_module m in
  March_tir.Lower.lower_module ~type_map m

let fn_text (m : March_tir.Tir.tir_module) name =
  match List.find_opt (fun (f : March_tir.Tir.fn_def) -> f.fn_name = name) m.tm_fns with
  | Some f -> March_tir.Pp.string_of_fn_def f
  | None -> Alcotest.failf "no fn %s in the module" name

(* The names a function binds, with repeats. *)
let binders (fn : March_tir.Tir.fn_def) : string list =
  let open March_tir.Tir in
  let acc = ref [] in
  let add (v : var) = acc := v.v_name :: !acc in
  let rec go = function
    | ELet (v, a, b) -> add v; go a; go b
    | ELetRec (fns, b) ->
      List.iter (fun (f : fn_def) ->
          acc := f.fn_name :: !acc; List.iter add f.fn_params; go f.fn_body) fns;
      go b
    | ECase (_, brs, d) ->
      List.iter (fun (br : branch) -> List.iter add br.br_vars; go br.br_body) brs;
      Option.iter go d
    | ESeq (a, b) -> go a; go b
    | _ -> ()
  in
  List.iter add fn.fn_params; go fn.fn_body; !acc

let test_lowered_text_is_local () =
  let a = lower without_extra and b = lower (with_extra main_live) in
  List.iter (fun name ->
      Alcotest.(check string) (name ^ ": same TIR with a function declared before it")
        (fn_text a name) (fn_text b name))
    [ "bump"; "target" ];
  let a = March_tir.Trmc.transform_module a and b = March_tir.Trmc.transform_module b in
  let trmc_names (m : March_tir.Tir.tir_module) =
    List.filter_map (fun (f : March_tir.Tir.fn_def) ->
        if starts_with "bump" f.fn_name then Some f.fn_name else None) m.tm_fns in
  Alcotest.(check bool) "TRMC rewrote bump (a $dps helper exists)" true
    (List.length (trmc_names a) = 2);
  List.iter (fun name ->
      Alcotest.(check string) (name ^ ": same TIR after TRMC")
        (fn_text a name) (fn_text b name))
    (trmc_names a @ [ "target" ])

let emit src =
  let tir = lower src in
  let iface_methods = March_tir.Lower.get_iface_methods () in
  let pipe = March_tir.Contract_pipeline.run ~iface_methods ~opt:true tir in
  March_tir.Llvm_emit.emit_module ~k_table:pipe.March_tir.Contract_pipeline.k_table
    pipe.March_tir.Contract_pipeline.final

(* Every [define] of [ir], by the line that opens it. *)
let definitions ir =
  let out = ref [] and cur = ref None in
  List.iter (fun l ->
      match !cur with
      | None -> if starts_with "define " l then cur := Some (l, [ l ])
      | Some (head, ls) ->
        if l = "}" then begin out := (head, String.concat "\n" (List.rev (l :: ls))) :: !out; cur := None end
        else cur := Some (head, l :: ls))
    (String.split_on_char '\n' ir);
  List.rev !out

(* The inliner's instance suffix ([x_i14]) comes from a counter that lives as
   long as the process, so the second module emitted by this test process
   continues the first one's.  One compiler run per program has no such
   carry-over: the next test compares those byte for byte. *)
let mask_inline_instances (s : string) : string =
  let b = Buffer.create (String.length s) in
  let n = String.length s in
  let i = ref 0 in
  while !i < n do
    if !i + 2 < n && s.[!i] = '_' && s.[!i + 1] = 'i'
       && s.[!i + 2] >= '0' && s.[!i + 2] <= '9' then begin
      Buffer.add_string b "_i#";
      i := !i + 2;
      while !i < n && s.[!i] >= '0' && s.[!i] <= '9' do incr i done
    end else begin Buffer.add_char b s.[!i]; incr i end
  done;
  Buffer.contents b

let test_llvm_definitions_ignore_an_unreached_fn () =
  let a = definitions (mask_inline_instances (emit without_extra))
  and b = definitions (mask_inline_instances (emit (with_extra main_plain))) in
  Alcotest.(check bool) "the program emitted functions" true (List.length a > 3);
  Alcotest.(check bool) "the unreached fn was pruned" false
    (List.exists (fun (h, _) ->
         let n = String.length "@extra" and hl = String.length h in
         let rec go i = i + n <= hl && (String.sub h i n = "@extra" || go (i + 1)) in go 0) b);
  Alcotest.(check (list string)) "the same functions are defined"
    (List.map fst a) (List.map fst b);
  List.iter2 (fun (head, body_a) (_, body_b) ->
      Alcotest.(check string) ("identical definition: " ^ head) body_a body_b)
    a b

(* The whole compiler, one run per program: the two `.ll` files are the same
   bytes.  Both sources are compiled under one file name, since the name is
   in the module's text. *)
let test_emitted_module_ignores_an_unreached_fn () =
  let main_exe = find_main_exe () in
  let tmp = Filename.temp_file "march_fresh_names" "" in
  Sys.remove tmp; Unix.mkdir tmp 0o755;
  let emit_ll sub src =
    let dir = Filename.concat tmp sub in
    Unix.mkdir dir 0o755;
    let oc = open_out (Filename.concat dir "prog.march") in
    output_string oc src; close_out oc;
    let (rc, out) = run_capture (Printf.sprintf "cd %s && %s --emit-llvm prog.march </dev/null"
        (Filename.quote dir) (Filename.quote main_exe)) in
    if rc <> 0 then begin
      rm_rf_temp_dir tmp;
      Alcotest.failf "--emit-llvm failed in %s (rc %d):\n%s" sub rc out
    end;
    read_file_contents (Filename.concat dir "prog.ll") in
  let a = emit_ll "a" without_extra in
  let b = emit_ll "b" (with_extra main_plain) in
  rm_rf_temp_dir tmp;
  Alcotest.(check bool) "IR was emitted" true (String.length a > 1000);
  Alcotest.(check bool) "the two modules are byte-identical" true (String.equal a b)

(* Module-level lets of the entry module are lowered outside any function and
   folded into each function that uses them, so their temporaries meet the
   function's own in one body. *)
let test_binders_stay_unique_within_a_function () =
  let src = {|mod Test do
  type IntList = INil | ICons(Int, IntList)
  fn pick(xs : IntList, d : Int) : Int do
    match xs do
    INil -> d
    ICons(h, _) -> h
    end
  end
  let base = pick(ICons(pick(INil, 7) + 1, INil), pick(INil, 2) * 3)
  let scale = fn (a, b) -> a * pick(INil, b) + base
  fn use_both(n : Int) : Int do
    let k = pick(ICons(n + 1, INil), pick(INil, n) * 2)
    match ICons(k, INil) do
    INil -> base
    ICons(h, _) when h > scale(n, 2) -> h + base
    ICons(h, _) -> scale(h, pick(INil, 4)) + k
    end
  end
  fn main() : Int do use_both(3) + scale(1, 2) + base end
end|} in
  let m = lower src in
  List.iter (fun (fn : March_tir.Tir.fn_def) ->
      (* Compiler-minted names only: a source name may be bound in two
         sibling arms (`ICons(h, _)` twice), which is ordinary scoping. *)
      let names = List.sort compare
          (List.filter (fun n -> n <> "" && n.[0] = '$') (binders fn)) in
      let rec dups = function
        | a :: (b :: _ as rest) -> if a = b then a :: dups rest else dups rest
        | _ -> [] in
      Alcotest.(check (list string)) (fn.fn_name ^ ": no minted binder name used twice")
        [] (List.sort_uniq compare (dups names)))
    (List.filter (fun (f : March_tir.Tir.fn_def) ->
         List.mem f.fn_name [ "pick"; "use_both"; "main" ]) m.tm_fns);
  (* And the temporaries really are numbered per function: both of these
     start from 1 (RED control for the test itself, so that "unique" is not
     satisfied by one module-wide sequence). *)
  let has name fnname =
    List.exists (fun (f : March_tir.Tir.fn_def) ->
        f.fn_name = fnname && List.mem name (binders f)) m.tm_fns in
  Alcotest.(check bool) "pick binds $f1" true (has "$f1" "pick" || has "$t1" "pick");
  Alcotest.(check bool) "use_both binds $t1" true (has "$t1" "use_both")

(* ── Release order does not depend on the numbering ─────────────────────
   Perceus releases, at the head of a match arm, the variables another arm
   still uses.  It emits them in name order, and string order puts [$f10]
   before [$f9]: which of two sibling constructor fields was released first
   flipped whenever their counters straddled a power of ten.  Renumbering
   must not move a release, so the order is [Tir_names.compare_minted_order]
   (stem, then counter as a number). *)

let test_compare_minted_order () =
  let cmp = March_tir.Tir_names.compare_minted_order in
  let sorted l = List.sort cmp l in
  Alcotest.(check (list string)) "counters compare as numbers"
    [ "$f2"; "$f9"; "$f10"; "$f11"; "$f100" ]
    (sorted [ "$f100"; "$f10"; "$f9"; "$f11"; "$f2" ]);
  Alcotest.(check (list string)) "by stem first"
    [ "$f12"; "$t3"; "acc"; "x"; "xs" ] (sorted [ "xs"; "$t3"; "x"; "$f12"; "acc" ]);
  Alcotest.(check (list string)) "names without a counter: string order"
    (List.sort String.compare [ "ys"; "acc"; "b"; "a"; "self" ])
    (sorted [ "ys"; "acc"; "b"; "a"; "self" ]);
  (* A total order: every permutation of a mixed list sorts to one result. *)
  let mixed = [ "$f9"; "$f10"; "$f1x"; "$f"; "$f07"; "$f7"; "f9"; "$t10_i2"; "$t3" ] in
  let rec perms = function
    | [] -> [ [] ]
    | l -> List.concat_map (fun x ->
        List.map (fun p -> x :: p) (perms (List.filter (fun y -> y <> x) l))) l in
  let expect = sorted mixed in
  Alcotest.(check bool) "one answer for every input order" true
    (List.for_all (fun p -> sorted p = expect)
       (List.filteri (fun i _ -> i mod 97 = 0) (perms mixed)))

(* [probe]'s first arm releases the two fields the second arm uses.  [n]
   extra additions in front shift the fields' counters; some [n] puts them on
   either side of 9/10. *)
let release_src n =
  let extra = String.concat "" (List.init n (fun _ -> " + k")) in
  Printf.sprintf {|mod Test do
  type IntList = INil | ICons(Int, IntList)
  type Three = Three(IntList, IntList, IntList)
  fn len(xs : IntList) : Int do
    match xs do
    INil -> 0
    ICons(_, t) -> 1 + len(t)
    end
  end
  fn mk(n : Int) : IntList do
    if n == 0 do INil else ICons(n, mk(n - 1)) end
  end
  fn probe(p : Three, k : Int) : Int do
    let w = k%s
    match p do
    Three(INil, _, _) -> w
    Three(ICons(h, _), ys, zs) -> h + len(ys) + len(zs) + w
    end
  end
  fn main() : Int do
    probe(Three(mk(0), mk(2), mk(3)), 7) + probe(Three(mk(1), mk(2), mk(3)), 7)
  end
end|} extra

(* In every post-Perceus fn made from [probe]: the releases at the head of
   the [INil] arm under the [Three] arm, as (field position, name). *)
let head_releases (m : March_tir.Tir.tir_module) : (int * string) list list =
  let open March_tir.Tir in
  let rec head_decs = function
    | ESeq (EDecRC (AVar v), rest) -> v.v_name :: head_decs rest
    | _ -> [] in
  let found = ref [] in
  let rec go fields = function
    | ECase (_, brs, d) ->
      List.iter (fun (br : branch) ->
          if br.br_tag = "Three" then
            go (Some (List.map (fun (v : var) -> v.v_name) br.br_vars)) (strip br.br_body)
          else begin
            (match fields, br.br_tag with
             | Some fs, "INil" ->
               let pos n =
                 let rec idx i = function
                   | [] -> None | x :: r -> if x = n then Some i else idx (i + 1) r in
                 idx 0 fs in
               let decs = List.filter_map (fun n -> Option.map (fun i -> (i, n)) (pos n))
                   (head_decs br.br_body) in
               if decs <> [] then found := decs :: !found
             | _ -> ());
            go fields br.br_body
          end) brs;
      Option.iter (go fields) d
    | ELet (_, a, b) | ESeq (a, b) -> go fields a; go fields b
    | ELetRec (fns, b) -> List.iter (fun (f : fn_def) -> go fields f.fn_body) fns; go fields b
    | _ -> ()
  (* The scrutinee's own release sits in front of the nested case. *)
  and strip = function
    | ESeq (EDecRC _, rest) -> strip rest
    | e -> e
  in
  List.iter (fun (f : fn_def) ->
      if starts_with "probe" f.fn_name then go None f.fn_body) m.tm_fns;
  List.rev !found

let test_release_order_ignores_numbering () =
  let per_n = List.init 12 (fun n ->
      let tir = lower (release_src n) in
      let iface_methods = March_tir.Lower.get_iface_methods () in
      let seen = ref None in
      ignore (March_tir.Contract_pipeline.run ~iface_methods ~opt:true
                ~after_perceus:(fun m -> seen := Some m) tir);
      match !seen with
      | Some m -> head_releases m
      | None -> Alcotest.fail "no post-Perceus module") in
  let positions = List.map (List.map (List.map fst)) per_n in
  let first = List.hd positions in
  Alcotest.(check bool) "the arm releases both sibling fields" true
    (List.exists (fun decs -> List.mem 1 decs && List.mem 2 decs) first);
  List.iteri (fun n p ->
      Alcotest.(check (list (list int)))
        (Printf.sprintf "%d extra temporaries: same release order by field position" n)
        first p) positions;
  (* The control: some variant really has the two fields' names on either
     side of a power of ten, where string order and counter order differ. *)
  let straddles decs =
    match List.assoc_opt 1 decs, List.assoc_opt 2 decs with
    | Some a, Some b -> String.length a <> String.length b
    | _ -> false in
  Alcotest.(check bool)
    ("a variant puts the fields across 9/10; names seen: "
     ^ String.concat " | " (List.map (fun decs ->
         String.concat "," (List.concat_map (List.map snd) decs)) per_n))
    true (List.exists (List.exists straddles) per_n)

let suites = [
  ("fresh-names", [
      Alcotest.test_case "lowered / TRMC'd TIR of a fn ignores a fn declared before it" `Quick
        test_lowered_text_is_local;
      Alcotest.test_case "LLVM definitions ignore an unreached fn declared before them" `Quick
        test_llvm_definitions_ignore_an_unreached_fn;
      Alcotest.test_case "march --emit-llvm is byte-identical with an unreached fn added" `Slow
        test_emitted_module_ignores_an_unreached_fn;
      Alcotest.test_case "binders stay unique within a fn (module-level lets folded in)" `Quick
        test_binders_stay_unique_within_a_function;
      Alcotest.test_case "compare_minted_order: counters as numbers, a total order" `Quick
        test_compare_minted_order;
      Alcotest.test_case "cross-branch release order ignores the numbering" `Quick
        test_release_order_ignores_numbering;
    ]);
]
