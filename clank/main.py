import os
import shlex
import subprocess
import sys
import time
from pathlib import Path
from tempfile import TemporaryDirectory
from uuid import uuid4

# Passed by buildPythonApplication's makeWrapperArgs in flake.nix
CLANK_EMPTY_DIRECTORY = os.environ["CLANK_EMPTY_DIRECTORY"]
CLANK_ROOT = os.environ["CLANK_ROOT"]
CLANK_PROXY_ROOT = os.getenv("CLANK_PROXY_ROOT")

# Passed by the user
CLANK_PODMAN_OPTS = os.getenv("CLANK_PODMAN_OPTS", default="")
# Set to enable the proxy sidecar: a second NixOS container in the same
# podman pod that holds the git.magenta.dk credentials and runs proxies as
# systemd services. The sandbox reaches them at http://localhost:<port> but
# can never read the credentials (pod members share only the network
# namespace).
CLANK_PROXY = os.getenv("CLANK_PROXY", default="")
# EnvironmentFile with the proxies' credentials (GITLAB_TOKEN and/or
# UPSTREAM_GIT_TOKEN, see proxy-sidecar/proxies.nix). Mounted into the
# sidecar only, never into the sandbox.
CLANK_PROXY_ENV_FILE = os.getenv(
    "CLANK_PROXY_ENV_FILE", default="~/.config/clank/proxy.env"
)
# In pod mode, network flags like `--publish` must be set on the pod itself,
# not on individual containers; use this env var to add them.
CLANK_POD_OPTS = os.getenv("CLANK_POD_OPTS", default="")


def cli() -> None:
    with TemporaryDirectory() as tmp:
        main(Path(tmp))


def main(tmp: Path) -> None:
    pod_name = f"clank-pod-{uuid4()}" if CLANK_PROXY else None

    # Prime the podman pause process to avoid AppArmor errors due to user
    # namespace creation. Dumb workaround for
    # https://github.com/containers/podman/issues/24642.
    subprocess.run(["podman", "unshare", "true"])

    try:
        if pod_name:
            start_proxy_sidecar(tmp, pod_name)
        run_container(tmp, pod_name)
    finally:
        if pod_name:
            subprocess.run(
                ["podman", "pod", "rm", "--force", pod_name],
                check=False,
            )


def parse_env_keys(env_file: Path) -> set[str]:
    """The keys with a non-empty value in an EnvironmentFile."""
    keys = set()
    for line in env_file.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        if value.strip().strip("'\""):
            keys.add(key.strip())
    return keys


def start_proxy_sidecar(tmp: Path, pod_name: str) -> None:
    if not CLANK_PROXY_ROOT:
        sys.exit("clank: CLANK_PROXY is set but CLANK_PROXY_ROOT is not")
    env_file = Path(CLANK_PROXY_ENV_FILE).expanduser()
    if not env_file.is_file():
        sys.exit(f"clank: CLANK_PROXY is set but {env_file} does not exist")
    configured = parse_env_keys(env_file)

    subprocess.run(
        [
            "podman",
            "pod",
            "create",
            f"--name={pod_name}",
            *shlex.split(CLANK_POD_OPTS),
        ],
        check=True,
    )

    sidecar = f"{pod_name}-proxies"
    subprocess.run(
        [
            "podman",
            "run",
            "--rm",
            "--detach",
            f"--pod={pod_name}",
            f"--name={sidecar}",
            # The proxy services use systemd sandboxing (ProtectSystem etc.),
            # which needs more capabilities than rootless podman grants by
            # default. Privileged is what the clank sandbox itself runs with.
            "--privileged",
            "--security-opt=label=disable",
            "--security-opt=apparmor=unconfined",
            # Backs /var/tmp, see container/hardware.nix (imported by the
            # sidecar's NixOS configuration).
            "--volume=/disk",
            # The credentials, readable by the sidecar's systemd only.
            f"--volume={env_file}:/clank/proxy.env:ro",
            # Boot NixOS exactly like the sandbox does, see run_container.
            "--mount=type=tmpfs,tmpfs-size=512M,destination=/",
            "--volume=/nix:/nix:ro",
            "--systemd=always",
            "--rootfs",
            f"{CLANK_EMPTY_DIRECTORY}:O",
            f"{CLANK_PROXY_ROOT}/init",
        ],
        check=True,
    )

    # Tell the sandbox which proxies are configured. The shell sources
    # /clank/proxy.sh on login (see container/shell.nix), and the AI opts in
    # per command, e.g. `HTTPS_PROXY=$CLANK_CRED_PROXY glab ...`.
    exports = []
    if "GITLAB_TOKEN" in configured:
        extract_sidecar_ca(sidecar, tmp)
        exports += [
            "export CLANK_CRED_PROXY=http://localhost:8080",
            "export CLANK_CRED_PROXY_CA=/clank/sidecar-ca.pem",
        ]
    if "UPSTREAM_GIT_TOKEN" in configured:
        exports += [
            "export CLANK_GIT_PROXY=http://localhost:8000",
        ]
    tmp.joinpath("proxy.sh").write_text("".join(f"{e}\n" for e in exports))


