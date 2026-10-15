"""Hermetic tests for .github/scripts/verify-release.py, the release check of the two deploy workflows.

The script runs for real. A stub `gh` first on PATH answers `gh api <endpoint>` from a table of
canned responses, so nothing here reaches GitHub; an endpoint that isn't in the table fails like a
404 does. The last tests cut the workflows' verify step out of their YAML and check how it is wired.

Run with: uvx pytest scripts/deploy/tests
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_ci_deploy import REPO, WORKFLOWS, workflow_steps  # noqa: E402

SCRIPT = REPO / ".github" / "scripts" / "verify-release.py"
SUBMODULES = {"api": "flowitup/folio-back-end", "frontend": "flowitup/folio-front-end"}
VERIFY_STEP = "Verify version↔sha tag"

FULL = "a" * 40
SHORT = FULL[:7]
OTHER = "b" * 40
TAG_OBJECT = "c" * 40
MASTER_TIP = "d" * 40
VERSION = "1.2.3"
REPO_NAME = "flowitup/folio-back-end"

STUB_GH = r'''#!/usr/bin/env python3
"""Stand-in for `gh`: answers `gh api <endpoint>` from ./responses.json ({endpoint: body}) and fails,
as a 404 does, for an endpoint that is not in it. Records every endpoint asked for."""
import json
import sys
from pathlib import Path

here = Path(__file__).resolve().parent
with (here / "gh.calls").open("a") as fh:
    fh.write(json.dumps(sys.argv[1:]) + "\n")
responses = json.loads((here / "responses.json").read_text())
if len(sys.argv) != 3 or sys.argv[1] != "api" or sys.argv[2] not in responses:
    sys.stderr.write("gh: Not Found (HTTP 404)\n")
    sys.exit(1)
print(json.dumps(responses[sys.argv[2]]))
'''


def genuine_release(sha: str = FULL, short: str | None = None) -> dict:
    """The API's answers for a release tag that points straight at `sha`, which is behind master."""
    return {
        f"repos/{REPO_NAME}/commits/{short or sha}": {"sha": sha},
        f"repos/{REPO_NAME}/git/ref/tags/v{VERSION}": {
            "ref": f"refs/tags/v{VERSION}",
            "object": {"type": "commit", "sha": sha},
        },
        f"repos/{REPO_NAME}/branches/master": {"commit": {"sha": MASTER_TIP}},
        f"repos/{REPO_NAME}/compare/{MASTER_TIP}...{sha}": {"status": "behind"},
    }


def run_verify(tmp_path: Path, responses: dict, sha: str = FULL, version: str = VERSION):
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir(exist_ok=True)
    gh = bin_dir / "gh"
    gh.write_text(STUB_GH)
    gh.chmod(0o755)
    (bin_dir / "responses.json").write_text(json.dumps(responses))
    output = tmp_path / "github-output"
    result = subprocess.run(
        [sys.executable, str(SCRIPT)],
        env={
            **os.environ,
            "PATH": f"{bin_dir}{os.pathsep}{os.environ.get('PATH', '')}",
            "SUBMODULE_REPO": REPO_NAME,
            "VERSION": version,
            "SHA": sha,
            "GITHUB_OUTPUT": str(output),
        },
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )
    calls = [json.loads(line) for line in (bin_dir / "gh.calls").read_text().splitlines()] if (bin_dir / "gh.calls").exists() else []
    return result, (output.read_text() if output.exists() else ""), calls


def assert_rejected(result, output: str, message: str) -> None:
    assert result.returncode == 1, result.stdout + result.stderr
    assert output == ""
    errors = [line for line in result.stdout.splitlines() if line.startswith("::error::")]
    assert len(errors) == 1 and message in errors[0], result.stdout


def test_accepts_a_release_tag_on_master(tmp_path):
    result, output, _ = run_verify(tmp_path, genuine_release())

    assert result.returncode == 0, result.stdout + result.stderr
    assert output == f"sha={FULL}\n"


def test_accepts_the_commit_master_is_at(tmp_path):
    responses = genuine_release()
    responses[f"repos/{REPO_NAME}/compare/{MASTER_TIP}...{FULL}"] = {"status": "identical"}

    result, output, _ = run_verify(tmp_path, responses)

    assert result.returncode == 0, result.stdout + result.stderr
    assert output == f"sha={FULL}\n"


