# Issue #14 steering and camera validation

Measured on Windows with Godot 4.7.2 stable (`ed1daf0bf`) and 120 Hz physics. The baseline is PR #9 head `e0d8eaf`.

## Isolated causes and measurements

The frozen-chassis test ran the same A/D commands with two cameras on one chassis. The base chase view swung by **11.712°** while the chassis yaw and the camera with the command offset disabled both moved **0.000°**. Both cameras on the fix moved **0.000°**. The command offset explains the stationary symptom independently of suspension and tire forces.

In a constant 18 m/s run, the table shows the worst difference between actual and expected camera travel per rendered frame. All three views produced the same error to the precision shown. At 30 FPS the render interval is an exact multiple of the physics tick interval. At 83 and 144 FPS the camera steps were uneven on the base.

| Simulated render FPS | Baseline peak frame error | Patched peak frame error |
| --- | ---: | ---: |
| 30 | ≤0.0001 m | <0.0001 m |
| 83 | 0.0831 m | <0.0001 m |
| 144 | 0.1250 m | <0.0001 m |

Near zero speed a direct 0.60 analog command moved normalized steering by **0.6000** on the first baseline tick and **0.0375** on the patched tick. The keyboard ramp masked the low-speed rate and consumed the first 200 ms of a full reversal. The test applies four alternating A/D pulses of 200 ms each and releases for 750 ms. The baseline started left and never crossed to the right during the opposite pulses. All patched runs crossed center in both directions and finished at 0.0000.

| Measured entry km/h | Normalized steering range, base → fix | Peak chassis yaw per tick, base → fix |
| ---: | --- | --- |
| 0.2 | [0.000, 0.840] → [−0.450, 0.900] | 0.002° → 0.002° |
| 19.3 | [0.000, 0.840] → [−0.450, 0.900] | 0.424° → 0.430° |
| 57.8 | [0.000, 0.770] → [−0.338, 0.752] | 0.598° → 0.534° |
| 115.9 | [0.000, 0.622] → [−0.134, 0.410] | 0.399° → 0.371° |

All views follow the interpolated chassis on render frames. Chase clearance uses a physics-tick ray, with immediate retraction and gradual extension. Planar speed drives the filtered FOV and forward look-ahead. In the 83 FPS pedal test, chase FOV went from 70.00° at launch to 72.38° after acceleration and 71.67° after braking, with a maximum measured frame change of 0.033°. The hood stayed attached to the interpolated chassis. The chase camera sat 2.45 m behind the car with a wall starting at 2.8 m and recovered to 6.19 m after the obstruction moved.

## Hands-on follow-up and road reentry

A physical-keyboard drive on PR #15 confirmed the camera improvement and reported that steering still felt sensitive when drifting off the road and then reentering. A level road/grass/road test at approximately 60 km/h isolated an instantaneous tire-coefficient change of 1.450. The Vela GT now blends contacted surface grip over time. The same test measures a maximum step of 0.143 and settled road grip of 2.900. Peak yaw-rate change during the measured reentry window was 0.004 rad/s in both runs. The Vela GT steering curve also applies less angle to partial steering while preserving maximum lock. This fixture isolates grip and does not model a physical bump at the terrain join.

## Reproduction

Run from the patched checkout using the console executable on Windows.

```powershell
godot --headless --path . --import --quit
godot --headless --path . --fixed-fps 60 --script res://tests/core/smoke.gd
foreach ($fps in 30, 60, 83, 144) {
    godot --headless --path . --fixed-fps $fps --script res://tests/core/steering_camera.gd
}
```

To measure the base, copy the regression script into an isolated checkout of `e0d8eaf`, import it and append `-- --baseline` to the regression commands. Baseline mode collects telemetry with assertions disabled.

For a Forward+ run, create a capture directory and run this command with its path.

```powershell
godot --path . --resolution 960x540 --fixed-fps 60 --script res://tests/core/steering_camera.gd -- --capture-dir <existing-directory>
```

The scripted graphical drive on an RTX 4050 Laptop GPU exercised acceleration, braking, A/D pulses, respawn, and all three views. The captures allow inspection of camera placement and clipping. The headless tests also covered reverse gear and forward exit, a moving handbrake turn, body and camera collisions, rollover reset, and pause. A second hands-on run is needed to confirm subjective feel after the road-reentry tuning. Physical Xbox-style controller hardware remains unverified.
