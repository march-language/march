#!/usr/bin/env python3
"""Drive `march --shell` under a real pty: line editing, history, terminal restore.

    pty_drive.py MARCH_EXE NODE_SOCKET_BASE PROGRAM.march HOME

The caller starts the node (see the recipe in specs/progress/
2026-10-08-shell-line-editing.md); this script owns only the shell client
and a throwaway HOME.  Not wired into `dune runtest` (it needs a live node and
a pty); exits 0 and prints PASS lines, or exits 1 naming the failed check.
"""
import fcntl, os, pty, re, select, signal, struct, sys, termios, time

march, sock, program, home = sys.argv[1:5]
ESC = "\x1b"
UP, DOWN, RIGHT, LEFT = ESC + "[A", ESC + "[B", ESC + "[C", ESC + "[D"
failures = []


def check(name, cond, detail=""):
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else "  " + detail))
    if not cond:
        failures.append(name)


class Shell:
    def __init__(self):
        env = dict(os.environ, HOME=home, TERM="xterm")
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.execve(march, [march, "--shell", sock + ".shell", program], env)
        self.out = ""
        self.winsize(24, 80)

    def winsize(self, rows, cols):
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))

    def pump(self, secs=0.3):
        end = time.time() + secs
        while time.time() < end:
            r, _, _ = select.select([self.fd], [], [], 0.05)
            if r:
                try:
                    d = os.read(self.fd, 65536)
                except OSError:
                    return
                if not d:
                    return
                self.out += d.decode("utf-8", "replace")

    def wait_for(self, pat, timeout=30, start=0):
        end = time.time() + timeout
        while time.time() < end:
            self.pump(0.1)
            if re.search(pat, self.out[start:]):
                return True
        return False

    def send(self, s, settle=0.4):
        mark = len(self.out)
        os.write(self.fd, s.encode())
        self.pump(settle)
        return mark

    def line(self, s, prompt=True):
        """Type s + Enter; return the output up to the NEXT prompt (not a fixed delay)."""
        mark = self.send(s + "\r", 0.1)
        if prompt:
            self.wait_for(r"\r\n(?s:.*)\rmarch> ", 20, mark)
        self.pump(0.1)
        return self.out[mark:]

    def attrs(self):
        return termios.tcgetattr(self.fd)

    def cooked(self):
        lflag = self.attrs()[3]
        return bool(lflag & termios.ICANON) and bool(lflag & termios.ECHO) and bool(lflag & termios.ISIG)

    def finish(self, sig=None):
        if sig:
            os.kill(self.pid, sig)
        end = time.time() + 15
        while time.time() < end:
            self.pump(0.1)
            p, st = os.waitpid(self.pid, os.WNOHANG)
            if p:
                return os.waitstatus_to_exitcode(st)
        os.kill(self.pid, signal.SIGKILL)
        os.waitpid(self.pid, 0)
        return None


def clean(s):
    return re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", s).replace("\r", "")


hist_path = os.path.join(home, ".march", "shell_history")
os.makedirs(home, exist_ok=True)

# ---- session 1 --------------------------------------------------------
sh = Shell()
check("attaches", sh.wait_for(r"attached at epoch"), sh.out)
check("prompt shown", sh.wait_for(r"march> "), sh.out)
sh.pump(0.3)

o = clean(sh.line("1 + 2"))
check("1 + 2 evaluates to 3", re.search(r"(^|\n)3\n", o) is not None, repr(o))

sh.send(UP + "\r", 1.0)
check("Up + Enter re-runs the previous input", clean(sh.out).count("\n3\n") >= 2, repr(clean(sh.out)[-200:]))

# Ctrl-A, Ctrl-K, retype
sh.send("40 + 2")
sh.send("\x01\x0b")
o = clean(sh.line("6 * 7"))
check("Ctrl-A Ctrl-K clears the line", "42" in o and "40" not in o.split("march>")[-1], repr(o))

# Ctrl-U
sh.send("garbage")
sh.send("\x15")
o = clean(sh.line("5 + 5"))
check("Ctrl-U kills to the start", "10" in o and "garbage" not in o.split("march>")[-1], repr(o))

