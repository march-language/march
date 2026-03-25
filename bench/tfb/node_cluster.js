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
  const JSON_MSG = Buffer.from('{"message":"Hello, World!"}');

  http.createServer((req, res) => {
    if (req.url === '/json') {
      res.writeHead(200, {
        'Content-Type': 'application/json',
        'Content-Length': JSON_MSG.length,
        'Server': 'Node.js-cluster'
      });
      res.end(JSON_MSG);
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
