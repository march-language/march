(function () {
  "use strict";

  // Read the Jekyll baseurl and deploy version from data attributes on the root element.
  // data-ver is set to the Jekyll build timestamp so browsers always fetch the
  // current march.js after a deploy rather than serving a stale cached copy.
  var pgWrap = document.getElementById("pg-wrap") || {};
  var base   = pgWrap.dataset.base || "";
  var ver    = pgWrap.dataset.ver  || "0";

  /* ------------------------------------------------------------------ */
  /* State                                                               */
  /* ------------------------------------------------------------------ */
  var bundleLoaded  = false;
  var bundleLoading = false;
  var inputHistory  = [];
  var historyIdx    = -1;
  var pendingCode   = null;

  var historyEl = document.getElementById("pg-history");
  var inputEl   = document.getElementById("pg-input");
  var loadingEl = document.getElementById("pg-loading-msg");

  /* ------------------------------------------------------------------ */
  /* Stdlib doc lookup — used by h(name)                                */
  /* ------------------------------------------------------------------ */
  function searchStdlib(name) {
    var stdlib = window.marchStdlib || {};
    var results = [];
    // Match exactly "fn <name>(" at the start of a (possibly indented) line
    var re = new RegExp("^\\s*fn\\s+" + name + "\\s*\\(");

    Object.keys(stdlib).forEach(function (filename) {
      var src    = stdlib[filename];
      var base   = filename.replace(/\.march$/, "");
      var modName = base.charAt(0).toUpperCase() + base.slice(1);
      var lines  = src.split("\n");

      for (var i = 0; i < lines.length; i++) {
        if (re.test(lines[i])) {
          // Grab doc string from the preceding line if present
          var doc = "";
          if (i > 0) {
            var prev = lines[i - 1].trim();
            var m = prev.match(/^doc\s+"(.+)"$/);
            if (m) doc = m[1];
          }
          // Strip the "do" and body — just show the signature
          var sig = lines[i].trim().replace(/\s+do\s*$/, "");
          results.push({ mod: modName, sig: sig, doc: doc });
        }
      }
    });

    return results;
  }

  /* ------------------------------------------------------------------ */
  /* Bundle loading                                                      */
  /* ------------------------------------------------------------------ */
  function loadScript(src, onload, onerror) {
    var s = document.createElement("script");
    s.src = src;
    s.onload = onload;
    s.onerror = onerror;
    document.head.appendChild(s);
  }

  function loadBundle(callback) {
    if (bundleLoaded) { callback(); return; }
    if (bundleLoading) { pendingCode = callback; return; }
    bundleLoading = true;
    loadingEl.textContent = "Loading interpreter\u2026";

    // Load stdlib first, then the interpreter bundle.
    // Append ?v=<deploy-timestamp> so browsers always fetch the latest build.
    loadScript(base + "/assets/march_stdlib.js?v=" + ver, function () {
      loadScript(base + "/assets/march.js?v=" + ver, function () {
        bundleLoaded  = true;
        bundleLoading = false;
        loadingEl.textContent = "Ready.";
        setTimeout(function () { loadingEl.textContent = ""; }, 1500);
        callback();
        if (pendingCode) { var cb = pendingCode; pendingCode = null; cb(); }
      }, function () {
        bundleLoading = false;
        loadingEl.textContent = "Failed to load interpreter.";
      });
    }, function () {
      // stdlib failed — try loading the interpreter anyway (REPL will work without stdlib)
      loadScript(base + "/assets/march.js?v=" + ver, function () {
        bundleLoaded  = true;
        bundleLoading = false;
        loadingEl.textContent = "Ready (no stdlib).";
        setTimeout(function () { loadingEl.textContent = ""; }, 1500);
        callback();
        if (pendingCode) { var cb = pendingCode; pendingCode = null; cb(); }
      }, function () {
        bundleLoading = false;
        loadingEl.textContent = "Failed to load interpreter.";
      });
    });
  }

  /* ------------------------------------------------------------------ */
  /* Append output to history                                            */
  /* ------------------------------------------------------------------ */
  function appendLine(text, cssClass) {
    var entry = document.createElement("div");
    entry.className = "pg-entry";
    var span = document.createElement("span");
    span.className = cssClass;
    span.textContent = text;
    entry.appendChild(span);
    historyEl.appendChild(entry);
    historyEl.scrollTop = historyEl.scrollHeight;
  }

  function appendInput(code) {
    code.split("\n").forEach(function (line, i) {
      var entry = document.createElement("div");
      entry.className = "pg-entry";
      var span = document.createElement("span");
      if (i === 0) {
        span.className = "pg-input-line";
        span.textContent = line;
      } else {
        span.style.color = "#6b7280";
        span.textContent = "      " + line;
      }
      entry.appendChild(span);
      historyEl.appendChild(entry);
    });
    historyEl.scrollTop = historyEl.scrollHeight;
  }

  /* ------------------------------------------------------------------ */
  /* Submit code                                                         */
  /* ------------------------------------------------------------------ */
  function submitCode(code) {
    if (!code.trim()) return;

    if (inputHistory[0] !== code) inputHistory.unshift(code);
    if (inputHistory.length > 50) inputHistory.pop();
    historyIdx = -1;

    appendInput(code);
    inputEl.value = "";
    autoResize();

    var trimmed = code.trim();

    if (trimmed === ":reset") {
      if (bundleLoaded && window.marchResetSession) {
        window.marchResetSession();
      }
      historyEl.innerHTML = "";
      appendLine("Session reset.", "pg-info");
      return;
    }

    if (trimmed === ":help" || trimmed === "h()") {
      var helpLines = [
        "March REPL — quick reference",
        "",
        "Commands:",
        "  :reset        clear session and history",
        "  :help / h()   show this message",
        "",
        "Syntax hints:",
        "  let x = 42                  bind a value",
        "  fn double(n) do n * 2 end   define a function",
        "  List.map([1,2,3], fn x -> x * 2)   map over a list",
        "  if cond do expr else expr end       conditional",
        "  match val do Pat -> expr end        pattern match",
        "",
        "Use Shift+Enter for multi-line input, Enter to run.",
        "Click the chips above to load examples."
      ];
      helpLines.forEach(function (line) {
        appendLine(line || "\u00a0", "pg-info");
      });
      return;
    }

    loadBundle(function () {
      if (!window.marchEvalLine) {
        appendLine("Interpreter not available.", "pg-error");
        return;
      }

      // h(name) — stdlib documentation lookup
      var helpMatch = trimmed.match(/^h\((\w+)\)$/);
      if (helpMatch) {
        var fnName = helpMatch[1];
        var hits   = searchStdlib(fnName);
        if (hits.length === 0) {
          appendLine("No stdlib docs found for '" + fnName + "'.", "pg-error");
          appendLine("Tip: try h() for general help, or check the docs.", "pg-info");
        } else {
          hits.forEach(function (entry) {
            var header = entry.mod + "." + fnName;
            if (entry.doc) header += " — " + entry.doc;
            appendLine(header, "pg-info");
            appendLine("  " + entry.sig, "pg-output");
          });
        }
        return;
      }

      var result = window.marchEvalLine(code);
      if (result.output && result.output.trim()) {
        appendLine(result.output.trimEnd(), "pg-output");
      }
      if (result.error !== null) {
        appendLine(result.error, "pg-error");
      }
    });
  }

  /* ------------------------------------------------------------------ */
  /* Auto-resize textarea                                                */
  /* ------------------------------------------------------------------ */
  function autoResize() {
    inputEl.style.height = "auto";
    inputEl.style.height = inputEl.scrollHeight + "px";
  }

  /* ------------------------------------------------------------------ */
  /* Input event handlers                                                */
  /* ------------------------------------------------------------------ */
  inputEl.addEventListener("keydown", function (e) {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      submitCode(inputEl.value);
    } else if (e.key === "ArrowUp" && !e.shiftKey) {
      if (inputHistory.length > 0) {
        historyIdx = Math.min(historyIdx + 1, inputHistory.length - 1);
        inputEl.value = inputHistory[historyIdx];
        autoResize();
        setTimeout(function () {
          inputEl.selectionStart = inputEl.selectionEnd = inputEl.value.length;
        }, 0);
        e.preventDefault();
      }
    } else if (e.key === "ArrowDown" && !e.shiftKey) {
      if (historyIdx > 0) {
        historyIdx--;
        inputEl.value = inputHistory[historyIdx];
      } else {
        historyIdx = -1;
        inputEl.value = "";
      }
      autoResize();
      e.preventDefault();
    } else {
      if (!bundleLoaded && !bundleLoading) {
        loadBundle(function () {});
      }
    }
  });

  inputEl.addEventListener("input", autoResize);

  /* ------------------------------------------------------------------ */
  /* Public helpers (called by onclick attrs in playground.html)         */
  /* ------------------------------------------------------------------ */
  window.pgLoad = function (code) {
    var txt = document.createElement("textarea");
    txt.innerHTML = code;
    inputEl.value = txt.value;
    autoResize();
    inputEl.focus();
  };

  window.pgSubmit = function () {
    submitCode(inputEl.value);
  };

  window.pgReset = function () {
    submitCode(":reset");
  };

  // Start loading the bundle immediately on page load
  window.addEventListener("load", function () {
    loadBundle(function () {});
  });
})();
