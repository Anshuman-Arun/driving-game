"""Independent executable numerical traffic stress reference, not Godot test.

Mirrors the high-level traffic policy to exercise 16-agent route/stop/merge
invariants against the real v1 fixture in environments without Godot installed.
The GDScript suite is authoritative for the engine implementation itself.
"""
from __future__ import annotations
import math
import random
from pathlib import Path
import json

DATA = json.loads((Path(__file__).resolve().parents[1] / "fixtures/intersection_v1.json").read_text())
LANES = {l["id"]: l for l in DATA["lanes"]}
DT = 1 / 30

def dist(a, b):
    return math.dist(a, b)

def mul(a, x):
    return tuple(v * x for v in a)

def sub(a,b):
    return tuple(x-y for x,y in zip(a,b))

def dot(a,b):
    return sum(x*y for x,y in zip(a,b))

def path_length(l):
    return sum(dist(p,q) for p,q in zip(l["points"], l["points"][1:]))

def pose(lid, s):
    pts = LANES[lid]["points"]
    s = max(0, min(path_length(LANES[lid]),s))
    for p,q in zip(pts, pts[1:]):
        delta = sub(q,p)
        d = dist(q,p)
        if s <= d:
            return tuple(x + (y-x) * s/d for x,y in zip(p,q)),mul(delta,1/d)
        s -= d
    return tuple(pts[-1]),mul(sub(pts[-1], pts[-2]),1/dist(pts[-1],pts[-2]))

