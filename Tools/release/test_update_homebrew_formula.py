#!/usr/bin/env python3
"""Regression tests for the Homebrew formula renderer."""

from __future__ import annotations

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("update-homebrew-formula.py")
TEMPLATE = Path(__file__).with_name("mac-sync.rb.in")


class UpdateHomebrewFormulaTests(unittest.TestCase):
    def test_renders_current_formula_without_stable_install_paths(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            workspace = Path(temporary_directory)
            template = workspace / "mac-sync.rb.in"
            shutil.copyfile(TEMPLATE, template)
            output = workspace / "Formula" / "mac-sync-current.rb"
            subprocess.run(
                [
                    "python3",
                    str(SCRIPT),
                    "--formula",
                    str(output),
                    "--template",
                    str(template),
                    "--formula-class",
                    "MacSyncCurrent",
                    "--formula-name",
                    "mac-sync-current",
                    "--url",
                    (
                        "https://github.com/stephenlclarke/mac-sync/releases/"
                        "download/current/mac-sync-current-0123456789ab-arm64.tar.gz"
                    ),
                    "--version",
                    "current.123.0123456789ab",
                    "--asset",
                    "mac-sync-current-0123456789ab-arm64.tar.gz",
                    "--label",
                    "current",
                    "--sha256",
                    "a" * 64,
                    "--conflicts-with",
                    "mac-sync",
                ],
                cwd=workspace,
                check=True,
            )

            rendered = output.read_text(encoding="utf-8")
            self.assertIn("class MacSyncCurrent < Formula", rendered)
            self.assertIn('version "current.123.0123456789ab"', rendered)
            self.assertIn('conflicts_with "mac-sync"', rendered)
            self.assertIn('open "#{opt_prefix}/MacSync.app"', rendered)
            self.assertIn("brew services start mac-sync-current", rendered)
            self.assertIn("brew services restart mac-sync-current", rendered)
            self.assertIn("brew services stop mac-sync-current", rendered)
            self.assertNotIn("brew --prefix mac-sync", rendered)

    def test_rejects_output_outside_workspace(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            workspace = Path(temporary_directory)
            result = subprocess.run(
                [
                    "python3",
                    str(SCRIPT),
                    "--formula",
                    "../mac-sync.rb",
                    "--template",
                    str(TEMPLATE),
                    "--formula-name",
                    "mac-sync",
                    "--url",
                    "https://example.invalid/mac-sync.tar.gz",
                    "--version",
                    "0.1.0",
                    "--asset",
                    "mac-sync.tar.gz",
                    "--label",
                    "stable",
                    "--sha256",
                    "b" * 64,
                    "--conflicts-with",
                    "mac-sync-current",
                ],
                cwd=workspace,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("path escapes workspace", result.stderr)


if __name__ == "__main__":
    unittest.main()
