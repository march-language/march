#!/usr/bin/env python3
"""Execute the generated ABI-refusal path, including its March panic string.

A compiler wrapper perturbs only the expected ABI argument at generated work
entry call sites. The published slot retains its real ABI, so the real runtime
must reject it. This exercises the normally defensive path without an unsafe
activation or weakening the deployment signature gate.
"""
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile

compiler = str(Path(sys.argv[1]).resolve())
clang = shutil.which("clang")
assert clang, "clang is required"
with tempfile.TemporaryDirectory(prefix="hcr-work-entry-") as temp:
    work = Path(temp)
    (work / "home").mkdir()
    (work / "bin").mkdir()
    wrapper = work / "bin" / "clang"
    wrapper.write_text("#!/usr/bin/env python3\n" + '''import os, pathlib, re, sys
for arg in sys.argv[1:]:
    if arg.endswith('.ll'):
        path = pathlib.Path(arg)
        text = path.read_text()
        text, count = re.subn(
            r'(call ptr @march_dispatch_enter_work_compatible\\(i32 [^,]+, ptr )[^,]+',
            r'\\1@.incompatible_work_abi', text)
        if count:
            text += '\\n@.incompatible_work_abi = private constant [65 x i8] c"' + '0' * 64 + '\\\\00"\\n'
            path.write_text(text)
            pathlib.Path(os.environ['WORK_ENTRY_INJECTED']).write_text(str(count))
os.execv(os.environ['WORK_ENTRY_CLANG'], [os.environ['WORK_ENTRY_CLANG']] + sys.argv[1:])
''')
    wrapper.chmod(0o755)
    source = work / "app.march"
    source.write_text('''mod WorkEntry do
  needs IO
  needs Session.Live
  needs ClusterNode.Live
  @[endpoints]
  protocol Ping do
    value: Client -> Server : Int
  end
  fn serve(_env : (), s : Cap(Session.Live), st : Ping_Server.Entry) : Ping_Server.Yield do
    Ping_Server.recv_Value(s, st, fn (_n, done) -> Ping_Server.close(s, done))
  end
end
''')
    topology = work / "topology.json"
    topology.write_text(json.dumps({
        "version": 1, "env": None, "sources": ["topology.toml"],
        "roles": [{"name": "Ping.Server", "protocol": "Ping", "role": "Server",
                   "body": "WorkEntry.serve", "actor": None, "capacity": 1,
                   "place": None, "set": False}],
        "pools": [{"name": "back", "start": None, "serves": ["Ping.Server"],
                   "serves_all": False, "initiates": None, "caps": None,
                   "isolate": False, "public": [], "main": None,
                   "replicas": None, "hosts": []}],
        "drain": None, "backend": None, "control": None,
    }))
    injected = work / "injected"
    env = os.environ | {
        "HOME": str(work / "home"),
        "PATH": str(work / "bin") + os.pathsep + os.environ["PATH"],
        "WORK_ENTRY_CLANG": clang,
        "WORK_ENTRY_INJECTED": str(injected),
    }
    for key in ("MARCH_STDLIB", "MARCH_RUNTIME_DIR"):
        if env.get(key):
            env[key] = str(Path(env[key]).resolve())
    binary = work / "app"
    built = subprocess.run(
        [compiler, "--compile", "--hot-reload", "WorkEntry", "--topology",
         str(topology), "-o", str(binary), str(source)],
        cwd=work, env=env, capture_output=True, text=True, timeout=180,
    )
    assert built.returncode == 0, built.stdout + built.stderr
    assert injected.exists(), "compiler did not emit a guarded work-entry call"
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    env |= {"MARCH_NODE_NAME": "work-entry-test", "MARCH_NODE_PORT": str(port),
            "MARCH_CLUSTER_NODES": "", "MARCH_CLUSTER_SECRET": "work-entry-test",
            "MARCH_POOLS": "back", "MARCH_PLACEMENT_SETTLE_MS": "0"}
    process = subprocess.Popen([str(binary)], cwd=work, env=env,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        stdout, stderr = process.communicate(timeout=15)
    except subprocess.TimeoutExpired:
        # A failed service task may leave the supervisor alive. This test pins
        # readable refusal without a segfault, not whole-process termination.
        process.kill()
        stdout, stderr = process.communicate()
    assert "hot reload: incompatible generated work entry" in stderr, (process.returncode, stdout, stderr)
    assert "restart required" in stderr, stderr
    assert process.returncode not in (0, -11), "ABI refusal succeeded or segfaulted"
    print("generated work entry rejects incompatible ABI with restart diagnostic")
