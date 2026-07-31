// Node.js HTTP server with cluster (multi-process) — TFB plaintext + JSON
// Usage: node node_cluster.js
const cluster = require('cluster');
const http = require('http');
const os = require('os');

if (cluster.isPrimary) {
  const numWorkers = os.cpus().length;
  console.log(`Node.js cluster: spawning ${numWorkers} workers on :8080`);
  for (let i = 0; i < numWorkers; i++) {
    cluster.fork();
  }
} else {
  const HELLO = Buffer.from('Hello, World!');

  // Serialized per request, matching node_http.js and
  // bench/tfb/tfb_server.march -- see the comment in node_http.js.

  http.createServer((req, res) => {
    if (req.url === '/json') {
      const body = Buffer.from(JSON.stringify({ message: 'Hello, World!' }));
      res.writeHead(200, {
        'Content-Type': 'application/json',
        'Content-Length': body.length,
        'Server': 'Node.js-cluster'
      });
      res.end(body);
    } else {
      res.writeHead(200, {
        'Content-Type': 'text/plain',
        'Content-Length': HELLO.length,
        'Server': 'Node.js-cluster'
      });
      res.end(HELLO);
    }
  }).listen(8080);
}
