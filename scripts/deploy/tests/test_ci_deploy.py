"""Hermetic tests for scripts/deploy/ci-deploy.sh, the forced command of Folio's CI deploy key.

Each test runs the real script from a temporary copy of the host layout: a stand-in for
/opt/folio/scripts/ holding ci-deploy.sh (a symlink to the file under test), a stub deploy-runner.sh
and the other host files, with both compose files one level up. Stub `docker` and `logger`
executables come first on PATH, so nothing here touches a Docker daemon, a registry, the network or
the system journal.

sshd gives a forced command the client's request in SSH_ORIGINAL_COMMAND (unset for a plain shell
request) and invokes it as `<login shell> -c <command>`; the tests do both exactly the same way. On
this host no other client-controlled variable gets through except the AcceptEnv ones (LANG, LC_*,
COLORTERM, NO_COLOR), because PermitUserEnvironment is off.

ci-deploy.sh starts every child with `env -i`, so the stubs can't be told through the environment
where to record their calls: each one finds the shared state directory from its own location.

Run with: uvx pytest scripts/deploy/tests
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import stat
import subprocess
import textwrap
from dataclasses import dataclass
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[3]
CI_DEPLOY_SH = REPO / "scripts" / "deploy" / "ci-deploy.sh"
WORKFLOWS = {
    "api": REPO / ".github" / "workflows" / "deploy-backend.yml",
    "frontend": REPO / ".github" / "workflows" / "deploy-frontend.yml",
}
REGISTRY = "europe-west1-docker.pkg.dev"

SHA = "a" * 40
SHORT_SHA = "abc1234"
TOKEN = "ya29.stub-registry-token"  # a fixed test fixture value, never a real credential

# The host files in the order ci-deploy.sh hashes them: (path under /opt/folio, repository path).
HOST_FILES = [
    ("scripts/ci-deploy.sh", "scripts/deploy/ci-deploy.sh"),
    ("scripts/deploy-runner.sh", "scripts/deploy/deploy-runner.sh"),
    ("scripts/wait-healthy.sh", "scripts/deploy/wait-healthy.sh"),
    ("scripts/rollback.sh", "scripts/deploy/rollback.sh"),
    ("docker-compose.yml", "docker-compose.yml"),
    ("docker-compose.prod.yml", "docker-compose.prod.yml"),
]

STUB_DOCKER = r'''#!/usr/bin/env python3
"""Stand-in for `docker`: records each call (argv and environment) and handles only
`--config DIR login ...`, which reads the password from stdin and writes DIR/config.json."""
import json
import os
import sys
from pathlib import Path

state = Path(__file__).resolve().parent.parent / "state"
argv = sys.argv[1:]
with (state / "docker.calls").open("a") as fh:
    fh.write(json.dumps({"argv": argv, "env": dict(os.environ)}) + "\n")
if len(argv) >= 3 and argv[0] == "--config" and argv[2] == "login":
    (state / "login.stdin").write_text(sys.stdin.read())
    exit_file = state / "login-exit"
    code = int(exit_file.read_text()) if exit_file.exists() else 0
    if code == 0:
        Path(argv[1], "config.json").write_text(json.dumps({"auths": {argv[-1]: {"auth": "stub"}}}))
    sys.exit(code)
print(f"stub docker: unhandled invocation: {argv}", file=sys.stderr)
sys.exit(1)
'''

STUB_RUNNER = r'''#!/usr/bin/env python3
"""Stand-in for the owner-installed deploy-runner.sh: records its argv, environment and stdin, and
the Docker config it was handed, then exits with the code in state/runner-exit (0 when absent)."""
import json
import os
import sys
from pathlib import Path

state = Path(__file__).resolve().parent.parent.parent / "state"
cfg = os.environ.get("DOCKER_CONFIG", "")
config = Path(cfg, "config.json") if cfg else None
record = {
    "argv": sys.argv[1:],
    "env": dict(os.environ),
    "stdin": sys.stdin.read(),
    "cfg_mode": oct(os.stat(cfg).st_mode & 0o777) if cfg and os.path.isdir(cfg) else None,
    "logged_in": bool(config and config.exists() and "europe-west1-docker.pkg.dev" in config.read_text()),
}
(state / "runner.json").write_text(json.dumps(record))
print("deploy-runner stub ran")
exit_file = state / "runner-exit"
sys.exit(int(exit_file.read_text()) if exit_file.exists() else 0)
'''

# Stand-in for util-linux `logger`: ci-deploy.sh always passes the message as arguments. It runs in
# ci-deploy.sh's own environment, so the locale it records is the one the request was matched under.
STUB_LOGGER = r'''#!/usr/bin/env bash
state="$(dirname "$0")/../state"
printf '%s\n' "$*" >> "$state/logger.calls"
printf '%s\n' "${LC_ALL-<unset>}" >> "$state/logger.locale"
'''


def _write_executable(path: Path, content: str) -> None:
    path.write_text(content)
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


@dataclass
class Harness:
    """Runs ci-deploy.sh the way sshd does, from a temporary host layout."""

    bin_dir: Path
    state_dir: Path
    host_dir: Path  # stands in for /opt/folio

    @property
    def script(self) -> Path:
        return self.host_dir / "scripts" / "ci-deploy.sh"

    def host_files_sha256(self) -> str:
        digest = hashlib.sha256()
        for host_path, _ in HOST_FILES:
            digest.update((self.host_dir / host_path).read_bytes())
        return digest.hexdigest()

    def request(self, svc: str = "api", sha: str = SHA, files_sha256: str | None = None) -> str:
        return f"deploy {svc} {sha} {files_sha256 or self.host_files_sha256()}"

    def env(self, ssh_command: str | None, extra: dict[str, str] | None = None) -> dict[str, str]:
        env = dict(os.environ)
        env.pop("SSH_ORIGINAL_COMMAND", None)
        env["PATH"] = f"{self.bin_dir}{os.pathsep}{env.get('PATH', '')}"
        env.update(extra or {})
        if ssh_command is not None:
            env["SSH_ORIGINAL_COMMAND"] = ssh_command
        return env

    def run(
        self, ssh_command: str | None, stdin: str = "", extra_env: dict[str, str] | None = None
    ) -> subprocess.CompletedProcess:
        return subprocess.run(
            ["bash", "-c", str(self.script)],
            env=self.env(ssh_command, extra_env),
            input=stdin,
            text=True,
            capture_output=True,
            timeout=10,
            check=False,
        )

    def docker_calls(self) -> list[dict]:
        p = self.state_dir / "docker.calls"
        return [json.loads(line) for line in p.read_text().splitlines()] if p.exists() else []

    def runner(self) -> dict | None:
        p = self.state_dir / "runner.json"
        return json.loads(p.read_text()) if p.exists() else None

    def log_lines(self) -> list[str]:
        p = self.state_dir / "logger.calls"
        return p.read_text().splitlines() if p.exists() else []

    def logger_locales(self) -> list[str]:
        p = self.state_dir / "logger.locale"
        return p.read_text().splitlines() if p.exists() else []


@pytest.fixture
def harness(tmp_path: Path) -> Harness:
    bin_dir, state_dir, host_dir = tmp_path / "bin", tmp_path / "state", tmp_path / "opt-folio"
    for d in (bin_dir, state_dir, host_dir / "scripts"):
        d.mkdir(parents=True)
    # On the host ci-deploy.sh sits next to deploy-runner.sh and finds every host file from its own
    # path, so the file under test is linked into the same layout. Every stand-in differs, so a
    # change in the hashing order changes the hash too.
    (host_dir / "scripts" / "ci-deploy.sh").symlink_to(CI_DEPLOY_SH)
    _write_executable(host_dir / "scripts" / "deploy-runner.sh", STUB_RUNNER)
    (host_dir / "scripts" / "wait-healthy.sh").write_text("# wait-healthy.sh stand-in, hashed only\n")
    (host_dir / "scripts" / "rollback.sh").write_text("# rollback.sh stand-in, hashed only\n")
    (host_dir / "docker-compose.yml").write_text("# docker-compose.yml stand-in\nservices: {}\n")
    (host_dir / "docker-compose.prod.yml").write_text("# docker-compose.prod.yml stand-in\nservices: {}\n")
    _write_executable(bin_dir / "docker", STUB_DOCKER)
    _write_executable(bin_dir / "logger", STUB_LOGGER)
    return Harness(bin_dir=bin_dir, state_dir=state_dir, host_dir=host_dir)


# <H> is replaced by the harness's real host-files sha256 (<HU>: the same, uppercased), so each case
# differs from a valid request only in what its id names. Every case also sends a valid token, so a
# refusal can only come from the grammar.
REFUSED_COMMANDS = [
    pytest.param(None, id="shell-request"),
    pytest.param("", id="empty"),
    pytest.param("id", id="id"),
    pytest.param("cat /opt/atelier/.env", id="read-another-apps-secrets"),
    pytest.param("deploy", id="deploy-alone"),
    pytest.param("deploy api", id="no-sha"),
    pytest.param(f"deploy api {SHA}", id="no-host-files-sha256"),
    pytest.param(f"deploy worker {SHA} <H>", id="worker-service"),
    pytest.param(f"deploy ai-browser {SHA} <H>", id="ai-browser-service"),
    pytest.param(f"deploy API {SHA} <H>", id="uppercase-service"),
    pytest.param(f"deploy api {'a' * 6} <H>", id="6-hex-sha"),
    pytest.param(f"deploy api {'a' * 41} <H>", id="41-hex-sha"),
    pytest.param(f"deploy api {'A' * 40} <H>", id="uppercase-sha"),
    pytest.param(f"deploy api {'g' * 40} <H>", id="non-hex-sha"),
    pytest.param(f"deploy api {SHA} {'a' * 63}", id="63-hex-files-sha256"),
    pytest.param(f"deploy api {SHA} <H>a", id="65-hex-files-sha256"),
    pytest.param(f"deploy api {SHA} <HU>", id="uppercase-files-sha256"),
    pytest.param(f"deploy api {SHA} <H>\n", id="newline-suffixed"),
    pytest.param(f" deploy api {SHA} <H>", id="leading-space"),
    pytest.param(f"deploy api {SHA} <H> ", id="trailing-space"),
    pytest.param(f"deploy  api {SHA} <H>", id="double-space"),
    pytest.param(f"deploy\tapi\t{SHA}\t<H>", id="tab-separated"),
    pytest.param(f"deploy api {SHA} <H>; id", id="semicolon-payload"),
    pytest.param(f"deploy api {SHA} <H> && id", id="and-payload"),
    pytest.param(f"deploy api {SHA} <H>\nid", id="second-line-payload"),
    pytest.param("deploy api $(id) <H>", id="command-substitution"),
    pytest.param("deploy api `id` <H>", id="backticks"),
    # What the workflows sent before this key was restricted: none of it may pass any more.
    pytest.param("rm -rf '/tmp/folio-deploy-1' && mkdir -p '/tmp/folio-deploy-1'", id="old-stage-dir"),
    pytest.param(f"docker login -u oauth2accesstoken --password-stdin {REGISTRY}", id="old-docker-login"),
    pytest.param(
        f"/opt/folio/scripts/deploy-runner.sh '{SHA}' api; rc=$?; "
        f"docker logout {REGISTRY} >/dev/null 2>&1 || true; exit $rc",
        id="old-deploy-runner-call",
    ),
    # File transfer: the sftp subsystem as sshd reports it, legacy scp in both directions, rsync.
    pytest.param("/usr/lib/openssh/sftp-server", id="sftp-subsystem"),
    pytest.param("internal-sftp", id="internal-sftp"),
    pytest.param("scp -t /opt/folio/scripts/", id="scp-upload"),
    pytest.param("scp -f /opt/atelier/.env", id="scp-download"),
    pytest.param("rsync --server -logDtpre.iLsfxCIvu . /opt/folio/", id="rsync-upload"),
]


@pytest.mark.parametrize("command", REFUSED_COMMANDS)
def test_refuses_everything_but_a_well_formed_deploy(harness, command):
    if command is not None:
        files_sha256 = harness.host_files_sha256()
        command = command.replace("<HU>", files_sha256.upper()).replace("<H>", files_sha256)

    result = harness.run(command, stdin=f"{TOKEN}\n")

    assert result.returncode == 2, result.stderr
    assert result.stderr.splitlines()[-1] == "rejected: unexpected command"
    assert "-t folio-ci-deploy -- rejected: unexpected command" in harness.log_lines()
    assert harness.docker_calls() == []
    assert harness.runner() is None


@pytest.mark.parametrize("svc", ["api", "frontend"])
def test_deploys_through_a_throwaway_registry_login(harness, svc):
    result = harness.run(harness.request(svc), stdin=f"{TOKEN}\n")

    assert result.returncode == 0, result.stderr
    [login] = harness.docker_calls()
    cfg = login["argv"][1]
    assert login["argv"] == ["--config", cfg, "login", "-u", "oauth2accesstoken", "--password-stdin", REGISTRY]
    assert (harness.state_dir / "login.stdin").read_text() == TOKEN
    runner = harness.runner()
    assert runner["argv"] == [SHA, svc]
    assert runner["env"]["DOCKER_CONFIG"] == cfg
    assert runner["logged_in"] is True
    assert runner["cfg_mode"] == "0o700"
    assert not Path(cfg).exists()  # the login is gone once the deploy is over
    assert "deploy-runner stub ran" in result.stdout
    assert f"-t folio-ci-deploy -- accepted: deploy {svc} {SHA}" in harness.log_lines()
    assert f"-t folio-ci-deploy -- deployed {svc} {SHA}" in harness.log_lines()


def test_accepts_a_short_sha_like_the_workflows_do(harness):
    result = harness.run(harness.request(sha=SHORT_SHA), stdin=f"{TOKEN}\n")

    assert result.returncode == 0, result.stderr
    assert harness.runner()["argv"] == [SHORT_SHA, "api"]


def test_the_token_reaches_nothing_but_the_registry_login(harness):
    result = harness.run(harness.request(), stdin=f"{TOKEN}\n")

    assert result.returncode == 0, result.stderr
    assert all(TOKEN not in json.dumps(call) for call in harness.docker_calls())  # argv and environment
    assert TOKEN not in json.dumps(harness.runner())  # argv, environment and stdin
    assert all(TOKEN not in line for line in harness.log_lines())
    assert TOKEN not in result.stdout + result.stderr


# What this host's sshd would forward from a client (AcceptEnv LANG LC_* COLORTERM NO_COLOR), plus
# variables that would redirect Docker or compose if a later sshd change ever let them through.
CLIENT_ENV = {
    "LANG": "tr_TR.UTF-8",
    "LC_ALL": "tr_TR.UTF-8",
    "LC_CTYPE": "tr_TR.UTF-8",
    "COLORTERM": "truecolor",
    "NO_COLOR": "1",
    "DOCKER_HOST": "tcp://203.0.113.1:2375",
    "DOCKER_CONFIG": "/decoy-docker-config",
    "COMPOSE_FILE": "/decoy/compose.yaml",
    "COMPOSE_PROFILES": "assistant",
    "COMPOSE_PROJECT_NAME": "decoy",
    "IMAGE_TAG": "latest",
}


def test_children_get_a_clean_environment(harness):
    result = harness.run(harness.request(), stdin=f"{TOKEN}\n", extra_env=CLIENT_ENV)

    assert result.returncode == 0, result.stderr
    [login] = harness.docker_calls()
    runner = harness.runner()
    for env in (login["env"], runner["env"]):
        assert env["HOME"] == "/root"
        assert env["LC_ALL"] == "C"
        assert "SSH_ORIGINAL_COMMAND" not in env
        leaked = {name for name in CLIENT_ENV if name in env and env[name] == CLIENT_ENV[name]}
        assert leaked == set()
    assert "DOCKER_CONFIG" not in login["env"]  # the login gets its config through --config only
    assert runner["env"]["DOCKER_CONFIG"] == login["argv"][1]


def test_the_request_is_matched_under_the_c_locale_whatever_the_client_sends(harness):
    result = harness.run(
        f"deploy api {'A' * 40} {harness.host_files_sha256()}", stdin=f"{TOKEN}\n", extra_env=CLIENT_ENV
    )

    assert result.returncode == 2, result.stderr
    assert harness.logger_locales() == ["C"]


def test_the_host_layout_comes_from_the_scripts_own_path(harness, tmp_path):
    """deploy-runner.sh and the host files are found next to the script itself. A directory named in
    the environment, under the names a later edit might plausibly read, is never used."""
    decoy = tmp_path / "decoy" / "scripts"
    decoy.mkdir(parents=True)
    _write_executable(decoy / "deploy-runner.sh", '#!/bin/sh\ntouch "$0.ran"\n')
    names = ("DIR", "DEPLOY_DIR", "FOLIO_DIR", "FOLIO_DEPLOY_DIR", "SCRIPTS_DIR")

    result = harness.run(harness.request(), stdin=f"{TOKEN}\n", extra_env={name: str(decoy) for name in names})

    assert result.returncode == 0, result.stderr
    assert harness.runner()["argv"] == [SHA, "api"]
    assert not (decoy / "deploy-runner.sh.ran").exists()


def test_deploy_runner_reads_nothing_the_client_sends_after_the_token(harness):
    result = harness.run(harness.request(), stdin=f"{TOKEN}\nsomething else\nand more\n")

    assert result.returncode == 0, result.stderr
    assert harness.runner()["stdin"] == ""


def test_refuses_when_the_host_files_differ_from_the_workflow(harness):
    workflow_sha256 = harness.host_files_sha256()
    compose = harness.host_dir / "docker-compose.prod.yml"
    compose.write_text(compose.read_text() + "# master changed, not installed on the host yet\n")

    result = harness.run(harness.request(files_sha256=workflow_sha256), stdin=f"{TOKEN}\n")

    assert result.returncode == 2, result.stderr
    last = result.stderr.splitlines()[-1]
    assert last.startswith("rejected: host files differ from the workflow's checkout")
    assert f"host {harness.host_files_sha256()}, workflow {workflow_sha256}" in last
    assert harness.docker_calls() == []
    assert harness.runner() is None


@pytest.mark.parametrize("host_path", [host_path for host_path, _ in HOST_FILES])
def test_every_host_file_is_covered_by_the_check(harness, host_path):
    workflow_sha256 = harness.host_files_sha256()
    target = harness.host_dir / host_path
    drifted = target.read_text() + "# drift\n"
    if target.is_symlink():  # the script under test: replace the link, never write through it
        target.unlink()
        _write_executable(target, drifted)
    else:
        target.write_text(drifted)

    result = harness.run(harness.request(files_sha256=workflow_sha256), stdin=f"{TOKEN}\n")

    assert result.returncode == 2, result.stderr
    assert "rejected: host files differ" in result.stderr
    assert harness.docker_calls() == []


def test_refuses_when_a_host_file_is_missing(harness):
    workflow_sha256 = harness.host_files_sha256()
    (harness.host_dir / "scripts" / "rollback.sh").unlink()

    result = harness.run(harness.request(files_sha256=workflow_sha256), stdin=f"{TOKEN}\n")

    assert result.returncode == 2, result.stderr
    assert result.stderr.splitlines()[-1] == "rejected: host files are missing"
    assert harness.docker_calls() == []


@pytest.mark.parametrize("stdin", [pytest.param("", id="nothing"), pytest.param("\n", id="empty-line")])
def test_refuses_without_a_registry_token(harness, stdin):
    result = harness.run(harness.request(), stdin=stdin)

    assert result.returncode == 2, result.stderr
    assert result.stderr.splitlines()[-1] == "rejected: no registry token on stdin"
    assert harness.docker_calls() == []
    assert harness.runner() is None


def test_the_token_read_is_bounded(harness):
    """A client that connects but never sends the token must not hold a root process open forever:
    the read gives up after its bound. This test genuinely waits that bound out (~15s)."""
    read_end, write_end = os.pipe()  # stays open and empty: never written to, never closed early
    try:
        result = subprocess.run(
            ["bash", "-c", str(harness.script)],
            env=harness.env(harness.request()),
            stdin=read_end,
            capture_output=True,
            text=True,
            timeout=25,
            check=False,
        )
    finally:
        os.close(read_end)
        os.close(write_end)

    assert result.returncode == 2
    assert "rejected: no registry token on stdin" in result.stderr
    assert harness.docker_calls() == []


def test_a_failed_registry_login_stops_before_deploy_runner(harness):
    (harness.state_dir / "login-exit").write_text("1")

    result = harness.run(harness.request(), stdin=f"{TOKEN}\n")

    assert result.returncode == 1
    assert result.stderr.splitlines()[-1] == "registry login failed"
    assert harness.runner() is None
    [login] = harness.docker_calls()
    assert not Path(login["argv"][1]).exists()


def test_a_failed_deploy_keeps_its_exit_code_and_drops_the_login(harness):
    (harness.state_dir / "runner-exit").write_text("3")

    result = harness.run(harness.request(), stdin=f"{TOKEN}\n")

    assert result.returncode == 3
    assert result.stderr.splitlines()[-1] == f"deploy of api {SHA} failed (exit 3)"
    [login] = harness.docker_calls()
    assert not Path(login["argv"][1]).exists()


# The workflows' side of the contract. Each workflow's own guard and deploy scripts are cut out of the
# YAML and run with `bash -e` (the runner's default shell) against stub `ssh` and `gcloud`, from the
# root of this checkout, exactly as the runner would.

GUARD_STEP = "Check the CI key is restricted on the host"
DEPLOY_STEP = "Deploy on VM (ci-deploy.sh → deploy-runner.sh)"
PROD = "root@192.0.2.10"
SSH_CALL = re.compile(r"\bssh (?:-T )?\$SSH_OPTS\b")

STUB_SSH = r'''#!/usr/bin/env python3
"""Stand-in for the runner's `ssh`: records argv and stdin, then answers with the exit code on the
first line of ./ssh-reply and the rest of that file on stderr (exit 0, silent, when it is absent)."""
import json
import sys
from pathlib import Path

here = Path(__file__).resolve().parent
reply = (here / "ssh-reply").read_text() if (here / "ssh-reply").exists() else "0\n"
code, _, stderr = reply.partition("\n")
with (here / "ssh.calls").open("a") as fh:
    fh.write(json.dumps({"argv": sys.argv[1:], "stdin": sys.stdin.read()}) + "\n")
sys.stderr.write(stderr)
sys.exit(int(code))
'''

# Stand-in for `gcloud auth print-access-token`: prints ./gcloud-token, and fails when it is absent.
STUB_GCLOUD = r'''#!/usr/bin/env bash
token="$(dirname "$0")/gcloud-token"
[[ "$*" == "auth print-access-token" && -f "$token" ]] || { echo "stub gcloud: cannot mint a token" >&2; exit 1; }
cat "$token"
'''


def step_script(workflow: Path, step_name: str) -> str:
    """The `run: |` script of the named step, dedented as the runner writes it out."""
    lines = workflow.read_text().splitlines()
    start = next(i for i, line in enumerate(lines) if line.strip() == f"- name: {step_name}")
    step_indent = len(lines[start]) - len(lines[start].lstrip())
    run = next(i for i in range(start + 1, len(lines)) if lines[i].strip() == "run: |")
    assert not any(line.strip().startswith("- name:") for line in lines[start + 1 : run]), "step has no run:"
    body = []
    for line in lines[run + 1 :]:
        if line.strip() and len(line) - len(line.lstrip()) <= step_indent + 2:
            break
        body.append(line)
    return textwrap.dedent("\n".join(body))


def run_step(tmp_path: Path, script: str, **env: str) -> tuple[subprocess.CompletedProcess, list[dict]]:
    bin_dir = tmp_path / "bin"
    return (
        subprocess.run(
            ["bash", "-e", "-c", script],
            cwd=REPO,
            env={
                **os.environ,
                "PATH": f"{bin_dir}{os.pathsep}{os.environ.get('PATH', '')}",
                "SSH_OPTS": "-o BatchMode=yes",
                "PROD_SSH_USER": "root",
                "PROD_HOST": "192.0.2.10",
                **env,
            },
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        ),
        [json.loads(line) for line in (bin_dir / "ssh.calls").read_text().splitlines()]
        if (bin_dir / "ssh.calls").exists()
        else [],
    )


@pytest.fixture
def runner_bin(tmp_path: Path) -> Path:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    _write_executable(bin_dir / "ssh", STUB_SSH)
    _write_executable(bin_dir / "gcloud", STUB_GCLOUD)
    return bin_dir


GUARD_REPLIES = [
    pytest.param("2\nrejected: unexpected command\n", True, id="refused-by-the-forced-command"),
    pytest.param("2\na line printed first\nrejected: unexpected command\n", True, id="refusal-after-another-line"),
    pytest.param("0\n", False, id="unrestricted-key-gets-a-shell"),
    pytest.param("1\nrejected: unexpected command\n", False, id="right-text-wrong-exit-code"),
    pytest.param("2\nrejected: something else\n", False, id="another-refusal"),
    pytest.param("2\nnot rejected: unexpected command\n", False, id="refusal-text-inside-a-longer-line"),
    pytest.param("1\nrrsync error: SSH_ORIGINAL_COMMAND does not run rsync\n", False, id="another-forced-command"),
    pytest.param("255\nssh: connect to host 192.0.2.10 port 22: Connection timed out\n", False, id="unreachable"),
]


@pytest.mark.parametrize("svc", sorted(WORKFLOWS))
@pytest.mark.parametrize(("reply", "passes"), GUARD_REPLIES)
def test_guard_step_passes_only_when_the_host_refuses_a_shell(tmp_path, runner_bin, svc, reply, passes):
    (runner_bin / "ssh-reply").write_text(reply)

    result, calls = run_step(tmp_path, step_script(WORKFLOWS[svc], GUARD_STEP))

    assert (result.returncode == 0) is passes, result.stdout + result.stderr
    [call] = calls
    assert call["argv"][0] == "-T" and call["argv"][-1] == PROD  # a shell request: no command after the host
    assert call["stdin"] == ""


@pytest.mark.parametrize("svc", sorted(WORKFLOWS))
def test_deploy_step_sends_one_request_with_the_token_on_stdin(tmp_path, runner_bin, svc):
    (runner_bin / "gcloud-token").write_text(f"{TOKEN}\n")

    result, calls = run_step(tmp_path, step_script(WORKFLOWS[svc], DEPLOY_STEP), SHA=SHA)

    assert result.returncode == 0, result.stderr
    [call] = calls
    # The workflow hashes this checkout's host files in ci-deploy.sh's order (HOST_FILES), which the
    # harness tests above hold ci-deploy.sh to.
    files_sha256 = hashlib.sha256(b"".join((REPO / repo_path).read_bytes() for _, repo_path in HOST_FILES))
    assert call["argv"][-2:] == [PROD, f"deploy {svc} {SHA} {files_sha256.hexdigest()}"]
    assert call["stdin"] == f"{TOKEN}\n"
    assert TOKEN not in json.dumps(call["argv"]) and TOKEN not in result.stdout + result.stderr


@pytest.mark.parametrize("svc", sorted(WORKFLOWS))
def test_deploy_step_fails_before_connecting_when_no_token_can_be_minted(tmp_path, runner_bin, svc):
    result, calls = run_step(tmp_path, step_script(WORKFLOWS[svc], DEPLOY_STEP), SHA=SHA)

    assert result.returncode != 0
    assert calls == []


@pytest.mark.parametrize("svc", sorted(WORKFLOWS))
def test_deploy_step_fails_when_the_host_refuses(tmp_path, runner_bin, svc):
    (runner_bin / "gcloud-token").write_text(f"{TOKEN}\n")
    (runner_bin / "ssh-reply").write_text("2\nrejected: host files differ from the workflow's checkout\n")

    result, _ = run_step(tmp_path, step_script(WORKFLOWS[svc], DEPLOY_STEP), SHA=SHA)

    assert result.returncode == 2


@pytest.mark.parametrize("svc", sorted(WORKFLOWS))
def test_workflow_reaches_the_host_only_through_the_guard_and_the_deploy_step(svc):
    text = WORKFLOWS[svc].read_text()

    assert len(SSH_CALL.findall(text)) == 2
    assert SSH_CALL.search(step_script(WORKFLOWS[svc], GUARD_STEP))
    assert SSH_CALL.search(step_script(WORKFLOWS[svc], DEPLOY_STEP))
    assert "scp " not in text and "rsync" not in text
