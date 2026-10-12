(* Capability sandbox profile derivation (design §4.3, mechanism B).

   The profile is the security boundary, so the tests that matter are the
   ones proving it neither over-blocks nor under-blocks:
   - a granted capability must survive (a sandbox that blocks everything
     passes any "is it blocked?" test and is useless);
   - a withheld capability must be denied;
   - grants must flow DOWN the lattice (IO.Network grants IO.NetListen), and
     holding a child must satisfy the parent's class (IO.NetListen keeps
     network access). Getting that direction backwards silently denies a
     granted capability, which is indistinguishable from correct
     containment. *)

open March_forge

(* [test_forge_fix_applies_capability_errors] and
   [test_scaffolded_app_builds_clean] below shell out to bare `march`/`forge`
   via [Sys.command]/[Sys.getenv "PATH"], resolved through ambient PATH. Left
   as-is that is CI-vacuous or CI-broken for exactly the reason
   [test_build_check.ml]'s [setup_hermetic_march] documents at length: a
   fresh CI checkout has no `.march-version` pin, no `~/.march/current`
   global, and no `march`/`forge` on PATH, so the bare commands either fail
   to resolve (rc=127, failing the `= 0` assertions for the wrong reason) or
   — locally, where a stale installed release happens to be on PATH — pass
   vacuously without ever exercising the build under test.

   Fix: symlink the JUST-BUILT `march` and `forge` (passed in by the dune
   rule below as MARCH_TEST_BIN / FORGE_TEST_BIN) onto a private bin/
   directory prepended to PATH, and point MARCH_HOME at an empty directory so
   no global toolchain resolves and the bare `march`/`forge` invoked by the
   subprocess commands in this file hit our symlinks. Mirrors
   [test_build_check.ml]'s [setup_hermetic_march] structurally, but that
   suite never exercises a real native compile (its `forge build` cases only
   cover a `Lib` project and error-before-compile paths), so it never hit the
   next problem: [resolve_exe_path]/[find_stdlib_dir]/[runtime_dir] in
   `bin/main.ml` resolve stdlib/runtime relative to [Sys.executable_name],
   and when `march` is invoked as a bare name resolved through PATH to a
   symlink, that resolves relative to the SYMLINK's directory (our private
   bin/), not the real build tree three levels up -- so a `forge build` under
   this symlink setup failed with "cannot find runtime/march_runtime.c" even
   though `forge check` (which never needs runtime/) passed. Fix: also pass
   the just-staged runtime/ and stdlib/ directories (MARCH_TEST_RUNTIME_DIR /
   MARCH_TEST_STDLIB_DIR, backed by `(source_tree ../../runtime)` /
   `(source_tree ../../stdlib)` deps in the dune rule) and export them as
   MARCH_RUNTIME_DIR / MARCH_STDLIB, which both take priority over
   exe-relative resolution (see the two doc comments in `bin/main.ml`). *)
let setup_hermetic_toolchain () =
  let resolve env_var =
    match Sys.getenv_opt env_var with
    | None | Some "" ->
      Printf.eprintf
        "test_cap_sandbox: %s is not set. The dune rule must pass the built \
         binary/directory (see forge/test/dune) -- refusing to fall back to \
         an ambient PATH binary, which would not exercise this build.\n"
        env_var;
      exit 2
    | Some rel ->
      if Filename.is_relative rel then Filename.concat (Sys.getcwd ()) rel else rel
  in
  let march_abs = resolve "MARCH_TEST_BIN" in
  let forge_abs = resolve "FORGE_TEST_BIN" in
  let runtime_dir_abs = resolve "MARCH_TEST_RUNTIME_DIR" in
  let stdlib_dir_abs = resolve "MARCH_TEST_STDLIB_DIR" in
  List.iter
    (fun abs ->
       if not (Sys.file_exists abs) then begin
         Printf.eprintf "test_cap_sandbox: %s does not exist\n" abs;
         exit 2
       end)
    [ march_abs; forge_abs; runtime_dir_abs; stdlib_dir_abs ];
  let bindir = Filename.temp_dir "march_hermetic_bin_" "" in
  let link_as name abs =
    let link = Filename.concat bindir name in
    try Unix.symlink abs link
    with Unix.Unix_error _ ->
      (* Symlinks unavailable -- fall back to a copy. *)
      ignore (Sys.command (Printf.sprintf "cp %s %s && chmod +x %s"
                              (Filename.quote abs) (Filename.quote link)
                              (Filename.quote link)))
  in
  link_as "march" march_abs;
  link_as "forge" forge_abs;
  let old_path = match Sys.getenv_opt "PATH" with Some p -> p | None -> "" in
  Unix.putenv "PATH" (bindir ^ ":" ^ old_path);
  (* Empty MARCH_HOME => no global toolchain resolves => the bare
     `march`/`forge` invoked by the shelled-out commands hit our PATH
     symlinks, not an installed release. *)
  Unix.putenv "MARCH_HOME" (Filename.temp_dir "march_hermetic_home_" "");
  (* Override resolution explicitly -- see the doc comment above for why
     exe-relative resolution can't be trusted once `march` is invoked through
     a PATH-resolved symlink. *)
  Unix.putenv "MARCH_RUNTIME_DIR" runtime_dir_abs;
  Unix.putenv "MARCH_STDLIB" stdlib_dir_abs

