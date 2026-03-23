use zed_extension_api::{self as zed, LanguageServerId, Result, Worktree, settings::LspSettings};

struct MarchExtension;

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
}

zed::register_extension!(MarchExtension);
