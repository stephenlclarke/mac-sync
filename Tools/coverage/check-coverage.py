#!/usr/bin/env python3
"""Check Swift coverage reports against the required minimum."""

from __future__ import annotations

import argparse
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def generic_line_coverage(path: Path) -> float:
    covered = 0
    total = 0
    root = ET.parse(path).getroot()
    for line in root.findall(".//lineToCover"):
        total += 1
        if line.attrib.get("covered") == "true":
            covered += 1
    return percentage(covered, total)


def percentage(covered: int, total: int) -> float:
    if total == 0:
        return 0.0
    return covered * 100.0 / total


def main() -> int:
    parser = argparse.ArgumentParser(description="Check generated coverage reports.")
    parser.add_argument("--minimum", type=float, default=80.0)
    parser.add_argument("--swift", type=Path, required=True)
    args = parser.parse_args()

    actual = generic_line_coverage(args.swift)
    print(f"Swift coverage: {actual:.2f}%")
    if actual + 1e-9 < args.minimum:
        print(f"Swift coverage is below required {args.minimum:.2f}%", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
