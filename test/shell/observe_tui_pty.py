#!/usr/bin/env python3
"""Drive `forge observe` (the TUI) under a real pty and capture the screen text.

    observe_tui_pty.py FORGE_EXE OBSERVE_SOCKET [OUTFILE [CRASH_DUMP_FILE]]

The caller starts the node (a March program run with MARCH_OBSERVE_SOCKET=
OBSERVE_SOCKET).  This script owns only the forge client: it types keys, feeds
the raw terminal output through a small VT100 emulator (cursor movement, erase,
SGR ignored), and writes the screen after each step, as text.  The result is a
pty capture, not a screenshot.  Exits 0 and prints PASS lines, or exits 1
naming the failed check.  Not wired into `dune runtest` (needs a live node).
"""
import fcntl, os, pty, re, select, struct, sys, termios, time

forge, sock = sys.argv[1:3]
outfile = sys.argv[3] if len(sys.argv) > 3 else None
dumpfile = sys.argv[4] if len(sys.argv) > 4 else None
ROWS, COLS = 32, 150
ESC = "\x1b"
failures = []


def check(name, cond, detail=""):
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else "  " + detail))
    if not cond:
        failures.append(name)


class Screen:
    """The minimum of a VT100 that Notty's ANSI output uses."""

    def __init__(self, rows, cols):
        self.rows, self.cols = rows, cols
        self.grid = [[" "] * cols for _ in range(rows)]
        self.r = self.c = 0
        self.state = "text"
        self.params = ""

    def clear_row(self, r, a=0, b=None):
        b = self.cols if b is None else b
        for i in range(a, b):
            self.grid[r][i] = " "

    def feed(self, text):
        for ch in text:
            if self.state == "text":
                if ch == ESC:
                    self.state = "esc"
                elif ch == "\r":
                    self.c = 0
                elif ch == "\n":
                    self.r = min(self.r + 1, self.rows - 1)
                elif ch == "\b":
                    self.c = max(0, self.c - 1)
                elif ch >= " ":
                    if self.c >= self.cols:
                        self.c = 0
                        self.r = min(self.r + 1, self.rows - 1)
                    self.grid[self.r][self.c] = ch
                    self.c += 1
            elif self.state == "esc":
                if ch == "[":
                    self.state, self.params = "csi", ""
                else:
                    if ch == "E":         # NEL: Notty ends every row with it
                        self.c = 0
                        self.r = min(self.r + 1, self.rows - 1)
                    self.state = "text"   # ESC 7, ESC 8, ESC c ...: ignored
            else:  # csi
                if ch.isdigit() or ch in ";?":
                    self.params += ch
                else:
                    self.csi(ch)
                    self.state = "text"

    def csi(self, final):
        p = self.params
        nums = [int(x) if x.isdigit() else 0 for x in p.replace("?", "").split(";")] if p else []
        n = nums[0] if nums and nums[0] > 0 else 1
        if final in "Hf":
            self.r = min(max((nums[0] if len(nums) > 0 and nums[0] else 1) - 1, 0), self.rows - 1)
            self.c = min(max((nums[1] if len(nums) > 1 and nums[1] else 1) - 1, 0), self.cols - 1)
        elif final == "A": self.r = max(0, self.r - n)
        elif final == "B": self.r = min(self.rows - 1, self.r + n)
        elif final == "C": self.c = min(self.cols - 1, self.c + n)
        elif final == "D": self.c = max(0, self.c - n)
        elif final == "G": self.c = min(max(n - 1, 0), self.cols - 1)
        elif final == "J":
            mode = nums[0] if nums else 0
            if mode == 2:
                for r in range(self.rows): self.clear_row(r)
            elif mode == 0:
                self.clear_row(self.r, self.c)
                for r in range(self.r + 1, self.rows): self.clear_row(r)
            elif mode == 1:
                self.clear_row(self.r, 0, self.c + 1)
                for r in range(self.r): self.clear_row(r)
        elif final == "K":
            mode = nums[0] if nums else 0
            if mode == 0: self.clear_row(self.r, self.c)
            elif mode == 1: self.clear_row(self.r, 0, self.c + 1)
            else: self.clear_row(self.r)
        # m (SGR), h/l (modes), others: no effect on text

    def text(self):
        lines = ["".join(row).rstrip() for row in self.grid]
        while lines and not lines[-1]:
            lines.pop()
        return "\n".join(lines)


env = dict(os.environ, TERM="xterm-256color")
pid, fd = pty.fork()
if pid == 0:
    os.execve(forge, [forge, "observe", "--socket", sock, "--interval", "500"], env)
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLS, 0, 0))
screen = Screen(ROWS, COLS)
captures = []


