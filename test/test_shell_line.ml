(** The remote shell's line editor (lib/repl/shell_line.ml): pure key
    handling, history and the history file. *)

module L = March_repl.Shell_line

let esc = "\027"
let up = esc ^ "[A" and down = esc ^ "[B" and right = esc ^ "[C" and left = esc ^ "[D"

let rep n s = String.concat "" (List.init n (fun _ -> s))

(* Type [s] into a fresh editor over [hist]; return the editor. *)
let typed ?(hist = [||]) s = fst (L.feed_string (L.create hist) s)
let after t s = fst (L.feed_string t s)
let check_line msg (b, c) (t : L.t) =
  Alcotest.(check (pair string int)) msg (b, c) (t.L.buf, t.L.cur)

let test_insert_and_cursor () =
  let t = typed "abc" in
  check_line "typed" ("abc", 3) t;
  check_line "left" ("abc", 2) (after t left);
  check_line "insert in the middle" ("abXc", 3) (after t (left ^ "X"));
  check_line "left clamps at 0" ("abc", 0) (after t (rep 5 left));
  check_line "right clamps at end" ("abc", 3) (after t (right ^ right));
  check_line "home" ("abc", 0) (after t (esc ^ "[H"));
  check_line "end" ("abc", 3) (after (after t "\001") (esc ^ "[F"));
  check_line "SS3 home (ESC O H)" ("abc", 0) (after t (esc ^ "OH"));
  check_line "^A ^E" ("abc", 3) (after (after t "\001") "\005");
  check_line "1~ and 4~" ("abc", 3) (after (after t (esc ^ "[1~")) (esc ^ "[4~"));
  check_line "^B" ("abc", 2) (after t "\002");
  check_line "^F" ("abc", 1) (after (after t "\001") "\006");
  check_line "backspace mid-line" ("ac", 1) (after t (left ^ "\127"));
  check_line "backspace at 0 is a no-op" ("abc", 0) (after (after t "\001") "\127");
  check_line "^H backspaces" ("ab", 2) (after t "\008");
  check_line "delete (ESC[3~)" ("ac", 1) (after t (left ^ left ^ esc ^ "[3~"));
  check_line "delete at end is a no-op" ("abc", 3) (after t (esc ^ "[3~"));
  check_line "^D mid-line deletes forward" ("bc", 0) (after (after t "\001") "\004")

let test_kill () =
  let t = typed "echo hello world" in
  let at_world = after t (rep 5 left) in                (* cursor before "world" *)
  check_line "^U kills to start" ("world", 0) (after at_world "\021");
  check_line "^K kills to end" ("echo hello ", 11) (after at_world "\011");
  check_line "^W kills a word" ("echo hello ", 11) (after t "\023");
  check_line "^W skips trailing spaces" ("echo ", 5) (after (typed "echo hello   ") "\023");
  check_line "^W at 0 no-op" ("echo hello world", 0) (after (after t "\001") "\023");
  check_line "^K at end no-op" ("echo hello world", 16) (after t "\011");
  check_line "Alt-b" ("echo hello world", 11) (after t (esc ^ "b"));
  check_line "Ctrl-Left" ("echo hello world", 11) (after t (esc ^ "[1;5D"));
  check_line "Alt-f from 0" ("echo hello world", 4) (after (after t "\001") (esc ^ "f"))

let s_mixed = "a\xc3\xa9\xe2\x82\xac\xf0\x9f\x98\x80z"   (* a, e-acute, euro, emoji, z *)

let test_utf8 () =
  let t = typed s_mixed in
  Alcotest.(check int) "bytes" 11 t.L.cur;
  Alcotest.(check int) "5 chars" 5 (L.chars t.L.buf);
  check_line "left over z" (s_mixed, 10) (after t left);
  check_line "left over the emoji is one step" (s_mixed, 6) (after t (left ^ left));
  check_line "right over a 2-byte char" (s_mixed, 3) (after (after t "\001") (right ^ right));
  check_line "backspace removes a whole char" ("a\xc3\xa9\xe2\x82\xacz", 6) (after t (left ^ "\127"));
  check_line "delete removes a whole char" ("a\xe2\x82\xac\xf0\x9f\x98\x80z", 1)
    (after (after t "\001") (right ^ esc ^ "[3~"));
  let t = after (typed "") "\xe2\x82" in
  check_line "split char: pending, nothing inserted" ("", 0) t;
  check_line "completed by the next read" ("\xe2\x82\xac", 3) (after t "\xac");
  check_line "broken char dropped, next byte kept" ("x", 1) (after (typed "\xe2\x82") "x");
  check_line "stray continuation ignored" ("", 0) (typed "\x80");
  let w, c = L.view ~width:80 ~prompt_cols:7 (typed "\xe2\x82\xac\xe2\x82\xac") in
  Alcotest.(check (pair string int)) "cursor column counts chars" ("\xe2\x82\xac\xe2\x82\xac", 2) (w, c)

