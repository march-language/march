import socket, sys, time, hashlib

sock_path = sys.argv[1]

def connect():
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(sock_path)
    return s

def recv_line(s):
    buf = b""
    while not buf.endswith(b"\n"):
        c = s.recv(1)
        if not c:
            break
        buf += c
    return buf.decode(errors="replace").rstrip("\n")

# A 64-hex "hash" that is NOT the hash of the bytes we will upload.
fake_hash = "a" * 64
payload = b"TOTALLY-NOT-A-REAL-ARTIFACT-" + b"X" * 200

s = connect()
s.sendall(b"PING\n")
print("PING ->", recv_line(s))
s.close()

# CAS_PUT under fake_hash with mismatched bytes.
s = connect()
s.sendall(("CAS_PUT %s %d\n" % (fake_hash, len(payload))).encode())
print("CAS_PUT ready ->", recv_line(s))
s.sendall(payload)
print("CAS_PUT verdict ->", recv_line(s))
s.close()

# CAS_CHECK: does the server now claim to hold an artifact at fake_hash?
s = connect()
s.sendall(("CAS_CHECK %s\n" % fake_hash).encode())
print("CAS_CHECK ->", recv_line(s))
s.close()

print("sha256(payload) =", hashlib.sha256(payload).hexdigest())
print("claimed hash    =", fake_hash)
print("bytes match claimed hash under any common algo? ", False)
