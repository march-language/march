// March debug extension for VS Code.
//
// The entire debugger is implemented server-side by the `march` binary: this
// extension only tells VS Code how to launch the adapter (`march dap`, speaking
// the Debug Adapter Protocol over stdio). All breakpoint, stepping, stack, and
// variable handling lives in lib/dap + lib/eval.

const vscode = require("vscode");

function activate(context) {
  const factory = {
    createDebugAdapterDescriptor(session) {
      const marchPath = session.configuration.marchPath || "march";
      return new vscode.DebugAdapterExecutable(marchPath, ["dap"]);
    },
  };

  // Fill in `program` with the active file when omitted.
  const provider = {
    resolveDebugConfiguration(_folder, config) {
      if (!config.type && !config.request && !config.name) {
        const editor = vscode.window.activeTextEditor;
        if (editor && editor.document.languageId === "march") {
          config.type = "march";
          config.request = "launch";
          config.name = "Debug March file";
          config.program = "${file}";
        }
      }
      return config;
    },
  };

  context.subscriptions.push(
    vscode.debug.registerDebugAdapterDescriptorFactory("march", factory),
    vscode.debug.registerDebugConfigurationProvider("march", provider)
  );
}

function deactivate() {}

module.exports = { activate, deactivate };
