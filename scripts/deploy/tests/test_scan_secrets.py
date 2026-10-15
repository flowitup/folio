"""Hermetic tests for .github/scripts/scan-secrets.py, the secret scan of pushes and pull requests.

Each test builds a throwaway git repository, commits a base and a change, and runs the real script on
the diff between them. The credential-shaped values are assembled at run time from fake parts, so this
file never holds a string the scan itself would flag.

Run with: uvx pytest scripts/deploy/tests
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[3]
SCRIPT = REPO / ".github" / "scripts" / "scan-secrets.py"
WORKFLOW = REPO / ".github" / "workflows" / "secret-scan.yml"

FAKE = {  # obviously fake values in the shape of each rule
    "private key": "-----BEGIN " + "RSA PRIVATE KEY-----",
    "Resend API key": "re" + "_" + "FAKEFAKE" + "_" + "x" * 24,
    "AWS access key id": "AKIA" + "FAKEFAKEFAKEFAKE",
    "GitHub token": "ghp" + "_" + "x" * 36,
    "Google API key": "AIza" + "x" * 35,
    "Slack token": "xoxb" + "-" + "0" * 12,
    "Stripe live key": "sk" + "_live_" + "x" * 24,
}


def git(repo: Path, *args: str) -> str:
    return subprocess.run(
        ["git", "-c", "user.name=t", "-c", "user.email=t@example.invalid", "-c", "commit.gpgsign=false", *args],
        cwd=repo,
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()


@pytest.fixture
def repo(tmp_path: Path) -> Path:
    git(tmp_path, "init", "-q")
    (tmp_path / "existing.txt").write_text("nothing here\n")
    git(tmp_path, "add", "-A")
    git(tmp_path, "commit", "-qm", "base")
    return tmp_path


def commit(repo: Path, files: dict[str, str]) -> None:
    for name, text in files.items():
        (repo / name).parent.mkdir(parents=True, exist_ok=True)
        (repo / name).write_text(text)
    git(repo, "add", "-A")
    git(repo, "commit", "-qm", "change")


def scan(repo: Path, base: str = "HEAD~1"):
    return subprocess.run(
        [sys.executable, str(SCRIPT)],
        cwd=repo,
        env={**os.environ, "BASE": git(repo, "rev-parse", base)},
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )


@pytest.mark.parametrize("rule", sorted(FAKE))
def test_each_rule_flags_an_added_line_without_printing_the_value(repo, rule):
    commit(repo, {"app/config.py": f"a = 1\nTOKEN = '{FAKE[rule]}'\n"})

    result = scan(repo)

    assert result.returncode == 1, result.stdout
    assert f"::error file=app/config.py,line=2::{rule} added" in result.stdout
    assert FAKE[rule] not in result.stdout + result.stderr


def test_clean_changes_pass(repo):
    commit(repo, {"app/config.py": "name = 're_test_key'\nurl = 'https://example.invalid'\n", "docs.md": "# hi\n"})

    result = scan(repo)

    assert result.returncode == 0, result.stdout
    assert "no credential-shaped text" in result.stdout


def test_existing_content_and_removed_lines_are_not_scanned(repo):
    # A credential already in the base (history, old fixtures) must not fail the scan of a later change.
    commit(repo, {"old.py": f"KEY = '{FAKE['GitHub token']}'\n"})
    commit(repo, {"new.py": "x = 1\n"})
    assert scan(repo).returncode == 0

    commit(repo, {"old.py": "KEY = None\n"})  # removing it adds nothing
    assert scan(repo).returncode == 0


def test_a_line_marked_allow_is_skipped(repo):
    commit(repo, {"fixture.py": f"KEY = '{FAKE['Resend API key']}'  # secret-scan: allow\n"})

    assert scan(repo).returncode == 0


def test_the_scan_covers_every_commit_between_base_and_head(repo):
    commit(repo, {"a.py": f"KEY = '{FAKE['AWS access key id']}'\n"})
    commit(repo, {"b.py": "x = 1\n"})

    result = scan(repo, base="HEAD~2")

    assert result.returncode == 1
    assert "::error file=a.py,line=1::AWS access key id added" in result.stdout


def test_a_credential_added_then_removed_by_a_later_commit_is_still_found(repo):
    # The net diff BASE..HEAD is clean, but the key sits in the public history of the push.
    commit(repo, {"a.py": f"KEY = '{FAKE['GitHub token']}'\n"})
    commit(repo, {"a.py": "KEY = None\n"})

    result = scan(repo, base="HEAD~2")

    assert result.returncode == 1, result.stdout
    assert "::error file=a.py,line=1::GitHub token added" in result.stdout
    assert FAKE["GitHub token"] not in result.stdout + result.stderr


def test_a_credential_in_a_commit_already_before_the_base_stays_out_of_scope(repo):
    commit(repo, {"a.py": f"KEY = '{FAKE['GitHub token']}'\n"})
    commit(repo, {"a.py": "KEY = None\n"})

    assert scan(repo).returncode == 0


@pytest.mark.parametrize("prefix", ["++ ", "+++ ", "-- ", "++"])
def test_an_added_line_that_looks_like_a_diff_header_is_scanned(repo, prefix):
    # The diff shows the line as '+' + text: '+++ b' or '+++ /dev/null' must not be read as a file header.
    commit(repo, {"a.txt": f"ok\n{prefix}{FAKE['private key']}\n"})

    result = scan(repo)

    assert result.returncode == 1, result.stdout
    assert "::error file=a.txt,line=2::private key added" in result.stdout


def test_added_lines_shaped_like_headers_do_not_redirect_the_following_findings(repo):
    commit(repo, {"a.txt": f"++ /dev/null\n+++ b/other.txt\nTOKEN = '{FAKE['Slack token']}'\n"})

    result = scan(repo)

    assert result.returncode == 1
    assert "::error file=a.txt,line=3::Slack token added" in result.stdout


@pytest.mark.parametrize("sep", ["\u2028", "\x0b", "\x0c", "\x1c", "\u0085", "\r"])
def test_a_line_separator_inside_an_added_line_does_not_hide_the_next_line(repo, sep):
    # str.splitlines() would cut 'x<sep>+y' in two added lines, end the hunk early and skip the key line.
    commit(repo, {"a.txt": f"x{sep}+y\nk = '{FAKE['AWS access key id']}'\n"})

    result = scan(repo)

    assert result.returncode == 1, result.stdout
    assert "::error file=a.txt,line=2::AWS access key id added" in result.stdout


@pytest.mark.parametrize("sep", ["\r", "\x0c", "\u2028"])
def test_a_credential_after_a_line_separator_inside_an_added_line_is_found(repo, sep):
    commit(repo, {"a.txt": f"pad{sep}K = '{FAKE['AWS access key id']}'\n"})

    result = scan(repo)

    assert result.returncode == 1, result.stdout
    assert "::error file=a.txt,line=1::AWS access key id added" in result.stdout


def test_a_binary_attribute_does_not_hide_the_added_lines(repo):
    commit(repo, {".gitattributes": "* -diff\n", "a.txt": f"K = '{FAKE['private key']}'\n"})

    result = scan(repo)

    assert result.returncode == 1, result.stdout
    assert "::error file=a.txt,line=1::private key added" in result.stdout


def test_a_nul_byte_does_not_hide_the_added_lines(repo):
    (repo / "b.bin").write_bytes(b"\x00\n" + FAKE["GitHub token"].encode() + b"\n")
    git(repo, "add", "-A")
    git(repo, "commit", "-qm", "change")

    result = scan(repo)

    assert result.returncode == 1, result.stdout
    assert "::error file=b.bin,line=2::GitHub token added" in result.stdout


def test_a_finding_is_reported_once_when_commits_and_net_diff_both_show_it(repo):
    commit(repo, {"a.py": f"KEY = '{FAKE['AWS access key id']}'\n"})

    result = scan(repo)

    assert len([line for line in result.stdout.splitlines() if line.startswith("::error")]) == 1


def test_a_missing_base_commit_falls_back_to_the_net_diff(repo):
    commit(repo, {"a.py": f"KEY = '{FAKE['AWS access key id']}'\n"})
    empty_tree = git(repo, "hash-object", "-t", "tree", "/dev/null")

    result = subprocess.run(
        [sys.executable, str(SCRIPT)],
        cwd=repo,
        env={**os.environ, "BASE": empty_tree},
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )

    assert result.returncode == 1, result.stdout + result.stderr
    assert "AWS access key id added" in result.stdout


def test_an_unusual_file_name_does_not_hide_a_finding(repo):
    commit(repo, {'dir/we"ird\tname.py': f"KEY = '{FAKE['Slack token']}'\n"})

    result = scan(repo)

    assert result.returncode == 1
    assert "Slack token added" in result.stdout
    assert len([line for line in result.stdout.splitlines() if line.startswith("::error file=dir/we")]) == 1


def test_the_scan_and_its_tests_do_not_trip_it(repo):
    commit(repo, {path.name: path.read_text() for path in (SCRIPT, Path(__file__), WORKFLOW)})

    result = scan(repo)

    assert result.returncode == 0, result.stdout


def test_workflow_passes_the_diff_base_through_env_only():
    text = WORKFLOW.read_text()
    run = text[text.index("run: |") :]

    assert "${{" not in run
    assert "PR_BASE: ${{ github.event.pull_request.base.sha }}" in text
    assert "PUSH_BEFORE: ${{ github.event.before }}" in text
    assert "permissions:\n  contents: read" in text
    assert "${{ secrets." not in text
