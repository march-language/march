// Island performance benchmark — concurrency/throughput/latency test.
//
// Tests the island_perf_server at concurrency levels: 10, 50, 100, 500, 1000.
// Each level sends REQUESTS_PER_LEVEL total requests in batches of CONCURRENCY.
//
// Measures:
//   - Throughput (req/sec)
//   - Latency p50 / p95 / p99 (ms)
//   - Error rate (non-200 responses)
//   - Consistency: all successful requests return exactly {"ok":true}
//
// Usage:
//   node bench/island_perf_bench.mjs [host] [port]
//   node bench/island_perf_bench.mjs 127.0.0.1 8899

import http from 'http';

const HOST = process.argv[2] || '127.0.0.1';
const PORT = parseInt(process.argv[3] || '8899', 10);

const CONCURRENCY_LEVELS = [10, 50, 100, 500, 1000];
const REQUESTS_PER_LEVEL = 1000;

function percentile(sorted, p) {
  const idx = Math.ceil((p / 100) * sorted.length) - 1;
  return sorted[Math.max(0, idx)];
}

function postUpdate() {
  return new Promise((resolve) => {
    const start = performance.now();
    const opts = {
      hostname: HOST,
      port: PORT,
      path: '/update',
      method: 'POST',
    };
    const req = http.request(opts, (res) => {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => {
        const latency = performance.now() - start;
        resolve({ status: res.statusCode, latency, data });
      });
    });
    req.on('error', (err) => {
      const latency = performance.now() - start;
      resolve({ status: 0, latency, error: err.message });
    });
    req.end();
  });
}

function ping() {
  return new Promise((resolve) => {
    http.get({ hostname: HOST, port: PORT, path: '/ping' }, (res) => {
      let data = '';
      res.on('data', (c) => { data += c; });
      res.on('end', () => resolve(res.statusCode === 200));
    }).on('error', () => resolve(false));
  });
}

async function runLevel(concurrency) {
  const total = REQUESTS_PER_LEVEL;
  const latencies = [];
  let errors = 0;
  let successes = 0;
  let bodyMismatches = 0;

  const start = performance.now();

  // Send requests in batches of `concurrency`
  let sent = 0;
  while (sent < total) {
    const batchSize = Math.min(concurrency, total - sent);
    const batch = [];
    for (let i = 0; i < batchSize; i++) {
      batch.push(postUpdate());
    }
    const results = await Promise.all(batch);
    for (const r of results) {
      latencies.push(r.latency);
      if (r.status === 200) {
        successes++;
        if (r.data !== '{"ok":true}') bodyMismatches++;
      } else {
        errors++;
      }
    }
    sent += batchSize;
  }

  const elapsed = (performance.now() - start) / 1000;
  const sorted = [...latencies].sort((a, b) => a - b);

  return {
    concurrency,
    total,
    successes,
    errors,
    errorRate: (errors / total * 100).toFixed(1),
    throughput: (total / elapsed).toFixed(1),
    p50: percentile(sorted, 50).toFixed(1),
    p95: percentile(sorted, 95).toFixed(1),
    p99: percentile(sorted, 99).toFixed(1),
    consistent: bodyMismatches === 0,
    bodyMismatches,
  };
}

async function waitForServer(retries = 20, delayMs = 250) {
  for (let i = 0; i < retries; i++) {
    if (await ping()) return true;
    await new Promise(r => setTimeout(r, delayMs));
  }
  return false;
}

async function main() {
  console.log(`\n=== Island Perf Bench: ${HOST}:${PORT} ===`);
  console.log(`  ${REQUESTS_PER_LEVEL} POST /update requests per concurrency level\n`);

  const ready = await waitForServer();
  if (!ready) {
    console.error('ERROR: server not responding at ' + HOST + ':' + PORT);
    process.exit(1);
  }

  const results = [];
  for (const c of CONCURRENCY_LEVELS) {
    process.stdout.write(`  concurrency=${String(c).padEnd(5)} ... `);
    const r = await runLevel(c);
    results.push(r);
    console.log(`${r.throughput.padStart(8)} req/s  errors=${r.errors}`);
  }

  console.log('\n--- Results ---');
  console.log(
    'conc'.padEnd(7) +
    'ok'.padEnd(6) +
    'err%'.padEnd(7) +
    'req/s'.padEnd(10) +
    'p50ms'.padEnd(9) +
    'p95ms'.padEnd(9) +
    'p99ms'.padEnd(9) +
    'consistent'
  );
  console.log('-'.repeat(70));
  for (const r of results) {
    console.log(
      String(r.concurrency).padEnd(7) +
      String(r.successes).padEnd(6) +
      (r.errorRate + '%').padEnd(7) +
      r.throughput.padEnd(10) +
      r.p50.padEnd(9) +
      r.p95.padEnd(9) +
      r.p99.padEnd(9) +
      (r.consistent ? 'YES' : `NO (${r.bodyMismatches} mismatches)`)
    );
  }
  console.log('');
}

main().catch(e => { console.error(e); process.exit(1); });
