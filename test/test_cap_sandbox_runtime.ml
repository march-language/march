(* Runtime enforcement tests for --cap-sandbox (specs/2026-08-12-cap-sandbox-
   runtime-enforcement-test-design.md). test_cap_sandbox_profile.ml and
   test_cap_strip.ml verify the embedded SBPL (macOS) / seccomp -D flag
   (Linux) STRINGS are correct. Nothing verified the RUNTIME BEHAVIOR those
   strings are supposed to produce until this file: that a withheld
   capability's syscall actually fails at runtime while a held one still
   succeeds.

   A pure March program cannot call a capability-gated builtin without
   holding that exact capability -- the type checker rejects it at compile
   time -- so a fixture that "holds X but not Y" can never reach Y's syscall
   through ordinary March code. The way around this is exactly the boundary
   the sandbox exists to backstop: extern / IO.Foreign. An extern block's
   declared Cap(X) annotation is self-declared and unverified (the compiler
   cannot see what the linked C code does), so a module can hold IO.Foreign
   (+ two of the three IO classes under test) and NOT hold the third, declare
   its extern block Cap(IO.Foreign) (trivially satisfied), and have the C
   code call socket()/execve()/fork()/open() directly. See specs/lang/
   capabilities.md's "IO.Foreign -- calling unverified C" section.

   The "process" class on the two backends: on Linux, withholding IO.Process
   denies execve/execveat and never gates fork/clone. On macOS it denies BOTH
   process-fork and process-exec (exec was ungated baseline until 2026-09-21;
   see specs/progress/2026-09-21-cap-sandbox-macos-process-exec-gated.md).
   The deny-process macOS fixture therefore probes fork AND an in-place exec,
   and a separate hold-process fixture shows both still work with the
   capability held. *)

let compiler_exe =
  let exe_dir = Filename.dirname Sys.executable_name in
  Filename.concat exe_dir "../bin/main.exe"

let require_compiler () =
  if not (Sys.file_exists compiler_exe) then
    Alcotest.failf
      "compiler not found at %s — test/dune must declare bin/main.exe as a \
       dep of run_compiler" compiler_exe

let uname_s () =
  try
    let ic = Unix.open_process_in "uname -s" in
    let s = try input_line ic with End_of_file -> "" in
    ignore (Unix.close_process_in ic);
    s
  with _ -> ""

let is_linux = uname_s () = "Linux"
let is_macos = uname_s () = "Darwin"

(* Shared syscall probes for the --ffi-c shim. Each returns 0 on success or
   the failing syscall's raw errno (EPERM = 1 on both platforms). Portable
   POSIX, no #ifdef needed. *)
let shim_src =
  {|
#include <sys/socket.h>
#include <sys/wait.h>
#include <sys/types.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <signal.h>
#include <poll.h>

int64_t sbx_probe_socket(void) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return (int64_t)errno;
    close(fd);
    return 0;
}

/* macOS network probe: Seatbelt's network* deny does not gate socket()
   creation itself, only the actual network operation -- forge/lib/
   cap_sandbox.ml's own measurement notes "deny network* -> program runs,
   bind fails cleanly ENFORCEABLE". bind() to loopback:0 (OS-assigned port)
   is the minimal operation that actually exercises the gate. */
int64_t sbx_probe_bind(void) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return (int64_t)errno;
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof addr);
    addr.sin_family = AF_INET;
    addr.sin_port = 0;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    int rc = bind(fd, (struct sockaddr *)&addr, sizeof addr);
    if (rc < 0) {
        int e = errno;
        close(fd);
        return (int64_t)e;
    }
    close(fd);
    return 0;
}

/* Linux listen probes.  listen() on an UNBOUND socket auto-binds an
   ephemeral port, so a filter that denied only bind() would still let a
   program listen: both syscalls are probed. connect() to a closed loopback
   port must fail with ECONNREFUSED, not EPERM -- that is what shows the
   listen deny did not also take out the client half. */
int64_t sbx_probe_listen_unbound(void) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return (int64_t)errno;
    int rc = listen(fd, 1);
    int e = errno;
    close(fd);
    return rc < 0 ? (int64_t)e : 0;
}

/* A blocking connect() can be interrupted by the runtime's own preemption
   signal and return EINTR (seen on a macOS CI runner: "connect = 4"). The
   connection attempt carries on in the kernel, so an EINTR is not the verdict:
   wait for it to finish and read the real outcome from SO_ERROR. */
int64_t sbx_probe_connect_refused(void) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return (int64_t)errno;
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof addr);
    addr.sin_family = AF_INET;
    addr.sin_port = htons(1);
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    int rc = connect(fd, (struct sockaddr *)&addr, sizeof addr);
    int e = rc < 0 ? errno : 0;
    if (rc < 0 && e == EINTR) {
        struct pollfd p = { fd, POLLOUT, 0 };
        int n;
        do { n = poll(&p, 1, 5000); } while (n < 0 && errno == EINTR);
        int soerr = 0;
        socklen_t len = sizeof soerr;
        if (n > 0 && getsockopt(fd, SOL_SOCKET, SO_ERROR, &soerr, &len) == 0)
            e = soerr;
    }
    close(fd);
    return (int64_t)e;
}

