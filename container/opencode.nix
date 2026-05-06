{
  pkgs,
  vars,
  ...
}: {
  environment.systemPackages = [
    pkgs.opencode
  ];

  # https://opencode.ai/docs/config
  systemd.tmpfiles.rules = let
    opencodeJson = pkgs.writeText "opencode.json" (builtins.toJSON {
      autoupdate = false;
      provider = {
        scaleway = {
          options = {
            # Magenta's "AI" Scaleway project
            baseURL = "https://api.scaleway.ai/594a268d-8577-4b86-a983-be375e13e197/v1";
          };
        };
      };
    });
  in [
    "L+ /root/.config/opencode/AGENTS.md - - - - ${vars.AGENTS_md}"
    "L+ /root/.config/opencode/opencode.json - - - - ${opencodeJson}"
  ];

  fileSystems."/root/.local/share/opencode" = {
    device = "/persist/root/.local/share/opencode";
    fsType = "none";
    options = ["bind"];
  };
  fileSystems."/root/.local/state/opencode" = {
    device = "/persist/root/.local/state/opencode";
    fsType = "none";
    options = ["bind"];
  };
}
