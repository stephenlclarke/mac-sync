"""Deterministic tests for runtime inspection and pinned source extraction."""

import io
from pathlib import Path
import tarfile
import tempfile
import unittest

from audit_runtime import minimum_versions, system_dependencies
from build_runtime import digest, extract


class RuntimeAuditTests(unittest.TestCase):
    def test_rejects_non_system_dependencies(self) -> None:
        output = "tool:\n\t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0)\n\t/opt/homebrew/opt/example.dylib (compatibility version 1.0.0)\n"
        self.assertEqual(system_dependencies(output), ["/opt/homebrew/opt/example.dylib"])

    def test_ignores_compiler_tool_version(self) -> None:
        output = "Load command 1\n cmd LC_BUILD_VERSION\n minos 13.0\n sdk 27.2\n tool LD\n version 1300.1\nLoad command 2\n cmd LC_SOURCE_VERSION\n version 99.1\n"
        self.assertEqual(minimum_versions(output), [(13, 0)])
        self.assertEqual(minimum_versions("cmd LC_VERSION_MIN_MACOSX\n version 14.0\n sdk 27.2\n"), [(14, 0)])

    def test_hashes_stream_and_extracts_one_safe_source_root(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / "test.tar.gz"
            with tarfile.open(archive, "w:gz") as output:
                item = tarfile.TarInfo("source/file")
                item.size = 4
                output.addfile(item, io.BytesIO(b"test"))
            self.assertEqual(len(digest(archive)), 64)
            self.assertEqual((extract(archive, root / "extracted") / "file").read_bytes(), b"test")

    def test_rejects_archive_traversal(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / "unsafe.tar.gz"
            with tarfile.open(archive, "w:gz") as output:
                item = tarfile.TarInfo("../../escaped")
                output.addfile(item, io.BytesIO())
            with self.assertRaises(tarfile.FilterError):
                extract(archive, root / "extracted")
            self.assertFalse((root / "escaped").exists())


if __name__ == "__main__":
    unittest.main()
