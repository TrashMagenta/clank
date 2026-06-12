{lib, ...}: {
  # A single sidecar NixOS system that runs credential-holding proxies as
  # systemd services next to the clank sandbox, in the same podman pod. Pod
  # members share only the network namespace, so the AI reaches the proxies
  # at http://localhost:<port> but cannot read their environment, files or
  # processes: the credentials never exist inside the sandbox.
  #
  # It boots exactly like the sandbox does (tmpfs /, host /nix, /init), see
  # clank/main.py. The proxy services themselves are defined by the NixOS
  # modules shipped with the cred-sidecar and git-proxy-ai flakes; they are
  # imported in flake.nix and configured in ./proxies.nix.
  imports = [
    ../container/hardware.nix
    ./proxies.nix
  ];

  # Disable unneeded services
  networking.dhcpcd.enable = false;
  networking.firewall.enable = false;
  systemd.oomd.enable = false;

  networking.hostName = "clank-proxies";

  system.stateVersion = lib.trivial.release; # No need to read any comments!
}
