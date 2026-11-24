#!/usr/bin/env python3
"""Fail closed on incomplete, externally linked or incorrectly signed Store apps."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import plistlib
import re
import subprocess


TOOLS = {
    "mac-sync", "git", "rsync", "gtar", "age", "age-keygen",
    "git-remote-http", "git-remote-https", "git-credential-osxkeychain",
}
CHILD_ENTITLEMENTS = {
    "com.apple.security.app-sandbox": True,
    "com.apple.security.inherit": True,
}
MACHO_MAGICS = {b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"}


def run(*arguments: str) -> str:
    """Inspect the build with Apple's system tools, without executing its code."""
    return subprocess.check_output(arguments, stderr=subprocess.STDOUT, text=True)


def system_dependencies(output: str) -> list[str]:
    """Return non-system dylibs; no Homebrew or build-host paths may escape."""
    paths = [line.strip().split(" (", 1)[0] for line in output.splitlines()[1:] if " (" in line]
    return [path for path in paths if not path.startswith(("/System/Library/", "/usr/lib/"))]


def minimum_versions(output: str) -> list[tuple[int, ...]]:
    """Extract every deployment minimum, including legacy Mach-O commands."""
    values = re.findall(r"cmd LC_BUILD_VERSION\b(?:(?!Load command).)*?\bminos ([0-9.]+)", output, re.DOTALL)
    values += re.findall(r"cmd LC_VERSION_MIN_MACOSX\b(?:(?!Load command).)*?\bversion ([0-9.]+)", output, re.DOTALL)
    return [tuple(int(part) for part in value.split(".")) for value in values]


def audit(app: Path, signed: bool, distribution: bool) -> int:
    """Check the whole executable set and the submission-critical resources."""
    app = app.resolve(strict=True)
    with (app / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    if info.get("MacSyncDistribution") != "app-store":
        raise ValueError("Not an App Store edition")
    minimum = tuple(int(part) for part in info["LSMinimumSystemVersion"].split("."))
    helpers = app / "Contents/Helpers"
    if {path.name for path in helpers.iterdir()} != TOOLS:
        raise ValueError("Unexpected or missing runtime executables")
    runtime = app / "Contents/Resources/Runtime"
    build = json.loads((runtime / "build-info.json").read_text())
    if build["minimum_macos"] != info["LSMinimumSystemVersion"]:
        raise ValueError("App and runtime deployment targets differ")
    for resource in ["LICENSE", "LICENSE.md", "LICENSE-MIT.md", "NOTICE.md", "PrivacyInfo.xcprivacy",
                     "Runtime/Notices/Go-LICENSE", "Runtime/Sources/build_runtime.py", "Runtime/Sources/sources.json"]:
        if not (app / "Contents/Resources" / resource).is_file():
            raise ValueError(f"Missing resource: {resource}")
    agent = app / "Contents/Library/LaunchAgents/io.quux.mac-sync.background.plist"
    with agent.open("rb") as stream:
        definition = plistlib.load(stream)
    if definition.get("BundleProgram") != "Contents/MacOS/MacSync" or definition.get("ProgramArguments") != ["MacSync", "--background-agent"]:
        raise ValueError("Agent must run the same signed application")
    count = 0
    teams: set[str] = set()
    for path in sorted(app.rglob("*")):
        if path.is_symlink() and not path.resolve().is_relative_to(app):
            raise ValueError(f"Symlink escapes the app: {path}")
        if not path.is_file():
            continue
        with path.open("rb") as stream:
            magic = stream.read(4)
        if magic not in MACHO_MAGICS:
            continue
        count += 1
        if path.parent not in [helpers, app / "Contents/MacOS"]:
            raise ValueError(f"Executable outside a code directory: {path}")
        architectures = run("/usr/bin/lipo", "-archs", str(path)).split()
        if architectures != ["arm64"]:
            raise ValueError(f"Expected Apple silicon runtime: {path.name}: {architectures}")
        dependencies = system_dependencies(run("/usr/bin/otool", "-L", str(path)))
        versions = minimum_versions(run("/usr/bin/otool", "-l", str(path)))
        if dependencies or not versions or any(version > minimum for version in versions):
            raise ValueError(f"Unsupported runtime dependency or minimum: {path.name}: {dependencies}, {versions}")
        if signed:
            run("/usr/bin/codesign", "--verify", "--strict", str(path))
            data = subprocess.check_output(["/usr/bin/codesign", "-d", "--entitlements", ":-", str(path)], stderr=subprocess.DEVNULL)
            entitlements = plistlib.loads(data)
            if path.parent == helpers and entitlements != CHILD_ENTITLEMENTS:
                raise ValueError(f"Invalid inherited sandbox: {path.name}")
            if not entitlements.get("com.apple.security.app-sandbox") or entitlements.get("com.apple.security.get-task-allow"):
                raise ValueError(f"Invalid release sandbox: {path.name}")
            details = run("/usr/bin/codesign", "-dvv", str(path))
            team = re.search(r"^TeamIdentifier=(.+)$", details, re.MULTILINE)
            teams.add(team.group(1) if team else "missing")
            if distribution and not re.search(r"Authority=(?:Apple Distribution|3rd Party Mac Developer Application):", details):
                raise ValueError(f"Not signed for App Store distribution: {path.name}")
    if count != len(TOOLS) + 1:
        raise ValueError(f"Expected {len(TOOLS) + 1} native executables, found {count}")
    if signed:
        run("/usr/bin/codesign", "--verify", "--deep", "--strict", str(app))
        if len(teams) != 1 or (distribution and ("missing" in teams or "not set" in teams)):
            raise ValueError("All executables must have the same signing team")
    if distribution and not (app / "Contents/embedded.provisionprofile").is_file():
        raise ValueError("Missing App Store provisioning profile")
    print(f"Audited {count} executables; minimum macOS {info['LSMinimumSystemVersion']}; signed={signed}; upload-signing={distribution}")
    return count


def main() -> None:
    """Audit unsigned CI archives, locally signed tests, or submission exports."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--signed", action="store_true")
    parser.add_argument("--distribution", action="store_true")
    args = parser.parse_args()
    audit(args.app, args.signed or args.distribution, args.distribution)


if __name__ == "__main__":
    main()