let has_deny profile needle =
  let re = Str.regexp_string needle in
  try ignore (Str.search_forward re profile 0); true with Not_found -> false

let profile caps = Cap_sandbox.profile_for ~caps ~binary:"/tmp/whatever" ()

let test_withheld_network_is_denied () =
  (* Deny-default: withholding means the ALLOW is absent, not that an
     explicit deny is present. *)
  let p = profile [ "IO.Console" ] in
  Alcotest.(check bool) "profile is deny-default" true (has_deny p "(deny default)");
  Alcotest.(check bool) "no network cap => no (allow network" false
    (has_deny p "(allow network")

let test_granted_child_keeps_parent_class () =
  (* IO.NetListen is a CHILD of IO.Network; holding it must keep network
     access. Regression: the subsumption ran held-over-parent and denied
     network to a program that had been granted IO.NetListen. *)
  let p = profile [ "IO.NetListen" ] in
  Alcotest.(check bool) "IO.NetListen granted => bind allowed" true
    (has_deny p "(allow network-bind)");
  Alcotest.(check bool) "IO.NetListen granted => inbound allowed" true
    (has_deny p "(allow network-inbound)")

let test_netconnect_does_not_grant_listen () =
  (* The split: holds_under is bidirectional, so IO.NetConnect alone makes
     IO.Network "held"; a network* grant on that opened network-bind to a
     connect-only program. *)
  List.iter
    (fun cap ->
       let p = profile [ cap ] in
       Alcotest.(check bool) (cap ^ " => outbound allowed") true
         (has_deny p "(allow network-outbound)");
       Alcotest.(check bool) (cap ^ " => NO bind") false
         (has_deny p "(allow network-bind)");
       Alcotest.(check bool) (cap ^ " => NO inbound") false
         (has_deny p "(allow network-inbound)");
       Alcotest.(check bool) (cap ^ " => NO network*") false
         (has_deny p "(allow network*)"))
    [ "IO.NetConnect"; "IO.NetConnect.TLS"; "IO.WebSocket"; "IO.Database" ];
  Alcotest.(check bool) "IO.NetListen => NO outbound" false
    (has_deny (profile [ "IO.NetListen" ]) "(allow network-outbound)")

let test_granted_parent_covers_child () =
  List.iter
    (fun cap ->
       let p = profile [ cap ] in
       List.iter
         (fun op ->
            Alcotest.(check bool) (cap ^ " granted => " ^ op) true
              (has_deny p ("(allow " ^ op ^ ")")))
         [ "network-outbound"; "network-bind"; "network-inbound" ])
    [ "IO.Network"; "IO" ]

let test_file_write_and_process_gating () =
  let pure = profile [ "IO.Console" ] in
  Alcotest.(check bool) "no write cap => no (allow file-write*)" false
    (has_deny pure "(allow file-write*)");
  Alcotest.(check bool) "no process cap => no (allow process-fork)" false
    (has_deny pure "(allow process-fork)");
  let w = profile [ "IO.FileWrite" ] in
  Alcotest.(check bool) "write granted => allowed" true
    (has_deny w "(allow file-write*)")

