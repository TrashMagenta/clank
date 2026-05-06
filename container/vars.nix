{pkgs, ...}: {
  _module.args.vars = {
    AGENTS_md = pkgs.writeText "AGENTS.md" ''
      Run unknown commands using `nix shell nixpkgs#<package>`
    '';
  };
}
