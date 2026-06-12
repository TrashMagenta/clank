{pkgs, ...}: let
  # Both proxies read their credentials from /clank/proxy.env, which the host
  # CLI bind mounts (read-only) from ~/.config/clank/proxy.env into THIS
  # container only; it is never mounted into the sandbox. systemd loads it via
  # EnvironmentFile, so the secrets live in the unit's environment and nowhere
  # else.
  proxyEnv = "/clank/proxy.env";

  # Skip (rather than fail) a proxy whose credential is not configured.
  # ExecCondition runs with the unit's environment (incl. EnvironmentFile);
  # a non-zero exit marks the unit as skipped, so a proxy.env containing only
  # one of the tokens simply starts only the matching proxy.
  requireEnv = name:
    pkgs.writeShellScript "require-${name}" ''
      [ -n "''${${name}:-}" ]
    '';
in {
  # Credential-injecting forward proxy (mitmproxy). The AI opts in per
  # command, e.g.:
  #   HTTPS_PROXY=http://localhost:8080 SSL_CERT_FILE=/clank/sidecar-ca.pem \
  #     glab api projects
  # and the proxy swaps in the real token at the network edge.
  services.cred-sidecar = {
    enable = true;
    mode = "forward";
    # The pod shares one loopback, so the sandbox reaches this on
    # localhost:8080 while nothing outside the pod can.
    listenAddress = "127.0.0.1";
    port = 8080;
    gitlabHost = "git.magenta.dk";
    # Only proxy the host we inject for; the AI is expected to talk to
    # everything else directly (it just has no credentials for it).
    allowedHosts = ["git.magenta.dk"];
    tokenFile = proxyEnv;
  };
  systemd.services.cred-sidecar.serviceConfig.ExecCondition =
    requireEnv "GITLAB_TOKEN";

  # The ai/ push gateway (FINOS GitProxy). The AI pushes to
  #   http://localhost:8000/git.magenta.dk/<group>/<repo>.git
  # and only branches under ai/ on allow-listed repos are forwarded upstream.
  services.git-proxy-ai = {
    enable = true;
    serverPort = 8000;
    # The admin UI defaults to 8080, which collides with cred-sidecar in the
    # shared network namespace.
    uiPort = 8081;
    environmentFile = proxyEnv;
  };
  systemd.services.git-proxy-ai.serviceConfig.ExecCondition =
    requireEnv "UPSTREAM_GIT_TOKEN";
}
