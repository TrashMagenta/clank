{
  pkgs,
  vars,
  ...
}: {
  # Cringe
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (pkgs.lib.getName pkg) [
      "claude-code"
    ];

  environment.systemPackages = [
    (pkgs.claude-code.overrideAttrs (previousAttrs: {
      # The most upvoted issue on Claude Code: "Feature Request: Support
      # AGENTS.md", i.e. "stop requiring me to put ads for Anthropic in my
      # repo". Don't let them win.
      # https://github.com/anthropics/claude-code/issues/6235
      postInstall = ''
        ${previousAttrs.postInstall or ""}
        # Claude Code is a binary file, but luckily the strings `CLAUDE.md` and
        # `AGENTS.md` are of the same length 😎
        sed -i -e 's/CLAUDE\.md/AGENTS\.md/g' $out/bin/.claude-wrapped
      '';
    }))
  ];

  # https://code.claude.com/docs/en/settings
  systemd.tmpfiles.rules = let
    claudeJson = pkgs.writeText "claude.json" (builtins.toJSON {
      # Claude Code asks us to log in during onboarding. We may want to use
      # CLAUDE_CODE_OAUTH_TOKEN instead.
      hasCompletedOnboarding = true;
      # Always trust the mounted host volume
      projects = {
        "/root/host" = {
          hasTrustDialogAccepted = true;
        };
      };
    });
    settingsJson = pkgs.writeText "settings.json" (builtins.toJSON {
      # Disable commercials in git commits
      attribution = {
        commit = "";
        pr = "";
      };
      env = {
        # Allow bypassPermissions as root
        # https://github.com/anthropics/claude-code/issues/3490
        IS_SANDBOX = "1";
        # DISABLE_AUTOUPDATER, DISABLE_BUG_COMMAND,
        # DISABLE_ERROR_REPORTING and DISABLE_TELEMETRY.
        CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
      };
      # Default to the best model
      model = "opus";
      # yolo
      permissions.defaultMode = "bypassPermissions";
      skipDangerousModePermissionPrompt = true;
    });
  in [
    "C /root/.claude.json 0600 root root - ${claudeJson}"
    "C /root/.claude/settings.json 0600 root root - ${settingsJson}"
    # We must use AGENTS.md, rather than CLAUDE.md, since we patched the binary
    "L+ /root/.claude/AGENTS.md - - - - ${vars.AGENTS_md}"
  ];

  # https://code.claude.com/docs/en/claude-directory#application-data
  fileSystems."/root/.claude" = {
    device = "/persist/root/.claude";
    fsType = "none";
    options = ["bind"];
  };
}
