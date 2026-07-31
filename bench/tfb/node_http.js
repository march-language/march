// Minimal Node.js HTTP server — TFB plaintext + JSON
// Usage: node node_http.js
const http = require('http');

const HELLO = Buffer.from('Hello, World!');

// The /json body is serialized PER REQUEST, not hoisted to a module-level
// constant. TFB's rules require the JSON test to exercise a real serializer,
// and bench/tfb/tfb_server.march calls Json.to_string on every request --
// pre-baking it here would measure Node writing a fixed buffer against March
// actually encoding, which is not the same work.

const server = http.createServer((req, res) => {
  if (req.url === '/json') {
    const body = Buffer.from(JSON.stringify({ message: 'Hello, World!' }));
    res.writeHead(200, {
      'Content-Type': 'application/json',
      'Content-Length': body.length,
      'Server': 'Node.js'
    });
    res.end(body);
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
