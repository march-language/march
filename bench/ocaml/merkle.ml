(* Merkle tree benchmark — matches bench/merkle.march (1024 leaves, 50 rounds)
   Uses digestif SHA-256 (pure-OCaml implementation, in the march opam switch).
   Compile:
     ocamlfind ocamlopt -package digestif -linkpkg bench/ocaml/merkle.ml \
       -o /tmp/ocaml_merkle *)

let sha256_hex s =
  Digestif.SHA256.(digest_string s |> to_hex)

type node =
  | Leaf   of string               (* (hash) *)
  | Branch of string * node * node (* (hash, left, right) *)

let hash_of = function
  | Leaf h         -> h
  | Branch (h,_,_) -> h

let make_leaf v = Leaf (sha256_hex v)

let make_branch l r =
  Branch (sha256_hex (hash_of l ^ hash_of r), l, r)

let rec build_range (vals : string array) lo hi =
  if hi - lo = 1 then make_leaf vals.(lo)
  else
    let mid = (lo + hi) / 2 in
    let l   = build_range vals lo  mid in
    let r   = build_range vals mid hi  in
    make_branch l r

let rec diff_count a b =
  if hash_of a = hash_of b then 0
  else match a, b with
    | Leaf _, _   -> 1
    | _, Leaf _   -> 1
    | Branch (_, la, ra), Branch (_, lb, rb) ->
      diff_count la lb + diff_count ra rb

let run_once () =
  let vals_a = Array.init 1024 string_of_int in
  let vals_b = Array.init 1024 (fun i ->
    if i mod 8 = 0 then "modified_" ^ string_of_int i
    else string_of_int i) in
  let ta = build_range vals_a 0 1024 in
  let tb = build_range vals_b 0 1024 in
  diff_count ta tb

let () =
  let total = ref 0 in
  for _ = 1 to 50 do total := !total + run_once () done;
  Printf.printf "%d\n" !total