let test_target_binary_always_launchable () =
  (* Denying exec or read of the target prevents the process from starting
     at all — measured as exit 71 / SIGABRT. The profile must always carve
     these out or enforcement degenerates into "nothing runs". *)
  let p = Cap_sandbox.profile_for ~caps:[] ~binary:"/tmp/target-bin" () in
  Alcotest.(check bool) "exec is permitted by the baseline" true
    (has_deny p "(allow process-exec)");
  Alcotest.(check bool) "target is read-allowed" true
    (has_deny p "(allow file-read* (literal \"/tmp/target-bin\"))");
  (* Without these the runtime aborts under deny-default -- the reason the
     first deny-default attempt was wrongly judged infeasible. *)
  List.iter
    (fun needed ->
      Alcotest.(check bool)
        (Printf.sprintf "baseline includes %s" needed) true (has_deny p needed))
    [ "(allow mach*)"; "(allow sysctl-read)"; "(allow ipc-posix-shm)" ]

let test_unenforceable_caps_are_declared_advisory () =
  (* These must never be silently treated as enforced: denying them kills
     the runtime, so a report claiming enforcement would be false. *)
  List.iter
    (fun cap ->
      match Cap_sandbox.enforceability cap with
      | Cap_sandbox.Advisory _ -> ()
      | Cap_sandbox.Enforced ->
        Alcotest.failf "%s is claimed Enforced but cannot be" cap)
    (* IO.FileRead is NOT in this list: it is genuinely Enforced on the
       bwrap backend and Advisory on SBPL, so it gets its own
       backend-aware test rather than a blanket claim. *)
    [ "IO.Clock"; "IO.Spawn"; "IO.Foreign" ];
  match Cap_sandbox.enforceability "IO.Network" with
  | Cap_sandbox.Enforced -> ()
  | Cap_sandbox.Advisory _ ->
    Alcotest.fail "IO.Network is enforceable and must be reported as such"


(* Linux backend: the same capability decisions expressed as bubblewrap
   flags.  Tested independently of which backend this host actually has, so
   the Linux mapping is covered when developing on macOS. *)
let test_bwrap_withholds_and_grants () =
  let pure = Cap_sandbox.bwrap_args ~caps:[ "IO.Console" ] () in
  Alcotest.(check bool) "no network cap => --unshare-net" true
    (List.mem "--unshare-net" pure);
  (* With neither read nor write granted the namespace is an ALLOW-LIST, so
     the root is deliberately not bound wholesale — see
     test_bwrap_read_scoping. A writable /tmp is still provided so failures
     mean the withheld capability rather than incidental breakage. *)
  Alcotest.(check bool) "no read cap => root not bound wholesale" false
    (List.mem "--ro-bind / /" pure);
  Alcotest.(check bool) "no write cap => still a writable /tmp" true
    (List.mem "--tmpfs /tmp" pure);
  let ro = Cap_sandbox.bwrap_args ~caps:[ "IO.FileRead" ] () in
  Alcotest.(check bool) "read but no write => read-only root" true
    (List.mem "--ro-bind / /" ro);
  let net = Cap_sandbox.bwrap_args ~caps:[ "IO.NetListen" ] () in
  Alcotest.(check bool) "network child grant => no --unshare-net" false
    (List.mem "--unshare-net" net);
  (* IO.FileWrite and IO.FileRead are SIBLINGS under IO.FileSystem, so
     granting write alone does not grant read: such a program gets the
     allow-list namespace with a writable /tmp, and cannot see the rest of
     the filesystem it would be writing to. Only IO.FileSystem (or IO)
     grants both and yields a fully writable bind. *)
  let w = Cap_sandbox.bwrap_args ~caps:[ "IO.FileWrite" ] () in
  Alcotest.(check bool) "write alone does not open the whole fs" false
    (List.mem "--dev-bind / /" w);
  Alcotest.(check bool) "write alone still gets a writable /tmp" true
    (List.mem "--tmpfs /tmp" w);
  let fs = Cap_sandbox.bwrap_args ~caps:[ "IO.FileSystem" ] () in
  Alcotest.(check bool) "IO.FileSystem => read+write bind" true
    (List.mem "--dev-bind / /" fs);
  let root = Cap_sandbox.bwrap_args ~caps:[ "IO" ] () in
  Alcotest.(check bool) "root grant => nothing withheld" true
    (root = [ "--dev-bind / /" ])


(* Read scoping (Linux).  Verified end-to-end in a 6.12 container using the
   flags this function emits: /etc/hosts DENIED without IO.FileRead, OK with
   it, OK under a root IO grant. *)
