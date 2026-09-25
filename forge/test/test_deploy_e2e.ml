(** `forge host init`, `forge deploy` and `forge deploy --plan` end to end,
    over real ssh, against a Debian container with sshd (distributed-deploys
    build step 10b, items 2, 4 and 5).

    The real forge binary (FORGE_TEST_BIN) and compiler (MARCH_TEST_BIN), a
    scratch copy of examples/topology_app whose `back` pool runs on the
    container (`topology.prod.toml`, `[backend] kind = "ssh"`):

    1. `forge host init --env prod` prepares it and records its target.
    2. `forge deploy --env prod --yes`: nothing is deployed, so the plan
       restarts `back`: forge cross-builds the base image for the recorded
       target, uploads it, restarts the unit, waits for the reload socket
       (through the ssh tunnel) and pushes the signed topology.
    3. A second deploy of the same tree has nothing to do.
    4. A changed role body: `--plan` says hot patch; the deploy activates
       it through the tunnel on the running node; `forge topology status`
       shows the patch and that the node runs what forge deployed.
    5. `forge deploy --compact`: the base image is rebuilt from the current
       version and the node restarted onto it; its persisted patch stack is
       empty afterwards (item 5).

    The container has no systemd: a stand-in `systemctl` runs a unit's
    ExecStart with its Environment= as the unit's User (setpriv), which is
    what restart, is-active and kill need. Skipped, loudly, when Docker, zig
    or the cross sysroot is missing; never a vacuous pass. *)

let getenv_abs v =
  match Sys.getenv_opt v with
  | None | Some "" -> Printf.eprintf "test_deploy_e2e: %s is not set (see forge/test/dune)\n" v; exit 2
  | Some p -> if Filename.is_relative p then Filename.concat (Sys.getcwd ()) p else p

let read_file path = try In_channel.with_open_bin path In_channel.input_all with Sys_error _ -> ""
let write_file path s = Out_channel.with_open_bin path (fun oc -> output_string oc s)

let contains s sub =
  let n = String.length s and k = String.length sub in
  let rec go i = i + k <= n && (String.sub s i k = sub || go (i + 1)) in
  go 0

let expect what text subs =
  List.iter (fun s -> if not (contains text s) then Alcotest.failf "%s: expected %S in:\n%s" what s text) subs

let sh cmd = Sys.command cmd = 0

let capture cmd =
  let ic = Unix.open_process_in cmd in
  let s = In_channel.input_all ic in
  ignore (Unix.close_process_in ic);
  String.trim s

let banner reason =
  let bar = String.make 72 '*' in
  Printf.eprintf "%s\n* SKIP: forge deploy end-to-end (container): %s\n* The ssh deploy path is NOT exercised by this run.\n%s\n%!"
    bar reason bar

let skip reason = banner reason; Alcotest.skip ()

let fake_systemctl = {|#!/bin/sh
# A stand-in for systemctl in a container without systemd (forge test_deploy_e2e).
cmd=$1; shift
[ "$cmd" = "--quiet" ] && { cmd=$1; shift; }
unit=$1; [ "$unit" = "--quiet" ] && unit=$2
case "$cmd" in --signal=*) sig=${cmd#--signal=}; cmd=kill; unit=$1 ;; esac
[ "$cmd" = "kill" ] && case "$1" in --signal=*) sig=${1#--signal=}; unit=$2 ;; esac
pidf=/run/fake-systemd-$unit.pid
alive() { [ -f "$pidf" ] && kill -0 "$(cat "$pidf")" 2>/dev/null; }
case "$cmd" in
  daemon-reload|enable) exit 0 ;;
  is-enabled) exit 1 ;;
  is-active) if alive; then echo active; else echo inactive; exit 3; fi ;;
  kill) alive && kill -"${sig:-TERM}" "$(cat "$pidf")" ;;
  stop) if alive; then kill "$(cat "$pidf")"; while alive; do sleep 0.2; done; fi ;;
  restart|start)
    f=/etc/systemd/system/$unit
    if alive; then kill "$(cat "$pidf")"; n=0; while alive && [ $n -lt 100 ]; do sleep 0.1; n=$((n+1)); done; fi
    exe=$(sed -n 's/^ExecStart=//p' "$f"); user=$(sed -n 's/^User=//p' "$f")
    envfile=$(sed -n 's/^EnvironmentFile=-\{0,1\}//p' "$f")
    (
      set -a
      [ -f "$envfile" ] && . "$envfile"
      for e in $(sed -n 's/^Environment=//p' "$f"); do export "$e"; done
      cd /
      exec setpriv --reuid="$user" --regid="$user" --init-groups "$exe"
    ) > "/var/log/$unit.log" 2>&1 &
    echo $! > "$pidf" ;;
  *) echo "fake systemctl: $cmd not supported" >&2; exit 1 ;;