let test_history () =
  let hist = [| "one"; "two"; "three" |] in
  let t = typed ~hist "dr" in
  let t1 = after t up in
  check_line "up: newest" ("three", 5) t1;
  check_line "up again" ("two", 3) (after t1 up);
  check_line "up past oldest clamps" ("one", 3) (after t (rep 5 up));
  check_line "down back" ("three", 5) (after (after t1 up) down);
  check_line "down past newest restores the draft" ("dr", 2) (after t1 down);
  check_line "down with nothing to restore" ("dr", 2) (after t down);
  check_line "up into empty history" ("dr", 2) (after (typed "dr") up);
  check_line "SS3 up (ESC O A)" ("three", 5) (after t (esc ^ "OA"));
  check_line "^P then ^N" ("dr", 2) (after (after t "\016") "\014");
  check_line "ESC[1A" ("three", 5) (after t (esc ^ "[1A"));
  check_line "draft survives a deep round trip" ("dr", 2) (after t (rep 3 up ^ rep 3 down));
  let t2, evs = L.feed_string t1 (left ^ "X\r") in
  check_line "recalled line edited" ("threXe", 5) t2;
  Alcotest.(check bool) "and accepted as edited" true (evs = [ L.Accept "threXe" ])

let test_events () =
  let ev s = snd (L.feed_string (typed "ab") s) in
  Alcotest.(check bool) "enter" true (ev "\r" = [ L.Accept "ab" ]);
  Alcotest.(check bool) "newline" true (ev "\n" = [ L.Accept "ab" ]);
  Alcotest.(check bool) "^C" true (ev "\003" = [ L.Interrupt ]);
  Alcotest.(check bool) "^D on a non-empty line is not EOF" true (ev "\004" = []);
  Alcotest.(check bool) "^D on an empty line is EOF" true
    (snd (L.feed_string (L.create [||]) "\004") = [ L.Eof ]);
  Alcotest.(check bool) "^L" true (ev "\012" = [ L.Clear ]);
  check_line "reset keeps history, drops the line" ("", 0) (L.reset (typed ~hist:[| "h" |] "zz"));
  check_line "reset then up recalls" ("h", 1) (after (L.reset (typed ~hist:[| "h" |] "zz")) up)

let test_escape_across_reads () =
  let hist = [| "prev" |] in
  let t = after (typed ~hist "") esc in
  Alcotest.(check string) "ESC pending" esc t.L.pend;
  let t = after t "[" in
  check_line "ESC [ pending, buffer untouched" ("", 0) t;
  check_line "completed by A in a third read" ("prev", 4) (after t "A");
  let t = L.timeout (after (typed ~hist "q") esc) in
  Alcotest.(check string) "timeout clears a bare ESC" "" t.L.pend;
  check_line "bare ESC leaves the line alone" ("q", 1) t;
  check_line "and the next key is an ordinary key" ("qz", 2) (after t "z");
  let t = L.timeout (after (typed "q") (esc ^ "[1;")) in
  check_line "truncated sequence dropped on timeout" ("q", 1) t;
  check_line "next key ordinary" ("qz", 2) (after t "z")

let test_unknown_sequences () =
  let ab = typed "ab" in
  check_line "unknown CSI final ignored" ("ab", 2) (after ab (esc ^ "[Z"));
  check_line "PageUp/PageDown ignored" ("ab", 2) (after ab (esc ^ "[5~" ^ esc ^ "[6~"));
  check_line "F5 (ESC[15~): no digits leak" ("ab", 2) (after ab (esc ^ "[15~"));
  check_line "modified arrows (ESC[1;2A) ignored" ("ab", 2) (after ab (esc ^ "[1;2A"));
  check_line "ESC x (unknown Alt key) swallowed" ("ab", 2) (after ab (esc ^ "x"));
  check_line "F1 (ESC O P) ignored" ("ab", 2) (after ab (esc ^ "OP"));
  check_line "control bytes ignored" ("ab", 2) (after ab "\009\026\000");
  check_line "malformed CSI dropped" ("ab", 2) (after ab (esc ^ "[\001"));
  check_line "text after a dropped sequence works" ("abc", 3) (after ab (esc ^ "[15~c"))

