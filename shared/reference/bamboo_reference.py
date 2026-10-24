#!/usr/bin/env python3
"""Reference implementation of the CTL-470 protocol and driver behaviour (docs/protocol.md).

Platform-neutral and stdlib-only, so every port (macOS Swift, Windows, Linux) can check itself
against the same golden files in shared/testdata/.

    python3 bamboo_reference.py decode CAPTURE.hex   # one JSON object per report
    python3 bamboo_reference.py events CAPTURE.hex   # pointer events the driver should emit
    python3 bamboo_reference.py regen                # rewrite shared/testdata/*.expected.jsonl
    python3 bamboo_reference.py check                # verify golden files are current

Capture format: one HID input report per line, space-separated hex bytes, report ID first.
Captures carry no timestamps; the event model assumes PACKET_INTERVAL between reports.
"""

import json
import math
import sys
from pathlib import Path

# --- device ------------------------------------------------------------------

VENDOR_ID = 0x056A
MODELS = {0x00DD: {"name": "CTL-470", "max_x": 14720, "max_y": 9200, "max_pressure": 1023}}
MODEL = MODELS[0x00DD]

PEN_REPORT_ID = 0x02
MODE_FEATURE_REPORT = bytes([0x02, 0x02])  # Wacom (tablet) mode
HID_FEATURE_REPORT = bytes([0x02, 0x01])   # plain mouse mode


def decode(report: bytes):
    """Decodes one input report; returns None for non-pen reports."""
    if len(report) < 9 or report[0] != PEN_REPORT_ID:
        return None
    flags = report[1]
    s = {
        "in_range": bool(flags & 0x80),
        "proximity": bool(flags & 0x40),
        "ready": bool(flags & 0x20),
        "eraser": False, "tip": False, "lower_button": False, "upper_button": False,
        "x": 0, "y": 0, "pressure": 0, "distance": report[8],
    }
    if s["proximity"]:
        s["x"] = report[2] | report[3] << 8
        s["y"] = report[4] | report[5] << 8
        s["eraser"] = bool(flags & 0x08)
    if s["ready"]:
        s["pressure"] = min(report[6] | (report[7] & 0x03) << 8, MODEL["max_pressure"])
        s["tip"] = bool(flags & 0x01)
        s["lower_button"] = bool(flags & 0x02)
        s["upper_button"] = bool(flags & 0x04)
    return s


# --- filtering ---------------------------------------------------------------

PACKET_INTERVAL = 0.005       # s; measured ~4.8 ms between pen reports
TIP_THRESHOLD = 8             # raw pressure a tip must exceed to count as down
CLICK_SNAP_DURATION = 0.15    # s the cursor holds at touch-down...
CLICK_SNAP_RADIUS = 250.0     # ...unless it travels this far (tablet units, 100 ≈ 1 mm)
DOUBLE_CLICK_DISTANCE = 300.0 # tablet units
DOUBLE_CLICK_INTERVAL = 0.5   # s; macOS default, platforms should use the system setting


class OneEuro:
    def __init__(self, min_cutoff=1.0, beta=0.02, d_cutoff=1.0):
        self.min_cutoff, self.beta, self.d_cutoff = min_cutoff, beta, d_cutoff
        self.value = None
        self.derivative = 0.0
        self.last_time = 0.0

    @staticmethod
    def _alpha(cutoff, dt):
        tau = 1 / (2 * math.pi * cutoff)
        return 1 / (1 + tau / dt)

    def reset(self):
        self.value = None

    def __call__(self, x, t):
        if self.value is None:
            self.value, self.last_time = x, t
            return x
        dt = max(t - self.last_time, 1 / 1000)
        self.last_time = t
        raw = (x - self.value) / dt
        self.derivative += self._alpha(self.d_cutoff, dt) * (raw - self.derivative)
        cutoff = self.min_cutoff + self.beta * abs(self.derivative)
        self.value += self._alpha(cutoff, dt) * (x - self.value)
        return self.value


