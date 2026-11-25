#!/usr/bin/env python3
"""Quantify high-RPM amplitude flutter independently from clipped-sample checks."""
import array
import json
import math
import pathlib
import statistics
import sys
import wave

def metrics(pcm, rate):
    # 5 ms RMS envelope; 10–85 Hz band catches audible rapid tremolo.
    # Remove the average, Hann-window and sum the DFT band power.
    width = rate // 200
    env = [20*math.log10(max(1e-7,math.sqrt(sum(v*v for v in pcm[i:i+width])/width)/32768))
           for i in range(0,len(pcm)-width+1,width)]
    mean = statistics.fmean(env)
    window = [0.5-0.5*math.cos(2*math.pi*i/(len(env)-1)) for i in range(len(env))]
    x = [(v-mean)*w for v,w in zip(env,window)]
    n = len(x)
    env_rate = rate/width
    band = 0.0
    for k in range(math.ceil(10*n/env_rate),math.floor(85*n/env_rate)+1):
        a = 2*math.pi*k/n
        c = sum(v*math.cos(a*i) for i,v in enumerate(x))
        s = sum(v*math.sin(a*i) for i,v in enumerate(x))
        band += 2*(c*c+s*s)/(n*sum(w*w for w in window))
    p10, p90 = statistics.quantiles(env,n=10)[0],statistics.quantiles(env,n=10)[8]
    return {"flutter_rms_db":round(math.sqrt(band),4),"envelope_p90_p10_db":round(p90-p10,4),
            "rms_dbfs":round(20*math.log10(max(1e-8,math.sqrt(sum(v*v for v in pcm)/len(pcm))/32768)),3)}

def load(path):
    with wave.open(str(path),"rb") as f:
        assert f.getnchannels()==1 and f.getsampwidth()==2
        rate=f.getframerate()
        x=array.array("h",f.readframes(f.getnframes()))
    if sys.byteorder!="little": x.byteswap()
    assert len(x)==rate*12,"Incomplete plateau capture"
    return rate,x

def main():
    d=pathlib.Path(sys.argv[1]); reports=[]; ok=True
    for profile in ("aventador_svj","mclaren_senna"):
        rate,short=load(d/(profile+"_high_rpm_short.wav"))
        rate2,extended=load(d/(profile+"_high_rpm_extended.wav"))
        assert rate==rate2
        for i,(rpm,load_amount) in enumerate(((0.85,1),(0.85,0),(1,1),(1,0))):
            # 3 seconds at constant RPM/load; discard 100ms on either side.
            lo=round((i*3+0.1)*rate); hi=round((i*3+2.9)*rate)
            a,b=metrics(short[lo:hi],rate),metrics(extended[lo:hi],rate)
            ratio=b["flutter_rms_db"]/max(0.01,a["flutter_rms_db"])
            # Don't claim a psychoacoustic pass. Reject severe new flutter or loss of signal.
            passed=ratio<=1.35 and b["rms_dbfs"]>-45 and abs(a["rms_dbfs"]-b["rms_dbfs"])<6.0
            row={"profile":profile,"redline_fraction":rpm,"load":load_amount,"short":a,"extended":b,
                 "flutter_ratio":round(ratio,3),"passed":passed}
            reports.append(row); ok &= passed
            print("High-RPM modulation:",json.dumps(row))
    (d/"high_rpm_modulation.json").write_text(json.dumps(reports,indent=2)+"\n")
    return 0 if ok else 1
if __name__=="__main__":
    raise SystemExit(main())
