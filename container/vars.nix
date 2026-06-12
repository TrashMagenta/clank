{pkgs, ...}: {
  _module.args.vars = {
    AGENTS_md = pkgs.writeText "AGENTS.md" ''
      - Run unknown commands using `nix shell nixpkgs#<package>`
      - Avoid writing em-dashes (`—`) in comments or commit messages
      - If $CLANK_CRED_PROXY is set, you can make authenticated GitLab API
        calls without holding a token, e.g.:
        `HTTPS_PROXY=$CLANK_CRED_PROXY SSL_CERT_FILE=$CLANK_CRED_PROXY_CA GITLAB_TOKEN=dummy glab api projects`
      - If $CLANK_GIT_PROXY is set, you can push branches named `ai/*` via
        `git push $CLANK_GIT_PROXY/git.magenta.dk/<group>/<repo>.git ai/<branch>`
    '';
  };
}
