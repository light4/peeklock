#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///
"""Build PeekLock.app, sign it with the local Apple Development identity, optionally install."""

from __future__ import annotations

import argparse
import hashlib
import os
import plistlib
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
BUNDLE_ID = "io.i01.peeklock"
VERSION_FILE = ROOT / "Sources" / "PeekLockCore" / "Version.swift"


def read_version() -> str:
    match = re.search(r'peekLockVersion = "([^"]+)"', VERSION_FILE.read_text())
    if not match:
        raise SystemExit(f"cannot find peekLockVersion in {VERSION_FILE}")
    return match.group(1)


VERSION = read_version()


def run(argv: list[str], **kwargs) -> subprocess.CompletedProcess[str]:
    print("+", " ".join(argv), flush=True)
    return subprocess.run(argv, check=True, text=True, cwd=ROOT, timeout=900, **kwargs)


def find_identity() -> str:
    out = run(["security", "find-identity", "-v", "-p", "codesigning"], capture_output=True).stdout
    for line in out.splitlines():
        match = re.search(r'\b([0-9A-F]{40})\s+"(Apple Development: [^"]+)"', line)
        if match:
            return match.group(1)
    raise SystemExit("no 'Apple Development' signing identity found (use --identity or --adhoc)")


def make_icon(resources: Path) -> None:
    iconset = BUILD / "AppIcon.iconset"
    shutil.rmtree(iconset, ignore_errors=True)
    run(["swift", "scripts/make-icon.swift", str(iconset)])
    run(["iconutil", "-c", "icns", str(iconset), "-o", str(resources / "AppIcon.icns")])


def build_bundle(config: str) -> Path:
    run(["swift", "build", "-c", config, "--product", "PeekLockApp"])
    run(["swift", "build", "-c", config, "--product", "peeklock"])
    bin_dir = Path(
        run(["swift", "build", "-c", config, "--show-bin-path"], capture_output=True).stdout.strip()
    )

    app = BUILD / "PeekLock.app"
    shutil.rmtree(app, ignore_errors=True)
    macos = app / "Contents" / "MacOS"
    resources = app / "Contents" / "Resources"
    helpers = app / "Contents" / "Helpers"
    for d in (macos, resources, helpers):
        d.mkdir(parents=True)
    shutil.copy2(bin_dir / "PeekLockApp", macos / "PeekLock")
    # The CLI lives in Helpers/: on case-insensitive APFS, MacOS/peeklock == MacOS/PeekLock.
    shutil.copy2(bin_dir / "peeklock", helpers / "peeklock")
    make_icon(resources)

    info = {
        "CFBundleIdentifier": BUNDLE_ID,
        "CFBundleName": "PeekLock",
        "CFBundleDisplayName": "PeekLock",
        "CFBundleExecutable": "PeekLock",
        "CFBundleIconFile": "AppIcon",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": VERSION,
        "CFBundleVersion": VERSION,
        "LSMinimumSystemVersion": "13.0",
        "LSUIElement": True,
        "NSHighResolutionCapable": True,
        "NSHumanReadableCopyright": "PeekLock — xtrlock-style input lock for macOS",
    }
    with open(app / "Contents" / "Info.plist", "wb") as fh:
        plistlib.dump(info, fh)
    return app


def sign(app: Path, identity: str) -> None:
    base = ["codesign", "--force", "--options", "runtime", "--timestamp=none", "--sign", identity]
    run(base + ["--identifier", f"{BUNDLE_ID}.cli", str(app / "Contents/Helpers/peeklock")])
    run(base + [str(app)])
    run(["codesign", "--verify", "--strict", "--verbose=2", str(app)])


def make_zip(app: Path) -> Path:
    """Zip with ditto (keeps the code signature intact) and write a .sha256 next to it."""
    archive = BUILD / f"PeekLock-{VERSION}.zip"
    archive.unlink(missing_ok=True)
    run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(archive)])
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    checksum = archive.with_name(archive.name + ".sha256")
    checksum.write_text(f"{digest}  {archive.name}\n")
    print(f"zipped {archive}\nsha256 {digest}")
    return archive


def install(app: Path) -> None:
    dest = Path.home() / "Applications" / "PeekLock.app"
    subprocess.run(["pkill", "-x", "PeekLock"], check=False, timeout=10)
    shutil.rmtree(dest, ignore_errors=True)
    dest.parent.mkdir(parents=True, exist_ok=True)
    run(["ditto", str(app), str(dest)])
    link = Path.home() / ".local" / "bin" / "peeklock"
    link.parent.mkdir(parents=True, exist_ok=True)
    if link.is_symlink() or link.exists():
        link.unlink()
    link.symlink_to(dest / "Contents" / "Helpers" / "peeklock")
    print(f"installed {dest}")
    print(f"linked    {link} -> {os.readlink(link)}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--debug", action="store_true", help="build debug (includes 60s safety auto-unlock)"
    )
    parser.add_argument("--identity", help="codesign identity (default: first Apple Development)")
    parser.add_argument(
        "--adhoc", action="store_true", help="ad-hoc sign (permissions reset on every rebuild)"
    )
    parser.add_argument(
        "--install",
        action="store_true",
        help="install to ~/Applications and link CLI to ~/.local/bin",
    )
    parser.add_argument(
        "--zip", action="store_true", help="also create build/PeekLock-<version>.zip + .sha256"
    )
    parser.add_argument("--print-version", action="store_true", help="print version and exit")
    args = parser.parse_args()

    if args.print_version:
        print(VERSION)
        return 0

    app = build_bundle("debug" if args.debug else "release")
    identity = "-" if args.adhoc else (args.identity or find_identity())
    sign(app, identity)
    print(f"built {app}")
    if args.zip:
        make_zip(app)
    if args.install:
        install(app)
    return 0


if __name__ == "__main__":
    sys.exit(main())
