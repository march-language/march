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

   macOS gates a DIFFERENT operation for the "process" class than Linux:
   (allow process-exec) is unconditional baseline on macOS (bin/main.ml:3527)
   -- only (allow process-fork) is conditioned on IO.Process. Linux is the
   reverse: execve/execveat are denied, fork/clone never are. So the macOS
   fixtures probe fork, not exec; the deny-process macOS fixture additionally
   probes the always-allowed exec as an informational last step, documenting
   the asymmetry rather than asserting a denial that doesn't exist -- see
   specs/todos/2026-08-12-cap-sandbox-macos-process-exec-not-gated.md for the
   follow-up on whether that should change. *)

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

/* macOS-only informational probe: process-exec is never gated by IO.Process
   there (only process-fork is), so this always succeeds. execve()s the
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
let compile_and_run (src : string) : string =
  require_compiler ();
  let march_src = Filename.temp_file "sbx_runtime" ".march" in
  let oc = open_out march_src in
  output_string oc src;
  close_out oc;
  let shim_c = Filename.temp_file "sbx_runtime_shim" ".c" in
  let oc = open_out shim_c in
  output_string oc shim_src;
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

(* ── macOS: IO.Process gates fork, not exec (see the asymmetry note in the
   module doc comment and specs/todos/2026-08-12-cap-sandbox-macos-process-
   exec-not-gated.md). The "socket" probe is bound to sbx_probe_bind, not
   sbx_probe_socket -- Seatbelt's network* deny does not gate socket()
   creation, only the actual network operation (bind/connect); confirmed by
   direct inspection of the embedded profile (`strings <bin> | grep
   '(version 1)'`) after a raw socket()-only probe returned 0 in a fixture
   that withheld IO.Network. forge/lib/cap_sandbox.ml's own measurement notes
   the same thing ("deny network* -> program runs, bind fails cleanly"). The
   printed label stays "socket=" for output-format consistency with the Linux
   fixtures; only the underlying C symbol differs. Same anchor-call pattern,
   and same explicit-`main`-grant requirement, as the Linux fixtures above,
   and for the same reasons. ─────────────────────────────────────────────── *)

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
    fn probe_socket() : Int = "sbx_probe_bind"
    fn probe_fork() : Int = "sbx_probe_fork"
    fn probe_write_open() : Int = "sbx_probe_write_open"
    fn probe_exec_inplace() : Int = "sbx_probe_exec_inplace"
  end

  fn main(_c : Cap(IO.Console), _f : Cap(IO.Foreign), _n : Cap(IO.NetConnect), _w : Cap(IO.FileWrite)) : Unit do
    let _anchor_net = tcp_connect("127.0.0.1", 1)
    let _anchor_write = file_write("/tmp/march_sbx_anchor_write", "")
    println("socket=" ++ int_to_string(probe_socket()))
    println("fork=" ++ int_to_string(probe_fork()))
    println("write=" ++ int_to_string(probe_write_open()))
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
    fn probe_socket() : Int = "sbx_probe_bind"
    fn probe_fork() : Int = "sbx_probe_fork"
    fn probe_write_open() : Int = "sbx_probe_write_open"
  end

  fn main(_c : Cap(IO.Console), _f : Cap(IO.Foreign), _n : Cap(IO.NetConnect), _p : Cap(IO.Process)) : Unit do
    let _anchor_net = tcp_connect("127.0.0.1", 1)
    let _anchor_proc = process_pid()
    println("socket=" ++ int_to_string(probe_socket()))
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
    check_field "socket" 0 out;
    check_field "fork" 1 out;
    check_field "write" 0 out;
    check_field "exec" 0 out
  end

let test_macos_deny_write () =
  if not is_macos then Alcotest.skip ()
  else begin
    let out = compile_and_run macos_deny_write_src in
    check_field "socket" 0 out;
    check_field "fork" 0 out;
    check_field "write" 1 out
  end

let tests : unit Alcotest.test_case list =
  [ Alcotest.test_case "linux: NET withheld denies socket, EXEC/WRITE still allowed" `Slow test_linux_deny_net;
    Alcotest.test_case "linux: PROCESS withheld denies execve, NET/WRITE still allowed" `Slow test_linux_deny_exec;
    Alcotest.test_case "linux: FILEWRITE withheld denies write-open, NET/EXEC still allowed" `Slow test_linux_deny_write;
    Alcotest.test_case "macos: NET withheld denies socket, FORK/WRITE still allowed" `Slow test_macos_deny_net;
    Alcotest.test_case "macos: PROCESS withheld denies fork, NET/WRITE still allowed, EXEC still allowed (documented asymmetry)" `Slow test_macos_deny_process;
    Alcotest.test_case "macos: FILEWRITE withheld denies write-open, NET/FORK still allowed" `Slow test_macos_deny_write;
  ]
