#!/usr/bin/env python3
"""Build pinned, self-contained tools and their corresponding-source materials."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tarfile
import urllib.parse


RECIPE = Path(__file__).resolve()
# The bundled corresponding-source recipe also works after copying Sources
# out of the application. Never write build products into a signed app bundle.
ROOT = RECIPE.parents[2] if RECIPE.parent.name == "runtime" else RECIPE.parent
LOCK = Path(__file__).with_name("sources.json")


def run(arguments: list[str], cwd: Path, env: dict[str, str]) -> str:
    """Run a build command; retain normal compiler output in the build log."""
    completed = subprocess.run(arguments, cwd=cwd, env=env, check=True,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               text=True)
    print(completed.stdout, end="", flush=True)
    return completed.stdout


def digest(path: Path) -> str:
    """Hash without retaining source archives in memory."""
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def extract(archive: Path, destination: Path) -> Path:
    """Reject traversal and escaping links before extracting pinned source."""
    destination.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive) as source:
        source.extractall(destination, filter="data")
    roots = list(destination.iterdir())
    if len(roots) != 1 or not roots[0].is_dir():
        raise ValueError(f"Expected one source directory in {archive.name}")
    return roots[0]


def fetch_sources(lock: dict, work: Path, env: dict[str, str]) -> dict[str, Path]:
    """Download over TLS and require the committed source hash."""
    archives = work / "downloads"
    archives.mkdir(exist_ok=True)
    result: dict[str, Path] = {}
    for name, record in lock["sources"].items():
        url = record["url"]
        if urllib.parse.urlsplit(url).scheme != "https":
            raise ValueError("Runtime sources must use HTTPS")
        archive = archives / Path(urllib.parse.urlsplit(url).path).name
        supplied = RECIPE.parent / archive.name
        if not archive.exists() and supplied.is_file():
            shutil.copy2(supplied, archive)
        if not archive.exists():
            run(["/usr/bin/curl", "--fail", "--location", "--retry", "3",
                 "--proto", "=https", "--output", str(archive), url], work, env)
        if digest(archive) != record["sha256"]:
            raise ValueError(f"Source hash mismatch: {name}")
        source_root = work / "sources" / f"{name}-{record['sha256'][:16]}"
        result[name] = (next(source_root.iterdir()) if source_root.exists()
                        else extract(archive, source_root))
    return result


def copy_program(source: Path, destination: Path) -> None:
    """Copy only an expected executable into the runtime bin directory."""
    if not source.is_file() or not os.access(source, os.X_OK):
        raise ValueError(f"Missing built executable: {source}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)


def copy_notice(source: Path, destination: Path) -> None:
    """Keep copies of read-only Go module notices replaceable on rebuild."""
    if destination.exists():
        destination.chmod(0o644)
    shutil.copyfile(source, destination)
    destination.chmod(0o644)


def build(work: Path, jobs: int) -> Path:
    """Build native tools without linking Homebrew libraries."""
    lock = json.loads(LOCK.read_text())
    work.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    env.update(MACOSX_DEPLOYMENT_TARGET=lock["minimum_macos"],
               CGO_ENABLED="0", GOOS="darwin", GOTOOLCHAIN="local",
               GOCACHE=str(work / "go-cache"),
               GOMODCACHE=str(work / "go-modules"))
    for key in ["CPATH", "LIBRARY_PATH", "LDFLAGS", "CPPFLAGS",
                "PKG_CONFIG_PATH", "DYLD_LIBRARY_PATH"]:
        env.pop(key, None)
    go = shutil.which("go")
    if go is None:
        raise ValueError("Install the development Go toolchain first")
    if lock["go_version"] not in subprocess.check_output([go, "version"], text=True):
        raise ValueError(f"Use {lock['go_version']} for reproducible runtime builds")
    output = work / "Tools"
    fingerprint = {
        "format": 2, "architecture": platform.machine(),
        "minimum_macos": lock["minimum_macos"],
        "sources_lock_sha256": digest(LOCK), "recipe_sha256": digest(RECIPE),
        "go_version": lock["go_version"],
        "compiler": subprocess.check_output(["/usr/bin/clang", "--version"], text=True),
        "sdk": subprocess.check_output(["/usr/bin/xcrun", "--show-sdk-version"], text=True).strip(),
    }
    info = output / "build-info.json"
    if info.is_file():
        saved = json.loads(info.read_text())
        products = saved.pop("products", {})
        if saved == fingerprint and products and all(
            (output / name).is_file() and digest(output / name) == value
            for name, value in products.items()
        ):
            print(f"Verified cached runtime: {output}", flush=True)
            return output
    source = fetch_sources(lock, work, env)
    if output.exists():
        # Only our narrowly scoped generated payload is replaced, never sources.
        if output.is_symlink() or not info.is_file():
            raise ValueError("Refusing to replace an unrecognised Tools directory")
        shutil.rmtree(output)
    output.mkdir(exist_ok=True)
    flags = f"-O2 -mmacosx-version-min={lock['minimum_macos']}"
    git_args = ["/usr/bin/make", f"-j{jobs}", "NO_HOMEBREW=1",
                "NO_DARWIN_PORTS=1", "NO_FINK=1", "NO_GETTEXT=1",
                "NO_PERL=1", "NO_PYTHON=1", "NO_TCLTK=1", "NO_EXPAT=1",
                "NO_RUST=1", "CURL_CONFIG=/usr/bin/false",
                f"CURL_CFLAGS=-I{source['curl-headers'] / 'include'}",
                "CURL_LDFLAGS=-lcurl", f"CFLAGS={flags}",
                "git", "git-remote-http"]
    run(git_args, source["git"], env)
    run([*git_args[:-2], "contrib/credential/osxkeychain/git-credential-osxkeychain"], source["git"], env)
    for name in ["git", "git-remote-http"]:
        destination = (output / "bin" / name if name == "git"
                       else output / "libexec/git-core" / name)
        copy_program(source["git"] / name, destination)
    copy_program(source["git"] / "git-remote-http", output / "libexec/git-core/git-remote-https")
    copy_program(source["git"] / "contrib/credential/osxkeychain/git-credential-osxkeychain",
                 output / "libexec/git-core/git-credential-osxkeychain")
    for name, arguments, program in [
        ("rsync", ["--disable-idn", "--disable-xxhash", "--disable-zstd", "--disable-lz4",
                   "--disable-openssl", "--disable-md2man"], "rsync"),
        ("tar", ["--disable-nls", "--without-libiconv-prefix",
                 "--without-libintl-prefix"], "src/tar"),
    ]:
        tool_env = env | {"CFLAGS": flags, "LDFLAGS": f"-mmacosx-version-min={lock['minimum_macos']}"}
        if not (source[name] / "Makefile").exists():
            run(["./configure", *arguments], source[name], tool_env)
        make_args = ["/usr/bin/make", f"-j{jobs}"]
        if name == "tar":
            make_args.append("LIBS=-liconv")
        run([*make_args, "rsync" if name == "rsync" else "all"], source[name], tool_env)
        copy_program(source[name] / program, output / "bin" / ("gtar" if name == "tar" else name))
    for program in ["age", "age-keygen"]:
        version = lock["sources"]["age"]["version"]
        run([go, "build", "-p", str(jobs), "-trimpath", f"-ldflags=-s -w -X main.Version=v{version}",
             "-o", str(output / "bin" / program), f"./cmd/{program}"], source["age"], env)
    templates = output / "share/git-core/templates"
    templates.mkdir(parents=True, exist_ok=True)
    notices = output / "Notices"
    notices.mkdir(exist_ok=True)
    for name, directory in source.items():
        target = notices / name
        target.mkdir(exist_ok=True)
        for pattern in ["COPYING*", "LICENSE*", "NOTICE*"]:
            for item in directory.glob(pattern):
                if item.is_file():
                    copy_notice(item, target / item.name)
    # Retain notices for every Go dependency, not just age itself.
    modules = run([go, "list", "-m", "-json", "all"], source["age"], env)
    decoder = json.JSONDecoder()
    while modules.strip():
        module, end = decoder.raw_decode(modules.lstrip())
        modules = modules.lstrip()[end:]
        directory = module.get("Dir")
        if directory:
            target = notices / "go-modules" / module["Path"]
            target.mkdir(parents=True, exist_ok=True)
            for pattern in ["LICENSE*", "COPYING*"]:
                for item in Path(directory).glob(pattern):
                    if item.is_file():
                        copy_notice(item, target / item.name)
    go_root = subprocess.check_output([go, "env", "GOROOT"], text=True).strip()
    go_license = Path(go_root) / "LICENSE"
    if not go_license.is_file():
        go_license = Path(go_root).parent / "LICENSE"
    copy_notice(go_license, notices / "Go-LICENSE")
    shutil.copy2(LOCK, output / "sources.json")
    source_offer = output / "Sources"
    source_offer.mkdir(exist_ok=True)
    for name, record in lock["sources"].items():
        if name != "curl-headers":
            archive = work / "downloads" / Path(urllib.parse.urlsplit(record["url"]).path).name
            shutil.copy2(archive, source_offer / archive.name)
    headers = source_offer / "curl-public-headers"
    if not headers.exists():
        shutil.copytree(source["curl-headers"] / "include", headers)
    shutil.copy2(Path(__file__), source_offer / "build_runtime.py")
    shutil.copy2(LOCK, source_offer / "sources.json")
    shutil.copy2(Path(__file__).with_name("README.md"), source_offer / "README.md")
    fingerprint["products"] = {
        str(path.relative_to(output)): digest(path)
        for path in sorted(output.rglob("*")) if path.is_file()
    }
    info.write_text(json.dumps(fingerprint, indent=2) + "\n")
    print(f"Runtime ready: {output}", flush=True)
    return output


def main() -> None:
    """Build only under the repository's generated-artifact directory."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=Path, default=ROOT / ".build/store-runtime")
    parser.add_argument("--jobs", type=int, default=2)
    args = parser.parse_args()
    work = args.work.resolve()
    if any(parent.suffix == ".app" for parent in RECIPE.parents):
        parser.error("Copy the Sources folder out of the application before building")
    if not work.is_relative_to(ROOT / ".build") or not 1 <= args.jobs <= 8:
        parser.error("Use a work directory under .build and 1–8 jobs")
    try:
        build(work, args.jobs)
    except subprocess.CalledProcessError as error:
        print(error.stdout or "", flush=True)
        raise SystemExit(f"Runtime build failed: {error.cmd[0]}") from error


if __name__ == "__main__":
    main()
