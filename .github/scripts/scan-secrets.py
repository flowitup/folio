#!/usr/bin/env python3
"""Fail when the lines a push or pull request adds contain something shaped like a credential.

Only the diff from BASE to HEAD (env, any git revisions) is read: history and existing files are never
scanned, so old fixtures can't fail it. The rules are the high-signal token formats; a line that has to
keep a harmless look-alike carries `secret-scan: allow`. A finding names the rule, file and line, never
the matched text, so the log doesn't republish the secret.
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
HUNK = re.compile(r"^@@ -\S+ \+(\d+)")


def added_lines(base: str, head: str):
    """(path, line number, text) of every line added between the two revisions."""
    diff = subprocess.run(
        ["git", "diff", "--no-color", "--unified=0", "--no-renames", "--no-prefix", base, head],
        capture_output=True,
        text=True,
        errors="replace",
        check=True,
    ).stdout
    path, number = None, 0
    for line in diff.splitlines():
        if line.startswith("+++ "):
            # Git quotes an unusual file name, so the header is read whole, not matched on a pattern.
            path = None if line == "+++ /dev/null" else re.sub(r"[^\w./-]", "_", line[4:].strip('"'))
        elif m := HUNK.match(line):
            number = int(m.group(1))
        elif path and line.startswith("+"):
            yield path, number, line[1:]
            number += 1


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
