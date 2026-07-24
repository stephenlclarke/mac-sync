#!/usr/bin/env python3
"""Regression tests for GitHub release publication shell compatibility."""

from __future__ import annotations

import hashlib
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("publish-github-release.sh")
COMMIT = "1" * 40


def write_executable(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8")
    path.chmod(
        path.stat().st_mode
        | stat.S_IXUSR
        | stat.S_IXGRP
        | stat.S_IXOTH
    )


class PublishGitHubReleaseTests(unittest.TestCase):
    def test_current_stage_handles_empty_latest_option_on_macos_bash(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            workspace = Path(temporary_directory)
            fake_bin = workspace / "bin"
            fake_bin.mkdir()
            archive = workspace / "mac-sync-current-111111111111-arm64.tar.gz"
            checksum = workspace / f"{archive.name}.sha256"
            notes = workspace / "notes.md"
            state = workspace / "release-viewed"
            archive.write_bytes(b"archive")
            checksum.write_text("checksum\n", encoding="utf-8")
            notes.write_text("# Current build\n", encoding="utf-8")

            write_executable(
                fake_bin / "git",
                """#!/bin/bash
set -euo pipefail
if [[ "$*" == "remote get-url --push origin" ]]; then
  printf 'https://github.com/stephenlclarke/mac-sync.git\\n'
  exit 0
fi
if [[ "$1" == "ls-remote" ]]; then
  exit 0
fi
printf 'unexpected git call: %s\\n' "$*" >&2
exit 1
""",
            )
            write_executable(
                fake_bin / "gh",
                """#!/bin/bash
set -euo pipefail
if [[ "$1 $2" == "release view" ]]; then
  if [[ ! -f "$FAKE_STATE" ]]; then
    touch "$FAKE_STATE"
    exit 1
  fi
  if [[ "$*" == *"$FAKE_CHECKSUM_NAME"* ]]; then
    printf 'sha256:%s\\n' "$FAKE_CHECKSUM_DIGEST"
  else
    printf 'sha256:%s\\n' "$FAKE_ARCHIVE_DIGEST"
  fi
  exit 0
fi
if [[ "$1 $2" == "release create" ]]; then
  exit 0
fi
printf 'unexpected gh call: %s\\n' "$*" >&2
exit 1
""",
            )

            environment = os.environ.copy()
            environment.pop("BASH_ENV", None)
            environment.update(
                {
                    "FAKE_ARCHIVE_DIGEST": hashlib.sha256(archive.read_bytes()).hexdigest(),
                    "FAKE_CHECKSUM_DIGEST": hashlib.sha256(checksum.read_bytes()).hexdigest(),
                    "FAKE_CHECKSUM_NAME": checksum.name,
                    "FAKE_STATE": str(state),
                    "GH_REPO": "stephenlclarke/mac-sync",
                    "GH_TOKEN": "test-token",
                    "PATH": f"{fake_bin}:{environment['PATH']}",
                }
            )
            resolved_git = subprocess.run(
                ["/bin/bash", "-c", "command -v git"],
                env=environment,
                capture_output=True,
                text=True,
                check=True,
            ).stdout.strip()
            self.assertEqual(resolved_git, str(fake_bin / "git"))
            result = subprocess.run(
                [
                    "/bin/bash",
                    str(SCRIPT),
                    "current-stage",
                    "current",
                    COMMIT,
                    "Current build",
                    str(notes),
                    str(archive),
                    str(checksum),
                    "false",
                ],
                cwd=workspace,
                env=environment,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
