#!/usr/bin/env python3
"""Write mac-sync package provenance metadata."""

from __future__ import annotations

import argparse
import json
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
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--source", required=True)
    parser.add_argument("--branch", required=True)
    parser.add_argument("--lane", required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--build-type", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    output = path_under_workspace(args.output, Path.cwd().resolve())
    output.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "version": args.version,
        "source": args.source,
        "branch": args.branch,
        "lane": args.lane,
        "commit": args.commit,
        "build": args.build,
        "buildType": args.build_type,
    }
    output.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
