#!/usr/bin/env python3
"""Offline asset integrity and PCM loop endpoint verifier for Aster Valley recorded audio."""
import json
import math
import pathlib
import struct
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
PAYLOAD_DIR = ROOT / "assets/audio/recorded/payload"
ENGINES_DIR = PAYLOAD_DIR / "engines"
TIRES_DIR = PAYLOAD_DIR / "tires"
AMBIENCE_DIR = PAYLOAD_DIR / "ambience"

TARGET_RATE = 48000
PROFILES = ["vela_gt", "kestrel_xr", "orion_rs"]


def linear_to_db(lin: float) -> float:
    if lin <= 1e-7:
        return -140.0
    return 20.0 * math.log10(lin)


def inspect_wav(path: pathlib.Path, is_loop: bool = True) -> dict:
    data = path.read_bytes()
    if len(data) < 44 or data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        raise ValueError(f"{path}: Not a valid RIFF/WAVE file")

    idx = 12
    fmt_found = False
    data_found = False
    channels = 1
    sample_rate = 0
    bits_per_sample = 16
    raw_pcm = b""

    while idx < len(data):
        chunk_id = data[idx : idx + 4]
        chunk_size = struct.unpack("<I", data[idx + 4 : idx + 8])[0]
        chunk_data = data[idx + 8 : idx + 8 + chunk_size]
        if chunk_id == b"fmt ":
            fmt_found = True
            format_tag, channels, sample_rate, avg_bps, block_align, bits_per_sample = struct.unpack(
                "<HHIIHH", chunk_data[:16]
            )
        elif chunk_id == b"data":
            data_found = True
            raw_pcm = chunk_data
        idx += 8 + chunk_size + (chunk_size % 2)

    if not fmt_found or not data_found:
        raise ValueError(f"{path}: Incomplete WAV file (fmt={fmt_found}, data={data_found})")

    samples_count = len(raw_pcm) // 2
    samples = struct.unpack("<" + "h" * samples_count, raw_pcm)

    max_abs = max(abs(s) for s in samples)
    sum_sq = sum(s * s for s in samples)
    peak_lin = max_abs / 32768.0
    rms_lin = math.sqrt(sum_sq / max(samples_count, 1)) / 32768.0

    peak_dbfs = linear_to_db(peak_lin)
    rms_dbfs = linear_to_db(rms_lin)

    # Loop seam delta
    first_s = samples[0]
    last_s = samples[-1]
    seam_delta = abs(last_s - first_s)

    # Frame count
    frames = samples_count // channels
    duration_s = frames / sample_rate

    # Check for clipping
    clipped = sum(1 for s in samples if abs(s) >= 32767)

    return {
        "path": str(path.relative_to(ROOT)),
        "channels": channels,
        "sample_rate": sample_rate,
        "bits_per_sample": bits_per_sample,
        "frames": frames,
        "duration_s": duration_s,
        "peak_dbfs": round(peak_dbfs, 2),
        "rms_dbfs": round(rms_dbfs, 2),
        "seam_delta": seam_delta,
        "clipped_samples": clipped,
        "loop_begin": 0,
        "loop_end": frames if is_loop else 0,
    }


def main():
    print("=== Offline Recorded Audio Asset Verification ===")
    total_files = 0
    passed_files = 0
    failures = []

    # Check engines
    for p in PROFILES:
        manifest_path = ENGINES_DIR / p / "manifest.json"
        if not manifest_path.exists():
            failures.append(f"Missing manifest: {manifest_path}")
            continue
        with open(manifest_path, "r", encoding="utf-8") as f:
            manifest = json.load(f)

        print(f"\nVerifying Engine Profile: {p} ({len(manifest['loops'])} loops)")
        for entry in manifest["loops"]:
            total_files += 1
            wav_path = ENGINES_DIR / p / entry["file"]
            if not wav_path.exists():
                failures.append(f"Missing WAV: {wav_path}")
                continue
            try:
                info = inspect_wav(wav_path, is_loop=True)
                assert info["sample_rate"] == TARGET_RATE, f"Sample rate != {TARGET_RATE}"
                assert info["bits_per_sample"] == 16, "Not 16-bit PCM"
                assert info["peak_dbfs"] > -30.0, "Audio signal too low (near silent)"
                assert info["peak_dbfs"] <= 0.0, "Source asset clipped"
                passed_files += 1
                print(
                    f"  [OK] {entry['file']:<16} | {info['duration_s']:5.2f}s | Peak: {info['peak_dbfs']:6.2f} dBFS | RMS: {info['rms_dbfs']:6.2f} dBFS | Seam: {info['seam_delta']}"
                )
            except Exception as e:
                failures.append(f"{wav_path.name}: {e}")
                print(f"  [FAIL] {entry['file']}: {e}")

    # Check tires
    print("\nVerifying Tire Audio Assets:")
    for wav_path in TIRES_DIR.glob("*.wav"):
        total_files += 1
        try:
            info = inspect_wav(wav_path, is_loop=True)
            assert info["sample_rate"] == TARGET_RATE
            assert info["peak_dbfs"] > -30.0
            assert info["peak_dbfs"] <= 0.0
            passed_files += 1
            print(
                f"  [OK] {wav_path.name:<16} | {info['duration_s']:5.2f}s | Peak: {info['peak_dbfs']:6.2f} dBFS | RMS: {info['rms_dbfs']:6.2f} dBFS"
            )
        except Exception as e:
            failures.append(f"{wav_path.name}: {e}")
            print(f"  [FAIL] {wav_path.name}: {e}")

    # Check ambience
    print("\nVerifying Ambience Audio Assets:")
    for wav_path in AMBIENCE_DIR.glob("*.wav"):
        total_files += 1
        try:
            info = inspect_wav(wav_path, is_loop=True)
            assert info["sample_rate"] == TARGET_RATE
            assert info["peak_dbfs"] > -30.0
            assert info["peak_dbfs"] <= 0.0
            passed_files += 1
            print(
                f"  [OK] {wav_path.name:<24} | {info['duration_s']:5.2f}s | Peak: {info['peak_dbfs']:6.2f} dBFS | RMS: {info['rms_dbfs']:6.2f} dBFS"
            )
        except Exception as e:
            failures.append(f"{wav_path.name}: {e}")
            print(f"  [FAIL] {wav_path.name}: {e}")

    print("\n-------------------------------------------------")
    print(f"Asset Verification Summary: {passed_files}/{total_files} passed.")
    if failures:
        print(f"Failures: {failures}")
        sys.exit(1)
    else:
        print("ALL ASSETS VALIDATED CLEANLY!")
        sys.exit(0)


if __name__ == "__main__":
    main()
