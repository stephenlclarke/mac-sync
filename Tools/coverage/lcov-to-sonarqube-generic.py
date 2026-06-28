#!/usr/bin/env python3
"""Convert LCOV line coverage into SonarQube generic coverage XML."""

from __future__ import annotations

import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def usage() -> None:
    print("usage: lcov-to-sonarqube-generic.py <input.lcov> <output.xml> [project-root]", file=sys.stderr)


def path_under_root(path: str | Path, root: Path) -> Path:
    candidate = path if isinstance(path, Path) else Path(path)
    if not candidate.is_absolute():
        candidate = root / candidate
    resolved = candidate.resolve(strict=False)
    try:
        resolved.relative_to(root)
    except ValueError as error:
        raise SystemExit(f"path escapes project root: {path}") from error
    return resolved


def relative_path(path: str, root: Path) -> str:
    return path_under_root(path, root).relative_to(root).as_posix()


def parse_lcov(path: Path, root: Path) -> dict[str, dict[int, bool]]:
    files: dict[str, dict[int, bool]] = {}
    current: str | None = None

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if line.startswith("SF:"):
            current = relative_path(line[3:], root)
            files.setdefault(current, {})
            continue
        if line.startswith("DA:") and current is not None:
            line_number_text, count_text, *_ = line[3:].split(",")
            files[current][int(line_number_text)] = int(count_text) > 0
            continue
        if line == "end_of_record":
            current = None

    return files


def write_generic_coverage(files: dict[str, dict[int, bool]], output: Path) -> None:
    coverage = ET.Element("coverage", version="1")
    for file_path in sorted(files):
        file_element = ET.SubElement(coverage, "file", path=file_path)
        for line_number in sorted(files[file_path]):
            ET.SubElement(
                file_element,
                "lineToCover",
                lineNumber=str(line_number),
                covered=str(files[file_path][line_number]).lower(),
            )

    tree = ET.ElementTree(coverage)
    ET.indent(tree, space="  ")
    tree.write(output, encoding="utf-8", xml_declaration=True)


def main() -> int:
    if len(sys.argv) not in (3, 4):
        usage()
        return 2

    workspace = Path.cwd().resolve()
    root = path_under_root(sys.argv[3] if len(sys.argv) == 4 else ".", workspace)
    input_path = path_under_root(sys.argv[1], root)
    output_path = path_under_root(sys.argv[2], root)
    write_generic_coverage(parse_lcov(input_path, root), output_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
