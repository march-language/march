use zed_extension_api::{
    self as zed, DebugAdapterBinary, DebugConfig, DebugRequest, DebugScenario,
    DebugTaskDefinition, LanguageServerId, Result, StartDebuggingRequestArguments,
    StartDebuggingRequestArgumentsRequest, Worktree, settings::LspSettings,
};

struct MarchExtension;

impl MarchExtension {
    /// Resolve the path to the `march` binary (the debug adapter runs
    /// `march dap`). Honours a user-provided override, else falls back to PATH.
    fn march_binary(user_provided: Option<String>) -> String {
        user_provided.unwrap_or_else(|| "march".to_string())
    }
}

impl zed::Extension for MarchExtension {
    fn new() -> Self {
        MarchExtension
    }

    fn language_server_command(
        &mut self,
        _language_server_id: &LanguageServerId,
        worktree: &Worktree,
    ) -> Result<zed::Command> {
        let path = LspSettings::for_worktree("march-lsp", worktree)
            .ok()
            .and_then(|s| s.binary)
            .and_then(|b| b.path)
            .unwrap_or_else(|| "march-lsp".to_string());

        Ok(zed::Command {
            command: path,
            args: vec![],
            env: vec![],
        })
    }

    // ---- Debug Adapter Protocol ------------------------------------------

    /// Launch the March DAP server (`march dap`, stdio transport). The
    /// adapter-agnostic `config.config` JSON (program / stopOnEntry) is passed
    /// straight through as the DAP `launch` request arguments.
    fn get_dap_binary(
        &mut self,
        _adapter_name: String,
        config: DebugTaskDefinition,
        user_provided_debug_adapter_path: Option<String>,
        _worktree: &Worktree,
    ) -> Result<DebugAdapterBinary, String> {
        Ok(DebugAdapterBinary {
            command: Some(Self::march_binary(user_provided_debug_adapter_path)),
            arguments: vec!["dap".to_string()],
            envs: vec![],
            cwd: None,
            connection: None, // stdio transport
            request_args: StartDebuggingRequestArguments {
                configuration: config.config,
                request: StartDebuggingRequestArgumentsRequest::Launch,
            },
        })
    }

    /// The March debugger only launches programs (no attach).
    fn dap_request_kind(
        &mut self,
        _adapter_name: String,
        _config: zed::serde_json::Value,
    ) -> Result<StartDebuggingRequestArgumentsRequest, String> {
        Ok(StartDebuggingRequestArgumentsRequest::Launch)
    }

    /// Turn the new-session UI's generic config into a March debug scenario.
    fn dap_config_to_scenario(&mut self, config: DebugConfig) -> Result<DebugScenario, String> {
        let launch = match config.request {
            DebugRequest::Launch(launch) => launch,
            DebugRequest::Attach(_) => {
                return Err("The March debugger supports launch only.".to_string());
            }
        };
        let configuration = zed::serde_json::json!({
            "program": launch.program,
            "args": launch.args,
            "cwd": launch.cwd,
            "stopOnEntry": config.stop_on_entry.unwrap_or(false),
        });
        Ok(DebugScenario {
            label: config.label,
            adapter: config.adapter,
            build: None,
            config: configuration.to_string(),
            tcp_connection: None,
        })
    }
}

zed::register_extension!(MarchExtension);
