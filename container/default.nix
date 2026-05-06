{lib, ...}: {
  imports = [
    ./claude.nix
    ./hardware.nix
    ./opencode.nix
    ./podman.nix
    ./shell.nix
    ./vars.nix
  ];

  # Disable unneeded services
  networking.dhcpcd.enable = false;
  networking.firewall.enable = false;
  systemd.oomd.enable = false;

  networking.hostName = "clank";

  nix.settings.experimental-features = ["nix-command" "flakes"];

  system.stateVersion = lib.trivial.release; # No need to read any comments!
}
