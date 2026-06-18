/* playground.js — thin config wrapper around MarchRepl (march-repl.js) */
(function () {
  "use strict";

  var repl = new MarchRepl({
    wrapId:    "pg-wrap",
    historyId: "pg-history",
    inputId:   "pg-input",
    loadingId: "pg-loading-msg",
    cls: {
      entry:     "pg-entry",
      inputLine: "pg-input-line",
      output:    "pg-output",
      error:     "pg-error",
      info:      "pg-info"
    }
  });

  window.pgLoad     = function (code)        { repl.load(code); };
  window.pgLoadThen = function (setup, code) { repl.loadThen(setup, code); };
  window.pgSubmit   = function ()            { repl.submit(); };
  window.pgReset    = function ()            { repl.reset(); };
})();
