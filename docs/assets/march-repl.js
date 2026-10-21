/*
 * MarchRepl — shared REPL logic for the landing page and playground.
 *
 * Usage:
 *   var repl = new MarchRepl({ wrapId, historyId, inputId, loadingId, cls });
 *   repl.submit()           — eval whatever is in the textarea (a pasted
 *                             "march> " transcript runs one prompt line at a time)
 *   repl.run(code)          — eval code as if typed (queued: runs in order)
 *   repl.load(code)         — HTML-decode and load code into the textarea
 *   repl.loadThen(s, code)  — silently eval s, then load code into the textarea
 *   repl.clear()            — clear the screen; definitions and input history stay
 *   repl.reset()            — clear the screen and forget every definition
 *
 * cfg.cls must have: entry, inputLine, output, error, info
 */
(function (global) {
  "use strict";

  function MarchRepl(cfg) {
    var wrap       = document.getElementById(cfg.wrapId) || {};
    this._base     = (wrap.dataset && wrap.dataset.base) || "";
    this._ver      = (wrap.dataset && wrap.dataset.ver)  || "0";
    this._hist     = document.getElementById(cfg.historyId);
    this._input    = document.getElementById(cfg.inputId);
    this._loadEl   = document.getElementById(cfg.loadingId);
    this._cls      = cfg.cls;

    this._loaded   = false;
    this._loading  = false;
    this._pending  = null;
    this._cmdHist  = [];
    this._histIdx  = -1;

    var self = this;
    this._input.addEventListener("keydown", function (e) {
      if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault();
        self.submit();
      } else if (e.key === "ArrowUp" && !e.shiftKey && self._cmdHist.length) {
        e.preventDefault();
        self._histIdx = Math.min(self._histIdx + 1, self._cmdHist.length - 1);
        self._input.value = self._cmdHist[self._histIdx];
        self._resize();
        setTimeout(function () {
          self._input.selectionStart = self._input.selectionEnd = self._input.value.length;
        }, 0);
      } else if (e.key === "ArrowDown" && !e.shiftKey) {
        e.preventDefault();
        if (self._histIdx > 0) {
          self._histIdx--;
          self._input.value = self._cmdHist[self._histIdx];
        } else {
          self._histIdx = -1;
          self._input.value = "";
        }
        self._resize();
      } else if ((e.key === "l" || e.key === "L") && e.ctrlKey && !e.metaKey && !e.altKey) {
        // Ctrl+L clears the screen, as in a terminal. (Cmd+L is the browser's
        // address bar on macOS, so it is left alone.)
        e.preventDefault();
        self.clear();
      } else if (!self._loaded && !self._loading) {
        self._loadBundle(function () {});
      }
    });
    this._input.addEventListener("input", function () { self._resize(); });

    window.addEventListener("load", function () { self._loadBundle(function () {}); });
  }

  /* ------------------------------------------------------------------ */
  /* Bundle loading                                                      */
  /* ------------------------------------------------------------------ */

  MarchRepl.prototype._loadScript = function (src, ok, err) {
    var s = document.createElement("script");
    s.src = src; s.onload = ok; s.onerror = err;
    document.head.appendChild(s);
  };

  MarchRepl.prototype._loadBundle = function (cb) {
    var self = this;
    if (this._loaded)  { cb(); return; }
    if (this._loading) { this._pending = cb; return; }
    this._loading = true;
    this._loadEl.textContent = "Loading interpreter…";

    var finish = function () {
      self._loaded  = true;
      self._loading = false;
      self._loadEl.textContent = "Ready.";
      setTimeout(function () {
        if (self._loadEl.textContent === "Ready.") self._loadEl.textContent = "";
      }, 1500);
      cb();
      if (self._pending) { var f = self._pending; self._pending = null; f(); }
    };
    var fail = function () {
      self._loading = false;
      self._loadEl.textContent = "Failed to load interpreter.";
      // Still call back: each waiting input then reports "Interpreter not
      // available." and the run queue moves on instead of hanging.
      cb();
      if (self._pending) { var f = self._pending; self._pending = null; f(); }
    };

    // Startup stdlib, then the module index (which module lives in which file,
    // for on-demand loading), then the interpreter. A failed stdlib or index load
    // still leaves a working interpreter, just with less of the stdlib.
    var v = "?v=" + this._ver;
    var loadMarch = function () {
      self._loadScript(self._base + "/assets/march.js" + v, finish, fail);
    };
    var loadIndex = function () {
      self._loadScript(self._base + "/assets/march_stdlib_index.js" + v, loadMarch, loadMarch);
    };
    this._loadScript(this._base + "/assets/march_stdlib.js" + v, loadIndex, loadIndex);
  };

  /* ------------------------------------------------------------------ */
  /* On-demand stdlib modules                                            */
  /* ------------------------------------------------------------------ */

  // Before evaluating [code], load the stdlib modules it uses that this session
  // does not have yet (march.js's marchModulesNeeded follows the module index,
  // dependencies first), one stdlib/<file>.js each. Calls cb(null) when ready, or
  // cb(message) when [code] names a module that cannot run in a browser or a
  // module failed to load; then nothing is evaluated. Mirrors
  // scripts/browser-repl-node.js, which the CI smoke test and doc sweep use.
  MarchRepl.prototype._ensureModules = function (code, cb) {
    var self = this;
    if (!window.marchModulesNeeded) { cb(null); return; }
    var need = window.marchModulesNeeded(code);
    var unavailable = Array.prototype.slice.call(need.unavailable);
    if (unavailable.length) {
      cb(unavailable.map(function (u) {
        return u.module + " isn't available in the browser REPL: " + u.reason +
               ". Install March to run this: " + location.origin + self._base +
               "/docs/installation/";
      }).join("\n"));
      return;
    }
    var files = Array.prototype.slice.call(need.load);
    var next = function (i) {
      if (i >= files.length) { self._loadEl.textContent = ""; cb(null); return; }
      var file = files[i];
      self._loadEl.textContent = "Loading " + file.replace(/\.march$/, "") + "…";
      self._loadScript(
        self._base + "/assets/stdlib/" + file.replace(/\.march$/, ".js") + "?v=" + self._ver,
        function () {
          var r = window.marchLoadModule(file, (window.marchStdlib || {})[file] || "");
          if (r.error) { self._loadEl.textContent = ""; cb(r.error); }
          else next(i + 1);
        },
        function () {
          self._loadEl.textContent = "";
          cb("could not download the stdlib module " + file);
        });
    };
    next(0);
  };

  /* ------------------------------------------------------------------ */
  /* Syntax highlighter — minimal, regex-free, single-pass              */
  /* ------------------------------------------------------------------ */

  var _KWS = ['fn','pfn','let','type','ptype','mod','do','end','match','if','else','with','when',
              'actor','state','init','on','reply','spawn','send','run_until_idle',
              'true','false','in','import','use','doc',
              'linear','always_linear','needs','cap','proof','tag','transitions'];

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
      // comment
      if (c === "-" && line[i+1] === "-") { out += _col("--syn-cm", line.slice(i)); break; }
      // string
      if (c === '"') {
        var j = i + 1;
        while (j < n && line[j] !== '"') { if (line[j] === "\\") j++; j++; }
        out += _col("--syn-st", line.slice(i, j + 1));
        i = j + 1; continue;
      }
      // number
      if (c >= "0" && c <= "9") {
        var j = i;
        while (j < n && ((line[j] >= "0" && line[j] <= "9") || line[j] === ".")) j++;
        out += _col("--syn-nm", line.slice(i, j));
        i = j; continue;
      }
      // word
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
      // two-char operators
      var tw = c + (line[i+1] || "");
      if (tw === "->" || tw === "<-" || tw === "|>" || tw === "++" ||
          tw === "+." || tw === "-." || tw === "*." || tw === "/." ||
          tw === "==" || tw === "!=" || tw === "<=" || tw === ">=" || tw === "..") {
        out += _col("--syn-op", tw); i += 2; continue;
      }
      // single-char operators
      if ("|=:+-*/<>!".indexOf(c) >= 0) { out += _col("--syn-op", c); i++; continue; }
      // everything else
      out += _esc(c);
      i++;
    }
    return out;
  }

  /* ------------------------------------------------------------------ */
  /* Output helpers                                                      */
  /* ------------------------------------------------------------------ */

  MarchRepl.prototype._appendLine = function (text, cls) {
    var self = this;
    (text || "").split("\n").forEach(function (line) {
      var div = document.createElement("div");
      div.className = self._cls.entry;
      var sp = document.createElement("span");
      sp.className = cls;
      sp.textContent = line;
      div.appendChild(sp);
      self._hist.appendChild(div);
    });
    this._hist.scrollTop = this._hist.scrollHeight;
  };

  MarchRepl.prototype._appendInput = function (code) {
    var self = this;
    code.split("\n").forEach(function (line, i) {
      var div = document.createElement("div");
      div.className = self._cls.entry;
      var sp = document.createElement("span");
      sp.style.whiteSpace = "pre";
      if (i === 0) {
        sp.className = self._cls.inputLine;
        sp.innerHTML = _hlLine(line);
      } else {
        sp.style.color = "var(--text-faint)";
        sp.innerHTML = _hlLine("       " + line);
      }
      div.appendChild(sp);
      self._hist.appendChild(div);
    });
    this._hist.scrollTop = this._hist.scrollHeight;
  };

  MarchRepl.prototype._resize = function () {
    this._input.style.height = "auto";
    this._input.style.height = this._input.scrollHeight + "px";
  };

  /* ------------------------------------------------------------------ */
  /* h(name) — stdlib doc lookup                                        */
  /* ------------------------------------------------------------------ */

  MarchRepl.prototype._searchStdlib = function (name) {
    var stdlib = window.marchStdlib || {};
    var re = new RegExp("^\\s*fn\\s+" + name + "\\s*\\(");
    var hits = [];
    Object.keys(stdlib).forEach(function (filename) {
      var mod     = filename.replace(/\.march$/, "");
      var modName = mod.charAt(0).toUpperCase() + mod.slice(1);
      var lines   = stdlib[filename].split("\n");
      for (var i = 0; i < lines.length; i++) {
        if (re.test(lines[i])) {
          var doc = "";
          if (i > 0) {
            var m = lines[i - 1].trim().match(/^doc\s+"(.+)"$/);
            if (m) doc = m[1];
          }
          hits.push({
            modName: modName,
            sig:     lines[i].trim().replace(/\s+do\s*$/, ""),
            doc:     doc
          });
        }
      }
    });
    return hits;
  };

  /* ------------------------------------------------------------------ */
  /* Public API                                                          */
  /* ------------------------------------------------------------------ */

  // Inputs run strictly in order. One may wait on the interpreter download or
  // on an on-demand stdlib module, so later inputs (a "Try it" transcript sends
  // several at once) queue behind it rather than overtaking it or being
  // dropped by _loadBundle's single pending slot.
  MarchRepl.prototype._run = function (code) {
    this._queue = this._queue || [];
    this._queue.push(code);
    if (!this._busy) this._drain();
  };

  MarchRepl.prototype._drain = function () {
    var self = this;
    while (this._queue.length) {
      var code = this._queue.shift();
      this._busy = true;
      var pending = this._runNow(code, function () { self._busy = false; self._drain(); });
      if (pending) return; // the done callback resumes the queue
      this._busy = false;
    }
  };

  // Evaluate one input. Returns true when it finishes asynchronously, in which
  // case done() is called once it has; returns false when it already finished.
  MarchRepl.prototype._runNow = function (code, done) {
    var self = this;
    var cls  = this._cls;
    var trimmed = code.trim();

    if (!trimmed) { this._input.focus(); return; }

    if (this._cmdHist[0] !== code) this._cmdHist.unshift(code);
    if (this._cmdHist.length > 50) this._cmdHist.pop();
    this._histIdx = -1;

    if (trimmed === ":clear") {
      this._wipe();
      return;
    }

    this._appendInput(code);

    if (trimmed === ":reset") {
      if (this._loaded && window.marchResetSession) window.marchResetSession();
      this._wipe();
      this._appendLine("Session reset.", cls.info);
      return;
    }

    if (trimmed === ":help" || trimmed === "h()") {
      [
        "March REPL — quick reference",
        "",
        "Commands:",
        "  :clear        clear the screen (Ctrl+L); definitions stay",
        "  :reset        clear the screen and forget every definition",
        "  :help         show this message",
        "  h(name)       look up stdlib docs (e.g. h(map))",
        "",
        "Syntax hints:",
        "  let x = 42                          bind a value",
        "  fn double(n) do n * 2 end           define a function",
        "  List.map([1,2,3], fn x -> x * 2)   map over a list",
        "  if cond do expr else expr end        conditional",
        "  match val do Pat -> expr end         pattern match",
        "",
        "Shift+Enter for multi-line input. ↑↓ for history."
      ].forEach(function (line) {
        self._appendLine(line || " ", cls.info);
      });
      return;
    }

    this._loadBundle(function () {
      if (!window.marchEvalLine) {
        self._appendLine("Interpreter not available.", cls.error);
        done();
        return;
      }

      var hMatch = trimmed.match(/^h\((\w+)\)$/);
      if (hMatch) {
        var hits = self._searchStdlib(hMatch[1]);
        if (!hits.length) {
          self._appendLine("No stdlib docs found for '" + hMatch[1] + "'.", cls.error);
          self._appendLine("Tip: try h() for general help.", cls.info);
        } else {
          hits.forEach(function (h) {
            self._appendLine(
              h.modName + "." + hMatch[1] + (h.doc ? " — " + h.doc : ""),
              cls.info
            );
            self._appendLine("  " + h.sig, cls.output);
          });
        }
        done();
        return;
      }

      self._ensureModules(code, function (err) {
        if (err) { self._appendLine(err, cls.error); done(); return; }
        var result = window.marchEvalLine(code);
        if (result.output && result.output.trim()) self._appendLine(result.output.trimEnd(), cls.output);
        if (result.error !== null)                 self._appendLine(result.error, cls.error);
        done();
      });
    });
    return true;
  };

  // Split a pasted stdlib-doc transcript into its inputs.
  //
  // The stdlib pages' Copy button copies the whole doctest transcript, prompts
  // ("march> ...") and expected-output lines alike, and the "march> " shown in
  // the REPL history is a CSS ::before, so a pasted prompt line looks harmless.
  // On Sort.html a reader edited the first line to
  // "march> Sort.heapsort_by([8, 5, 2, 9999999, 1, 2], fn a -> fn b -> a <= b)"
  // and left the transcript's output line "[1, 2, 2, 5, 8]" under it; March
  // evaluated the two lines as one block and printed the value of the LAST
  // expression, the literal list, which looked exactly like heapsort dropping
  // 9999999. So when any line begins with "march> ", the text is a transcript:
  // each prompt line (prefix stripped) is one input, in order, and every other
  // line is expected output and is dropped. Text with no prompt line is
  // returned as the single input it always was.
  MarchRepl.splitTranscript = function (code) {
    var lines = code.split("\n");
    var inputs = [];
    for (var i = 0; i < lines.length; i++) {
      var m = lines[i].match(/^\s*march>(?:\s(.*))?$/);
      if (m) inputs.push(m[1] || "");
    }
    return inputs.length ? inputs : [code];
  };

  // Evaluate code as if the reader had typed it (used by "Try it" buttons).
  MarchRepl.prototype.run = function (code) { this._run(code); };

  // Submit whatever is currently in the textarea. A pasted doc transcript runs
  // one prompt line at a time (see splitTranscript).
  MarchRepl.prototype.submit = function () {
    var code = this._input.value;
    this._input.value = "";
    this._resize();
    var inputs = MarchRepl.splitTranscript(code);
    for (var i = 0; i < inputs.length; i++) this._run(inputs[i]);
  };

  // Remove every transcript entry except the one holding the loading-status
  // line: on the landing page and the cookbook sidebar that line lives inside
  // the transcript, and removing it would leave later "Loading interpreter…"
  // updates writing to a detached node.
  MarchRepl.prototype._wipe = function () {
    var keep = null;
    for (var n = this._loadEl; n && n !== this._hist; n = n.parentNode) keep = n;
    if (keep && keep.parentNode !== this._hist) keep = null;
    var kids = Array.prototype.slice.call(this._hist.childNodes);
    for (var i = 0; i < kids.length; i++) {
      if (kids[i] !== keep) this._hist.removeChild(kids[i]);
    }
  };

  // Clear the screen. The interpreter session (every definition) and the
  // up/down input history are kept; nothing is evaluated, so this works
  // before the interpreter has loaded and never triggers its download.
  MarchRepl.prototype.clear = function () {
    this._wipe();
    this._input.focus();
  };

  // Clear the screen and forget every definition.
  MarchRepl.prototype.reset = function () {
    this._input.value = "";
    this._resize();
    this._run(":reset");
  };

  // HTML-decode and load code into the textarea (used by chip onclick handlers).
  MarchRepl.prototype.load = function (code) {
    var ta = document.createElement("textarea");
    ta.innerHTML = code;
    this._input.value = ta.value;
    this._resize();
    this._input.focus();
    if (!this._loaded && !this._loading) this._loadBundle(function () {});
  };

  // Silently eval setup code, then load followup code into the textarea.
  // Used by error-demo chips that need prior state in scope.
  MarchRepl.prototype.loadThen = function (setup, code) {
    var self = this;
    this._loadBundle(function () {
      if (window.marchEvalLine) window.marchEvalLine(setup);
    });
    this.load(code);
  };

  global.MarchRepl = MarchRepl;

})(window);
