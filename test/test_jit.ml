(* test/test_jit.ml *)
let test_dlopen_libc () =
  (* On macOS, dlopen(NULL) gives the main program handle which includes libc *)
  let handle = March_jit.Jit.dlopen "" in
  (* getpid is always available *)
  let _sym = March_jit.Jit.dlsym handle "getpid" in
  March_jit.Jit.dlclose handle;
  Alcotest.(check pass) "dlopen/dlsym/dlclose round-trip" () ()

let () =
  Alcotest.run "march_jit" [
    "jit", [
      Alcotest.test_case "dlopen_libc" `Quick test_dlopen_libc;
    ]
  ]