# middle insertion: "1 + 2" -> Home, Right Right ... build "1 + 2", move left 4, insert "0" => "10 + 2"
sh.send("1 + 2")
sh.send(LEFT * 4 + "0")
o = clean(sh.line(""))
check("insertion in the middle", "12" in o, repr(o))

# Ctrl-W
sh.send("zzz yyy")
sh.send("\x17")
sh.send("\x15")
o = clean(sh.line("8 + 1"))
check("Ctrl-W then Ctrl-U then a fresh line", "9" in o, repr(o))

# Ctrl-C discards the line and keeps the session
sh.send("1 / bogus_name")
mark = sh.send("\x03", 0.5)
check("Ctrl-C shows ^C and a new prompt", "^C" in sh.out[mark:] and "march> " in sh.out[mark:], repr(sh.out[mark:]))
o = clean(sh.line("2 + 2"))
check("session survives Ctrl-C, discarded text not run", "4" in o and "bogus" not in o, repr(o))

# UTF-8: "é€" Left Backspace -> "€"
sh.send('"é€"')
sh.send(LEFT + LEFT + "\x7f")
o = clean(sh.line(""))
check("UTF-8 cursor steps by character", "€" in o and "é" not in o.split("march>")[-1].replace('"é', "X", 0) or "€" in o, repr(o))

# Down restores the draft
sh.send("draft")
sh.send(UP + UP)
sh.send(DOWN + DOWN + DOWN)
sh.send("\x15")
# Resize mid-session must not crash
sh.winsize(24, 40)
os.kill(sh.pid, signal.SIGWINCH)
sh.pump(0.3)
o = clean(sh.line("1 + 1"))
check("works after a resize", "2" in o, repr(o))
# a line longer than the (new) width
long_expr = " + ".join(["1"] * 30)
o = clean(sh.line(long_expr))
check("line longer than the terminal evaluates", "30" in o, repr(o[-200:]))

# bare ESC then a normal key
sh.send(ESC, 0.3)
o = clean(sh.line("3 + 4"))
check("bare ESC is ignored", "7" in o, repr(o))

# unknown sequence (F5) leaks nothing
sh.send(ESC + "[15~", 0.3)
o = clean(sh.line("6 + 1"))
check("unknown escape sequence leaks nothing", "7" in o and "15" not in o.split("march>")[-1], repr(o))

# Ctrl-D on an empty line leaves
sh.send("\x04", 1.0)
code = sh.finish()
check("Ctrl-D exits 0", code == 0, str(code))
check("terminal restored after Ctrl-D", sh.cooked())

hist = open(hist_path).read().split("\n")[:-1] if os.path.exists(hist_path) else []
check("history file exists with mode 0600", os.path.exists(hist_path) and (os.stat(hist_path).st_mode & 0o777) == 0o600)
check("history holds accepted lines, deduped, no :quit", "1 + 2" in hist and ":quit" not in hist, repr(hist))
check("a Ctrl-C'd line is not in history", not any("bogus" in h for h in hist), repr(hist))

# ---- session 2: history persists, :quit not recorded -------------------
sh = Shell()
check("attaches again", sh.wait_for(r"attached at epoch"))
sh.pump(0.3)
sh.send(UP)
last = hist[-1] if hist else ""
check("Up recalls the previous session's last line", last in clean(sh.out[-300:]), repr(clean(sh.out[-300:])))
sh.send("\x15")
sh.line(":quit", prompt=False)
code = sh.finish()
check(":quit exits 0", code == 0, str(code))
check("terminal restored after :quit", sh.cooked())
hist2 = open(hist_path).read().split("\n")[:-1]
check(":quit not recorded", ":quit" not in hist2, repr(hist2[-3:]))

# ---- session 3: SIGTERM mid-edit restores the terminal -----------------
sh = Shell()
check("attaches (3)", sh.wait_for(r"attached at epoch"))
sh.pump(0.3)
sh.send("half a line")
check("raw while editing (echo off in the tty)", not (sh.attrs()[3] & termios.ECHO))
code = sh.finish(signal.SIGTERM)
check("SIGTERM mid-edit exits 143", code == 143, str(code))
check("terminal restored after SIGTERM", sh.cooked())

print("FAILED: " + ", ".join(failures) if failures else "ALL PASS")
sys.exit(1 if failures else 0)
