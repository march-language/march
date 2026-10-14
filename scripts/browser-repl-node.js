// browser-repl-node.js — run the in-browser March REPL under Node, the way a page does.
//
// Shared by scripts/browser-repl-smoke.js and scripts/browser-repl-doc-sweep.js. It
// loads march_stdlib.js, march_stdlib_index.js and march.js into a `vm` context that
// stands in for a browser window, and `run(code)` follows the same steps as
// docs/assets/march-repl.js before each evaluation:
//   1. marchModulesNeeded(code): what the input needs that the session lacks;
//   2. an unavailable module named in the input -> the "isn't available" message,
//      nothing evaluated;
//   3. each missing file: read stdlib/<file>.js (the page fetches it), marchLoadModule;
//   4. marchEvalLine(code).
// Keep the two in step. The message text is the same, except that march-repl.js
// appends the install page URL.
'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');

function browserContext() {
  const ctx = { console, TextDecoder, TextEncoder, setTimeout, clearTimeout, performance,
                crypto: globalThis.crypto };
  // js_of_ocaml reaches the standard constructors through the global object.
  for (const name of Object.getOwnPropertyNames(globalThis)) {
    if (!(name in ctx) && /^[A-Z]/.test(name)) ctx[name] = globalThis[name];
  }
  for (const name of ['isNaN', 'isFinite', 'parseInt', 'parseFloat',
                      'encodeURIComponent', 'decodeURIComponent']) {
    ctx[name] = globalThis[name];
  }
  ctx.window = ctx; ctx.self = ctx; ctx.globalThis = ctx;
  vm.createContext(ctx);
  return ctx;
}

function unavailableMessage(u) {
  return `${u.module} isn't available in the browser REPL: ${u.reason}. ` +
         'Install March to run this.';
}

function loadRepl(assets) {
  const ctx = browserContext();
  const load = file => vm.runInContext(fs.readFileSync(path.join(assets, file), 'utf8'),
                                       ctx, { filename: file });
  load('march_stdlib.js');
  load('march_stdlib_index.js');
  load('march.js');
  for (const g of ['marchEvalLine', 'marchResetSession', 'marchModulesNeeded', 'marchLoadModule']) {
    if (typeof ctx[g] !== 'function') throw new Error(`march.js does not export ${g}`);
  }
  function run(code) {
    const need = ctx.marchModulesNeeded(code);
    const unavailable = Array.from(need.unavailable);
    if (unavailable.length) {
      return { output: '', error: unavailable.map(unavailableMessage).join('\n'), loaded: [] };
    }
    const loaded = [];
    for (const file of Array.from(need.load)) {
      load(path.join('stdlib', file.replace(/\.march$/, '.js')));
      const r = ctx.marchLoadModule(file, ctx.marchStdlib[file]);
      if (r.error) return { output: '', error: r.error, loaded };
      loaded.push(file);
    }
    const r = ctx.marchEvalLine(code);
    return { output: r.output, error: r.error, loaded };
  }
  return { ctx, run, reset: () => ctx.marchResetSession(), load };
}

module.exports = { browserContext, loadRepl, unavailableMessage };
