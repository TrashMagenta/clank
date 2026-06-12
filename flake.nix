{
  description = "clank";

  inputs = {
    nixpkgs = {
      url = "github:NixOS/nixpkgs/nixos-unstable";
    };
    # The proxies run by the proxy sidecar (see ./proxy-sidecar). Each flake
    # ships a NixOS module defining its systemd service.
    cred-sidecar = {
      url = "github:TrashMagenta/cred-sidecar";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    git-proxy-ai = {
      url = "github:TrashMagenta/git-proxy-ai";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    cred-sidecar,
    git-proxy-ai,
  }: let
    forAllSystems = nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed;
  in {
    # `nix fmt`
    formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);

    # `nix build` / `nix run` / `nix shell`
    packages = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      container = nixpkgs.lib.nixosSystem {
        system = system;
        modules = [./container];
      };

      # The proxy sidecar: a second NixOS system booted in the same podman
      # pod as clank when CLANK_PROXY is set. It holds the git.magenta.dk
      # credentials and runs the proxies as systemd services; the sandbox
      # only ever sees http://localhost:<port>.
      proxy-sidecar = nixpkgs.lib.nixosSystem {
        system = system;
        modules = [
          cred-sidecar.nixosModules.default
          git-proxy-ai.nixosModules.default
          ./proxy-sidecar
        ];
      };

      clank = pkgs.python3Packages.buildPythonApplication {
        pname = "clank";
        version = "0.0.1";
        pyproject = true;

        src = ./.;

        build-system = [pkgs.python3Packages.setuptools];

        doCheck = false; # has no tests, of course

        dependencies = [
          pkgs.podman
        ];

        makeWrapperArgs = builtins.concatLists [
          ["--set" "CLANK_EMPTY_DIRECTORY" "${pkgs.emptyDirectory}"]
          ["--set" "CLANK_ROOT" self.packages.${system}.container.config.system.build.toplevel]
          ["--set" "CLANK_PROXY_ROOT" self.packages.${system}.proxy-sidecar.config.system.build.toplevel]
        ];
      };
      default = self.packages.${system}.clank;
    });
  };
}
