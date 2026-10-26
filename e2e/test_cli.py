"""`peeklock` command-line behaviour (never locks input)."""

from __future__ import annotations

import pytest
from conftest import Build, app_running, in_ci, run


def test_help(debug_build: Build) -> None:
    result = run([str(debug_build.cli), "--help"])
    assert result.returncode == 0
    assert "Usage: peeklock [-b]" in result.stdout
    assert "-b" in result.stdout
    assert "--app" in result.stdout


def test_version(debug_build: Build) -> None:
    result = run([str(debug_build.cli), "--version"])
    assert result.returncode == 0
    assert result.stdout.strip().startswith("peeklock ")


def test_unknown_option_exits_2(debug_build: Build) -> None:
    result = run([str(debug_build.cli), "--definitely-not-an-option"])
    assert result.returncode == 2
    assert "unknown option --definitely-not-an-option" in result.stderr
    assert "Usage: peeklock" in result.stderr


def test_status_reports_permissions_and_hotkey(debug_build: Build) -> None:
    result = run([str(debug_build.cli), "--status"])
    assert result.returncode == 0
    lines = result.stdout.splitlines()
    assert any(line.startswith("Accessibility: ") for line in lines)
    assert any(line.startswith("Authentication: ") for line in lines)
    assert any(line.startswith("Unlock hotkey: ") for line in lines)
    assert any(line.startswith("Secure Event Input active: ") for line in lines)


@pytest.mark.skipif(app_running(), reason="PeekLock.app is running; --app would really lock")
def test_app_mode_without_running_app_fails(debug_build: Build) -> None:
    result = run([str(debug_build.cli), "--app"])
    assert result.returncode == 1
    assert "PeekLock.app is not running" in result.stderr


def test_refuses_to_lock_without_accessibility(
    debug_build: Build, accessibility_granted: bool
) -> None:
    """Never a fake lock: without Accessibility the CLI must exit 1 instead of locking."""
    if accessibility_granted:
        pytest.skip("this terminal has Accessibility; covered by test_lock.py instead")
    if not in_ci():
        pytest.skip("would open System Settings on this Mac; runs in CI only")
    result = run([str(debug_build.cli)], timeout=30)
    assert result.returncode == 1
    assert "Accessibility permission missing" in result.stderr
    assert "not locking" in result.stderr