def extract_sidecar_ca(sidecar: str, tmp: Path) -> None:
    """Copy the cred-sidecar's self-generated CA certificate into /clank.

    mitmproxy generates its CA on first start. The sandbox needs (only) the
    certificate to trust the proxy, e.g. via SSL_CERT_FILE. Poll until the
    sidecar's systemd has booted and the service has written it.
    """
    deadline = time.monotonic() + 60
    while True:
        result = subprocess.run(
            [
                "podman",
                "exec",
                sidecar,
                # podman exec does not get the NixOS PATH, so spell it out
                "/run/current-system/sw/bin/cat",
                "/var/lib/cred-sidecar/mitmproxy-ca-cert.pem",
            ],
            capture_output=True,
        )
        if result.returncode == 0 and b"BEGIN CERTIFICATE" in result.stdout:
            tmp.joinpath("sidecar-ca.pem").write_bytes(result.stdout)
            return
        if time.monotonic() > deadline:
            sys.exit("clank: timed out waiting for the cred-sidecar CA")
        time.sleep(0.5)


def run_container(tmp: Path, pod_name: str | None) -> None:
    command = [
        "podman",
        "run",
        "--rm",
        "-it",
    ]

    if pod_name:
        # Network namespace, hostname and published ports are owned by the
        # pod. The AI reaches the proxies at http://localhost:<port>.
        command.append(f"--pod={pod_name}")
    else:
        command += [
            f"--name=clank-{uuid4()}",
            # Do not create /etc/hostname in the container
            "--no-hostname",
        ]

    command += [
        # Kinda yolo, but you need at least `--device=/dev/fuse`, and
        # `--cap-add=SYS_ADMIN,NET_ADMIN,NET_RAW,mknod` to make podman compose
        # work inside the container anyway. Claude tried to break out for like
        # half an hour without success, so it's probably fine.
        # https://www.redhat.com/en/blog/podman-inside-container,
        "--privileged",
        "--security-opt=label=disable",
        "--security-opt=apparmor=unconfined",
        "--volume=/proc/sys:/proc/sys:rw",
        # Mount the current working directory at the same absolute path inside
        # the container, so absolute paths (e.g. in mounted Python virtual
        # environments) work.
        f"--volume=./:{Path.cwd()}:rw",
        # Root is tmpfs, but some things need to be on disk, or we will quickly
        # run out of ram. Bind mounts are defined in the NixOS configuration.
        "--volume=/disk",
        # Mount a volume shared amongst all Clank instances to /persist. Bind
        # mounts are defined in the NixOS configuration.
        "--volume=clank-persist:/persist",
        # Allow callers to configure Podman
        *shlex.split(CLANK_PODMAN_OPTS),
    ]

    home = Path.home()

    # Mount host's git config to ensure commits are done by the right author
    if home.joinpath(".config/git").exists():
        command += [
            f"--volume={home}/.config/git:/root/.config/git:ro",
        ]

    # We can use the host's images if it also uses Podman
    if home.joinpath(".local/share/containers/storage").exists():
        command += [
            f"--volume={home}/.local/share/containers/storage:/var/lib/shared:ro",
        ]

    # ~/.config/clank.sh is how we inject environment variables into the
    # container since all --env are gobbled by systemd (/init). You could also
    # use it to run arbitrary commands on startup.
    if home.joinpath(".config/clank.sh").exists():
        command += [
            f"--volume={home}/.config/clank.sh:/clank/clank.sh:ro",
        ]

    # Whatever extra arguments were given on the command line are run in the
    # container, e.g. `clank opencode --model=scaleway/qwen3.5-397b-a17b`. We
    # have to do it in this roundabout way because the command argument to
    # `podman run` has to be systemd (/init).
    tmp.joinpath("command").write_text(shlex.join(sys.argv[1:]))
    tmp.joinpath("cwd").write_text(str(Path.cwd()))
    command += [
        f"--volume={tmp}:/clank:ro",
    ]

    command += [
        # NixOS just needs an /init and /nix/store to start, so we mount an
        # empty tmpfs on / and bind mount the host's /nix. /init symlinks the
        # required files from /nix/store into / and starts systemd.
        "--mount=type=tmpfs,tmpfs-size=512M,destination=/",
        "--volume=/nix:/nix:ro",
        "--systemd=always",
        # Podman won't run without a container image, but `--rootfs` tells it
        # to use the empty directory as container file system instead. Podman
        # apparently creates a symlink `/etc/mtab -> /proc/mounts` *before* the
        # tmpfs root is mounted. This fails because CLANK_EMPTY_DIRECTORY is in
        # /nix/store and thus read-only. :O mounts it as an overlay on tmpfs,
        # which makes it writable.
        "--rootfs",
        f"{CLANK_EMPTY_DIRECTORY}:O",
        f"{CLANK_ROOT}/init",
    ]

    try:
        subprocess.run(command, check=True)
    except subprocess.CalledProcessError as e:
        # The systemd init process exits with status code 130 when properly
        # powered off.
        if e.returncode not in (0, 130):
            raise