class Sim:
    def __init__(self, seed, count=16):
        self.rng = random.Random(seed)
        self.cars = {}
        self.reservations = {}
        self.time = 0
        self.next_id = 1
        self.crossings = 0
        self.transits = 0
        self.inbound = {name: "center" for name in ("eb_in","wb_in","sb_in","nb_in")}
        self.inbound["eb_out1"] = "merge"
        self.inbound["feeder"] = "merge"
        self.inbound["sb_out1"] = "side"
        self.inbound["nb_in_far"] = "side"
        for _ in range(count):
            if not self.spawn():
                raise AssertionError("cannot initialize 16 cars without overlap")

    def spawn(self):
        ids = sorted(LANES)
        for _ in range(150):
            lane_id = self.rng.choice(ids)
            s = self.rng.uniform(.1, .85) * path_length(LANES[lane_id])
            pos, _ = pose(lane_id, s)
            if not 24 < dist(pos,(0,1,0)) < 175:
                continue
            if (lane_id in ("eb_cross", "wb_cross", "sb_cross", "nb_cross") and s < 23) or (lane_id in ("eb_out2", "feeder", "sb_out2", "nb_in") and s < 15):
                continue
            if any(dist(pos, c["pos"]) < 12 for c in self.cars.values()):
                continue
            options = LANES[lane_id]["next_lane_ids"]
            nxt = self.rng.choice(options) if options else ""
            id = self.next_id
            self.next_id += 1
            self.cars[id] = {"id":id,"lane":lane_id,"s":s,"speed":0.0,"pos":pos,
                "next":nxt,"factor":self.rng.uniform(.75,1.08),"wait":0.0,"stopped":False,
                "reserved":"","entered":"","clearance":0.0}
            return True
        return False

    def safe_curve_speed(self, a):
        lane = a["lane"]
        s = a["s"]
        speed = LANES[lane]["speed_limit_kph"] / 3.6 * a["factor"]
        start, direction = pose(lane, s)
        for ahead in (6,12,20,30):
            actual = min(ahead,path_length(LANES[lane])-s)
            if actual < .25:
                continue
            end, dr = pose(lane, s+actual)
            curvature = math.acos(max(-1,min(1,dot(direction,dr)))) / actual
            if curvature > 1e-4:
                corner = math.sqrt(3.2/curvature)
                speed = min(speed, math.sqrt(corner*corner + 2*3.5*max(0,actual-4)))
        return speed

    def cmd(self, a):
        lane = a["lane"]
        remaining = path_length(LANES[lane])-a["s"]
        desired = self.safe_curve_speed(a)
        leader_gap = float("inf")
        leader_speed = 0.0
        for b in self.cars.values():
            if b["id"] == a["id"]:
                continue
            gap = float("inf")
            if b["lane"] == lane and b["s"] > a["s"]:
                gap = b["s"] - a["s"]
            elif b["lane"] == a["next"]:
                gap = remaining + b["s"]
            if gap < leader_gap:
                leader_gap = gap
                leader_speed = b["speed"]
        if leader_gap < 80:
            desired = min(desired,max(0,leader_speed + (leader_gap-(5.5+a["speed"]*1.4))*.65))
        waiting = False
        if a["next"] == "":
            desired = min(desired, math.sqrt(2*4.8*max(0,remaining-.5)))
        jid = self.inbound.get(lane,"")
        if jid and a["next"] and remaining < 16 and not a["reserved"]:
            blocked = self.reservations.get(jid,-1) not in (-1,a["id"])
            if jid == "center" and not a["stopped"]:
                if remaining < 3.4 and a["speed"] < .45:
                    a["wait"] += DT
                    if a["wait"] >= .7:
                        a["stopped"] = True
                blocked = blocked or not a["stopped"]
            if blocked:
                desired = min(desired,math.sqrt(2*4.8*max(0,remaining-2.5)))
                waiting = True
            elif remaining < 3.4:
                self.reservations[jid] = a["id"]
                a["reserved"] = jid
                a["entered"] = a["next"]
                a["clearance"] = 21 if jid == "center" else (13 if jid == "side" else 12)
        if waiting and remaining <= 2.65:
            desired = 0
        return desired, waiting, leader_gap

    def step(self):
        self.time += DT
        commands = {id:self.cmd(car) for id,car in sorted(self.cars.items())}
        for id, a in sorted(self.cars.items()):
            desired, waiting, gap = commands[id]
            v = a["speed"]
            accel = max(-4.8,min(2.1,(desired-v)/DT))
            next_speed = max(0,v+accel*DT)
            ds = (v+next_speed)*.5*DT
            if gap < 80:
                ds = min(ds,max(0,gap-5.5))
            if waiting:
                ds = min(ds,max(0,path_length(LANES[a["lane"]])-a["s"]-2.5))
            if ds < .0001 and v > .01:
                next_speed = max(0,v-7*DT)
            a["speed"] = next_speed
            a["s"] += ds
            old_lane = a["lane"]
            if a["s"] >= path_length(LANES[old_lane]) - 1e-5 and a["next"]:
                a["s"] -= path_length(LANES[old_lane])
                a["lane"] = a["next"]
                opts = LANES[a["lane"]]["next_lane_ids"]
                a["next"] = self.rng.choice(opts) if opts else ""
                a["stopped"] = False
                a["wait"] = 0
                self.transits += 1
            if a["reserved"] and a["lane"] == a["entered"] and a["s"] >= a["clearance"]:
                if self.reservations.get(a["reserved"]) == id:
                    del self.reservations[a["reserved"]]
                a["reserved"] = ""
                a["entered"] = ""
                self.crossings += 1
            a["pos"],_ = pose(a["lane"],a["s"])


def run(seed, seconds=90):
    sim = Sim(seed)
    min_dist = float("inf")
    moving_steps = 0
    max_wait = 0
    for _ in range(seconds*30):
        sim.step()
        cars = list(sim.cars.values())
        moving_steps += sum(a["speed"] > .5 for a in cars)
        max_wait = max(max_wait,max(a["wait"] for a in cars))
        for i,a in enumerate(cars):
            for b in cars[i+1:]:
                d = dist(a["pos"],b["pos"])
                min_dist = min(min_dist,d)
                if d < 3.6:
                    raise AssertionError(f"seed {seed}: overlap {d:.2f} at t={sim.time:.2f} lanes={a['lane']}/{b['lane']} details={a}/{b}")
    assert sim.crossings >= 8, (seed,sim.crossings)
    assert sim.transits >= 15, (seed,sim.transits)
    assert moving_steps >= 6000, (seed,moving_steps)
    return (seed,sim.transits,sim.crossings,moving_steps,round(min_dist,3),round(max_wait,2))

if __name__ == "__main__":
    for seed in (21,20261121,9181):
        a = run(seed)
        b = run(seed)
        assert a == b
        print("PASS seed=%d  cars=16  sim=90s  transitions=%d  crossings=%d  moving_steps=%d  min_spacing=%.2fm  longest_stop=%.2fs  deterministic=yes" % a)
