"""Shared fixtures: build the binaries once per session and expose their paths."""

from __future__ import annotations

import os
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
BUNDLE_ID = "com.light4.peeklock"


def run(argv: list[str], *, timeout: float = 60, **kwargs) -> subprocess.CompletedProcess[str]:
    """Run without raising; tests assert on returncode/stdout/stderr themselves."""
    return subprocess.run(
        argv, text=True, capture_output=True, timeout=timeout, cwd=ROOT, check=False, **kwargs
    )


@dataclass(frozen=True)
class Build:
    bin_dir: Path

    @property
    def cli(self) -> Path:
        return self.bin_dir / "peeklock"

    @property
    def app(self) -> Path:
        return self.bin_dir / "PeekLockApp"


@pytest.fixture(scope="session")
def debug_build() -> Build:
    """`swift build` (debug: includes the safety auto-unlock used by the lock tests)."""
    subprocess.run(["swift", "build"], cwd=ROOT, check=True, text=True, timeout=900)
    bin_dir = subprocess.run(
        ["swift", "build", "--show-bin-path"],
        cwd=ROOT,
        check=True,
        text=True,
        capture_output=True,
        timeout=120,
    ).stdout.strip()
    return Build(Path(bin_dir))


@pytest.fixture(scope="session")
def cli_status(debug_build: Build) -> str:
    return run([str(debug_build.cli), "--status"]).stdout


@pytest.fixture(scope="session")
def accessibility_granted(cli_status: str) -> bool:
    """Whether *this terminal* (the TCC responsible process) has Accessibility."""
    return "Accessibility: granted" in cli_status


def signing_identity() -> str | None:
    out = run(["security", "find-identity", "-v", "-p", "codesigning"]).stdout
    match = re.search(r'\b([0-9A-F]{40})\s+"Apple Development: ', out)
    return match.group(1) if match else None


def app_running() -> bool:
    return run(["pgrep", "-x", "PeekLock"]).returncode == 0


def in_ci() -> bool:
    return os.environ.get("CI", "").lower() == "true"
