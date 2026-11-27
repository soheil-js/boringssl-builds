#!/usr/bin/env python3

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import shutil
import stat
import sys
import zipfile
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Package BoringSSL shared libraries and public headers."
    )
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--build", required=True, type=Path)
    parser.add_argument("--rid", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--upstream-sha", default="unknown")
    return parser.parse_args()


def _handle_remove_readonly(func, path: str, exc_info) -> None:
    try:
        os.chmod(path, stat.S_IWRITE)
    except OSError:
        pass
    func(path)


def remove_tree_safe(target: Path) -> None:
    if not target.exists():
        return
    if sys.version_info >= (3, 12):
        shutil.rmtree(target, onexc=_handle_remove_readonly)
    else:
        shutil.rmtree(target, onerror=_handle_remove_readonly)


def find_one(root: Path, names: list[str]) -> Path:
    matches: list[Path] = []

    for name in names:
        for p in root.rglob(name):
            if not p.is_file() or p.is_symlink():
                continue
            if p.stat().st_size <= 0:
                continue
            lower_parts = {part.lower() for part in p.parts}
            if "test" in lower_parts or "tests" in lower_parts:
                continue
            matches.append(p)

    unique = sorted(set(matches), key=lambda p: (len(p.parts), str(p)))
    if not unique:
        raise FileNotFoundError(
            f"Could not find any valid non-empty file matching {names!r} under {root}"
        )

    if len(unique) > 1:
        print(
            f"Warning: multiple candidates for {names}; using {unique[0]}",
            file=sys.stderr,
        )

    return unique[0]


def copy_headers(source: Path, destination: Path) -> None:
    headers = source / "include" / "openssl"
    if not headers.is_dir():
        raise FileNotFoundError(f"Public headers directory not found: {headers}")

    target_headers = destination / "include" / "openssl"
    remove_tree_safe(target_headers)
    shutil.copytree(headers, target_headers)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    args = parse_args()

    source = args.source.resolve()
    build = args.build.resolve()
    output = args.output.resolve()

    if not source.is_dir() or not build.is_dir():
        raise FileNotFoundError("Source or build directory does not exist.")

    supported = {
        "win-x64", "win-arm64",
        "linux-x64", "linux-arm64",
        "osx-x64", "osx-arm64",
    }
    if args.rid not in supported:
        raise ValueError(f"Unsupported RID: {args.rid}")

    package_root = output / f"boringssl-{args.rid}"
    archive = output / f"boringssl-{args.rid}.zip"
    temp_archive = output / f".boringssl-{args.rid}.zip.tmp"

    remove_tree_safe(package_root)
    if temp_archive.exists():
        temp_archive.unlink()

    package_root.mkdir(parents=True, exist_ok=True)
    output.mkdir(parents=True, exist_ok=True)

    copy_headers(source, package_root)

    lib_dir = package_root / "lib"
    bin_dir = package_root / "bin"
    lib_dir.mkdir(exist_ok=True)
    bin_dir.mkdir(exist_ok=True)

    copied: list[Path] = []

    if args.rid.startswith("win-"):
        shared_names = {
            "crypto": ["crypto.dll"],
            "ssl": ["ssl.dll"],
        }
        import_names = {
            "crypto": ["crypto.lib"],
            "ssl": ["ssl.lib"],
        }

        for names in shared_names.values():
            file = find_one(build, names)
            target = bin_dir / file.name
            shutil.copy2(file, target)
            copied.append(target)

        for names in import_names.values():
            file = find_one(build, names)
            target = lib_dir / file.name
            shutil.copy2(file, target)
            copied.append(target)

    elif args.rid.startswith("linux-"):
        for names in (["libcrypto.so"], ["libssl.so"]):
            file = find_one(build, names)
            target = lib_dir / file.name
            shutil.copy2(file, target)
            copied.append(target)

    else:
        for names in (["libcrypto.dylib"], ["libssl.dylib"]):
            file = find_one(build, names)
            target = lib_dir / file.name
            shutil.copy2(file, target)
            copied.append(target)

    license_candidates = [
        source / "LICENSE",
        source / "LICENSE.txt",
    ]
    license_file = next((p for p in license_candidates if p.is_file()), None)
    if license_file:
        shutil.copy2(license_file, package_root / "LICENSE")

    metadata = {
        "project": "BoringSSL",
        "upstream_repository": "https://github.com/google/boringssl",
        "upstream_commit": args.upstream_sha,
        "rid": args.rid,
        "build_type": "Release",
        "build_shared_libs": True,
        "built_on": platform.platform(),
        "libraries": [
            {
                "path": str(file.relative_to(package_root)).replace(os.sep, "/"),
                "sha256": sha256(file),
            }
            for file in copied
        ],
        "headers_directory": "include/openssl",
        "note": (
            "BoringSSL does not promise API or ABI stability. "
            "Use these headers and binaries from the same package."
        ),
    }

    (package_root / "build-info.json").write_text(
        json.dumps(metadata, indent=2) + "\n",
        encoding="utf-8",
    )

    with zipfile.ZipFile(
        temp_archive,
        mode="w",
        compression=zipfile.ZIP_DEFLATED,
        compresslevel=6,
    ) as zip_file:
        for file in sorted(package_root.rglob("*")):
            if file.is_file():
                zip_file.write(
                    file,
                    file.relative_to(package_root).as_posix(),
                )

    if archive.exists():
        archive.unlink()
    temp_archive.replace(archive)

    print(f"Created package: {archive}")
    print(f"Included files: {len(copied)} native libraries/import libraries")


if __name__ == "__main__":
    main()