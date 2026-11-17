"""Test fail-closed notarisation without Apple credentials or uploads."""

import subprocess
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path

from notarize_app import notarize


class NotarizationTests(unittest.TestCase):
    """Require signing, Apple acceptance, a staple and a Gatekeeper pass."""

    def setUp(self) -> None:
        """Keep simulated Apple acceptance out of real build logs."""
        output = patch("builtins.print")
        output.start()
        self.addCleanup(output.stop)

    def test_acceptance_staples_and_assesses(self) -> None:
        """Deployable output requires every independent verification step."""
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / "MacSync.app"
            app.mkdir()
            calls: list[list[str]] = []

            def runner(arguments: list[str], _timeout: float) -> subprocess.CompletedProcess[str]:
                calls.append(arguments)
                output = '{"id":"submission-id","status":"Accepted"}' if "submit" in arguments else ""
                signature = "Authority=Developer ID Application: Example" if "-d" in arguments else ""
                return subprocess.CompletedProcess(arguments, 0, output, signature)

            self.assertEqual(notarize(app, "stored-profile", runner), "submission-id")
            self.assertTrue(any("staple" in call for call in calls))
            self.assertTrue(any("validate" in call for call in calls))
            self.assertEqual(calls[-1][0], "spctl")
            self.assertFalse(any("--password" in call for call in calls))

    def test_rejection_never_staples(self) -> None:
        """An invalid or still-processing submission cannot become success."""
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / "MacSync.app"
            app.mkdir()
            for status in ["Invalid", "In Progress", "Rejected"]:
                calls: list[list[str]] = []

                def runner(arguments: list[str], _timeout: float) -> subprocess.CompletedProcess[str]:
                    calls.append(arguments)
                    output = '{"id":"id","status":"' + status + '"}' if "submit" in arguments else ""
                    return subprocess.CompletedProcess(arguments, 0, output, "Authority=Developer ID Application: Example")

                with self.assertRaises(RuntimeError):
                    notarize(app, "profile", runner)
                self.assertFalse(any("staple" in call for call in calls))

    def test_unsigned_or_missing_profile_stops_before_upload(self) -> None:
        """Never silently replace distribution signing with ad hoc signing."""
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / "MacSync.app"
            app.mkdir()

            def runner(arguments: list[str], _timeout: float) -> subprocess.CompletedProcess[str]:
                self.assertNotIn("submit", arguments)
                return subprocess.CompletedProcess(arguments, 0, "", "Signature=adhoc")

            with self.assertRaises(ValueError):
                notarize(app, "", runner)
            with self.assertRaises(ValueError):
                notarize(app, "profile", runner)


if __name__ == "__main__":
    unittest.main()
