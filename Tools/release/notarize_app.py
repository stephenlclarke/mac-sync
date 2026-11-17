"""Submit a Developer ID app to Apple, staple its ticket and verify Gatekeeper."""

from __future__ import annotations

import argparse
import json
import subprocess
import tempfile
from pathlib import Path
from typing import Callable, Sequence

CommandRunner = Callable[[Sequence[str], float], subprocess.CompletedProcess[str]]


def run_command(arguments: Sequence[str], timeout: float) -> subprocess.CompletedProcess[str]:
    """Run an Apple tool without shell expansion or password arguments."""
    return subprocess.run(arguments, capture_output=True, text=True, check=False, timeout=timeout)


def checked(runner: CommandRunner, arguments: Sequence[str], timeout: float = 120) -> subprocess.CompletedProcess[str]:
    """Reject tool failures without printing credentials or arbitrary output."""
    result = runner(arguments, timeout)
    if result.returncode:
        raise RuntimeError(f"{arguments[0]} {arguments[1]} failed (exit {result.returncode}). The app was not approved for deployment.")
    return result


def notarize(app: Path, profile: str, runner: CommandRunner = run_command) -> str:
    """Notarise and assess an existing signed app using stored credentials."""
    if not app.is_dir() or app.suffix != ".app":
        raise ValueError("Choose an existing .app bundle.")
    if not profile.strip() or any(character in profile for character in "\r\n\0"):
        raise ValueError("A saved notarytool Keychain profile is required. Do not pass a password.")
    checked(runner, ["codesign", "--verify", "--deep", "--strict", str(app)])
    signature = checked(runner, ["codesign", "-d", "--verbose=4", str(app)])
    if "Authority=Developer ID Application:" not in signature.stderr + signature.stdout:
        raise ValueError("A Developer ID Application signature is required; ad hoc signing is not accepted.")
    with tempfile.TemporaryDirectory(prefix="mac-sync-notarization-") as directory:
        archive = Path(directory) / "MacSync.zip"
        checked(runner, ["ditto", "-c", "-k", "--keepParent", str(app), str(archive)], 600)
        print("Submitting the signed app to Apple. Waiting for an explicit acceptance…", flush=True)
        result = runner(["xcrun", "notarytool", "submit", str(archive), "--keychain-profile", profile,
                         "--output-format", "json", "--wait", "--timeout", "30m"], 2100)
        try:
            response = json.loads(result.stdout)
        except (json.JSONDecodeError, TypeError) as error:
            raise RuntimeError("Apple submission did not return a result. Check the saved Keychain profile; the app was not deployed.") from error
        if not isinstance(response, dict):
            raise RuntimeError("Apple submission returned an invalid result; the app was not deployed.")
        identifier = response.get("id", "unknown")
        if result.returncode or response.get("status") != "Accepted":
            raise RuntimeError(f"Apple did not accept submission {identifier}. Inspect it with notarytool info/log; the app was not deployed.")
    checked(runner, ["xcrun", "stapler", "staple", str(app)], 600)
    checked(runner, ["xcrun", "stapler", "validate", str(app)], 600)
    checked(runner, ["spctl", "--assess", "--type", "execute", "--verbose=2", str(app)], 120)
    print(f"Apple accepted {identifier}; ticket stapled and Gatekeeper assessment passed.", flush=True)
    return str(identifier)


def main() -> None:
    """Read public build paths and a non-secret Keychain profile name."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--keychain-profile", required=True)
    arguments = parser.parse_args()
    try:
        notarize(arguments.app.resolve(), arguments.keychain_profile)
    except (ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
