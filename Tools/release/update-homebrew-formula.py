#!/usr/bin/env python3
"""Render a Homebrew formula for a published release asset."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


def path_under_workspace(path: Path, workspace: Path) -> Path:
    candidate = path if path.is_absolute() else workspace / path
    resolved = candidate.resolve(strict=False)
    try:
        resolved.relative_to(workspace)
    except ValueError as error:
        raise SystemExit(f"path escapes workspace: {path}") from error
    return resolved


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--formula", required=True, type=Path)
    parser.add_argument("--template", type=Path)
    parser.add_argument("--formula-class")
    parser.add_argument("--formula-name", required=True)
    parser.add_argument("--url", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--asset", required=True)
    parser.add_argument("--label", required=True)
    parser.add_argument("--sha256", required=True)
    parser.add_argument("--conflicts-with", required=True)
    return parser.parse_args()


def replace_once(pattern: str, replacement: str, text: str) -> str:
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.MULTILINE)
    if count != 1:
        raise SystemExit(f"expected exactly one match for pattern: {pattern}")
    return updated


def main() -> None:
    args = parse_args()
    workspace = Path.cwd().resolve()
    formula = path_under_workspace(args.formula, workspace)
    template = path_under_workspace(args.template, workspace) if args.template is not None else None

    if template is not None:
        text = template.read_text(encoding="utf-8")
    elif formula.exists():
        text = formula.read_text(encoding="utf-8")
    else:
        raise SystemExit(f"formula does not exist and no template was supplied: {formula}")

    if args.formula_class is not None:
        if re.fullmatch(r"[A-Z][A-Za-z0-9]*", args.formula_class) is None:
            raise SystemExit(f"invalid formula class: {args.formula_class}")
        text = replace_once(r"^class \w+ < Formula$", f"class {args.formula_class} < Formula", text)

    if re.fullmatch(r"[a-z0-9][a-z0-9@+_.-]*", args.conflicts_with) is None:
        raise SystemExit(f"invalid conflicting formula: {args.conflicts_with}")
    if re.fullmatch(r"[a-z0-9][a-z0-9@+_.-]*", args.formula_name) is None:
        raise SystemExit(f"invalid formula name: {args.formula_name}")

    text = replace_once(r'^  url ".+"$', f'  url "{args.url}"', text)
    text = replace_once(r"^  sha256 .+$", f'  sha256 "{args.sha256}"', text)
    text = replace_once(r'^  version ".+"$', f'  version "{args.version}"', text)
    text = replace_once(
        r'^  conflicts_with ".+", because: ".+"$',
        f'  conflicts_with "{args.conflicts_with}", because: "both install the mac-sync executables"',
        text,
    )
    text = replace_once(
        r"This formula installs the .+ prebuilt package asset:\n        .+\.tar\.gz",
        f"This formula installs the {args.label} prebuilt package asset:\n        {args.asset}",
        text,
    )
    text = re.sub(
        r"brew services (start|restart|stop) mac-sync$",
        rf"brew services \1 {args.formula_name}",
        text,
        flags=re.MULTILINE,
    )
    formula.parent.mkdir(parents=True, exist_ok=True)
    formula.write_text(text, encoding="utf-8")


if __name__ == "__main__":
    main()
