#!/usr/bin/env python3
"""Original deterministic Aster Valley sound synthesis; Python standard library only.
Run from any directory: python modules/audio/tools/synthesize.py
"""
from __future__ import annotations
import math
from pathlib import Path
import struct
import wave

RATE = 22050
ASSETS = Path(__file__).resolve().parents[1] / "assets"
TAU = math.tau
PROFILES = {
    "vela": {"hz": (55, 95, 150), "harmonics": (0.94, 0.35, 0.22, 0.11, 0.06), "rattle": 23},
    "orion": {"hz": (75, 135, 205), "harmonics": (0.72, 0.54, 0.32, 0.22, 0.12), "rattle": 37},
    "kestrel": {"hz": (45, 85, 130), "harmonics": (1.0, 0.47, 0.34, 0.19, 0.10), "rattle": 17},
}
NOISE_BINS = {
    "roll_asphalt": (83, 127, 211, 347, 569, 877, 1297, 1811, 2417),
    "roll_gravel": (53, 113, 193, 379, 647, 1049, 1637, 2801, 3517),
    "roll_grass": (31, 67, 103, 181, 283, 443, 709, 1187),
    "tire_squeal": (431, 977, 1507, 2017, 2731, 3319),
    "tire_skid": (167, 347, 691, 1103, 1637, 2207, 3251),
    "wind": (7, 17, 31, 53, 89, 157, 271, 457, 761),
    "countryside": (5, 11, 23, 41, 79, 137, 251, 419, 683),
    "overrun": (73, 137, 233, 401, 653, 997, 1531, 2101),
}
DURATIONS = {
    "roll_asphalt": 4, "roll_gravel": 4, "roll_grass": 4,
    "tire_squeal": 3, "tire_skid": 3, "wind": 5,
    "countryside": 8, "overrun": 3,
    "gearshift": 0.60, "collision": 0.75, "suspension": 0.55,
}


def _hash(name: str) -> int:
    return sum((i + 1) * ord(c) for i, c in enumerate(name))


def _engine(name: str, band: int, t: float) -> float:
    p = PROFILES[name]
    phase = TAU * p["hz"][band] * t + 0.075 * math.sin(TAU * t)
    v = 0.0
    for h, a in enumerate(p["harmonics"], 1):
        v += a * math.sin(h * phase + h * 0.39)
    v += (0.075 if name != "orion" else 0.11) * math.sin(TAU * p["rattle"] * t + 0.8)
    # Modulation remains periodic at the exact loop boundary.
    v *= 0.85 + 0.15 * math.sin(TAU * 2 * t + 0.2)
    return v


def _noise(name: str, t: float, duration: int) -> float:
    seed = _hash(name)
    v = 0.0
    bins = NOISE_BINS[name]
    for j, hz in enumerate(bins):
        phase = ((seed * (j + 3) * 17) % 1009) / 1009.0 * TAU
        amp = 1.0 / (1.0 + j * 0.18)
        v += amp * math.sin(TAU * hz * t + phase)
    v /= max(1.0, len(bins) * 0.62)
    if name == "tire_squeal":
        v += 0.3 * math.sin(TAU * 1037 * t + 0.2 * math.sin(TAU * t))
    if name == "countryside":
        # Two original birdsong chirps with zero energy at loop edges.
        for center, f in ((2.05, 1180.0), (5.60, 1560.0)):
            x = (t - center) / 0.27
            envelope = math.exp(-x * x * 5)
            v += 0.14 * envelope * math.sin(TAU * (f * t + 52 * (t - center) ** 2))
        v *= 0.76
    if name == "overrun":
        pulse = max(0.0, math.sin(TAU * 7 * t)) ** 8
        v *= 0.35 + 0.85 * pulse
    if name == "wind":
        v *= 0.7 + 0.2 * math.sin(TAU * t / duration)
    return v


def _oneshot(name: str, t: float) -> float:
    if name == "gearshift":
        return (0.75 * math.sin(TAU * (170 * t + 75 * t * t)) + 0.3 * math.sin(TAU * 780 * t)) * math.exp(-12 * t)
    if name == "collision":
        return (0.78 * math.sin(TAU * (83 * t - 25 * t * t)) + 0.43 * math.sin(TAU * 273 * t) +
                0.2 * math.sin(TAU * 1061 * t)) * math.exp(-9.5 * t)
    return (0.82 * math.sin(TAU * (91 * t - 21 * t * t)) + 0.3 * math.sin(TAU * 305 * t)) * math.exp(-16 * t)


def generate(name: str) -> tuple[int, ...]:
    if name.startswith("engine_"):
        _, profile, band_name = name.split("_")
        duration = 3
        band = {"low": 0, "mid": 1, "high": 2}[band_name]
        waveform = lambda t: _engine(profile, band, t)
    else:
        duration = DURATIONS[name]
        waveform = (lambda t: _oneshot(name, t)) if name in ("gearshift", "collision", "suspension") else (lambda t: _noise(name, t, int(duration)))
    count = round(RATE * duration)
    raw = [waveform(i / RATE) for i in range(count)]
    peak = max(abs(v) for v in raw) or 1.0
    target = 0.77 if name.startswith("engine_") else (0.69 if name in ("gearshift", "collision", "suspension") else 0.58)
    return tuple(max(-32767, min(32767, round(v * 32767 * target / peak))) for v in raw)


def write(name: str) -> Path:
    samples = generate(name)
    path = ASSETS / f"{name}.wav"
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(struct.pack("<" + "h" * len(samples), *samples))
    return path


def names() -> list[str]:
    return [f"engine_{profile}_{band}" for profile in PROFILES for band in ("low", "mid", "high")] + list(NOISE_BINS) + ["gearshift", "collision", "suspension"]


if __name__ == "__main__":
    for asset in names():
        path = write(asset)
        print(f"{path.name}: {path.stat().st_size} bytes")
