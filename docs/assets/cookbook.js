(function () {
  'use strict';

  var repl = null;
  var panelOpen = false;

  /* ── Panel open / close ─────────────────────────────────────────────── */

  function openPanel() {
    var panel  = document.getElementById('ck-repl-panel');
    var layout = document.getElementById('d-layout');
    panel.classList.add('open');
    layout.classList.add('repl-open');
    panelOpen = true;
    ensureRepl();
  }

  function closePanel() {
    var panel  = document.getElementById('ck-repl-panel');
    var layout = document.getElementById('d-layout');
    panel.classList.remove('open');
    layout.classList.remove('repl-open');
    panelOpen = false;
  }

  document.getElementById('ck-repl-close').addEventListener('click', closePanel);
  // The panel (and so these buttons) is only visible once openPanel() has
  // created the REPL; the guard covers a click racing that.
  document.getElementById('ck-repl-clear').addEventListener('click', function () { if (repl) repl.clear(); });
  document.getElementById('ck-repl-reset').addEventListener('click', function () { if (repl) repl.reset(); });

  /* ── MarchRepl instantiation (lazy) ────────────────────────────────── */

  function ensureRepl() {
    if (repl) return;

    repl = new MarchRepl({
      wrapId:    'ck-repl-panel',
      historyId: 'ck-repl-history',
      inputId:   'ck-repl-input',
      loadingId: 'ck-repl-loading',
      cls: {
        entry:     'ck-repl-entry',
        inputLine: 'ck-repl-iline',
        output:    'ck-repl-oline',
        error:     'ck-repl-eline',
        info:      'ck-repl-info'
      }
    });

    document.getElementById('ck-repl-submit').addEventListener('click', function () {
      repl.submit();
    });
  }

  /* ── Run a snippet in the panel ────────────────────────────────────── */

  function runSnippet(code) {
    if (!panelOpen) openPanel();
    ensureRepl();
    repl.load(code);
    repl.submit();
  }

  /* ── Copy to clipboard ──────────────────────────────────────────────── */

  function copyCode(btn, code) {
    navigator.clipboard.writeText(code).then(function () {
      var prev = btn.textContent;
      btn.textContent = 'copied!';
      btn.classList.add('ck-btn-copied');
      setTimeout(function () {
        btn.textContent = prev;
        btn.classList.remove('ck-btn-copied');
      }, 1500);
    });
  }

  /* ── Display-only blocks ─────────────────────────────────────────────── */

  // A ```march block whose fence follows a `<!-- repl:skip -->` comment line in
  // the page source (a fragment, or code that needs a file system or sockets)
  // gets a copy button but no run button. kramdown keeps the comment, as a
  // sibling of the block's outermost wrapper; other comments may sit between.
  // scripts/cookbook-run-blocks-check.js runs every other block (CI).
  function displayOnly(block) {
    for (var el = block; el && !(el.classList && el.classList.contains('d-content')); el = el.parentNode) {
      var p = el.previousSibling;
      while (p && (p.nodeType === 8 || (p.nodeType === 3 && !p.textContent.trim()))) {
        if (p.nodeType === 8 && /^\s*repl:skip\s*$/.test(p.data)) return true;
        p = p.previousSibling;
      }
      if (p) return false; // a real element precedes this one: no marker applies
    }
    return false;
  }

  /* ── Inject copy/run buttons into every code block ──────────────────── */

  function injectButtons() {
    var blocks = document.querySelectorAll(
      '.d-content .highlight, .d-content pre:not(.highlight pre)'
    );

    blocks.forEach(function (block) {
      var codeEl = block.querySelector('code');
      if (!codeEl) return;

      var cls = codeEl.className || '';
      var isMarch = cls.indexOf('language-march') >= 0;
      var code = codeEl.textContent.trim();
      if (!code) return;

      var wrap = document.createElement('div');
      wrap.className = 'ck-code-btns';

      var copyBtn = document.createElement('button');
      copyBtn.className = 'ck-btn';
      copyBtn.textContent = 'copy';
      copyBtn.setAttribute('aria-label', 'Copy code');
      copyBtn.addEventListener('click', function () { copyCode(copyBtn, code); });
      wrap.appendChild(copyBtn);

      if (isMarch && !displayOnly(block)) {
        var runBtn = document.createElement('button');
        runBtn.className = 'ck-btn ck-btn-run';
        runBtn.textContent = 'run';
        runBtn.setAttribute('aria-label', 'Run in REPL');
        runBtn.addEventListener('click', function () { runSnippet(code); });
        wrap.appendChild(runBtn);
      }

      block.appendChild(wrap);
    });
  }

  document.addEventListener('DOMContentLoaded', injectButtons);
}());
