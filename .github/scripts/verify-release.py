#!/usr/bin/env python3
"""Decide whether a deploy request names a released commit of the sub-repo.

Run by deploy-backend.yml and deploy-frontend.yml before anything is built. The request (a
repository_dispatch payload or the manual inputs) is chosen by whoever sends it, so nothing in it is
trusted until the GitHub API agrees:

  1. SHA resolves to one commit of SUBMODULE_REPO; a short SHA is expanded to its full 40 characters
     and the workflow carries the full one from here on.
  2. The tag refs/tags/v<VERSION> exists (an exact ref, not a branch or a prefix match) and points at
     that commit, directly or through annotated tag objects.
  3. The commit is on the repo's master: master is identical to it or ahead of it. A released commit
     stays on master for good, so redeploying or rolling back to an older release passes.

Inputs: env SUBMODULE_REPO, VERSION, SHA, GH_TOKEN (read by `gh`), GITHUB_OUTPUT. On success it appends
`sha=<full sha>` to GITHUB_OUTPUT; on any failure, or when the API cannot answer, it exits 1. When a
call failed (rate limit, expired token, 5xx), the error names what GitHub said: first line of gh's
stderr, filtered and without the token.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys

FULL_SHA = re.compile(r"[0-9a-f]{40}")
MAX_TAG_DEPTH = 5


def fail(message: str) -> None:
    print(f"::error::{message}")
    sys.exit(1)


last_error = ""


def gh_api(path: str):
    """The parsed JSON of a GET on `path`, or None when the API refuses it or doesn't answer.

    Why it failed is kept in `last_error` for `why()`, so a rate limit or a bad token isn't reported as a
    missing tag."""
    global last_error
    last_error = ""
    try:
        result = subprocess.run(["gh", "api", path], capture_output=True, text=True, check=False)
    except OSError:
        last_error = "gh could not be run"
        return None
    if result.returncode != 0:
        lines = [line for line in result.stderr.splitlines() if line.strip()]
        hint = lines[0] if lines else f"gh exited with status {result.returncode}"
        token = os.environ.get("GH_TOKEN", "")
        if token:
            hint = hint.replace(token, "REDACTED")
        last_error = re.sub(r"[^\w .,:;()/'=-]", "_", hint)[:160]
        return None
    try:
        return json.loads(result.stdout)
    except ValueError:
        return None


def why() -> str:
    """The reason the last API call failed, for the end of an error message; empty when it answered."""
    return f" (GitHub API: {last_error})" if last_error else ""


def object_of(response) -> dict:
    obj = response.get("object") if isinstance(response, dict) else None
    return obj if isinstance(obj, dict) else {}


def main() -> None:
    repo = os.environ["SUBMODULE_REPO"]
    version = os.environ.get("VERSION", "")
    sha = os.environ.get("SHA", "")
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        fail("invalid version")
    if not re.fullmatch(r"[0-9a-f]{7,40}", sha):
        fail("invalid sha")
    tag = f"v{version}"

    commit = gh_api(f"repos/{repo}/commits/{sha}")
    full = commit.get("sha") if isinstance(commit, dict) else None
    # A branch or tag named like the SHA could be resolved instead of the commit: it must be that commit.
    if not isinstance(full, str) or not FULL_SHA.fullmatch(full) or not full.startswith(sha):
        fail(f"{sha} is not a commit of {repo}{why()}")

    ref = gh_api(f"repos/{repo}/git/ref/tags/{tag}")
    if not isinstance(ref, dict) or ref.get("ref") != f"refs/tags/{tag}":
        fail(f"tag {tag} does not exist on {repo}{why()}")
    obj = object_of(ref)
    for _ in range(MAX_TAG_DEPTH):
        if obj.get("type") != "tag" or not isinstance(obj.get("sha"), str):
            break
        if not FULL_SHA.fullmatch(obj["sha"]):
            fail(f"tag {tag} has an unreadable target")
        obj = object_of(gh_api(f"repos/{repo}/git/tags/{obj['sha']}"))
    if obj.get("type") != "commit" or not isinstance(obj.get("sha"), str) or not FULL_SHA.fullmatch(obj["sha"]):
        fail(f"tag {tag} on {repo} does not point at a commit{why()}")
    if obj["sha"] != full:
        fail(f"tag {tag} points at {obj['sha']} but the caller passed {full}")

    branch = gh_api(f"repos/{repo}/branches/master")
    tip = branch.get("commit", {}).get("sha") if isinstance(branch, dict) and isinstance(branch.get("commit"), dict) else None
    if not isinstance(tip, str) or not FULL_SHA.fullmatch(tip):
        fail(f"cannot read the master branch of {repo}{why()}")
    # head=SHA against base=master: "behind" means the SHA is an ancestor of master.
    comparison = gh_api(f"repos/{repo}/compare/{tip}...{full}")
    status = comparison.get("status") if isinstance(comparison, dict) else None
    if status not in ("identical", "behind"):
        shown = status if isinstance(status, str) and re.fullmatch(r"[a-z]{1,16}", status) else "unknown"
        fail(f"{full} is not on the master branch of {repo} (compare status: {shown}){why()}")

    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        output.write(f"sha={full}\n")
    print(f"::notice::tag {tag} points at {full} and {full} is on master of {repo}")


if __name__ == "__main__":
    main()