/* Linux process probe: fork (never gated on Linux -- the scheduler needs
   threads), then execve in the child. The seccomp filter is inherited
   across both fork and execve, so if IO.Process is withheld the child's
   execve itself fails; it _exit()s with a sentinel derived from errno that
   the parent decodes back. If execve succeeds the child becomes /bin/true
   and exits 0. */
int64_t sbx_probe_execve(void) {
    pid_t pid = fork();
    if (pid < 0) return -1;
    if (pid == 0) {
        char *argv[] = { (char *)"/bin/true", NULL };
        char *envp[] = { NULL };
        execve("/bin/true", argv, envp);
        _exit(100 + (errno & 0x7f));
    }
    int status = 0;
    waitpid(pid, &status, 0);
    if (WIFEXITED(status)) {
        int code = WEXITSTATUS(status);
        if (code >= 100) return (int64_t)(code - 100);
        return 0;
    }
    return -1;
}

/* macOS process probe: fork alone is what's gated there, so no exec needed
   to observe the denial. */
int64_t sbx_probe_fork(void) {
    pid_t pid = fork();
    if (pid < 0) return (int64_t)errno;
    if (pid == 0) _exit(0);
    int status = 0;
    waitpid(pid, &status, 0);
    return 0;
}

int64_t sbx_probe_write_open(void) {
    char path[64];
    snprintf(path, sizeof path, "/tmp/march_sbx_probe_%d", (int)getpid());
    int fd = open(path, O_WRONLY | O_CREAT, 0644);
    if (fd < 0) return (int64_t)errno;
    close(fd);
    unlink(path);
    return 0;
}

/* macOS in-place exec probe: process-exec is gated by IO.Process there (with
   process-fork), so this returns EPERM when the capability is withheld and
   never returns when it is held. execve()s the
   CURRENT process (no fork) into /bin/echo, which prints "exec=0" to the
   same stdout the caller was already writing to -- never returns on
   success, so callers must treat it as the last statement in main().

   The caller is a March program running under the runtime's green-thread
   scheduler, which runs a background preemption thread that periodically
   pthread_kill()s SIGUSR1 at worker threads (runtime/march_scheduler.c).
   execve() resets the SIGUSR1 handler to default (terminate) but the signal
   MASK survives exec, so a SIGUSR1 already in flight at the moment of exec
   was observed to kill the freshly-exec'd /bin/echo before it could print
   anything. Blocking SIGUSR1 immediately before the call closes the race:
   the signal mask carries into the new image, so it simply stays pending
   and un-delivered in a process that never unblocks or waits for it. */
int64_t sbx_probe_exec_inplace(void) {
    sigset_t set;
    sigemptyset(&set);
    sigaddset(&set, SIGUSR1);
    sigprocmask(SIG_BLOCK, &set, NULL);
    char *argv[] = { (char *)"/bin/echo", (char *)"exec=0", NULL };
    char *envp[] = { NULL };
    execve("/bin/echo", argv, envp);
    printf("exec=%d\n", errno);
    return (int64_t)errno;
}
|}

(* Compiles [src] (a March fixture) with the shared shim under --cap-sandbox,
   runs the resulting binary, and returns its stdout. Fails loudly (not
   skip) on a nonzero compile exit or a nonzero run exit -- a crashing or
   killed process means the filter didn't return EPERM the way it's supposed
   to, which is itself a real finding, not a thing to silently swallow. *)
let compile_and_run ?(shim = shim_src) (src : string) : string =
  require_compiler ();
  let march_src = Filename.temp_file "sbx_runtime" ".march" in
  let oc = open_out march_src in
  output_string oc src;
  close_out oc;
  let shim_c = Filename.temp_file "sbx_runtime_shim" ".c" in
  let oc = open_out shim_c in
  output_string oc shim;
  close_out oc;
  let bin = Filename.temp_file "sbx_runtime" ".bin" in
  let log = Filename.temp_file "sbx_runtime" ".log" in
  let compile_rc =
    Sys.command
      (Printf.sprintf "%s --cap-sandbox --compile --ffi-c %s -o %s %s > %s 2>&1"
         (Filename.quote compiler_exe) (Filename.quote shim_c)
         (Filename.quote bin) (Filename.quote march_src) (Filename.quote log))
  in
  if compile_rc <> 0 then begin
    let ic = open_in log in
    let out = really_input_string ic (in_channel_length ic) in
    close_in ic;
    Alcotest.failf "--cap-sandbox compile failed (%d):\n%s" compile_rc out
  end;
  let run_out = Filename.temp_file "sbx_runtime_out" ".txt" in
  let run_rc =
    Sys.command (Printf.sprintf "%s > %s 2>&1" (Filename.quote bin) (Filename.quote run_out))
  in
  let ic = open_in run_out in
  let out = really_input_string ic (in_channel_length ic) in
  close_in ic;
  List.iter (fun f -> try Sys.remove f with Sys_error _ -> ())
    [ march_src; shim_c; bin; log; run_out ];
  if run_rc <> 0 then
    Alcotest.failf "compiled binary exited %d (expected 0 -- a denied \
                     syscall should return EPERM, not crash the process):\n%s"
      run_rc out;
  out