let test_bwrap_read_scoping () =
  let deny = Cap_sandbox.bwrap_args ~binary:"/tmp/app" ~caps:[ "IO.Console" ] () in
  Alcotest.(check bool) "no read cap => allow-list namespace, not whole fs" true
    (List.exists (fun f -> f = "--ro-bind-try /usr /usr") deny);
  Alcotest.(check bool) "no read cap => root NOT bound wholesale" false
    (List.mem "--ro-bind / /" deny || List.mem "--dev-bind / /" deny);
  let grant = Cap_sandbox.bwrap_args ~binary:"/tmp/app" ~caps:[ "IO.FileRead" ] () in
  Alcotest.(check bool) "read cap => whole fs visible" true
    (List.mem "--ro-bind / /" grant)

let test_binary_bound_after_tmpfs () =
  (* Regression: --tmpfs /tmp masks everything under it, including a binary
     living there, making the program unlaunchable. The bind must come after
     every tmpfs. Only the GRANTED direction exposes this — the denied
     direction passes either way. *)
  let check caps =
    let fl = Cap_sandbox.bwrap_args ~binary:"/tmp/app" ~caps () in
    let idx p = 
      let rec go i = function
        | [] -> -1
        | x :: tl -> if x = p then i else go (i + 1) tl
      in go 0 fl
    in
    let t = idx "--tmpfs /tmp" in
    let b = idx "--ro-bind-try '/tmp/app' '/tmp/app'" in
    if t >= 0 then
      Alcotest.(check bool)
        (Printf.sprintf "binary bound after tmpfs for %s"
           (String.concat "," caps))
        true (b > t)
  in
  check [ "IO.Console" ];
  check [ "IO.FileRead" ]

let test_filereads_enforceability_matches_backend () =
  (* IO.FileRead is Enforced on Linux (allow-list namespace) and Advisory on
     macOS (dyld must map libs first). Whichever host runs the suite, the
     claim must match what that backend can actually do. *)
  match Cap_sandbox.enforceability "IO.FileRead" with
  | Cap_sandbox.Enforced ->
    Alcotest.(check bool) "Enforced only claimed on the bwrap backend" true
      (Sys.file_exists "/usr/bin/bwrap" || Sys.file_exists "/bin/bwrap")
  | Cap_sandbox.Advisory _ ->
    Alcotest.(check bool) "Advisory only on a non-bwrap backend" true
      (not (Sys.file_exists "/usr/bin/bwrap" || Sys.file_exists "/bin/bwrap"))

