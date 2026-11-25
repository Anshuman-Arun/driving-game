#!/usr/bin/env python3
"""Gate audible exhaust continuity from actual PCM, independent of mixer counters."""
import array
import csv
import json
import math
import pathlib
import statistics
import sys
import wave

PROFILES = ("aventador_svj", "mclaren_senna")

def db(value):
    return 20 * math.log10(max(value, 1e-8))

def inspect(directory, profile):
    path = directory / (profile + "_exhaust_only.wav")
    with wave.open(str(path), "rb") as wav:
        assert wav.getnchannels() == 2 and wav.getsampwidth() == 2, "Expected stereo PCM16"
        rate = wav.getframerate()
        frames = wav.getnframes()
        pcm = array.array("h", wav.readframes(frames))
    if sys.byteorder != "little":
        pcm.byteswap()
    assert frames >= 28 * rate, "Incomplete 31-second capture"
    with (directory / (profile + "_rpm_trace.csv")).open(newline="") as f:
        trace = list(csv.DictReader(f))
    assert len(trace) >= 1700 and trace[-1]["scenario"] == "camera_perspective", "Incomplete telemetry trace"
    # Whole capture: a genuine engine cannot output repeated millisecond-long
    # exact digital zero runs. Ignore the first/last quarter second.
    max_zero = consecutive = runs = 0
    for i in range(rate//4, frames-rate//4):
        if pcm[2*i] == 0 and pcm[2*i+1] == 0:
            consecutive += 1
        else:
            if consecutive >= rate*0.002:
                runs += 1
            max_zero = max(max_zero,consecutive)
            consecutive = 0
    max_zero = max(max_zero,consecutive)
    # Smooth full-throttle sweep: check 10 ms energy, not only max peak.
    width = rate//100
    rms = []
    for start in range(round(rate*1.25),round(rate*4.7)-width,width):
        energy = sum((int(pcm[2*i])**2+int(pcm[2*i+1])**2)*0.5
                     for i in range(start,start+width))/width
        rms.append(db(math.sqrt(energy)/32768.0))
    quiet = sum(x < -60 for x in rms)
    report = {"profile":profile,"frames":frames,"rate":rate,
              "zero_runs_2ms":runs,"max_zero_ms":max_zero*1000/rate,
              "quiet_10ms_sweep_blocks":quiet,"sweep_median_rms_dbfs":statistics.median(rms),
              "sweep_p10_rms_dbfs":statistics.quantiles(rms,n=10)[0],
              "max_adjacent_rms_jump_db":max(abs(a-b) for a,b in zip(rms,rms[1:]))}
    report["passed"] = max_zero < rate*0.002 and quiet == 0
    return report

def main():
    directory = pathlib.Path(sys.argv[1])
    reports = []
    for profile in PROFILES:
        try:
            report = inspect(directory,profile)
        except Exception as exc:
            report = {"profile":profile,"passed":False,"error":str(exc)}
        reports.append(report)
        print("Exhaust continuity:",json.dumps(report))
    (directory/"exhaust_continuity.json").write_text(json.dumps(reports,indent=2)+"\n")
    return 0 if all(x["passed"] for x in reports) else 1

if __name__ == "__main__":
    raise SystemExit(main())
