let test_linux_identities () =
  let open March_tir.Llvm_toplevel in
  let amd64 = Result.get_ok (March_tir.Hcr_abi.of_target
    (LinuxGnu { arch = X86_64; glibc_min = "2.36" })) in
  let arm64 = Result.get_ok (March_tir.Hcr_abi.of_target
    (LinuxGnu { arch = Arm64; glibc_min = "2.36" })) in
  Alcotest.(check string) "amd64 triple"
    "x86_64-unknown-linux-gnu" amd64.llvm_triple;
  Alcotest.(check string) "arm64 triple"
    "aarch64-unknown-linux-gnu" arm64.llvm_triple;
  Alcotest.(check string) "amd64 canonical target"
    "linux/amd64" amd64.canonical_target;
  Alcotest.(check string) "arm64 canonical target"
    "linux/arm64" arm64.canonical_target

let test_unsupported_target () =
  match March_tir.Hcr_abi.of_target March_tir.Llvm_toplevel.Wasm32Wasi with
  | Error msg -> Alcotest.(check string) "diagnostic"
      "hot reload requires a native dynamic loader and Unix-domain sockets; target wasm32-wasi is unsupported" msg
  | Ok _ -> Alcotest.fail "WASM must not advertise HCR"

let () =
  Alcotest.run "hcr_abi" [
    ("target identity", [
      Alcotest.test_case "linux identities" `Quick test_linux_identities;
      Alcotest.test_case "unsupported target" `Quick test_unsupported_target;
    ])
  ]
