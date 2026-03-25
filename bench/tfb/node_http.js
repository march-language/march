// Minimal Node.js HTTP server — TFB plaintext + JSON
// Usage: node node_http.js
const http = require('http');

const HELLO = Buffer.from('Hello, World!');
const JSON_MSG = Buffer.from('{"message":"Hello, World!"}');

const server = http.createServer((req, res) => {
  if (req.url === '/json') {
    res.writeHead(200, {
      'Content-Type': 'application/json',
      'Content-Length': JSON_MSG.length,
      'Server': 'Node.js'
    });
    res.end(JSON_MSG);
  } else {
    res.writeHead(200, {
      'Content-Type': 'text/plain',
      'Content-Length': HELLO.length,
      'Server': 'Node.js'
    });
    res.end(HELLO);
  }
});

server.listen(8080, () => {
  console.log('Node.js listening on :8080');
});
