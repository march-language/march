(function () {
  "use strict";
  var base = document.getElementById("tp-wrap").dataset.base || "";
  var ver = document.getElementById("tp-wrap").dataset.ver || "0";
  var loaded = false, loading = false, pending = null;

  function loadScript(src, ok, err) {
    var s = document.createElement("script");
    s.src = src; s.onload = ok; s.onerror = err;
    document.head.appendChild(s);
  }

  function ensureCompilerLoaded(cb) {
    if (loaded) { cb(); return; }
    if (loading) { pending = cb; return; }
    loading = true;
    setStatus("Loading compiler…");
    loadScript(base + "/assets/march_stdlib.js?v=" + ver, function () {
      loadScript(base + "/assets/march_compile.js?v=" + ver, function () {
        loaded = true; loading = false;
        setStatus("Ready.");
        cb();
        if (pending) { var f = pending; pending = null; f(); }
      }, onLoadFail);
    }, function () {
      loadScript(base + "/assets/march_compile.js?v=" + ver, function () {
        loaded = true; loading = false;
        setStatus("Ready (no stdlib bundle).");
        cb();
      }, onLoadFail);
    });
  }

  function onLoadFail() {
    loading = false;
    setStatus("Failed to load compiler.");
  }

  function setStatus(s) { document.getElementById("tp-status").textContent = s; }

  /* ------------------------------------------------------------------ */
  /* Syntax highlighter — same tokenizer as march-repl.js's _hlLine, but */
  /* applied LIVE to the editable textarea (that one only highlights    */
  /* already-submitted read-only history entries). Duplicated rather    */
  /* than shared: these are two independent js_of_ocaml-adjacent bundle */
  /* pages, not meant to be coupled.                                    */
  /* ------------------------------------------------------------------ */

  var _KWS = ['fn', 'pfn', 'let', 'type', 'ptype', 'mod', 'do', 'end', 'match', 'if', 'else', 'with', 'when',
              'actor', 'state', 'init', 'on', 'reply', 'spawn', 'send', 'run_until_idle',
              'true', 'false', 'in', 'import', 'use', 'doc',
              'linear', 'always_linear', 'needs', 'cap', 'proof', 'tag', 'transitions'];

  function _esc(s) {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  }
  function _col(v, s) {
    return '<span style="color:var(' + v + ')">' + _esc(s) + '</span>';
  }

  function _hlLine(line) {
    var out = "", i = 0, n = line.length;
    while (i < n) {
      var c = line[i];
      if (c === "-" && line[i + 1] === "-") { out += _col("--syn-cm", line.slice(i)); break; }
      if (c === '"') {
        var j = i + 1;
        while (j < n && line[j] !== '"') { if (line[j] === "\\") j++; j++; }
        out += _col("--syn-st", line.slice(i, j + 1));
        i = j + 1; continue;
      }
      if (c >= "0" && c <= "9") {
        var j = i;
        while (j < n && ((line[j] >= "0" && line[j] <= "9") || line[j] === ".")) j++;
        out += _col("--syn-nm", line.slice(i, j));
        i = j; continue;
      }
      var lo = c >= "a" && c <= "z", hi = c >= "A" && c <= "Z";
      if (lo || hi || c === "_") {
        var j = i;
        while (j < n) {
          var d = line[j];
          if (!((d >= "a" && d <= "z") || (d >= "A" && d <= "Z") ||
                (d >= "0" && d <= "9") || d === "_")) break;
          j++;
        }
        var w = line.slice(i, j);
        out += (_KWS.indexOf(w) >= 0) ? _col("--syn-kw", w) :
               hi                      ? _col("--syn-tp", w) :
               _col("--syn-id", w);
        i = j; continue;
      }
      var tw = c + (line[i + 1] || "");
      if (tw === "->" || tw === "<-" || tw === "|>" || tw === "++" ||
          tw === "+." || tw === "-." || tw === "*." || tw === "/." ||
          tw === "==" || tw === "!=" || tw === "<=" || tw === ">=" || tw === "..") {
        out += _col("--syn-op", tw); i += 2; continue;
      }
      if ("|=:+-*/<>!".indexOf(c) >= 0) { out += _col("--syn-op", c); i++; continue; }
      out += _esc(c);
      i++;
    }
    return out;
  }

  function renderHighlight() {
    var editor = document.getElementById("tp-editor");
    var hl = document.getElementById("tp-highlight");
    var html = editor.value.split("\n").map(_hlLine).join("\n");
    // A trailing newline needs an extra blank line in the backdrop too,
    // or the <pre> collapses it and the caret drifts out of sync on the
    // last line.
    hl.innerHTML = html + (editor.value.endsWith("\n") ? "\n" : "") + " ";
  }

  function syncHighlightScroll() {
    var editor = document.getElementById("tp-editor");
    var hl = document.getElementById("tp-highlight");
    hl.scrollTop = editor.scrollTop;
    hl.scrollLeft = editor.scrollLeft;
  }

  function showErrors(errs) {
    var el = document.getElementById("tp-errors");
    if (!errs || !errs.length) {
      el.textContent = ""; el.classList.remove("visible");
      return;
    }
    el.textContent = errs.join("\n");
    el.classList.add("visible");
  }

  // Reads the SITE's actual theme colors (light/dark toggle, see docs.html's
  // :root / :root.light) so the game iframe blends with the page instead of
  // carrying its own hardcoded dark-blue palette. Read once per Run — the
  // iframe won't live-follow a theme toggle mid-session, only on next Run,
  // which is an acceptable tradeoff for how rarely that happens mid-edit.
  function themeColors() {
    var s = getComputedStyle(document.documentElement);
    function v(name, fallback) {
      var val = s.getPropertyValue(name).trim();
      return val || fallback;
    }
    return {
      bg: v("--bg", "#07101a"),
      bgCode: v("--bg-code", "#0c1928"),
      text: v("--text", "#cce5f5"),
      textMuted: v("--text-muted", "#4a7898"),
      border: v("--border", "#0f2438")
    };
  }

  var BOARD_COLS = 10, BOARD_ROWS = 20;

  // The board rendered at a fixed 16px/cell regardless of how much space the
  // panel actually had — tiny and lost in the middle of a tall panel. Instead
  // size cells from the ACTUAL space #tp-iframe-host has right now (measured
  // before the old iframe is torn down, since the host's own size comes from
  // outer flex layout and doesn't depend on its children), reserving room for
  // the HUD/game-over lines and some breathing room, so the board fills most
  // of the panel on a big screen and still fits on a small one.
  function computeCellSize() {
    var host = document.getElementById("tp-iframe-host");
    var rect = host.getBoundingClientRect();
    var reservedV = 155; // HUD + game-over + pause-status + time-travel bar + gaps + body padding
    var reservedH = 32;  // board border + side margin
    var byHeight = Math.floor((rect.height - reservedV) / BOARD_ROWS);
    var byWidth = Math.floor((rect.width - reservedH) / BOARD_COLS);
    var size = Math.min(byHeight, byWidth);
    if (!isFinite(size) || size <= 0) size = 20;
    return Math.max(12, Math.min(size, 44));
  }

  // The attributes that fully describe one game frame. Time travel copies
  // these verbatim between #game-state and #restore-request — see the
  // inline script below and Tetris.restore_from_request in tetris.march.
  var STATE_ATTRS = ["data-board", "data-piece", "data-rot", "data-x", "data-y",
                      "data-next", "data-score", "data-lines", "data-rng",
                      "data-over", "data-paused"];
  var HISTORY_CAP = 3000;

  // Runs inside the iframe as a plain (non-module) script, so it executes
  // synchronously during parse — before the deferred `type=module` script
  // that calls Tetris.main() — guaranteeing the MutationObserver below is
  // already attached when restart() makes its first move.
  //
  // Recording: a fresh snapshot of every #game-state attribute is captured
  // each time data-seq changes (bumped only by with_state's commit branch
  // and restart() in tetris.march — never by pausing or by restoring a
  // snapshot), so passively scrubbing history never records anything.
  //
  // Scrubbing writes the target frame to #restore-request (forcing
  // data-paused='true' so nothing can advance while you're looking at the
  // past — every gameplay function already refuses to run while paused)
  // and clicks #restore-trigger, which tetris.march wires to
  // restore_from_request(). "Resume from here" truncates the in-memory
  // history to the current frame and restores it with data-paused='false',
  // branching play forward from that point exactly like undo-then-edit.
  function timeTravelScript() {
    return (
      "(function(){" +
      "var ATTRS=" + JSON.stringify(STATE_ATTRS) + ";" +
      "var CAP=" + HISTORY_CAP + ";" +
      "var history=[],historyIndex=-1,followingLive=true;" +
      "var gs=document.getElementById('game-state');" +
      "var req=document.getElementById('restore-request');" +
      "var trigger=document.getElementById('restore-trigger');" +
      "var slider=document.getElementById('tt-slider');" +
      "var backBtn=document.getElementById('tt-back');" +
      "var fwdBtn=document.getElementById('tt-fwd');" +
      "var resumeBtn=document.getElementById('tt-resume');" +
      "var pauseBtn=document.getElementById('pause-btn');" +
      "var label=document.getElementById('tt-label');" +
      "function capture(){" +
      "var s={};ATTRS.forEach(function(a){s[a]=gs.getAttribute(a);});return s;" +
      "}" +
      "function writeRequest(snap,pausedOverride){" +
      "ATTRS.forEach(function(a){" +
      "req.setAttribute(a,a==='data-paused'&&pausedOverride!==null?pausedOverride:snap[a]);" +
      "});" +
      "trigger.click();" +
      "}" +
      "function updateUI(){" +
      "var n=history.length;" +
      "slider.max=String(Math.max(n-1,0));" +
      "slider.value=String(Math.max(historyIndex,0));" +
      "slider.disabled=n<=1;" +
      "backBtn.disabled=historyIndex<=0;" +
      "fwdBtn.disabled=historyIndex>=n-1;" +
      "label.textContent='Frame '+(n?historyIndex+1:0)+'/'+n;" +
      // While scrubbed away from the live tip, "Pause"/"Resume" and this
      // button would otherwise both read "Resume" at once — toggling plain
      // pause means nothing while inspecting a past frame anyway (you can't
      // play against history without branching), so hide it and leave this
      // as the one unambiguous action. visibility (not display) so toggling
      // it never changes the row's height and shifts the game underneath.
      "resumeBtn.style.visibility=followingLive?'hidden':'visible';" +
      "pauseBtn.style.display=followingLive?'':'none';" +
      "}" +
      "function scrubTo(i){" +
      "i=Math.max(0,Math.min(i,history.length-1));" +
      "historyIndex=i;" +
      "followingLive=(i===history.length-1);" +
      "writeRequest(history[i],followingLive?null:'true');" +
      "updateUI();" +
      "}" +
      "new MutationObserver(function(){" +
      "history.push(capture());" +
      "if(history.length>CAP)history.shift();" +
      "if(followingLive)historyIndex=history.length-1;" +
      "updateUI();" +
      "}).observe(gs,{attributes:true,attributeFilter:['data-seq']});" +
      // Dragging fires many 'input' events per second, each a distinct
      // recorded game frame (a piece can move/lock/clear/spawn between two
      // adjacent frames) — restoring every single one, un-throttled, flashes
      // through many visually different boards faster than the eye can
      // track, reading as jitter. Coalescing to the latest value once per
      // animation frame caps the restore rate to the display's own paint
      // rate without changing what a deliberate single step/click does.
      "var pendingScrub=null,scrubScheduled=false;" +
      "function scheduleScrub(i){" +
      "pendingScrub=i;" +
      "if(scrubScheduled)return;" +
      "scrubScheduled=true;" +
      "requestAnimationFrame(function(){scrubScheduled=false;scrubTo(pendingScrub);});" +
      "}" +
      "slider.addEventListener('input',function(e){scheduleScrub(parseInt(e.target.value,10));});" +
      "backBtn.addEventListener('click',function(){scrubTo(historyIndex-1);});" +
      "fwdBtn.addEventListener('click',function(){scrubTo(historyIndex+1);});" +
      "resumeBtn.addEventListener('click',function(){" +
      "var snap=history[historyIndex];" +
      "history.length=historyIndex+1;" +
      "followingLive=true;" +
      "writeRequest(snap,'false');" +
      "updateUI();" +
      "});" +
      "updateUI();" +
      "})();"
    );
  }

  function buildSrcdoc(js) {
    // tetris.mjs's own emitted code imports "./march_runtime.mjs" and
    // "./march_dom.mjs" by RELATIVE path. A srcdoc iframe's base URL is the
    // embedding page's URL, not the assets directory, so a plain relative
    // import silently resolves to the wrong place (and fails) unless we set
    // an explicit <base href> pointing at the assets directory.
    var assetsBase = window.location.origin + base + "/assets/tetris/";
    var t = themeColors();
    var cell = computeCellSize();
    var hudFont = Math.max(12, Math.round(cell * 0.5));
    var boardPx = cell * BOARD_COLS;
    return (
      "<!DOCTYPE html><html><head><meta charset='utf-8'>" +
      "<base href='" + assetsBase + "'>" +
      "<style>" +
      "*{box-sizing:border-box;margin:0;padding:0}" +
      "body{background:" + t.bg + ";color:" + t.text + ";font-family:system-ui,sans-serif;" +
      "display:flex;flex-direction:column;align-items:center;justify-content:center;gap:.75rem;height:100vh}" +
      "#board{display:flex;flex-direction:column;border:2px solid " + t.border + ";background:" + t.bgCode + "}" +
      ".tetris-row{display:flex}.tetris-cell{width:" + cell + "px;height:" + cell + "px;border:1px solid " + t.border + ";background:" + t.bgCode + "}" +
      "#hud{display:flex;gap:1rem;align-items:center;font-size:" + hudFont + "px;color:" + t.textMuted + "}" +
      ".hud-btn{font:inherit;color:inherit;background:transparent;border:1px solid " + t.border + ";" +
      "border-radius:4px;padding:2px 10px;cursor:pointer}" +
      ".hud-btn:hover{border-color:" + t.textMuted + "}" +
      ".hud-btn:disabled{opacity:.4;cursor:default}" +
      "#game-over{color:#f87171;font-weight:600;min-height:1.2em;font-size:" + hudFont + "px}" +
      "#pause-status{color:" + t.textMuted + ";font-weight:600;min-height:1.2em;font-size:" + hudFont + "px}" +
      // Squeezing the slider into the same row as the step buttons, frame
      // count, and "Resume from here" left it almost no width to shrink
      // into — it read as "collapsed". Full-width slider on its own row,
      // sized to match the board, with the controls on a row underneath.
      "#tt-bar{display:flex;flex-direction:column;gap:.4rem;font-size:" + hudFont + "px;" +
      "color:" + t.textMuted + ";width:" + boardPx + "px}" +
      "#tt-slider{width:100%}" +
      "#tt-controls{display:flex;align-items:center;justify-content:center;gap:.5rem}" +
      "#tt-label{white-space:nowrap;font-variant-numeric:tabular-nums}" +
      "</style></head><body>" +
      "<div id='board'></div>" +
      "<div id='hud'><span id='score'>Score: 0</span><span id='level'>Level: 0</span><span id='next'>Next: O</span>" +
      "<button id='pause-btn' class='hud-btn' type='button'>Pause</button></div>" +
      "<div id='game-over'></div>" +
      "<div id='pause-status'></div>" +
      "<div id='tt-bar'>" +
      "<input id='tt-slider' type='range' min='0' max='0' value='0'>" +
      "<div id='tt-controls'>" +
      "<button id='tt-back' class='hud-btn' type='button' title='Step back'>&#9664;</button>" +
      "<span id='tt-label'>Frame 0/0</span>" +
      "<button id='tt-fwd' class='hud-btn' type='button' title='Step forward'>&#9654;</button>" +
      "<button id='tt-resume' class='hud-btn' type='button' style='visibility:hidden'>Resume</button>" +
      "</div>" +
      "</div>" +
      "<div id='game-state' data-board='' data-piece='I' data-rot='0' data-x='3' data-y='0' " +
      "data-next='O' data-score='0' data-lines='0' data-rng='' data-over='false' data-paused='false' data-seq='0' style='display:none'></div>" +
      "<div id='restore-request' data-board='' data-piece='I' data-rot='0' data-x='3' data-y='0' " +
      "data-next='O' data-score='0' data-lines='0' data-rng='' data-over='false' data-paused='false' style='display:none'></div>" +
      "<button id='restore-trigger' type='button' style='display:none'></button>" +
      "<script>window.onerror = function (msg) { parent.postMessage({tpError: String(msg)}, '*'); };<\/script>" +
      "<script>" +
      "document.getElementById('pause-btn').addEventListener('click', function () {" +
      "document.body.dispatchEvent(new KeyboardEvent('keydown', {key: 'p', bubbles: true}));" +
      "});" +
      // Reflects the March side's actual data-paused attribute (rather than
      // guessing from the click alone) so the label stays correct even when
      // toggle_pause is a no-op — e.g. it refuses to pause a finished game.
      "new MutationObserver(function () {" +
      "var paused = document.getElementById('game-state').getAttribute('data-paused') === 'true';" +
      "document.getElementById('pause-btn').textContent = paused ? 'Resume' : 'Pause';" +
      "}).observe(document.getElementById('game-state'), {attributes: true, attributeFilter: ['data-paused']});" +
      "<\/script>" +
      "<script>" + timeTravelScript() + "<\/script>" +
      "<script type='module'>" +
      js +
      "<\/script>" +
      "</body></html>"
    );
  }

  // Each Run rebuilds a FRESH iframe rather than reusing the existing one —
  // this cleanly discards any intervals/listeners/DOM state left over from
  // the previous run instead of trying to individually tear them down.
  function mountJs(js) {
    var host = document.getElementById("tp-iframe-host");
    host.innerHTML = "";
    var iframe = document.createElement("iframe");
    iframe.id = "tp-iframe";
    iframe.style.width = "100%";
    iframe.style.height = "100%";
    iframe.style.border = "0";
    // Without this, arrow keys silently do nothing until the player clicks
    // into the board — keyboard focus stays on the outer page (e.g. on the
    // Run button) after every mount, since a fresh iframe never grabs it on
    // its own.
    iframe.onload = function () {
      if (iframe.contentWindow) iframe.contentWindow.focus();
    };
    host.appendChild(iframe);
    iframe.srcdoc = buildSrcdoc(js);
  }

  function mountStatic() {
    fetch(base + "/assets/tetris/tetris.mjs")
      .then(function (r) { return r.text(); })
      .then(mountJs);
  }

  window.addEventListener("message", function (ev) {
    if (ev.data && ev.data.tpError) showErrors(["runtime error: " + ev.data.tpError]);
  });

  window.tpRun = function () {
    var src = document.getElementById("tp-editor").value;
    ensureCompilerLoaded(function () {
      setStatus("Compiling…");
      var result = window.marchCompileToJs(src);
      if (result.js !== null) {
        showErrors([]);
        setStatus("Running.");
        mountJs(result.js);
      } else {
        showErrors(result.errors);
        setStatus("Compile failed.");
      }
    });
  };

  (function () {
    var editor = document.getElementById("tp-editor");
    editor.addEventListener("input", renderHighlight);
    editor.addEventListener("scroll", syncHighlightScroll);
    // Tab inserts a literal tab instead of moving focus, matching a real
    // code editor (and keeping March's 2-space-indent convention easy to
    // reach — Shift+Tab is intentionally not handled, out of scope for a
    // minimal editor).
    editor.addEventListener("keydown", function (ev) {
      if (ev.key !== "Tab") return;
      ev.preventDefault();
      var start = editor.selectionStart, end = editor.selectionEnd;
      editor.value = editor.value.slice(0, start) + "  " + editor.value.slice(end);
      editor.selectionStart = editor.selectionEnd = start + 2;
      renderHighlight();
    });
  })();

  fetch(base + "/assets/tetris/tetris-source.march.txt")
    .then(function (r) { return r.text(); })
    .then(function (src) {
      document.getElementById("tp-editor").value = src;
      renderHighlight();
    });

  window.addEventListener("load", mountStatic);
})();