let test_view () =
  Alcotest.(check (pair string int)) "short line: whole, cursor col" ("hello", 5)
    (L.view ~width:80 ~prompt_cols:7 (typed "hello"));
  let long = typed (String.make 100 'x' ^ "END") in
  let w, c = L.view ~width:40 ~prompt_cols:7 long in
  Alcotest.(check bool) "long: fits a row, cursor never in the last column" true
    (L.chars w + 7 < 40 && c + 7 < 40 && c = L.chars w);
  Alcotest.(check string) "long: the tail is visible at the end" "END"
    (String.sub w (String.length w - 3) 3);
  let w, c = L.view ~width:40 ~prompt_cols:7 (after long "\001") in
  Alcotest.(check (pair int int)) "long, cursor at 0: head shown" (32, 0) (L.chars w, c);
  let w, c = L.view ~width:3 ~prompt_cols:7 long in
  Alcotest.(check bool) "absurdly narrow does not crash, stays on one row" true
    (L.chars w <= 1 && c >= 0 && c <= 1)

let with_tmp f =
  let dir = Filename.concat (Filename.get_temp_dir_name ())
      (Printf.sprintf "shell_line_test.%d.%d" (Unix.getpid ()) (Random.bits ())) in
  Fun.protect (fun () -> f dir) ~finally:(fun () ->
      ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote dir))))

let test_record () =
  let h, a = L.record [||] "  1 + 2  " in
  Alcotest.(check bool) "added, trimmed" true (a && h = [| "1 + 2" |]);
  let h, a = L.record h "1 + 2" in
  Alcotest.(check bool) "identical to the previous: skipped" true (not a && h = [| "1 + 2" |]);
  let h, _ = L.record h "3" in
  let h, a2 = L.record h "1 + 2" in
  Alcotest.(check bool) "same as an older one: kept" true (a2 && Array.length h = 3);
  List.iter (fun l ->
      let _, a = L.record h l in
      Alcotest.(check bool) ("not recorded: " ^ String.escaped l) false a)
    [ ""; "   "; ":quit"; ":q"; "  :quit " ];
  let h = ref [||] in
  for i = 1 to 12 do h := fst (L.record ~cap:5 !h (string_of_int i)) done;
  Alcotest.(check bool) "capped to the newest" true (!h = [| "8"; "9"; "10"; "11"; "12" |])

let test_file () = with_tmp (fun dir ->
    let path = Filename.concat (Filename.concat dir ".march") "shell_history" in
    Alcotest.(check int) "missing file: empty" 0 (Array.length (L.load path));
    L.append path "one"; L.append path "two";
    Alcotest.(check bool) "appended and loaded" true (L.load path = [| "one"; "two" |]);
    Alcotest.(check int) "file mode 0600" 0o600 ((Unix.stat path).Unix.st_perm land 0o777);
    Alcotest.(check int) "dir mode 0700" 0o700
      ((Unix.stat (Filename.dirname path)).Unix.st_perm land 0o777);
    for i = 1 to 20 do L.append path (Printf.sprintf "l%d" i) done;
    let h = L.load ~cap:5 path in
    Alcotest.(check bool) "cap on load" true (h = [| "l16"; "l17"; "l18"; "l19"; "l20" |]);
    Alcotest.(check bool) "file trimmed" true (L.read_lines path = Array.to_list h);
    Alcotest.(check int) "trimmed file still 0600" 0o600 ((Unix.stat path).Unix.st_perm land 0o777);
    Unix.chmod path 0o644;
    ignore (L.load path);
    Alcotest.(check int) "load re-narrows to 0600" 0o600 ((Unix.stat path).Unix.st_perm land 0o777);
    L.append "/proc/nonexistent/x/shell_history" "z";   (* never raises *)
    let oc = open_out path in
    output_string oc "a\n\n  \nb\n"; close_out oc;
    Alcotest.(check bool) "blank lines skipped" true (L.load path = [| "a"; "b" |]))

let test_default_path () =
  let old = Sys.getenv_opt "HOME" in
  Unix.putenv "HOME" "/h";
  Alcotest.(check (option string)) "under HOME/.march" (Some "/h/.march/shell_history")
    (L.default_path ());
  (match old with Some h -> Unix.putenv "HOME" h | None -> ())

let tests = [
  Alcotest.test_case "insert, cursor movement, delete" `Quick test_insert_and_cursor;
  Alcotest.test_case "kill commands and word movement" `Quick test_kill;
  Alcotest.test_case "UTF-8: one step per char, split reads" `Quick test_utf8;
  Alcotest.test_case "history navigation and draft restoration" `Quick test_history;
  Alcotest.test_case "accept, interrupt, eof, clear" `Quick test_events;
  Alcotest.test_case "escape sequence split across reads; bare ESC" `Quick test_escape_across_reads;
  Alcotest.test_case "unknown sequences leak nothing" `Quick test_unknown_sequences;
  Alcotest.test_case "view: horizontal scroll, narrow terminal" `Quick test_view;
  Alcotest.test_case "record: dedup, skips, cap" `Quick test_record;
  Alcotest.test_case "history file: load, append, cap, modes" `Quick test_file;
  Alcotest.test_case "default path" `Quick test_default_path;
]
