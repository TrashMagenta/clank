{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.coreutils
    pkgs.git
    pkgs.jq
  ];

  # Unlike SSH, these variables aren't passed from the host terminal, so
  # everything is ugly by default.
  environment.variables = {
    COLORTERM = "truecolor";
    TERM = "xterm-256color";
  };

  programs.fish = {
    enable = true;
    generateCompletions = false; # *really* slow
    shellInit =
      # fish
      ''
        # Don't greet the user
        set fish_greeting
      '';
    loginShellInit =
      # fish
      ''
        # Load environment variables mounted from the host's ~/.config/clank.sh
        if test -s /clank/clank.sh
          source /clank/clank.sh
        end
        # Load the proxy sidecar's addresses, written by the host CLI when
        # CLANK_PROXY is set (see clank/main.py)
        if test -s /clank/proxy.sh
          source /clank/proxy.sh
        end
        # Enter the mounted host directory
        cd (cat /clank/cwd)
        # Run command if given as extra arguments on the command line.
        # Terminals spawned in OpenCode Web also run as login shells, so we use
        # a marker to avoid running the command in those.
        if test -s /clank/command; and not test -e /run/clank-avoid-recursion
          touch /run/clank-avoid-recursion
          exec sh /clank/command
        end
      '';
  };

  # Automatically log in as root
  users = {
    mutableUsers = false;
    users.root = {
      password = "";
      shell = pkgs.fish;
    };
  };
  services.getty.autologinUser = "root";

  # Exit the container when the shell exits -- otherwise you will be stuck in
  # an auto-login loop on CTRL-D.
  systemd.services."console-getty" = {
    unitConfig = {
      SuccessAction = "poweroff-immediate";
      FailureAction = "poweroff-immediate";
    };
  };

  programs.vim = {
    enable = true;
    defaultEditor = true;
  };

  # Persist fish history for a nicer experience
  fileSystems."/root/.local/share/fish" = {
    device = "/persist/root/.local/share/fish";
    fsType = "none";
    options = ["bind"];
  };
  # Persist e.g. pre-commit and poetry cache
  fileSystems."/root/.cache" = {
    device = "/persist/root/.cache";
    fsType = "none";
    options = ["bind"];
  };
}