esac
|}

let dockerfile = {|FROM debian:bookworm-slim
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends openssh-server libssl3 zlib1g procps util-linux >/dev/null \
 && rm -rf /var/lib/apt/lists/* && mkdir -p /run/sshd /root/.ssh && chmod 700 /root/.ssh
COPY systemctl /usr/local/bin/systemctl
RUN chmod 755 /usr/local/bin/systemctl
CMD ["/usr/sbin/sshd", "-D", "-e"]
|}

let image = "forge-deploy-e2e:1"

let test_deploy_over_ssh () =
  if not (sh "command -v docker >/dev/null 2>&1") then skip "docker is not installed";
  if not (sh "docker info >/dev/null 2>&1") then skip "docker's daemon is not reachable";
  if not (sh "command -v zig >/dev/null 2>&1") then skip "zig (the cross C compiler) is not installed";
  let arch = capture "docker info --format '{{.Architecture}}'" in
  let target, deb_arch = if arch = "x86_64" then ("linux/amd64", "amd64") else ("linux/arm64", "arm64") in
  let real_home = Option.value ~default:"" (Sys.getenv_opt "HOME") in
  let sysroot_var = "MARCH_CROSS_SYSROOT_" ^ String.uppercase_ascii deb_arch in
  let sysroot = match Sys.getenv_opt sysroot_var with
    | Some d when d <> "" -> d
    | _ -> Filename.concat real_home (".cache/march/cross-sysroot/linux-" ^ deb_arch) in
  if not (Sys.file_exists (Filename.concat sysroot "lib/libssl.so.3")) then
    skip (Printf.sprintf "no %s cross sysroot at %s (run scripts/fetch-cross-sysroot.sh %s)" target sysroot deb_arch);
  let dir = Filename.temp_dir "forge_deploy_e2e_" "" in
  let ctx = Filename.concat dir "image" in
  Unix.mkdir ctx 0o755;
  write_file (Filename.concat ctx "Dockerfile") dockerfile;
  write_file (Filename.concat ctx "systemctl") fake_systemctl;
  if not (sh (Printf.sprintf "docker build -q -t %s %s >%s/build.log 2>&1" image ctx dir)) then
    skip ("the Debian sshd image did not build (no network?): " ^ read_file (Filename.concat dir "build.log"));
  let key = Filename.concat dir "id_ed25519" in
  if not (sh (Printf.sprintf "ssh-keygen -q -t ed25519 -N '' -f %s" key)) then Alcotest.fail "ssh-keygen";
  let name = Printf.sprintf "forge-deploy-e2e-%d" (Unix.getpid ()) in
  if not (sh (Printf.sprintf "docker run -d --name %s --add-host web-1:127.0.0.1 -p 127.0.0.1::22 %s >/dev/null" name image)) then
    Alcotest.fail "docker run";
  Fun.protect ~finally:(fun () ->
      if Sys.getenv_opt "FORGE_E2E_KEEP" = None then ignore (sh (Printf.sprintf "docker rm -f %s >/dev/null 2>&1" name))
      else Printf.eprintf "kept container %s and %s\n%!" name dir) @@ fun () ->
  if not (sh (Printf.sprintf "docker cp %s.pub %s:/root/.ssh/authorized_keys && docker exec %s chown root:root /root/.ssh/authorized_keys" key name name))
  then Alcotest.fail "installing the key";
  let port = capture (Printf.sprintf "docker port %s 22/tcp | head -1 | sed 's/.*://'" name) in
  let cfg = Filename.concat dir "ssh_config" in
  write_file cfg (Printf.sprintf
                    "Host web-1\n  HostName 127.0.0.1\n  Port %s\n  User root\n  IdentityFile %s\n  IdentitiesOnly yes\n\
                    \  StrictHostKeyChecking no\n  UserKnownHostsFile /dev/null\n  LogLevel ERROR\n" port key);
  let rec wait n =
    if sh (Printf.sprintf "ssh -F %s web-1 true >/dev/null 2>&1" cfg) then ()
    else if n = 0 then Alcotest.fail "sshd never answered" else (Unix.sleepf 0.5; wait (n - 1))
  in
  wait 40;
  (* The toolchain under test, hermetically. *)
  let bin = Filename.concat dir "bin" in
  Unix.mkdir bin 0o755;
  Unix.symlink (getenv_abs "MARCH_TEST_BIN") (Filename.concat bin "march");
  Unix.symlink (getenv_abs "FORGE_TEST_BIN") (Filename.concat bin "forge");
  let home = Filename.concat dir "home" and mhome = Filename.concat dir "mhome" in
  Unix.mkdir home 0o755; Unix.mkdir mhome 0o755;
  let env =
    [ ("PATH", bin ^ ":" ^ Option.value ~default:"/usr/bin:/bin" (Sys.getenv_opt "PATH")); ("HOME", home);
      ("MARCH_HOME", mhome); ("MARCH_RUNTIME_DIR", getenv_abs "MARCH_TEST_RUNTIME_DIR");
      ("MARCH_STDLIB", getenv_abs "MARCH_TEST_STDLIB_DIR"); ("FORGE_SSH_CONFIG", cfg); (sysroot_var, sysroot) ]
  in
  let proj = Filename.concat dir "app" in
  if not (sh (Printf.sprintf "cp -R %s/. %s && chmod -R u+w %s && rm -rf %s/.forge %s/.march"
                (Filename.quote (getenv_abs "TOPOLOGY_APP_DIR")) proj proj proj proj)) then Alcotest.fail "copy the app";
  (* Hot-patchable code: today a topology app's own functions reach the
     compiler's IR without the entry module's name (Back.x, not
     TopologyApp.Back.x), so `--hot-reload TopologyApp` gives them no
     dispatch slot; the pool's module is the prefix that covers them.
     Back.scale is a plain function the role's closure calls. *)
  let src = Filename.concat proj "src/topology_app.march" in
  let edit what by =
    let text = read_file src in
    let changed = Str.replace_first (Str.regexp_string what) by text in
    if changed = text then Alcotest.failf "fixture: %S not found" what;
    write_file src changed
  in
  edit "      { factor: 10 }\n    end\n"
    "      { factor: 10 }\n    end\n\n    fn scale(n : Int, f : Int) : Int do\n      n * f\n    end\n";
  edit "n * env.factor" "scale(n, env.factor)";
  write_file (Filename.concat proj "forge.toml")
    (read_file (Filename.concat proj "forge.toml") ^ "\n[hot-reload]\nmodule_prefix = \"Back\"\n");
  write_file (Filename.concat proj "topology.prod.toml")
    "[pool.back]\nhosts = [{ host = \"root@web-1\", labels = [\"db\"] }]\n\n[backend]\nkind = \"ssh\"\n";
  let log = Filename.concat dir "forge.log" in
  let forge args =
    let exports = String.concat " " (List.map (fun (k, v) -> k ^ "=" ^ Filename.quote v) env) in
    let rc = Sys.command (Printf.sprintf "cd %s && env %s forge %s > %s 2>&1" (Filename.quote proj) exports args log) in
    let out = read_file log in
    Printf.printf "$ forge %s  (exit %d)\n%s\n%!" args rc out;
    (rc, out)
  in
  let ok args = match forge args with (0, out) -> out | (rc, out) -> Alcotest.failf "forge %s exited %d:\n%s" args rc out in
  ignore (ok "hot-reload keygen");
  let out = ok "host init --env prod" in
  expect "host init" out [ "back-web-1 (root@web-1, pool back)"; "target " ^ target ];
  (* 2: the first deploy restarts back onto a cross-built base image. *)
  let out = ok "deploy --env prod --plan" in
  expect "first plan" out [ "nothing has been deployed to this environment yet"; "pool back (build shared, 1 host): restart" ];
  let out = ok "deploy --env prod --yes" in
  expect "first deploy" out [ "==> pool back: restart"; "back-web-1: restarted"; "==> pushing the topology"; "deploy complete" ];
  let status = ok "topology status --env prod" in
  expect "status after the first deploy" status
    [ "back-web-1 (pool back, host root@web-1"; "reload server: "; "(target " ^ target ^ ")";
      "back-web-1: running code matches what forge last deployed" ];
  (* 3: nothing changed. *)
  expect "second deploy" (ok "deploy --env prod --yes") [ "nothing to deploy" ];
  (* 4a: an edit inside serve_one's closure: the closure is lifted
     ($lam...), has no dispatch slot and no slotted caller that changes (a
     closure is called through its value), and later generated names are
     renumbered: the running base cannot swap it, so the plan restarts. *)
  edit "scale(n, env.factor)" "scale(n, env.factor) + 0";
  expect "closure plan" (ok "deploy --env prod --plan")
    [ "pool back (build shared, 1 host): restart"; "no dispatch slot in the running base build" ];
  expect "closure deploy" (ok "deploy --env prod --yes") [ "==> pool back: restart"; "back-web-1: restarted"; "deploy complete" ];
  (* 4b: Back.scale is a slot, and `n * f` -> `n + f` makes no new
     generated names: a hot patch, activated on the running node through
     the ssh tunnel. *)
  edit "      n * f" "      n + f";
  expect "hot plan" (ok "deploy --env prod --plan") [ "changed: Back.scale"; "pool back (build shared, 1 host): hot patch" ];
  let out = ok "deploy --env prod --yes" in
  expect "hot deploy" out [ "==> pool back: hot patch"; "activated: Back.scale"; "Deploy complete"; "deploy complete" ];
  let status = ok "topology status --env prod" in
  expect "status after the hot patch" status [ "1 hot-patched"; "back-web-1: running code matches what forge last deployed";
                                               "patch stack: 1 persisted patch" ];
  (* 5: compaction: the base image is rebuilt from the current version, the
     node restarted onto it, and its persisted patch stack cleared. *)
  expect "compaction plan" (ok "deploy --env prod --compact --plan")
    [ "pool back (build shared, 1 host): restart"; "compaction: --compact";
      "compaction: build shared: --compact; its hosts restart on a base image rebuilt from the current version" ];
  let out = ok "deploy --env prod --compact --yes" in
  expect "compaction" out [ "==> pool back: restart"; "back-web-1: restarted";
                            "back-web-1: persisted patch stack cleared (was 1 entry)"; "deploy complete" ];
  let status = ok "topology status --env prod" in
  expect "status after compaction" status
    [ "0 hot-patched"; "patch stack: no hot patches persisted (the node runs its base build)";
      "back-web-1: running code matches what forge last deployed" ];
  if contains (capture (Printf.sprintf "docker exec %s sh -c 'ls /var/lib/march/topology_app/.march/cas/hcr_state/*/ 2>&1'" name))
      "base-changed" then Alcotest.fail "state.base-changed was left on the host"

let () =
  if not (sh "command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1") then
    banner "Docker is absent or its daemon is not reachable";
  Alcotest.run "deploy-e2e" [
    ("ssh", [ Alcotest.test_case "host init, first deploy, restart, hot patch, compaction over ssh" `Slow test_deploy_over_ssh ]);
  ]
