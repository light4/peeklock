"""Real input locking (opt-in: `uv run e2e/run.py --lock`).

Each test locks this Mac for a few seconds with the *debug* CLI, which also auto-unlocks
after PEEKLOCK_DEBUG_AUTOUNLOCK seconds as a safety net.

Method: synthetic probe events (F19 key down/up and a zero-delta scroll, both harmless) are
posted at the HID tap point and counted by a listen-only *session* tap in this process.
PeekLock's HID tap sits in front of the session tap, so while locked the probes must not
arrive. Every test first checks that probes do arrive without a lock, so a broken
environment fails loudly instead of passing by accident.

Requires, for this terminal app: Accessibility (post events, and for peeklock itself) and
Input Monitoring (listen-only tap).
"""

from __future__ import annotations

import os
import signal
import subprocess
import threading
import time
from collections.abc import Iterator

import pytest
from conftest import ROOT, Build

pytestmark = pytest.mark.skipif(
    os.environ.get("PEEKLOCK_E2E_LOCK") != "1",
    reason="locks input; run with `uv run e2e/run.py --lock`",
)

Quartz = pytest.importorskip("Quartz")

PROBE_TAG = 0x504B4C4B  # "PKLK", stored in kCGEventSourceUserData
KEY_F19 = 80
SAFETY_SECONDS = 20


class ProbeListener:
    """Listen-only session tap counting events tagged with PROBE_TAG."""

    def __init__(self) -> None:
        self.count = 0
        mask = (
            Quartz.CGEventMaskBit(Quartz.kCGEventKeyDown)
            | Quartz.CGEventMaskBit(Quartz.kCGEventKeyUp)
            | Quartz.CGEventMaskBit(Quartz.kCGEventScrollWheel)
        )
        self.tap = Quartz.CGEventTapCreate(
            Quartz.kCGSessionEventTap,
            Quartz.kCGTailAppendEventTap,
            Quartz.kCGEventTapOptionListenOnly,
            mask,
            self._callback,
            None,
        )
        if self.tap is None:
            pytest.skip("cannot create listen-only tap: grant Input Monitoring to this terminal")
        source = Quartz.CFMachPortCreateRunLoopSource(None, self.tap, 0)
        Quartz.CFRunLoopAddSource(
            Quartz.CFRunLoopGetCurrent(), source, Quartz.kCFRunLoopCommonModes
        )
        Quartz.CGEventTapEnable(self.tap, True)

    def _callback(self, proxy, event_type, event, refcon):
        tag = Quartz.CGEventGetIntegerValueField(event, Quartz.kCGEventSourceUserData)
        if tag == PROBE_TAG:
            self.count += 1
        return event

    def probe(self, settle: float = 0.8) -> int:
        """Post one key down/up + one scroll and return how many reached the session."""
        self.count = 0
        source = Quartz.CGEventSourceCreate(Quartz.kCGEventSourceStatePrivate)
        events = [
            Quartz.CGEventCreateKeyboardEvent(source, KEY_F19, True),
            Quartz.CGEventCreateKeyboardEvent(source, KEY_F19, False),
            Quartz.CGEventCreateScrollWheelEvent(source, Quartz.kCGScrollEventUnitPixel, 1, 0),
        ]
        for event in events:
            Quartz.CGEventSetIntegerValueField(event, Quartz.kCGEventSourceUserData, PROBE_TAG)
            Quartz.CGEventPost(Quartz.kCGHIDEventTap, event)
        deadline = time.monotonic() + settle
        while time.monotonic() < deadline:
            Quartz.CFRunLoopRunInMode(Quartz.kCFRunLoopDefaultMode, 0.05, False)
        return self.count


class Locker:
    """Runs the debug CLI and collects its stderr."""

    def __init__(self, build: Build, *args: str, safety: int = SAFETY_SECONDS) -> None:
        env = {**os.environ, "PEEKLOCK_DEBUG_AUTOUNLOCK": str(safety)}
        self.proc = subprocess.Popen(
            [str(build.cli), *args],
            cwd=ROOT,
            env=env,
            stderr=subprocess.PIPE,
            stdout=subprocess.DEVNULL,
            text=True,
        )
        self.stderr = ""
        self._reader = threading.Thread(target=self._read, daemon=True)
        self._reader.start()

    def _read(self) -> None:
        assert self.proc.stderr is not None
        for line in self.proc.stderr:
            self.stderr += line

    def wait_for(self, text: str, timeout: float = 10) -> None:
        deadline = time.monotonic() + timeout
        while text not in self.stderr and time.monotonic() < deadline:
            if self.proc.poll() is not None:
                break
            time.sleep(0.1)
        assert text in self.stderr, f"peeklock never printed {text!r}; stderr:\n{self.stderr}"

    def stop(self, timeout: float = 5) -> int:
        if self.proc.poll() is None:
            self.proc.send_signal(signal.SIGTERM)
        return self.proc.wait(timeout=timeout)


@pytest.fixture
def listener(debug_build: Build, accessibility_granted: bool) -> ProbeListener:
    if not accessibility_granted:
        pytest.skip("grant Accessibility to this terminal app")
    if not Quartz.CGPreflightPostEventAccess():
        pytest.skip("this terminal may not post events (Accessibility)")
    probe = ProbeListener()
    assert probe.probe() == 3, "control probe did not reach the session without a lock"
    return probe


@pytest.fixture
def locker(debug_build: Build) -> Iterator[list[Locker]]:
    started: list[Locker] = []
    yield started
    for item in started:  # never leave this Mac locked
        if item.proc.poll() is None:
            item.proc.kill()
            item.proc.wait(timeout=5)


def start_lock(build: Build, holder: list[Locker], *args: str, safety: int = SAFETY_SECONDS):
    lock = Locker(build, *args, safety=safety)
    holder.append(lock)
    lock.wait_for("auto-unlocking in")
    time.sleep(0.5)  # let the taps settle
    return lock


def test_lock_swallows_input_and_sigterm_releases(
    debug_build: Build, listener: ProbeListener, locker: list[Locker]
) -> None:
    lock = start_lock(debug_build, locker)
    assert lock.proc.poll() is None, lock.stderr
    assert listener.probe() == 0, "keys/scroll leaked through while locked"
    assert lock.stop() == 0
    assert listener.probe() == 3, "input still blocked after unlock"


def test_blank_mode_locks_and_releases(
    debug_build: Build, listener: ProbeListener, locker: list[Locker]
) -> None:
    lock = start_lock(debug_build, locker, "-b")
    assert listener.probe() == 0
    assert lock.stop() == 0
    assert listener.probe() == 3


def test_debug_safety_auto_unlock(
    debug_build: Build, listener: ProbeListener, locker: list[Locker]
) -> None:
    lock = start_lock(debug_build, locker, safety=3)
    assert listener.probe() == 0
    assert lock.proc.wait(timeout=15) == 0
    assert "safety auto-unlock fired" in lock.stderr
    assert listener.probe() == 3
