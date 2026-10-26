#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "pytest>=8",
#   "pyobjc-framework-Quartz>=10",
# ]
# ///
"""Run PeekLock end-to-end tests.

Examples:
  uv run e2e/run.py                 # CLI + bundle tests (safe, never locks input)
  uv run e2e/run.py --lock          # also run tests that really lock input for a few seconds
  uv run e2e/run.py -- -k status    # extra arguments after -- go to pytest
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

import pytest

E2E_DIR = Path(__file__).resolve().parent


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--lock",
        action="store_true",
        help="run input-locking tests (needs Accessibility + Input Monitoring for this terminal)",
    )
    parser.add_argument("pytest_args", nargs="*", help="extra pytest arguments (after --)")
    args = parser.parse_args()

    if args.lock:
        os.environ["PEEKLOCK_E2E_LOCK"] = "1"
    return pytest.main(
        [
            str(E2E_DIR),
            "--rootdir",
            str(E2E_DIR),
            "-p",
            "no:cacheprovider",
            "-ra",
            *args.pytest_args,
        ]
    )


if __name__ == "__main__":
    sys.exit(main())
