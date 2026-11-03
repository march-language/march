window.marchModuleIndex = {
 "core": [
  "prelude.march",
  "option.march",
  "result.march",
  "list.march",
  "task.march",
  "hamt.march",
  "map.march",
  "math.march",
  "string.march",
  "sort.march",
  "seq.march",
  "set.march",
  "array.march",
  "tuple.march",
  "char.march",
  "range.march",
  "enum.march",
  "json.march",
  "http.march",
  "http_transport.march",
  "http_client.march",
  "crypto.march",
  "deque.march",
  "vector_clock.march",
  "merkle.march",
  "crdt.march",
  "consistent_hash.march",
  "vault.march"
 ],
 "modules": {
  "Actor": {
   "file": "actor.march",
   "unavailable": null,
   "uses": [
    "IO",
    "List",
    "Scheduler"
   ]
  },
  "AhoCorasick": {
   "file": "aho_corasick.march",
   "unavailable": null,
   "uses": [
    "Array",
    "Option",
    "Queue"
   ]
  },
  "Array": {
   "file": "array.march",
   "unavailable": null,
   "uses": [
    "List",
    "String",
    "Tuple"
   ]
  },
  "Base64": {
   "file": "base64.march",
   "unavailable": null,
   "uses": [
    "Bytes"
   ]
  },
  "BigInt": {
   "file": "bigint.march",
   "unavailable": null,
   "uses": []
  },
  "Bytes": {
   "file": "bytes.march",
   "unavailable": null,
   "uses": [
    "Result"
   ]
  },
  "CRDT": {
   "file": "crdt.march",
   "unavailable": null,
   "uses": [
    "List",
    "Map",
    "Math",
    "UUID",
    "VectorClock"
   ]
  },
  "CRDT.GCounter": {
   "file": "crdt.march",
   "unavailable": null,
   "uses": [
    "List",
    "Map",
    "Math",
    "UUID",
    "VectorClock"
   ]
  },
  "CRDT.LWWRegister": {
   "file": "crdt.march",
   "unavailable": null,
   "uses": [
    "List",
    "Map",
    "Math",
    "UUID",
    "VectorClock"
   ]
  },
  "CRDT.ORSet": {
   "file": "crdt.march",
   "unavailable": null,
   "uses": [
    "List",
    "Map",
    "Math",
    "UUID",
    "VectorClock"
   ]
  },
  "CRDT.PNCounter": {
   "file": "crdt.march",
   "unavailable": null,
   "uses": [
    "List",
    "Map",
    "Math",
    "UUID",
    "VectorClock"
   ]
  },
  "Channel": {
   "file": "channel.march",
   "unavailable": null,
   "uses": [
    "PubSub"
   ]
  },
  "ChannelServer": {
   "file": "channel_server.march",
   "unavailable": null,
   "uses": [
    "Channel",
    "PubSub"
   ]
  },
  "ChannelSocket": {
   "file": "channel_socket.march",
   "unavailable": "it needs network sockets",
   "uses": [
    "Channel",
    "HttpServer",
    "Map",
    "Option",
    "PubSub",
    "WebSocket"
   ]
  },
  "Char": {
   "file": "char.march",
   "unavailable": null,
   "uses": [
    "String"
   ]
  },
  "Check": {
   "file": "check.march",
   "unavailable": null,
   "uses": [
    "Gen",
    "List",
    "Random",
    "Result"
   ]
  },
  "Cli": {
   "file": "cli.march",
   "unavailable": null,
   "uses": [
    "Char",
    "Env",
    "List",
    "Result",
    "String"
   ]
  },
  "Cluster": {
   "file": "cluster.march",
   "unavailable": "it needs the cluster runtime",
   "uses": [
    "List",
    "String",
    "System"
   ]
  },
  "ClusterAuth": {
   "file": "cluster_auth.march",
   "unavailable": "it needs the cluster runtime",
   "uses": [
    "Bytes",
    "Crypto",
    "List",
    "NodeCert",
    "String"
   ]
  },
  "ClusterConn": {
   "file": "cluster_conn.march",
   "unavailable": "it needs network sockets",
   "uses": [
    "ClusterAuth",
    "Handshake",
    "IO",
    "NetKernel",
    "NodeCert",
    "PeerRegistry",
    "Socket",
    "Vault"
   ]
  },
  "ClusterLoad": {
   "file": "cluster_load.march",
   "unavailable": "it needs the cluster runtime",
   "uses": [
    "List",
    "System"
   ]
  },
  "ClusterNode": {
   "file": "cluster_node.march",
   "unavailable": "it needs the cluster runtime",
   "uses": [
    "Bytes",
    "ClusterAuth",
    "Crypto",
    "DistLink",
    "File",
    "GlobalPid",
    "GlobalRegistry",
    "Handshake",
    "IO",
    "List",
    "Map",
    "Membership",
    "Msgpack",
    "NetFrame",
    "NetKernel",
    "Node",
    "NodeCert",
    "NodeIdentity",
    "NodeQueue",
    "NodeSend",
    "PeerReader",
    "Result",
    "SessionAP",
    "Socket",
    "String",
    "Swim",
    "SwimDriver",
    "System",
    "Vault"
   ]
  },
  "Compress": {
   "file": "compress.march",
   "unavailable": null,
   "uses": [
    "Bytes",
    "Seq"
   ]
  },
  "Compress.Brotli": {
   "file": "compress.march",
   "unavailable": null,
   "uses": [
    "Bytes",
    "Seq"
   ]
  },
  "Compress.Deflate": {
   "file": "compress.march",
   "unavailable": null,
   "uses": [
    "Bytes",
    "Seq"
   ]
  },
  "Compress.Gzip": {
   "file": "compress.march",
   "unavailable": null,
   "uses": [
    "Bytes",
    "Seq"
   ]
  },
  "Compress.Zstd": {
   "file": "compress.march",
   "unavailable": null,
   "uses": [
    "Bytes",
    "Seq"
   ]
  },
  "Config": {
   "file": "config.march",
   "unavailable": null,
   "uses": [
    "IO",
    "List",
    "Option",
    "Result",
    "Vault"
   ]
  },
  "ConsistentHash": {
   "file": "consistent_hash.march",
   "unavailable": null,
   "uses": [
    "Crypto",
    "List",
    "Map"
   ]
  },
  "Control": {
   "file": "control.march",
   "unavailable": null,
   "uses": [
    "Bytes",
    "ClusterNode",
    "Json",
    "List",
    "NodeCert",
    "Option",
    "Result",
    "String",
    "Topology",
    "Tuple",
    "Vault"
   ]
  },
  "Crypto": {
   "file": "crypto.march",
   "unavailable": null,
   "uses": [
    "Bytes",
    "IO",
    "Result"
   ]
  },
  "Csv": {
   "file": "csv.march",
   "unavailable": null,
   "uses": [
    "IO",
    "List",
    "String"
   ]
  },
  "DataFrame": {
   "file": "dataframe.march",
   "unavailable": "it needs 63-bit integers (the browser REPL's Int is 32-bit)",
   "uses": [
    "Hamt",
    "Json",
    "List",
    "Map",
    "Option",
    "Stats",
    "String"
   ]
  },
  "DateTime": {
   "file": "datetime.march",
   "unavailable": null,
   "uses": [
    "Duration"
   ]
  },
  "Decimal": {
   "file": "decimal.march",
   "unavailable": null,
   "uses": []
  },
  "Deque": {
   "file": "deque.march",
   "unavailable": null,
   "uses": [
    "List"
   ]
  },
  "Diagnose": {
   "file": "diagnose.march",
   "unavailable": null,
   "uses": [
    "Actor",
    "Json",
    "List",
    "Result"
   ]
  },
  "Diagnostics": {
   "file": "diagnostics.march",
   "unavailable": null,
   "uses": [
    "List"
   ]
  },
  "Dir": {
   "file": "dir.march",
   "unavailable": "it needs a file system",
   "uses": [
    "File",
    "IO"
   ]
  },
  "DistLink": {
   "file": "dist_link.march",
   "unavailable": "it needs the cluster runtime",
   "uses": [
    "GlobalPid",
    "IO",
    "List",
    "Map",
    "Msgpack",
    "NetKernel",
    "PeerRegistry"
   ]
  },
  "DistSupervisor": {
   "file": "dist_supervisor.march",
   "unavailable": "it needs the cluster runtime",
   "uses": [
    "DistLink",
    "GlobalPid",
    "List"
   ]
  },
  "Dns": {
   "file": "dns.march",
   "unavailable": null,
   "uses": [
    "List",
    "String"
   ]
  },
  "Duration": {
   "file": "duration.march",
   "unavailable": null,
   "uses": []
  },
  "Enum": {
   "file": "enum.march",
   "unavailable": null,
   "uses": [
    "HashMap",
    "Iterable",
    "List",
    "Map",
    "Set",
    "Sort",
    "Tuple"
   ]
  },
  "Env": {
   "file": "env.march",
   "unavailable": null,
   "uses": []
  },
  "File": {
   "file": "file.march",
   "unavailable": "it needs a file system",
   "uses": [
    "Dir",
    "IO",
    "List",
    "Seq",
    "String"
   ]
  },
  "Flow": {
   "file": "flow.march",
   "unavailable": null,
   "uses": [
    "Http",
    "Seq"
   ]
  },
  "Forge": {
   "file": "forge_nb.march",
   "unavailable": null,
   "uses": []
  },
  "Gen": {
   "file": "gen.march",
   "unavailable": null,
   "uses": [
    "Check",
    "List",
    "Option",
    "Random"
   ]
  },
  "GlobalPid": {
   "file": "global_pid.march",
   "unavailable": null,
   "uses": [
    "Msgpack"
   ]
  },
  "GlobalRegistry": {
   "file": "global_registry.march",
   "unavailable": "it needs the cluster runtime",
   "uses": [
    "List",
    "Map",
    "Merkle",
    "String",
    "VectorClock"
   ]
  },
  "Hamt": {
   "file": "hamt.march",
   "unavailable": null,
   "uses": [
    "List"
   ]
  },
  "Handle": {
   "file": "handle.march",
   "unavailable": null,
   "uses": []
  },
  "Handshake": {
   "file": "handshake.march",
   "unavailable": "it needs the cluster runtime",
   "uses": [
    "ClusterAuth",
    "Msgpack",
    "NodeCert",
    "NodeIdentity",
    "String"
   ]
  },
  "HashMap": {
   "file": "hash_map.march",
   "unavailable": null,
   "uses": [
    "List"
   ]
  },
  "Html": {
   "file": "html.march",
   "unavailable": null,
   "uses": [
    "Char",
    "IOList",
    "List",
    "String"
   ]
  },
  "Http": {
   "file": "http.march",
   "unavailable": null,
   "uses": [
    "Result",
    "Uri"
   ]
  },
  "HttpClient": {
   "file": "http_client.march",
   "unavailable": null,
   "uses": [
    "Http",
    "HttpTransport",
    "Result"
   ]
  },
  "HttpServer": {
   "file": "http_server.march",
   "unavailable": "it needs network sockets",
   "uses": [
    "HttpClient",
    "IO",
    "List"
   ]
  },
  "HttpTransport": {
   "file": "http_transport.march",
   "unavailable": null,
   "uses": [
    "Http",
    "IO",
    "Result",
    "Tls"
   ]
  },
  "IO": {
   "file": "io.march",
   "unavailable": null,
   "uses": [
    "Enum",
    "IOList"
   ]
  },
  "IOList": {
   "file": "iolist.march",
   "unavailable": null,
   "uses": []
  },
  "Iterable": {
   "file": "iterable.march",
   "unavailable": null,
   "uses": [
    "List"
   ]
  },
  "Js.Audio": {
   "file": "audio.march",
   "unavailable": null,
   "uses": [
    "Js.Dom"
   ]
  },
  "Js.Canvas": {
   "file": "canvas.march",
   "unavailable": null,
   "uses": [
    "Js.Dom"
   ]
  },
  "Js.Dom": {
   "file": "dom.march",
   "unavailable": null,
   "uses": [
    "List"
   ]
  },
  "Json": {
   "file": "json.march",
   "unavailable": null,
   "uses": []
  },
  "JsonStream": {
   "file": "json_stream.march",
   "unavailable": null,
   "uses": [
    "File",
    "Json",
    "Result",
    "Seq",
    "Tuple"
   ]
  },
  "LazyNicheProbe": {
   "file": "lazy_niche_probe.march",
   "unavailable": null,
   "uses": [
    "List"
   ]
  },
  "LinearMap": {
   "file": "linear_map.march",
   "unavailable": null,
   "uses": [
    "List",
    "Map",
    "Option"
   ]
  },
  "List": {
   "file": "list.march",
   "unavailable": null,
   "uses": [
    "Range",
    "Result",
    "String",
    "Tuple"
   ]
  },
  "Logger": {
   "file": "logger.march",
   "unavailable": null,
   "uses": [
    "Crypto",
    "File",
    "Option",
    "String"
   ]
  },
  "Map": {
   "file": "map.march",
   "unavailable": null,
   "uses": [
    "List"
   ]
  },
  "Math": {
   "file": "math.march",
   "unavailable": null,
   "uses": []
  },
  "Membership": {
   "file": "membership.march",
   "unavailable": "it needs the cluster runtime",
   "uses": [
    "List",
    "Map"
   ]
  },
  "Merkle": {
   "file": "merkle.march",
   "unavailable": null,
   "uses": [
    "Crypto",
    "List",
    "Option",
    "String"
   ]
  },
  "MlDsa": {
   "file": "ml_dsa.march",
   "unavailable": null,
   "uses": [
    "Bytes",
    "Crypto",
    "IO",
    "List"
   ]
  },
  "MlKem": {
   "file": "ml_kem.march",
   "unavailable": null,
   "uses": [
    "Bytes",
    "Crypto",
    "IO"
   ]
  },
  "Msgpack": {
   "file": "msgpack.march",
   "unavailable": "it needs 63-bit integers (the browser REPL's Int is 32-bit)",
   "uses": []
  },
  "NativeArray": {
   "file": "native_array.march",
   "unavailable": null,
   "uses": []
  },
  "NetFrame": {
   "file": "net_frame.march",
   "unavailable": "it needs 63-bit integers (the browser REPL's Int is 32-bit)",
   "uses": [
    "Bytes",
    "List"
   ]
  },
  "NetKernel": {
   "file": "net_kernel.march",
   "unavailable": "it needs network sockets",
   "uses": [
    "Bytes",
    "ClusterAuth",
    "Crypto",
    "GlobalRegistry",
    "Handshake",
    "List",
    "Msgpack",
    "NetFrame",
    "Node",
    "NodeCert",
    "NodeIdentity",
    "NodeSend",
    "Option",
    "Socket",
    "String",
    "Vault",
    "VectorClock"
   ]
  },
  "Node": {
   "file": "node.march",
   "unavailable": "it needs the cluster runtime",
   "uses": [
    "Bytes",
    "IO",
    "Json",
    "NodeQueue",
    "NodeSend",
    "PeerRegistry",
    "Vault"
   ]
  },
  "NodeCall": {
   "file": "node_call.march",
   "unavailable": "it needs the cluster runtime",
   "uses": [
    "Msgpack",
    "NetKernel",
    "NodeRpc",
    "RemoteCall"
   ]
  },
  "NodeCert": {
   "file": "node_cert.march",
   "unavailable": null,
   "uses": [
    "Bytes",
    "Crypto",
    "List",
    "Msgpack",
    "Result",
    "String"
   ]
  },
  "NodeIdentity": {
   "file": "node_identity.march",
   "unavailable": null,
   "uses": [
    "Crypto",
    "Handshake",
    "Msgpack"
   ]
  },
  "NodeQueue": {
   "file": "node_queue.march",
   "unavailable": "it needs 63-bit integers (the browser REPL's Int is 32-bit)",
   "uses": [
    "Actor",
    "Bytes",
    "ClusterNode",
    "Deque",
    "IO",
    "List",
    "Msgpack",
    "NetFrame",
    "NetKernel",
    "NodeSend",
    "Vault"
   ]
  },
  "NodeRpc": {
   "file": "node_rpc.march",
   "unavailable": "it needs the cluster runtime",
   "uses": [
    "Map",
    "NodeCall",
    "RemoteCall"
   ]
  },
  "NodeSend": {
   "file": "node_send.march",
   "unavailable": "it needs the cluster runtime",
   "uses": [
    "Bytes",
    "IO",
    "List",
    "Msgpack",
    "NetKernel",
    "Node",
    "SessionAP",
    "SessionNode",
    "String",
    "Vault"
   ]
  },
  "Option": {
   "file": "option.march",
   "unavailable": null,
   "uses": [
    "List"
   ]
  },
  "OrderedMap": {
   "file": "ordered_map.march",
   "unavailable": null,
   "uses": [
    "List"
   ]
  },
  "Parallel": {
   "file": "parallel.march",
   "unavailable": null,
   "uses": [
    "Array",
    "List",
    "RRB",
    "System"
   ]
  },
  "Parser": {
   "file": "parser.march",
   "unavailable": null,
   "uses": [
    "List",
    "Result",
    "String"
   ]
  },
  "Path": {
   "file": "path.march",
   "unavailable": null,
   "uses": [
    "List",
    "String"
   ]
  },
  "PeerReader": {
   "file": "peer_reader.march",
   "unavailable": "it needs the cluster runtime",
   "uses": [
    "Msgpack",
    "NetKernel"
   ]
  },
  "PeerRegistry": {
   "file": "peer_registry.march",
   "unavailable": "it needs the cluster runtime",
   "uses": [
    "Map",
    "NodeIdentity"
   ]
  },
  "Plot": {
   "file": "plot.march",
   "unavailable": null,
   "uses": [
    "File",
    "List",
    "Math",
    "Option",
    "Sort",
    "String"
   ]
  },
  "Prelude": {
   "file": "prelude.march",
   "unavailable": null,
   "uses": [
    "List",
    "Option",
    "Result",
    "String"
   ]
  },
  "Presence": {
   "file": "presence.march",
   "unavailable": null,
   "uses": [
    "Channel",
    "Map"
   ]
  },
  "Process": {
   "file": "process.march",
   "unavailable": "it needs operating-system processes",
   "uses": [
    "Seq"
   ]
  },
  "PubSub": {
   "file": "pubsub.march",
   "unavailable": null,
   "uses": [
    "ChannelServer",
    "Map"
   ]
  },
  "Queue": {
   "file": "queue.march",
   "unavailable": null,
   "uses": [
    "Option"
   ]
  },
  "RRB": {
   "file": "rrb_vec.march",
   "unavailable": null,
   "uses": [
    "Array",
    "Parallel"
   ]
  },
  "Random": {
   "file": "random.march",
   "unavailable": "it needs 63-bit integers (the browser REPL's Int is 32-bit)",
   "uses": [
    "IO",
    "List"
   ]
  },
  "Range": {
   "file": "range.march",
   "unavailable": null,
   "uses": [
    "List"
   ]
  },
  "Recon": {
   "file": "recon.march",
   "unavailable": null,
   "uses": [
    "Actor",
    "Json",
    "List",
    "String",
    "Tuple"
   ]
  },
  "Regex": {
   "file": "regex.march",
   "unavailable": null,
   "uses": []
  },
  "RemoteCall": {
   "file": "remote_call.march",
   "unavailable": "it needs the cluster runtime",
   "uses": [
    "GlobalPid",
    "Msgpack",
    "NetFrame"
   ]
  },
  "Result": {
   "file": "result.march",
   "unavailable": null,
   "uses": [
    "String"
   ]
  },
  "RingBuf": {
   "file": "ring_buf.march",
   "unavailable": null,
   "uses": []
  },
  "Scheduler": {
   "file": "scheduler.march",
   "unavailable": null,
   "uses": [
    "Actor"
   ]
  },
  "Seq": {
   "file": "seq.march",
   "unavailable": null,
   "uses": []
  },
  "Session": {
   "file": "session.march",
   "unavailable": null,
   "uses": [
    "Bytes",
    "List",
    "String",
    "Vault"
   ]
  },
  "SessionAP": {
   "file": "session_ap.march",
   "unavailable": null,
   "uses": [
    "List",
    "NodeCert"
   ]
  },
  "SessionNode": {
   "file": "session_node.march",
   "unavailable": "it needs the cluster runtime",
   "uses": [
    "Actor",
    "Bytes",
    "ClusterAuth",
    "ClusterConn",
    "ClusterNode",
    "Env",
    "GlobalPid",
    "IO",
    "List",
    "Membership",
    "Msgpack",
    "NetKernel",
    "NodeCert",
    "NodeIdentity",
    "NodeQueue",
    "NodeSend",
    "Option",
    "PeerReader",
    "PeerRegistry",
    "Result",
    "Session",
    "SessionAP",
    "String",
    "Topology",
    "Vault"
   ]
  },
  "Set": {
   "file": "set.march",
   "unavailable": null,
   "uses": [
    "List"
   ]
  },
  "ShellRender": {
   "file": "shell_render.march",
   "unavailable": null,
   "uses": [
    "Actor",
    "Array",
    "Deque",
    "HashMap",
    "Map",
    "OrderedMap",
    "Queue",
    "RRB",
    "Set",
    "SortedSet"
   ]
  },
  "Sigil": {
   "file": "sigil.march",
   "unavailable": null,
   "uses": [
    "IOList",
    "Toml",
    "Xml",
    "Yaml"
   ]
  },
  "Signal": {
   "file": "signal.march",
   "unavailable": "it needs operating-system processes",
   "uses": [
    "IO"
   ]
  },
  "Simd": {
   "file": "simd.march",
   "unavailable": null,
   "uses": [
    "Bytes",
    "List",
    "NativeArray"
   ]
  },
  "Socket": {
   "file": "socket.march",
   "unavailable": "it needs network sockets",
   "uses": [
    "IO",
    "Tls"
   ]
  },
  "Sort": {
   "file": "sort.march",
   "unavailable": null,
   "uses": [
    "Tuple"
   ]
  },
  "SortedSet": {
   "file": "sorted_set.march",
   "unavailable": null,
   "uses": [
    "List"
   ]
  },
  "Stats": {
   "file": "stats.march",
   "unavailable": null,
   "uses": [
    "List"
   ]
  },
  "String": {
   "file": "string.march",
   "unavailable": null,
   "uses": [
    "Bytes",
    "List",
    "Option"
   ]
  },
  "Swim": {
   "file": "swim.march",
   "unavailable": "it needs the cluster runtime",
   "uses": [
    "List",
    "Map",
    "Membership"
   ]
  },
  "SwimDriver": {
   "file": "swim_driver.march",
   "unavailable": "it needs the cluster runtime",
   "uses": [
    "ClusterLoad",
    "List",
    "Map",
    "Membership",
    "Msgpack",
    "NetKernel",
    "PeerRegistry",
    "Random",
    "String",
    "Swim"
   ]
  },
  "System": {
   "file": "system.march",
   "unavailable": null,
   "uses": [
    "IO"
   ]
  },
  "Task": {
   "file": "task.march",
   "unavailable": null,
   "uses": [
    "Enum",
    "List"
   ]
  },
  "Test": {
   "file": "test.march",
   "unavailable": null,
   "uses": [
    "List",
    "String"
   ]
  },
  "Tls": {
   "file": "tls.march",
   "unavailable": "it needs network sockets",
   "uses": [
    "HttpTransport",
    "IO",
    "Result",
    "Socket",
    "String"
   ]
  },
  "Toml": {
   "file": "toml.march",
   "unavailable": null,
   "uses": [
    "List",
    "String"
   ]
  },
  "Topology": {
   "file": "topology.march",
   "unavailable": "it needs the cluster runtime",
   "uses": [
    "ClusterNode",
    "Crypto",
    "Env",
    "File",
    "IO",
    "Json",
    "List",
    "Membership",
    "Option",
    "Session",
    "SessionNode",
    "Signal",
    "String",
    "Tuple",
    "Vault"
   ]
  },
  "Trace": {
   "file": "trace.march",
   "unavailable": null,
   "uses": [
    "Actor",
    "Json",
    "List",
    "String"
   ]
  },
  "Tuple": {
   "file": "tuple.march",
   "unavailable": null,
   "uses": [
    "List",
    "String"
   ]
  },
  "UUID": {
   "file": "uuid.march",
   "unavailable": null,
   "uses": [
    "Bytes",
    "IO",
    "Result"
   ]
  },
  "Uri": {
   "file": "uri.march",
   "unavailable": null,
   "uses": []
  },
  "Vault": {
   "file": "vault.march",
   "unavailable": null,
   "uses": [
    "IO",
    "List",
    "Option"
   ]
  },
  "VectorClock": {
   "file": "vector_clock.march",
   "unavailable": null,
   "uses": [
    "List",
    "Map",
    "Math"
   ]
  },
  "WebSocket": {
   "file": "websocket.march",
   "unavailable": "it needs network sockets",
   "uses": [
    "HttpServer",
    "IO"
   ]
  },
  "WorkDispatch": {
   "file": "work_dispatch.march",
   "unavailable": "it needs the cluster runtime",
   "uses": [
    "ClusterLoad",
    "ConsistentHash",
    "List",
    "NodeCall"
   ]
  },
  "Xml": {
   "file": "xml.march",
   "unavailable": null,
   "uses": [
    "List",
    "String"
   ]
  },
  "Yaml": {
   "file": "yaml.march",
   "unavailable": null,
   "uses": [
    "List",
    "String"
   ]
  }
 }
};