def test_a_short_sha_is_expanded_to_the_full_one(tmp_path):
    result, output, calls = run_verify(tmp_path, genuine_release(FULL, short=SHORT), sha=SHORT)

    assert result.returncode == 0, result.stdout + result.stderr
    assert output == f"sha={FULL}\n"  # the workflow builds and deploys the full SHA from here on
    assert ["api", f"repos/{REPO_NAME}/compare/{MASTER_TIP}...{FULL}"] in calls


def test_a_short_sha_that_resolves_to_a_different_commit_is_rejected(tmp_path):
    # A branch or tag called like the SHA can answer the lookup instead of the commit.
    responses = genuine_release(OTHER, short=SHORT)

    result, output, _ = run_verify(tmp_path, responses, sha=SHORT)

    assert_rejected(result, output, f"{SHORT} is not a commit of {REPO_NAME}")


def test_a_full_sha_the_api_resolves_elsewhere_is_rejected(tmp_path):
    responses = genuine_release()
    responses[f"repos/{REPO_NAME}/commits/{FULL}"] = {"sha": OTHER}

    result, output, _ = run_verify(tmp_path, responses)

    assert_rejected(result, output, f"{FULL} is not a commit of {REPO_NAME}")


def test_an_unknown_sha_is_rejected(tmp_path):
    responses = genuine_release()
    del responses[f"repos/{REPO_NAME}/commits/{FULL}"]

    result, output, _ = run_verify(tmp_path, responses)

    assert_rejected(result, output, f"{FULL} is not a commit of {REPO_NAME}")


def test_a_branch_called_like_the_version_is_not_a_tag(tmp_path):
    # `commits/v1.2.3` would have resolved a branch; only refs/tags/ counts.
    responses = genuine_release()
    del responses[f"repos/{REPO_NAME}/git/ref/tags/v{VERSION}"]
    responses[f"repos/{REPO_NAME}/commits/v{VERSION}"] = {"sha": FULL}
    responses[f"repos/{REPO_NAME}/git/ref/heads/v{VERSION}"] = {"object": {"type": "commit", "sha": FULL}}

    result, output, _ = run_verify(tmp_path, responses)

    assert_rejected(result, output, f"tag v{VERSION} does not exist on {REPO_NAME}")


def test_a_ref_answering_for_a_different_tag_is_rejected(tmp_path):
    responses = genuine_release()
    responses[f"repos/{REPO_NAME}/git/ref/tags/v{VERSION}"]["ref"] = f"refs/tags/v{VERSION}0"

    result, output, _ = run_verify(tmp_path, responses)

    assert_rejected(result, output, f"tag v{VERSION} does not exist on {REPO_NAME}")


def test_a_tag_pointing_at_another_commit_is_rejected(tmp_path):
    responses = genuine_release()
    responses[f"repos/{REPO_NAME}/git/ref/tags/v{VERSION}"]["object"]["sha"] = OTHER

    result, output, _ = run_verify(tmp_path, responses)

    assert_rejected(result, output, f"tag v{VERSION} points at {OTHER} but the caller passed {FULL}")


def annotated(responses: dict, target: str) -> dict:
    responses[f"repos/{REPO_NAME}/git/ref/tags/v{VERSION}"]["object"] = {"type": "tag", "sha": TAG_OBJECT}
    responses[f"repos/{REPO_NAME}/git/tags/{TAG_OBJECT}"] = {"object": {"type": "commit", "sha": target}}
    return responses


def test_an_annotated_tag_is_followed_to_its_commit(tmp_path):
    result, output, _ = run_verify(tmp_path, annotated(genuine_release(), FULL))

    assert result.returncode == 0, result.stdout + result.stderr
    assert output == f"sha={FULL}\n"


def test_an_annotated_tag_on_another_commit_is_rejected(tmp_path):
    result, output, _ = run_verify(tmp_path, annotated(genuine_release(), OTHER))

    assert_rejected(result, output, f"tag v{VERSION} points at {OTHER} but the caller passed {FULL}")


def test_an_annotated_tag_that_cannot_be_read_is_rejected(tmp_path):
    responses = annotated(genuine_release(), FULL)
    del responses[f"repos/{REPO_NAME}/git/tags/{TAG_OBJECT}"]

    result, output, _ = run_verify(tmp_path, responses)

    assert_rejected(result, output, f"tag v{VERSION} on {REPO_NAME} does not point at a commit")


def test_a_tag_on_a_tree_is_rejected(tmp_path):
    responses = genuine_release()
    responses[f"repos/{REPO_NAME}/git/ref/tags/v{VERSION}"]["object"] = {"type": "tree", "sha": FULL}

    result, output, _ = run_verify(tmp_path, responses)

    assert_rejected(result, output, f"tag v{VERSION} on {REPO_NAME} does not point at a commit")