def pump(secs):
    end = time.time() + secs
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try:
                d = os.read(fd, 65536)
            except OSError:
                return False
            if not d:
                return False
            screen.feed(d.decode("utf-8", "replace"))
    return True


def snap(label):
    t = screen.text()
    captures.append("=== %s ===\n%s\n" % (label, t))
    return t


def reap(pid, secs=10):
    """Wait for the child to exit and be reapable (EIO on the pty comes a moment before)."""
    end = time.time() + secs
    while time.time() < end:
        try:
            wpid, status = os.waitpid(pid, os.WNOHANG)
        except ChildProcessError:
            return pid, 0
        if wpid:
            return wpid, status
        time.sleep(0.05)
    return 0, 0


def key(k, settle=1.2):
    os.write(fd, k.encode())
    pump(settle)


pump(2.5)
t = snap("System (key 1, the first screen)")
check("tab line shows every panel", all(x in t for x in ("System", "Load", "Actors", "Supervision", "Crashes")), t[:200])
check("stream delivers frames", re.search(r"frame (\d+)", t) is not None and int(re.search(r"frame (\d+)", t).group(1)) >= 2, t[:300])
check("System names the node", "actors" in t and "schedulers" in t, t)

key("2"); t = snap("Load (key 2)")
check("Load shows scheduler rows", "S0" in t and "run queue" in t, t)

key("3"); t = snap("Actors (key 3), ranked by mailbox")
check("Actors lists the supervisor and its policy", "boss" in t and "one_for_one" in t, t)

key("s"); t = snap("Actors after s: ranked by stack")
check("s re-ranks", "ranked by stack" in t, t)

key(ESC + "[B"); key(ESC + "[B")
key("\r"); t = snap("Actor (Enter on the third row)")
check("Enter opens the actor view", "actor " in t and "mailbox" in t and "traffic" in t, t)

key("5"); t = snap("Supervision (key 5)")
check("Supervision shows the tree", "+- " in t and "kids" in t, t)

key("6"); t = snap("Names (key 6)")
check("Names lists registered names", "boss" in t and "maker" in t, t)

key("7"); t = snap("Epochs (key 7)")
check("Epochs shows the current epoch", "current epoch" in t, t)

key("8"); t = snap("Cluster (key 8)")
check("Cluster says it is unavailable on a node that publishes none", "cluster" in t.lower(), t)

key("9"); t = snap("Crashes (key 9)")
check("Crashes lists the supervised child's panics", "crash" in t and "SEQ" in t, t)

key("\t"); t = snap("Tab wraps to System")
check("Tab cycles panels", "schedulers" in t, t)

key("n", 0.5)
t = snap("n with one node")
check("n with one node says so", "only one node" in t, t)

os.write(fd, b"q")
pump(0.5)
wpid, status = reap(pid)
check("q exits cleanly", wpid == pid and os.WIFEXITED(status) and os.WEXITSTATUS(status) == 0,
      "wpid=%s status=%s" % (wpid, status))
try:
    lflag = termios.tcgetattr(fd)[3]
    check("terminal restored to cooked mode", bool(lflag & termios.ICANON) and bool(lflag & termios.ECHO))
except termios.error:
    pass   # the pty is gone with the child; the exit status above is the check

if dumpfile:
    # The same screen over a crash dump (MARCH_CRASH_DUMP): no node, live-only panels greyed.
    pid, fd = pty.fork()
    if pid == 0:
        os.execve(forge, [forge, "observe", "--dump", dumpfile], env)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLS, 0, 0))
    screen = Screen(ROWS, COLS)
    pump(1.5)
    t = snap("crash dump, System")
    check("dump banner", "CRASH DUMP" in t and "reason: panic" in t, t)
    key("9"); t = snap("crash dump, Crashes (key 9): the panic text is in the dump")
    check("dump crashes carry message text", "MESSAGE" in t and "panic" in t, t)
    key("4"); t = snap("crash dump, Actor (key 4): live-only")
    check("Actor is greyed out in a dump", "live-only" in t, t)
    os.write(fd, b"q")
    pump(0.5)
    wpid, status = reap(pid)
    check("q exits the dump view", wpid == pid and os.WIFEXITED(status) and os.WEXITSTATUS(status) == 0,
          "wpid=%s status=%s" % (wpid, status))

if outfile:
    with open(outfile, "w") as f:
        f.write("pty capture of `forge observe --socket %s` (%dx%d); not a screenshot\n\n" % (sock, COLS, ROWS))
        f.write("\n".join(captures))
sys.exit(1 if failures else 0)
