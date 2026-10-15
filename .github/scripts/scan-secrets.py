#!/usr/bin/env python3
"""Fail when the lines a push or pull request adds contain something shaped like a credential.

Only what BASE..HEAD (env, any git revisions) adds is read, commit by commit and as a net diff: history
before BASE and existing files are never scanned, so old fixtures can't fail it. The rules are the
high-signal token formats; a line that has to keep a harmless look-alike carries `secret-scan: allow`.
A finding names the rule, file and line, never the matched text, so the log doesn't republish the secret.
The scan is advisory: it catches the careless commit, not someone who means to hide a key.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys

RULES = {
    "private key": r"-----BEGIN (?:[A-Z]+ )*PRIVATE KEY-----",
    "Resend API key": r"\bre_[A-Za-z0-9]{6,}_[A-Za-z0-9]{20,}",
    "AWS access key id": r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b",
    "GitHub token": r"\b(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{50,})",
    "Google API key": r"\bAIza[0-9A-Za-z_-]{35}",
    "Slack token": r"\bxox[abprs]-[A-Za-z0-9-]{10,}",
    "Stripe live key": r"\b[rs]k_live_[0-9A-Za-z]{20,}",
}
ALLOW = "secret-scan: allow"
HUNK = re.compile(r"^@@ -\d+(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")
DIFF_ARGS = ["--no-color", "--unified=0", "--no-renames", "--no-prefix", "--no-ext-diff", "--no-textconv", "--text"]


def git_output(*args: str) -> str:
    # Bytes, not text=True: no newline translation, so a lone '\r' stays inside its line.
    return subprocess.run(["git", *args], capture_output=True, check=True).stdout.decode(errors="replace")


def parse_diff(diff: str):
    """(path, line number, text) of every added line of a unified diff (any number of files and commits)."""
    path, number, old_left, new_left = None, 0, 0, 0
    # Only '\n' ends a line of a diff: str.splitlines() also splits on U+2028, '\x0c' and the like, which
    # would miscount the lines of a hunk.
    for line in diff.split("\n"):
        if old_left > 0 or new_left > 0:
            # Inside a hunk the header's line counts say what is left, so a removed or added line that
            # itself starts with '-- ' or '++ ' is content and never taken for a file header.
            if line.startswith("+"):
                new_left = max(new_left - 1, 0)
                if path:
                    yield path, number, line[1:]
                number += 1
            elif line.startswith("-"):
                old_left = max(old_left - 1, 0)
            continue
        if line.startswith("+++ "):
            # Git quotes an unusual file name, so the header is read whole, not matched on a pattern.
            path = None if line == "+++ /dev/null" else re.sub(r"[^\w./-]", "_", line[4:].strip('"'))
        elif m := HUNK.match(line):
            old_left = int(m.group(1) or 1)
            number = int(m.group(2))
            new_left = int(m.group(3) or 1)


def added_lines(base: str, head: str):
    """Every line added between the two revisions: commit by commit, then the net diff.

    A credential added by one commit and removed by a later one of the same push is gone from the net
    diff but stays in the public history, so each commit's own patch is read as well. The net diff also
    covers what a merge commit changes. A line is reported once, the first time it is seen.
    """
    seen = set()
    diffs = []
    if subprocess.run(["git", "cat-file", "-e", f"{base}^{{commit}}"], capture_output=True, check=False).returncode == 0:
        diffs.append(git_output("log", "-p", "--no-merges", "--reverse", "--format=", *DIFF_ARGS, f"{base}..{head}"))
    diffs.append(git_output("diff", *DIFF_ARGS, base, head))
    for diff in diffs:
        for path, number, text in parse_diff(diff):
            if (path, text) not in seen:
                seen.add((path, text))
                yield path, number, text


def main() -> int:
    base, head = os.environ["BASE"], os.environ.get("HEAD", "HEAD")
    findings = [
        (name, path, number)
        for path, number, text in added_lines(base, head)
        if ALLOW not in text
        for name, pattern in RULES.items()
        if re.search(pattern, text)
    ]
    for name, path, number in findings:
        print(f"::error file={path},line={number}::{name} added; remove it and rotate the credential if it was real")
    if findings:
        print(f"{len(findings)} possible credential(s) in the added lines. A key that reached a public repository is "
              "compromised even after a force-push: rotate it. A look-alike that must stay carries 'secret-scan: allow'.")
        return 1
    print("no credential-shaped text in the added lines")
    return 0


if __name__ == "__main__":
    sys.exit(main())