(* Extracts the integer value of a "key=N" line from compile_and_run's
   output. *)
let field (name : string) (output : string) : int =
  let lines = String.split_on_char '\n' output in
  let prefix = name ^ "=" in
  let plen = String.length prefix in
  match
    List.find_opt
      (fun l -> String.length l > plen && String.sub l 0 plen = prefix)
      lines
  with
  | None -> Alcotest.failf "no %S line in output:\n%s" prefix output
  | Some line ->
    let v = String.sub line plen (String.length line - plen) in
    (try int_of_string (String.trim v)
     with _ -> Alcotest.failf "unparseable %S line: %S" prefix line)

let check_field (name : string) (expected : int) (output : string) : unit =
  Alcotest.(check int)
    (Printf.sprintf "%s = %d" name expected)
    expected (field name output)

(* ── Linux: IO.Process gates execve/execveat specifically ───────────────

   The SBPL/-D derivation (bin/main.ml's cap_sandbox_define) is driven by
   ACTUAL CAPABILITY USAGE in the module's own code (own_caps_of_this_module,
   bin/main.ml ~996), not by `needs` declarations alone. Confirmed empirically
   two ways: an extern block's declared Cap(X) does NOT count as a use for
   this purpose (only for the separate "extern blocks require the declared
   capability to be in needs" check) -- tagging every probe's extern block
   uniformly Cap(IO.Foreign) meant none of the two classes meant to stay
   held/allowed ever registered as "used", so they were wrongly denied too.
   What DOES register: a direct call to a real capability-tagged builtin. So
   each fixture below makes one throwaway "anchor" call per class meant to
   stay held -- tcp_connect to loopback for Network, process_pid for Process,
   file_write to a scratch path for FileWrite -- purely to get that class
   into the module's own-capability set; the result is discarded, and the
   call is otherwise inert (loopback-only, no external network; a real but
   harmless local file write; a read-only pid query). The class actually
   under test in each fixture is never anchored -- that's the whole point. *)

let linux_deny_net_src =
  {|
mod SbxDenyNet do
  needs IO.Console
  needs IO.Foreign
  needs IO.Process
  needs IO.FileWrite

  extern "raw" : Cap(IO.Foreign) do
    fn probe_socket() : Int = "sbx_probe_socket"
    fn probe_execve() : Int = "sbx_probe_execve"
    fn probe_write_open() : Int = "sbx_probe_write_open"
  end

  fn main(_c : Cap(IO.Console), _f : Cap(IO.Foreign), _p : Cap(IO.Process), _w : Cap(IO.FileWrite)) : Unit do
    let _anchor_proc = process_pid()
    let _anchor_write = file_write("/tmp/march_sbx_anchor_write", "")
    println("socket=" ++ int_to_string(probe_socket()))
    println("execve=" ++ int_to_string(probe_execve()))
    println("write=" ++ int_to_string(probe_write_open()))
  end
end
|}

let linux_deny_exec_src =
  {|
mod SbxDenyExec do
  needs IO.Console
  needs IO.Foreign
  needs IO.Network
  needs IO.FileWrite

  extern "raw" : Cap(IO.Foreign) do
    fn probe_socket() : Int = "sbx_probe_socket"
    fn probe_execve() : Int = "sbx_probe_execve"
    fn probe_write_open() : Int = "sbx_probe_write_open"
  end

  fn main(_c : Cap(IO.Console), _f : Cap(IO.Foreign), _n : Cap(IO.NetConnect), _w : Cap(IO.FileWrite)) : Unit do
    let _anchor_net = tcp_connect("127.0.0.1", 1)
    let _anchor_write = file_write("/tmp/march_sbx_anchor_write", "")
    println("socket=" ++ int_to_string(probe_socket()))
    println("execve=" ++ int_to_string(probe_execve()))
    println("write=" ++ int_to_string(probe_write_open()))
  end
end
|}

let linux_deny_write_src =
  {|
mod SbxDenyWrite do
  needs IO.Console
  needs IO.Foreign
  needs IO.Network
  needs IO.Process

  extern "raw" : Cap(IO.Foreign) do
    fn probe_socket() : Int = "sbx_probe_socket"
    fn probe_execve() : Int = "sbx_probe_execve"
    fn probe_write_open() : Int = "sbx_probe_write_open"
  end

  fn main(_c : Cap(IO.Console), _f : Cap(IO.Foreign), _n : Cap(IO.NetConnect), _p : Cap(IO.Process)) : Unit do
    let _anchor_net = tcp_connect("127.0.0.1", 1)
    let _anchor_proc = process_pid()
    println("socket=" ++ int_to_string(probe_socket()))
    println("execve=" ++ int_to_string(probe_execve()))
    println("write=" ++ int_to_string(probe_write_open()))
  end
end
|}

(* ── Linux: IO.NetListen gates bind/listen separately from IO.Network ──
   Holding only IO.NetConnect makes `holds "IO.Network"` true (holds is
   bidirectional), so socket() stays allowed for connect(); LISTEN is the
   narrower deny. Anchors: tcp_connect for NetConnect, tcp_listen for
   NetListen, as with the other classes above. *)
let linux_deny_listen_src =
  {|
mod SbxDenyListen do
  needs IO.Console
  needs IO.Foreign
  needs IO.NetConnect

  extern "raw" : Cap(IO.Foreign) do
    fn probe_socket() : Int = "sbx_probe_socket"
    fn probe_bind() : Int = "sbx_probe_bind"
    fn probe_listen() : Int = "sbx_probe_listen_unbound"
    fn probe_connect() : Int = "sbx_probe_connect_refused"
  end

  fn main(_c : Cap(IO.Console), _f : Cap(IO.Foreign), _n : Cap(IO.NetConnect)) : Unit do
    let _anchor_net = tcp_connect("127.0.0.1", 1)
    println("socket=" ++ int_to_string(probe_socket()))
    println("bind=" ++ int_to_string(probe_bind()))
    println("listen=" ++ int_to_string(probe_listen()))
    println("connect=" ++ int_to_string(probe_connect()))
  end
end
|}

let linux_hold_listen_src =
  {|
mod SbxHoldListen do
  needs IO.Console
  needs IO.Foreign
  needs IO.NetListen

  extern "raw" : Cap(IO.Foreign) do
    fn probe_bind() : Int = "sbx_probe_bind"
    fn probe_listen() : Int = "sbx_probe_listen_unbound"
  end

  fn main(_c : Cap(IO.Console), _f : Cap(IO.Foreign), _l : Cap(IO.NetListen)) : Unit do
    let _anchor_listen = tcp_listen(0)
    println("bind=" ++ int_to_string(probe_bind()))
    println("listen=" ++ int_to_string(probe_listen()))
  end
end
|}

let test_linux_deny_listen () =
  if not is_linux then Alcotest.skip ()
  else begin
    let out = compile_and_run linux_deny_listen_src in
    check_field "socket" 0 out;
    check_field "bind" 1 out;
    check_field "listen" 1 out;
    (* ECONNREFUSED is 111 on both x86_64 and aarch64 Linux. *)
    check_field "connect" 111 out
  end

let test_linux_hold_listen () =
  if not is_linux then Alcotest.skip ()
  else begin
    let out = compile_and_run linux_hold_listen_src in
    check_field "bind" 0 out;
    check_field "listen" 0 out
  end

let test_linux_deny_net () =
  if not is_linux then Alcotest.skip ()
  else begin
    let out = compile_and_run linux_deny_net_src in
    check_field "socket" 1 out;
    check_field "execve" 0 out;
    check_field "write" 0 out
  end

let test_linux_deny_exec () =
  if not is_linux then Alcotest.skip ()
  else begin
    let out = compile_and_run linux_deny_exec_src in
    check_field "socket" 0 out;
    check_field "execve" 1 out;
    check_field "write" 0 out
  end

let test_linux_deny_write () =
  if not is_linux then Alcotest.skip ()
  else begin
    let out = compile_and_run linux_deny_write_src in
    check_field "socket" 0 out;
    check_field "execve" 0 out;
    check_field "write" 1 out
  end

(* ── macOS: IO.Process gates fork AND exec (see the module doc comment).
   The "socket" probe is bound to sbx_probe_bind, not
   sbx_probe_socket -- Seatbelt's network* deny does not gate socket()
   creation, only the actual network operation (bind/connect); confirmed by
   direct inspection of the embedded profile (`strings <bin> | grep
   '(version 1)'`) after a raw socket()-only probe returned 0 in a fixture
   that withheld IO.Network. forge/lib/cap_sandbox.ml's own measurement notes
   the same thing ("deny network* -> program runs, bind fails cleanly"). The
   printed label stays "socket=" for output-format consistency with the Linux
   fixtures; only the underlying C symbol differs. That applies to the
   deny-net fixture only: the deny-process and deny-write fixtures hold
   IO.NetConnect, which grants network-outbound and NOT network-bind, so they
   probe a refused loopback connect ("connect=", ECONNREFUSED when allowed)
   instead of bind. Same anchor-call pattern,
   and same explicit-`main`-grant requirement, as the Linux fixtures above,
   and for the same reasons. ─────────────────────────────────────────────── *)

(* ECONNREFUSED is 61 on macOS (111 on Linux). *)
let econnrefused_macos = 61

let macos_deny_net_src =
  {|
mod SbxDenyNetMac do
  needs IO.Console
  needs IO.Foreign
  needs IO.Process
  needs IO.FileWrite

  extern "raw" : Cap(IO.Foreign) do
    fn probe_socket() : Int = "sbx_probe_bind"
    fn probe_fork() : Int = "sbx_probe_fork"
    fn probe_write_open() : Int = "sbx_probe_write_open"
  end

  fn main(_c : Cap(IO.Console), _f : Cap(IO.Foreign), _p : Cap(IO.Process), _w : Cap(IO.FileWrite)) : Unit do
    let _anchor_proc = process_pid()
    let _anchor_write = file_write("/tmp/march_sbx_anchor_write", "")
    println("socket=" ++ int_to_string(probe_socket()))
    println("fork=" ++ int_to_string(probe_fork()))
    println("write=" ++ int_to_string(probe_write_open()))
  end
end
|}

let macos_deny_process_src =
  {|
mod SbxDenyProcessMac do
  needs IO.Console
  needs IO.Foreign
  needs IO.Network
  needs IO.FileWrite

  extern "raw" : Cap(IO.Foreign) do
    fn probe_connect() : Int = "sbx_probe_connect_refused"
    fn probe_fork() : Int = "sbx_probe_fork"
    fn probe_write_open() : Int = "sbx_probe_write_open"
    fn probe_exec_inplace() : Int = "sbx_probe_exec_inplace"
  end

  fn main(_c : Cap(IO.Console), _f : Cap(IO.Foreign), _n : Cap(IO.NetConnect), _w : Cap(IO.FileWrite)) : Unit do
    let _anchor_net = tcp_connect("127.0.0.1", 1)
    let _anchor_write = file_write("/tmp/march_sbx_anchor_write", "")
    println("connect=" ++ int_to_string(probe_connect()))
    println("fork=" ++ int_to_string(probe_fork()))
    println("write=" ++ int_to_string(probe_write_open()))
    println("exec=" ++ int_to_string(probe_exec_inplace()))
  end
end
|}

(* Held IO.Process: fork and an in-place exec both succeed. The exec probe
   never returns on success; /bin/echo prints "exec=0" as the last line. *)
let macos_hold_process_src =
  {|
mod SbxHoldProcessMac do
  needs IO.Console
  needs IO.Foreign
  needs IO.Process

  extern "raw" : Cap(IO.Foreign) do
    fn probe_fork() : Int = "sbx_probe_fork"
    fn probe_exec_inplace() : Int = "sbx_probe_exec_inplace"
  end

  fn main(_c : Cap(IO.Console), _f : Cap(IO.Foreign), _p : Cap(IO.Process)) : Unit do
    let _anchor_proc = process_pid()
    println("fork=" ++ int_to_string(probe_fork()))
    println("exec=" ++ int_to_string(probe_exec_inplace()))
  end
end
|}

let macos_deny_write_src =
  {|
mod SbxDenyWriteMac do
  needs IO.Console
  needs IO.Foreign
  needs IO.Network
  needs IO.Process

  extern "raw" : Cap(IO.Foreign) do
    fn probe_connect() : Int = "sbx_probe_connect_refused"
    fn probe_fork() : Int = "sbx_probe_fork"
    fn probe_write_open() : Int = "sbx_probe_write_open"
  end

  fn main(_c : Cap(IO.Console), _f : Cap(IO.Foreign), _n : Cap(IO.NetConnect), _p : Cap(IO.Process)) : Unit do
    let _anchor_net = tcp_connect("127.0.0.1", 1)
    let _anchor_proc = process_pid()
    println("connect=" ++ int_to_string(probe_connect()))
    println("fork=" ++ int_to_string(probe_fork()))
    println("write=" ++ int_to_string(probe_write_open()))
  end
end
|}

let test_macos_deny_net () =
  if not is_macos then Alcotest.skip ()
  else begin
    let out = compile_and_run macos_deny_net_src in
    check_field "socket" 1 out;
    check_field "fork" 0 out;
    check_field "write" 0 out
  end

let test_macos_deny_process () =
  if not is_macos then Alcotest.skip ()
  else begin
    let out = compile_and_run macos_deny_process_src in
    check_field "connect" econnrefused_macos out;
    check_field "fork" 1 out;
    check_field "write" 0 out;
    check_field "exec" 1 out
  end

let test_macos_hold_process () =
  if not is_macos then Alcotest.skip ()
  else begin
    let out = compile_and_run macos_hold_process_src in
    check_field "fork" 0 out;
    check_field "exec" 0 out
  end

let test_macos_deny_write () =
  if not is_macos then Alcotest.skip ()
  else begin
    let out = compile_and_run macos_deny_write_src in
    check_field "connect" econnrefused_macos out;
    check_field "fork" 0 out;
    check_field "write" 1 out
  end

(* ── macOS: IO.NetListen is split from IO.NetConnect ──────────────────────
   The embedded profile grants network-outbound for IO.NetConnect and
   network-bind + network-inbound for IO.NetListen, instead of network* for
   either (which let a connect-only program bind).  The deny-listen fixture
   also does a REAL client round trip through March's own tcp_connect with a
   hostname ("localhost", so getaddrinfo runs) to a listener this test opens
   outside the sandbox: that is the "a connect-only program still works"
   half, not just a probe returning ECONNREFUSED.  The listener is never
   accept()ed; connect and the send complete against the backlog. *)


let macos_deny_listen_src port =
  Printf.sprintf
    {|
mod SbxDenyListenMac do
  needs IO.Console
  needs IO.Foreign
  needs IO.NetConnect

  extern "raw" : Cap(IO.Foreign) do
    fn probe_bind() : Int = "sbx_probe_bind"
    fn probe_listen() : Int = "sbx_probe_listen_unbound"
    fn probe_connect() : Int = "sbx_probe_connect_refused"
  end

  fn main(_c : Cap(IO.Console), _f : Cap(IO.Foreign), _n : Cap(IO.NetConnect)) : Unit do
    match tcp_connect("localhost", %d) do
    Ok(fd) ->
      println("roundtrip_connect=0")
      match tcp_send_all(fd, "ping") do
      Ok(_) -> println("roundtrip_send=0")
      Err(_) -> println("roundtrip_send=1")
      end
      tcp_close(fd)
    Err(m) -> println("roundtrip_connect=1 " ++ m)
    end
    println("bind=" ++ int_to_string(probe_bind()))
    println("listen=" ++ int_to_string(probe_listen()))
    println("connect=" ++ int_to_string(probe_connect()))
  end
end
|}
    port

let macos_hold_listen_src =
  {|
mod SbxHoldListenMac do
  needs IO.Console
  needs IO.Foreign
  needs IO.NetListen

  extern "raw" : Cap(IO.Foreign) do
    fn probe_bind() : Int = "sbx_probe_bind"
    fn probe_listen() : Int = "sbx_probe_listen_unbound"
    fn probe_connect() : Int = "sbx_probe_connect_refused"
  end

  fn main(_c : Cap(IO.Console), _f : Cap(IO.Foreign), _l : Cap(IO.NetListen)) : Unit do
    let _anchor_listen = tcp_listen(0)
    println("bind=" ++ int_to_string(probe_bind()))
    println("listen=" ++ int_to_string(probe_listen()))
    println("connect=" ++ int_to_string(probe_connect()))
  end
end
|}

let with_loopback_listener (f : int -> 'a) : 'a =
  let sock = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Fun.protect ~finally:(fun () -> try Unix.close sock with _ -> ()) (fun () ->
      Unix.setsockopt sock Unix.SO_REUSEADDR true;
      Unix.bind sock (Unix.ADDR_INET (Unix.inet_addr_loopback, 0));
      Unix.listen sock 8;
      match Unix.getsockname sock with
      | Unix.ADDR_INET (_, port) -> f port
      | _ -> Alcotest.fail "listener has no inet address")

let test_macos_deny_listen () =
  if not is_macos then Alcotest.skip ()
  else begin
    let out = with_loopback_listener (fun port ->
        compile_and_run (macos_deny_listen_src port)) in
    check_field "roundtrip_connect" 0 out;
    check_field "roundtrip_send" 0 out;
    check_field "bind" 1 out;
    check_field "listen" 1 out;
    check_field "connect" econnrefused_macos out
  end

let test_macos_hold_listen () =
  if not is_macos then Alcotest.skip ()
  else begin
    let out = compile_and_run macos_hold_listen_src in
    check_field "bind" 0 out;
    check_field "listen" 0 out;
    (* NetListen alone is not NetConnect: outbound is refused. *)
    check_field "connect" 1 out
  end

(* ── macOS: scoped IO.FileWrite resolves symlinks on the deployment machine ──
   Scope normalization is lexical (the build machine's filesystem is not the
   deployment machine's), but Seatbelt matches a subpath AFTER resolving
   symlinks. /tmp is a symlink to /private/tmp on macOS, so a scope baked
   into the profile as "/tmp/<x>" matched nothing and denied every write,
   including the in-scope ones. The runtime now realpath()s each scope in
   march_sandbox_install (longest existing prefix, remainder re-appended).
   Each fixture checks the in-scope write SUCCEEDS (the bug) and a write
   outside the scope, through the raw-C probe, is still refused (EPERM = 1)
   -- the latter is what keeps "resolve the scope" from quietly becoming
   "allow everything". *)

let fresh_tmp_dir (tag : string) : string =
  (* Deliberately spelled through /tmp, the symlinked path, not /private/tmp. *)
  let d =
    Printf.sprintf "/tmp/march_sbx_%s_%d_%d" tag (Unix.getpid ())
      (Random.State.bits (Random.State.make_self_init ()))
  in
  Unix.mkdir d 0o755;
  d

let rm_rf (d : string) : unit =
  ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote d)))

let result_line name expr =
  Printf.sprintf
    {|    match %s do
      Ok(_) -> println("%s=0")
      Err(_) -> println("%s=1")
    end|}
    expr name name

let scoped_fixture ~modname ~scope ~(body : string list) =
  Printf.sprintf
    {|
mod %s do
  needs IO.Console
  needs IO.Foreign
  needs IO.FileWrite("%s")

  extern "raw" : Cap(IO.Foreign) do
    fn probe_write_open() : Int = "sbx_probe_write_open"
  end

  fn main(_c : Cap(IO.Console), _f : Cap(IO.Foreign), _w : Cap(IO.FileWrite)) : Unit do
%s
    println("outscope=" ++ int_to_string(probe_write_open()))
  end
end
|}
    modname scope (String.concat "\n" body)

let test_macos_scope_under_symlinked_tmp () =
  if not is_macos then Alcotest.skip ()
  else begin
    let d = fresh_tmp_dir "scope" in
    Fun.protect ~finally:(fun () -> rm_rf d) (fun () ->
        let src =
          scoped_fixture ~modname:"SbxScopeTmpMac" ~scope:d
            ~body:
              [ result_line "inscope"
                  (Printf.sprintf "file_write(\"%s/in.txt\", \"x\")" d);
                (* A subdirectory that does not exist at startup. *)
                result_line "mkdir" (Printf.sprintf "dir_mkdir(\"%s/newdir\")" d);
                result_line "newsub"
                  (Printf.sprintf "file_write(\"%s/newdir/f.txt\", \"y\")" d) ]
        in
        let out = compile_and_run src in
        check_field "inscope" 0 out;
        check_field "mkdir" 0 out;
        check_field "newsub" 0 out;
        check_field "outscope" 1 out;
        Alcotest.(check bool) "in-scope file really written" true
          (Sys.file_exists (d ^ "/newdir/f.txt")))
  end

let test_macos_scope_not_yet_existing () =
  if not is_macos then Alcotest.skip ()
  else begin
    let d = fresh_tmp_dir "scope_new" in
    Fun.protect ~finally:(fun () -> rm_rf d) (fun () ->
        (* The scope itself does not exist when the sandbox is installed, so
           realpath fails on it: resolution must fall back to the longest
           existing prefix (d, itself behind /tmp) and re-append the rest. *)
        let scope = d ^ "/notyet" in
        let src =
          scoped_fixture ~modname:"SbxScopeNewMac" ~scope
            ~body:
              [ result_line "mkdir" (Printf.sprintf "dir_mkdir(\"%s\")" scope);
                result_line "inscope"
                  (Printf.sprintf "file_write(\"%s/f.txt\", \"x\")" scope) ]
        in
        let out = compile_and_run src in
        check_field "mkdir" 0 out;
        check_field "inscope" 0 out;
        check_field "outscope" 1 out)
  end

let test_macos_scope_is_symlink () =
  if not is_macos then Alcotest.skip ()
  else begin
    let d = fresh_tmp_dir "scope_link" in
    Fun.protect ~finally:(fun () -> rm_rf d) (fun () ->
        Unix.mkdir (d ^ "/real") 0o755;
        Unix.symlink "real" (d ^ "/link");
        let src =
          scoped_fixture ~modname:"SbxScopeLinkMac" ~scope:(d ^ "/link")
            ~body:
              [ result_line "inscope"
                  (Printf.sprintf "file_write(\"%s/link/f.txt\", \"x\")" d) ]
        in
        let out = compile_and_run src in
        check_field "inscope" 0 out;
        check_field "outscope" 1 out;
        Alcotest.(check bool) "write landed in the link's target" true
          (Sys.file_exists (d ^ "/real/f.txt")))
  end

(* ── A thread started BEFORE the install is filtered after it ──────────
   march_sandbox_install runs in spawn_main_impl, but threads can already
   exist by then: @main starts the hot-reload server first
   (llvm_toplevel.ml's hr_setup), and a linked C library's constructor can
   start its own.  On Linux the filter was installed with
   prctl(PR_SET_SECCOMP), which covers only the calling thread and its later
   children, so such a thread ran unfiltered; it is now installed with
   SECCOMP_FILTER_FLAG_TSYNC.  On macOS sandbox_init has always been
   process-wide; its case pins that the same probe is denied there too.

   The shim's constructor runs before main, so before the install: it starts
   a thread that blocks on a pipe.  After the install, March releases it and
   it runs sbx_probe_bind (socket() then bind() to loopback).  EPERM (1) is
   the filtered answer on both backends: Linux denies socket() when IO.Network
   is withheld, Seatbelt denies the bind().
   specs/progress/2026-09-30-cap-sandbox-linux-reload-thread-unfiltered.md *)
let early_thread_shim_src =
  shim_src
  ^ {|
#include <pthread.h>

static int sbx_early_pipe[2] = { -1, -1 };
static pthread_t sbx_early_tid;
static int64_t sbx_early_started = 0;
static int64_t sbx_early_result = -1;

static void *sbx_early_thread(void *arg) {
    (void)arg;
    char c;
    ssize_t n;
    do { n = read(sbx_early_pipe[0], &c, 1); } while (n < 0 && errno == EINTR);
    sbx_early_result = sbx_probe_bind();
    return NULL;
}

__attribute__((constructor)) static void sbx_start_early_thread(void) {
    if (pipe(sbx_early_pipe) != 0) return;
    if (pthread_create(&sbx_early_tid, NULL, sbx_early_thread, NULL) == 0)
        sbx_early_started = 1;
}

/* 1 iff the thread was created by the constructor, i.e. before main and so
   before march_sandbox_install. */
int64_t sbx_early_thread_started(void) { return sbx_early_started; }

/* Release the pre-existing thread, wait for it, return its probe's errno. */
int64_t sbx_early_thread_probe(void) {
    if (!sbx_early_started) return -1;
    char c = 'x';
    ssize_t n;
    do { n = write(sbx_early_pipe[1], &c, 1); } while (n < 0 && errno == EINTR);
    pthread_join(sbx_early_tid, NULL);
    return sbx_early_result;
}
|}

let early_thread_src =
  {|
mod SbxEarlyThread do
  needs IO.Console
  needs IO.Foreign

  extern "raw" : Cap(IO.Foreign) do
    fn early_started() : Int = "sbx_early_thread_started"
    fn early_probe() : Int = "sbx_early_thread_probe"
    fn probe_bind() : Int = "sbx_probe_bind"
  end

  fn main(_c : Cap(IO.Console), _f : Cap(IO.Foreign)) : Unit do
    println("started=" ++ int_to_string(early_started()))
    println("main=" ++ int_to_string(probe_bind()))
    println("early=" ++ int_to_string(early_probe()))
  end
end
|}

let test_early_thread_filtered () =
  if not (is_linux || is_macos) then Alcotest.skip ()
  else begin
    let out = compile_and_run ~shim:early_thread_shim_src early_thread_src in
    check_field "started" 1 out;
    (* The calling thread is filtered (unchanged behaviour)... *)
    check_field "main" 1 out;
    (* ...and so is the thread that already existed at install time. *)
    check_field "early" 1 out
  end

let tests : unit Alcotest.test_case list =
  [ Alcotest.test_case "linux: NET withheld denies socket, EXEC/WRITE still allowed" `Slow test_linux_deny_net;
    Alcotest.test_case "linux: PROCESS withheld denies execve, NET/WRITE still allowed" `Slow test_linux_deny_exec;
    Alcotest.test_case "linux: FILEWRITE withheld denies write-open, NET/EXEC still allowed" `Slow test_linux_deny_write;
    Alcotest.test_case "linux: NETLISTEN withheld (NetConnect held) denies bind/listen, connect still works" `Slow test_linux_deny_listen;
    Alcotest.test_case "linux: NETLISTEN held allows bind/listen" `Slow test_linux_hold_listen;
    Alcotest.test_case "linux+macos: a thread started before the install is filtered after it" `Slow test_early_thread_filtered;
    Alcotest.test_case "macos: NET withheld denies socket, FORK/WRITE still allowed" `Slow test_macos_deny_net;
    Alcotest.test_case "macos: PROCESS withheld denies fork AND exec, NET/WRITE still allowed" `Slow test_macos_deny_process;
    Alcotest.test_case "macos: PROCESS held allows fork and exec" `Slow test_macos_hold_process;
    Alcotest.test_case "macos: FILEWRITE withheld denies write-open, NET/FORK still allowed" `Slow test_macos_deny_write;
    Alcotest.test_case "macos: NETLISTEN withheld (NetConnect held) denies bind/listen, a real connect still works" `Slow test_macos_deny_listen;
    Alcotest.test_case "macos: NETLISTEN held allows bind/listen, denies outbound" `Slow test_macos_hold_listen;
    Alcotest.test_case "macos: FILEWRITE scope under symlinked /tmp allows in-scope writes, denies out-of-scope" `Slow test_macos_scope_under_symlinked_tmp;
    Alcotest.test_case "macos: FILEWRITE scope that does not exist yet resolves via its existing prefix" `Slow test_macos_scope_not_yet_existing;
    Alcotest.test_case "macos: FILEWRITE scope that is itself a symlink resolves to its target" `Slow test_macos_scope_is_symlink;
  ]