(* ── Declared path scopes (the binary's manifest) ──────────────────────
   Scope paths live under a root that does not exist, so resolve_scope
   (realpath of the longest existing prefix) returns them unchanged on any
   host and the expected flags are deterministic. *)
let nx = "/nonexistent_march_scope_root"

let idx fl p =
  let rec go i = function
    | [] -> -1
    | x :: tl -> if x = p then i else go (i + 1) tl
  in
  go 0 fl

let test_bwrap_write_scope () =
  let scopes = [ ("IO.FileWrite", Some (nx ^ "/out")) ] in
  let fl =
    Cap_sandbox.bwrap_args ~binary:"/tmp/app" ~scopes
      ~caps:[ "IO.FileRead"; "IO.FileWrite" ] ()
  in
  Alcotest.(check bool) "scoped write => root NOT writable" false
    (List.mem "--dev-bind / /" fl);
  Alcotest.(check bool) "unscoped read => whole tree read-only" true
    (List.mem "--ro-bind / /" fl);
  let b = idx fl (Printf.sprintf "--bind-try '%s/out' '%s/out'" nx nx) in
  Alcotest.(check bool) "write scope bound writable" true (b >= 0);
  Alcotest.(check bool) "write scope bound after the /tmp tmpfs" true
    (b > idx fl "--tmpfs /tmp")

let test_bwrap_read_scope () =
  let scopes = [ ("IO.FileRead", Some (nx ^ "/etc")) ] in
  let fl = Cap_sandbox.bwrap_args ~binary:"/tmp/app" ~scopes
      ~caps:[ "IO.FileRead" ] () in
  Alcotest.(check bool) "scoped read => allow-list, root not bound" false
    (List.mem "--ro-bind / /" fl || List.mem "--dev-bind / /" fl);
  Alcotest.(check bool) "loader paths still bound" true
    (List.mem "--ro-bind-try /usr /usr" fl);
  Alcotest.(check bool) "read scope bound read-only" true
    (List.mem (Printf.sprintf "--ro-bind-try '%s/etc' '%s/etc'" nx nx) fl);
  (* IO.FileSystem("/srv") scopes both: read-only bind first, then the
     writable one, so the writable mount wins. *)
  let fs = Cap_sandbox.bwrap_args
      ~scopes:[ ("IO.FileSystem", Some (nx ^ "/srv")) ]
      ~caps:[ "IO.FileSystem" ] () in
  let ro = idx fs (Printf.sprintf "--ro-bind-try '%s/srv' '%s/srv'" nx nx) in
  let rw = idx fs (Printf.sprintf "--bind-try '%s/srv' '%s/srv'" nx nx) in
  Alcotest.(check bool) "FileSystem scope: ro then rw" true (ro >= 0 && rw > ro);
  Alcotest.(check bool) "FileSystem scope: root not bound" false
    (List.mem "--ro-bind / /" fs || List.mem "--dev-bind / /" fs)

let test_scopes_never_widen () =
  (* A scope narrows a HELD class only: a withheld class stays withheld, and
     an unscoped grant (or no manifest at all) keeps the old flags exactly. *)
  let caps = [ "IO.Console" ] in
  Alcotest.(check (list string)) "withheld write: manifest changes nothing"
    (Cap_sandbox.bwrap_args ~binary:"/tmp/app" ~caps ())
    (Cap_sandbox.bwrap_args ~binary:"/tmp/app"
       ~scopes:[ ("IO.FileWrite", Some (nx ^ "/w")) ] ~caps ());
  let caps = [ "IO.FileRead"; "IO.FileWrite" ] in
  Alcotest.(check (list string)) "unscoped grant alongside a scope: unchanged"
    (Cap_sandbox.bwrap_args ~caps ())
    (Cap_sandbox.bwrap_args
       ~scopes:[ ("IO.FileWrite", Some (nx ^ "/w")); ("IO.FileWrite", None) ]
       ~caps ());
  Alcotest.(check string) "SBPL: no scopes => old profile"
    (Cap_sandbox.profile_for ~caps ~binary:"/b" ())
    (Cap_sandbox.profile_for ~scopes:[] ~caps ~binary:"/b" ())

let test_sbpl_write_scope () =
  let p = Cap_sandbox.profile_for
      ~scopes:[ ("IO.FileWrite", Some (nx ^ "/out")) ]
      ~caps:[ "IO.FileWrite" ] ~binary:"/b" () in
  Alcotest.(check bool) "blanket write grant gone" false
    (has_deny p "(allow file-write*)\n");
  Alcotest.(check bool) "subpath grant present" true
    (has_deny p (Printf.sprintf "(allow file-write* (subpath \"%s/out\"))" nx))

let test_resolve_scope_follows_symlinks () =
  let d = Filename.temp_dir "scope_res" "" in
  let real = Filename.concat d "real" in
  Unix.mkdir real 0o755;
  let link = Filename.concat d "link" in
  Unix.symlink real link;
  let real_abs = Unix.realpath real in
  Alcotest.(check string) "existing symlink resolved" real_abs
    (Cap_sandbox.resolve_scope link);
  Alcotest.(check string) "missing tail re-appended to the resolved prefix"
    (real_abs ^ "/not/yet")
    (Cap_sandbox.resolve_scope (link ^ "/not/yet"));
  ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote d)))

(* End to end: a REAL compiled binary carrying a scoped grant, run through
   `forge cap run`.  Asserted by host-side effects, not program output, so
   one test holds on both backends: macOS refuses the out-of-scope write
   (EPERM), Linux bwrap lets it land in the sandbox's private /tmp tmpfs,
   and either way nothing reaches the host outside the scope. *)
let bwrap_usable () =
  match Sys.command "bwrap --ro-bind / / true >/dev/null 2>&1" with
  | 0 -> true
  | _ -> false

let scope_fixture ~modname ~decl ~inside ~outside =
  Printf.sprintf
    {|mod %s do
  needs IO.Console
  needs %s

  fn main(_c : Cap(IO.Console), _w : Cap(IO.FileWrite)) : Unit do
    let outside = "%s"
    match file_write("%s", "x") do
      Ok(_) -> println("inscope=0")
      Err(_) -> println("inscope=1")
    end
    match file_write(outside ++ "", "x") do
      Ok(_) -> println("outscope=0")
      Err(_) -> println("outscope=1")
    end
  end
end
|}
    modname decl outside inside

