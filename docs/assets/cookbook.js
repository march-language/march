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

      if (isMarch) {
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
