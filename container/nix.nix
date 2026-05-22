{...}: {
  nix.settings.experimental-features = ["nix-command" "flakes"];

  # Run unpatched dynamic binaries on NixOS. Useful to run e.g. `ruff`
  # installed in a Python virtual environment.
  # https://github.com/nix-community/nix-ld
  programs.nix-ld.enable = true;
}