let compile_fixture dir name src =
  let path = Filename.concat dir (name ^ ".march") in
  let oc = open_out path in
  output_string oc src;
  close_out oc;
  let bin = Filename.concat dir name in
  let rc = Sys.command
      (Printf.sprintf "march --compile -o %s %s > %s.log 2>&1"
         (Filename.quote bin) (Filename.quote path) (Filename.quote bin)) in
  if rc <> 0 then Alcotest.failf "compiling %s failed (rc=%d), see %s.log" name rc bin;
  bin

let cap_run bin =
  Sys.command
    (Printf.sprintf "forge cap run %s > %s.run 2>&1" (Filename.quote bin)
       (Filename.quote bin))

let test_cap_run_enforces_declared_scope () =
  if (not Cap_sandbox.supported)
  || (Cap_sandbox.enforceability "IO.FileWrite" <> Cap_sandbox.Enforced)
  || (not (Sys.file_exists "/usr/bin/sandbox-exec") && not (bwrap_usable ()))
  then Alcotest.skip ()
  else begin
    (* Spelled through the unresolved temp dir (/var/folders -> /private/...
       on macOS) so the scope must be resolved on this machine to match. *)
    let d = Filename.temp_dir "cap_run_scope" "" in
    let scope = Filename.concat d "in" in
    Unix.mkdir scope 0o755;
    let inside = Filename.concat scope "a.txt" in
    let outside = Filename.concat d "out.txt" in
    let reset () =
      List.iter (fun f -> try Sys.remove f with Sys_error _ -> ()) [ inside; outside ]
    in
    (* Scoped grant: inside allowed, outside denied. *)
    let scoped =
      compile_fixture d "scoped"
        (scope_fixture ~modname:"CapRunScoped"
           ~decl:(Printf.sprintf "IO.FileWrite(\"%s\")" scope) ~inside ~outside)
    in
    (match Cap_binary.read scoped with
     | Ok t ->
       Alcotest.(check (result (list (pair string (option string))) string))
         "compiled binary carries its declared scope"
         (Ok [ ("IO.FileWrite", Some scope) ])
         (Cap_binary.scope_decls t)
     | Error e -> Alcotest.fail e);
    reset ();
    Alcotest.(check int) "scoped binary runs" 0 (cap_run scoped);
    Alcotest.(check bool) "in-scope write reached the host" true
      (Sys.file_exists inside);
    Alcotest.(check bool) "out-of-scope write did NOT reach the host" false
      (Sys.file_exists outside);
    (* Unscoped grant: behaves as before — writes anywhere. *)
    let unscoped =
      compile_fixture d "unscoped"
        (scope_fixture ~modname:"CapRunUnscoped" ~decl:"IO.FileWrite" ~inside
           ~outside)
    in
    (match Cap_binary.read unscoped with
     | Ok t ->
       Alcotest.(check (option string))
         "unscoped program embeds no manifest (identical to an old binary)"
         None t.Cap_binary.manifest
     | Error e -> Alcotest.fail e);
    reset ();
    Alcotest.(check int) "unscoped binary runs" 0 (cap_run unscoped);
    (* Host effects of the UNSCOPED run are asserted on macOS only.  On bwrap
       a program holding IO.FileWrite without IO.FileRead gets the allow-list
       namespace whose only writable place is a private /tmp tmpfs, so its
       writes never reach the host at all — a pre-existing limitation of
       bwrap_args, unchanged here and recorded in
       specs/todos/2026-08-04-path-scope-followups.md. *)
    if Sys.file_exists "/usr/bin/sandbox-exec" then begin
      Alcotest.(check bool) "unscoped: in-scope write lands" true
        (Sys.file_exists inside);
      Alcotest.(check bool) "unscoped: the 'outside' write lands too" true
        (Sys.file_exists outside)
    end;
    ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote d)))
  end