class PenFilter:
    def __init__(self):
        self.fx, self.fy = OneEuro(), OneEuro()
        self.anchor = None
        self.released = False

    def reset(self):
        self.fx.reset(); self.fy.reset()
        self.anchor, self.released = None, False

    def position(self, x, y, tip, t):
        p = (self.fx(float(x), t), self.fy(float(y), t))
        if not tip:
            self.anchor, self.released = None, False
            return p
        if self.anchor is None:
            self.anchor = (p[0], p[1], t)
            return p
        ax, ay, at = self.anchor
        if not self.released and t - at < CLICK_SNAP_DURATION and math.hypot(p[0] - ax, p[1] - ay) < CLICK_SNAP_RADIUS:
            return (ax, ay)
        self.released = True
        return p


# --- driver behaviour --------------------------------------------------------

def events(reports):
    """Yields the platform-neutral pointer events a driver should emit.

    Positions are normalised 0..1 over the full tablet; platforms apply their own
    screen mapping (and optional aspect-ratio crop) on top.
    """
    f = PenFilter()
    present = tip_down = lower = upper = False
    t = 0.0
    last_click_t, last_click_p, clicks = -1e9, (0.0, 0.0), 1
    for r in reports:
        t += PACKET_INTERVAL
        s = decode(r)
        if s is None:
            continue
        now_present = s["proximity"] and s["ready"]
        if now_present != present:
            if not now_present:
                for name, down in (("tip_up", tip_down), ("lower_up", lower), ("upper_up", upper)):
                    if down:
                        yield {"t": round(t, 3), "event": name}
                tip_down = lower = upper = False
                f.reset()
            yield {"t": round(t, 3), "event": "proximity_enter" if now_present else "proximity_exit",
                   "eraser": s["eraser"]}
            present = now_present
        if not present:
            continue
        tip = s["tip"] and s["pressure"] > TIP_THRESHOLD
        x, y = f.position(s["x"], s["y"], tip, t)
        base = {"t": round(t, 3), "x": round(x / MODEL["max_x"], 4), "y": round(y / MODEL["max_y"], 4),
                "pressure": round(s["pressure"] / MODEL["max_pressure"], 4)}
        if tip != tip_down:
            if tip:
                near = math.hypot(x - last_click_p[0], y - last_click_p[1]) < DOUBLE_CLICK_DISTANCE
                clicks = clicks + 1 if (t - last_click_t < DOUBLE_CLICK_INTERVAL and near) else 1
                last_click_t, last_click_p = t, (x, y)
            tip_down = tip
            yield {**base, "event": "tip_down" if tip else "tip_up", "clicks": clicks}
        elif s["lower_button"] != lower:
            lower = s["lower_button"]
            yield {**base, "event": "lower_down" if lower else "lower_up"}
        elif s["upper_button"] != upper:
            upper = s["upper_button"]
            yield {**base, "event": "upper_down" if upper else "upper_up"}
        else:
            yield {**base, "event": "drag" if (tip_down or lower or upper) else "move"}


# --- golden files ------------------------------------------------------------

TESTDATA = Path(__file__).resolve().parent.parent / "testdata"


def read_capture(path):
    return [bytes.fromhex(line) for line in Path(path).read_text().splitlines() if line.strip()]


def render(kind, reports):
    if kind == "decode":
        rows = (decode(r) for r in reports)
        rows = (r for r in rows if r is not None)
    else:
        rows = events(reports)
    return "".join(json.dumps(r, sort_keys=True) + "\n" for r in rows)


def golden_pairs():
    for capture in sorted(TESTDATA.glob("*.hex")):
        for kind in ("decode", "events"):
            yield capture, kind, capture.with_name(f"{capture.stem}.{kind}.expected.jsonl")


def main(argv):
    if len(argv) == 3 and argv[1] in ("decode", "events"):
        sys.stdout.write(render(argv[1], read_capture(argv[2])))
    elif argv[1:] == ["regen"]:
        for capture, kind, golden in golden_pairs():
            golden.write_text(render(kind, read_capture(capture)))
            print("wrote", golden.relative_to(TESTDATA.parent.parent))
    elif argv[1:] == ["check"]:
        stale = [g for c, k, g in golden_pairs() if not g.exists() or g.read_text() != render(k, read_capture(c))]
        for g in stale:
            print("stale:", g.relative_to(TESTDATA.parent.parent))
        sys.exit(1 if stale else 0)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv)