@pytest.mark.parametrize("status", ["ahead", "diverged", "unexpected", ""])
def test_a_commit_that_is_not_on_master_is_rejected(tmp_path, status):
    # "ahead": the commit has history master lacks, e.g. an unreviewed branch tagged v1.2.3.
    responses = genuine_release()
    responses[f"repos/{REPO_NAME}/compare/{MASTER_TIP}...{FULL}"] = {"status": status}

    result, output, _ = run_verify(tmp_path, responses)

    assert_rejected(result, output, f"{FULL} is not on the master branch of {REPO_NAME}")


def test_a_failed_compare_is_rejected(tmp_path):
    responses = genuine_release()
    del responses[f"repos/{REPO_NAME}/compare/{MASTER_TIP}...{FULL}"]

    result, output, _ = run_verify(tmp_path, responses)

    assert_rejected(result, output, f"{FULL} is not on the master branch of {REPO_NAME}")


def test_an_unreadable_master_branch_is_rejected(tmp_path):
    responses = genuine_release()
    del responses[f"repos/{REPO_NAME}/branches/master"]

    result, output, _ = run_verify(tmp_path, responses)

    assert_rejected(result, output, f"cannot read the master branch of {REPO_NAME}")


@pytest.mark.parametrize(
    ("sha", "version"),
    [
        pytest.param("", VERSION, id="no-sha"),
        pytest.param("abc123", VERSION, id="too-short"),
        pytest.param("A" * 40, VERSION, id="uppercase"),
        pytest.param(FULL + "a", VERSION, id="too-long"),
        pytest.param("../../" + SHORT, VERSION, id="path-in-sha"),
        pytest.param(FULL, "", id="no-version"),
        pytest.param(FULL, "1.2", id="two-part-version"),
        pytest.param(FULL, "1.2.3/../../x", id="path-in-version"),
        pytest.param(FULL, "1.2.3\n::set-output name=sha::" + OTHER, id="workflow-command-in-version"),
    ],
)
def test_malformed_input_is_rejected_before_the_api_is_asked(tmp_path, sha, version):
    result, output, calls = run_verify(tmp_path, genuine_release(), sha=sha, version=version)

    assert result.returncode == 1
    assert output == "" and calls == []
    assert len([line for line in result.stdout.splitlines() if line.startswith("::")]) == 1


# The workflows' side: each runs the script in the step that every later step depends on.


@pytest.mark.parametrize("svc", sorted(WORKFLOWS))
def test_workflow_verifies_before_it_checks_out_or_builds_anything(svc):
    text = WORKFLOWS[svc].read_text()
    steps = workflow_steps(WORKFLOWS[svc])
    order = list(steps)
    verify = steps[VERIFY_STEP]

    assert verify["run"] == "python3 .github/scripts/verify-release.py"
    assert verify["env"] == {
        "GH_TOKEN": "${{ secrets.SUBMODULE_TOKEN || secrets.GITHUB_TOKEN }}",
        "VERSION": "${{ steps.input.outputs.version }}",
        "SHA": "${{ steps.input.outputs.sha }}",
    }
    assert re.search(rf"- name: {VERIFY_STEP}\n\s+id: release\n", text)
    assert order.index(VERIFY_STEP) < next(i for i, name in enumerate(order) if name.startswith("Checkout folio-"))
    assert f"SUBMODULE_REPO: {SUBMODULES[svc]}" in text  # the script reads the repo from the workflow env


@pytest.mark.parametrize("svc", sorted(WORKFLOWS))
def test_everything_after_the_verify_step_uses_the_full_sha_it_resolved(svc):
    text = WORKFLOWS[svc].read_text()
    after = text[text.index(f"- name: {VERIFY_STEP}") :]
    uses = re.findall(r"^.*steps\.input\.outputs\.sha.*$", after, re.M)

    # Only the verify step's own input and the failure report's fallback may still read the request's SHA.
    assert [line.strip() for line in uses] == [
        "SHA: ${{ steps.input.outputs.sha }}",
        "SHA: ${{ steps.release.outputs.sha || steps.input.outputs.sha }}",
        "SHA: ${{ steps.release.outputs.sha || steps.input.outputs.sha }}",
    ]
    assert "sha: ${{ steps.release.outputs.sha }}" in text  # the job output the pointer bump commits
