"""Packaging: build PeekLock.app with scripts/package.py and inspect / launch it."""

from __future__ import annotations

import plistlib
import signal
import time
from pathlib import Path

import pytest
from conftest import BUNDLE_ID, ROOT, run, signing_identity

APP = ROOT / "build" / "PeekLock.app"


@pytest.fixture(scope="module")
def bundle(debug_build) -> Path:
    """Package the debug build (reuses the session build). Ad-hoc if no dev identity."""
    argv = ["uv", "run", "scripts/package.py", "--debug"]
    if signing_identity() is None:
        argv.append("--adhoc")
    result = run(argv, timeout=900)
    assert result.returncode == 0, result.stdout + result.stderr
    return APP


def test_layout(bundle: Path) -> None:
    contents = bundle / "Contents"
    assert (contents / "MacOS" / "PeekLock").is_file()
    assert (contents / "Helpers" / "peeklock").is_file()
    assert (contents / "Resources" / "AppIcon.icns").is_file()
    # Regression: on case-insensitive APFS, MacOS/peeklock would overwrite MacOS/PeekLock.
    assert [p.name for p in (contents / "MacOS").iterdir()] == ["PeekLock"]


def test_info_plist(bundle: Path) -> None:
    with open(bundle / "Contents" / "Info.plist", "rb") as fh:
        info = plistlib.load(fh)
    assert info["CFBundleIdentifier"] == BUNDLE_ID
    assert info["CFBundleExecutable"] == "PeekLock"
    assert info["LSUIElement"] is True
    assert info["CFBundleIconFile"] == "AppIcon"


def test_codesign_verifies(bundle: Path) -> None:
    result = run(["codesign", "--verify", "--strict", "--verbose=2", str(bundle)])
    assert result.returncode == 0, result.stderr
    assert "satisfies its Designated Requirement" in result.stderr
    cli = run(["codesign", "-dv", str(bundle / "Contents" / "Helpers" / "peeklock")])
    assert f"Identifier={BUNDLE_ID}.cli" in cli.stderr


def test_bundled_cli_runs(bundle: Path) -> None:
    result = run([str(bundle / "Contents" / "Helpers" / "peeklock"), "--version"])
    assert result.returncode == 0
    assert result.stdout.startswith("peeklock ")


def test_app_launches_as_menu_bar_agent(bundle: Path) -> None:
    """Launch a second instance, check it is an accessory app and logs its startup."""
    from AppKit import NSApplicationActivationPolicyAccessory, NSRunningApplication

    executable = str(bundle / "Contents" / "MacOS" / "PeekLock")
    before = set(run(["pgrep", "-f", executable]).stdout.split())
    assert run(["open", "-n", "-g", str(bundle)]).returncode == 0

    pid = None
    deadline = time.monotonic() + 15
    while pid is None and time.monotonic() < deadline:
        new = set(run(["pgrep", "-f", executable]).stdout.split()) - before
        pid = int(new.pop()) if new else None
        time.sleep(0.3)
    assert pid is not None, "PeekLock.app did not start"

    try:
        logged = ""
        deadline = time.monotonic() + 20
        while "PeekLock started." not in logged and time.monotonic() < deadline:
            time.sleep(1)
            logged = run(
                [
                    "log",
                    "show",
                    "--last",
                    "2m",
                    "--style",
                    "compact",
                    "--predicate",
                    f'subsystem == "{BUNDLE_ID}" AND processID == {pid}',
                ],
                timeout=60,
            ).stdout
        assert "PeekLock started." in logged, logged

        app = NSRunningApplication.runningApplicationWithProcessIdentifier_(pid)
        assert app is not None
        assert app.activationPolicy() == NSApplicationActivationPolicyAccessory
        assert app.bundleIdentifier() == BUNDLE_ID
    finally:
        run(["kill", f"-{signal.SIGTERM.value}", str(pid)])