let test_forge_fix_applies_capability_errors () =
  (* A capability-incorrect module must be repaired by `forge fix`, not
     refused. Both fixes are error-severity: the missing grant on `main`
     and the missing `needs` line. `collect_all_fixes` used to set
     `has_errors` on exactly the diagnostics that carry a fix (the ones
     `parse_fix_line` doesn't discard), so `forge fix` refused precisely
     when it had safe work to do. *)
  let dir = Filename.concat (Filename.get_temp_dir_name ()) "forge_fix_caps" in
  ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote dir)));
  ignore (Sys.command (Printf.sprintf "mkdir -p %s/lib" (Filename.quote dir)));
  let src = Filename.concat dir "lib/ffc.march" in
  let oc = open_out src in
  output_string oc "mod Ffc do\n  fn main() do\n    println(\"hi\")\n  end\nend\n";
  close_out oc;
  let toml = open_out (Filename.concat dir "forge.toml") in
  output_string toml "[package]\nname = \"ffc\"\nversion = \"0.1.0\"\ntype = \"app\"\n\n[deps]\n";
  close_out toml;
  let rc = Sys.command (Printf.sprintf "cd %s && forge fix > /dev/null 2>&1" (Filename.quote dir)) in
  Alcotest.(check int) "forge fix succeeds on capability errors" 0 rc;
  let ic = open_in src in
  let n = in_channel_length ic in
  let content = really_input_string ic n in
  close_in ic;
  Alcotest.(check bool) "needs line inserted" true
    (has_deny content "needs IO.Console");
  Alcotest.(check bool) "grant parameter inserted" true
    (has_deny content "Cap(IO.Console)")

let test_scaffolded_app_builds_clean () =
  let dir = Filename.concat (Filename.get_temp_dir_name ()) "forge_new_clean" in
  ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote dir)));
  let rc_new = Sys.command
    (Printf.sprintf "cd %s && forge new %s > /dev/null 2>&1"
       (Filename.quote (Filename.get_temp_dir_name ())) "forge_new_clean") in
  Alcotest.(check int) "forge new succeeds" 0 rc_new;
  let rc_check = Sys.command
    (Printf.sprintf "cd %s && forge check > /dev/null 2>&1" (Filename.quote dir)) in
  Alcotest.(check int) "a freshly scaffolded app checks clean" 0 rc_check;
  let rc_build = Sys.command
    (Printf.sprintf "cd %s && forge build > /dev/null 2>&1" (Filename.quote dir)) in
  Alcotest.(check int) "a freshly scaffolded app builds" 0 rc_build;
  let rc_test = Sys.command
    (Printf.sprintf "cd %s && forge test > /dev/null 2>&1" (Filename.quote dir)) in
  Alcotest.(check int) "a freshly scaffolded app's tests run" 0 rc_test

let tests =
  [
    Alcotest.test_case "bwrap read scoping" `Quick test_bwrap_read_scoping;
    Alcotest.test_case "binary bound after tmpfs" `Quick test_binary_bound_after_tmpfs;
    Alcotest.test_case "bwrap write scope" `Quick test_bwrap_write_scope;
    Alcotest.test_case "bwrap read scope" `Quick test_bwrap_read_scope;
    Alcotest.test_case "scopes never widen" `Quick test_scopes_never_widen;
    Alcotest.test_case "SBPL write scope" `Quick test_sbpl_write_scope;
    Alcotest.test_case "resolve_scope follows symlinks" `Quick
      test_resolve_scope_follows_symlinks;
    Alcotest.test_case "forge cap run enforces a declared scope" `Quick
      test_cap_run_enforces_declared_scope;
    Alcotest.test_case "IO.FileRead enforceability matches backend" `Quick
      test_filereads_enforceability_matches_backend;
    Alcotest.test_case "bwrap withholds and grants correctly" `Quick
      test_bwrap_withholds_and_grants;
    Alcotest.test_case "withheld network is denied" `Quick
      test_withheld_network_is_denied;
    Alcotest.test_case "granted child keeps parent class" `Quick
      test_granted_child_keeps_parent_class;
    Alcotest.test_case "NetConnect does not grant bind/inbound" `Quick
      test_netconnect_does_not_grant_listen;
    Alcotest.test_case "granted parent covers child" `Quick
      test_granted_parent_covers_child;
    Alcotest.test_case "file-write and process gating" `Quick
      test_file_write_and_process_gating;
    Alcotest.test_case "target binary is always launchable" `Quick
      test_target_binary_always_launchable;
    Alcotest.test_case "unenforceable caps declared advisory" `Quick
      test_unenforceable_caps_are_declared_advisory;
    Alcotest.test_case "forge fix applies capability errors" `Quick
      test_forge_fix_applies_capability_errors;
    Alcotest.test_case "scaffolded app builds clean" `Quick
      test_scaffolded_app_builds_clean;
  ]

let () =
  setup_hermetic_toolchain ();
  Alcotest.run "cap_sandbox" [ ("cap_sandbox", tests) ]
