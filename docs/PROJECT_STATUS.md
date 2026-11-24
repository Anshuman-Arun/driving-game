# Project status — single current-state log

## Recorded audio fidelity pass 5 (`fix/recorded-audio-mix`, 2026-11-24)

CI run 45441993515 (job 138615380879, revision 2d01ff1) completed. Godot import and all three real-time 31-second profile captures executed: Vela peak -9.34 dBFS, Kestrel -9.83 dBFS, Orion -9.97 dBFS; zero clipped samples and hard flats. The capture runner's signal/coverage gates passed. Strict CI still failed four suites due to ObjectDB/resource leaks at shutdown (tires, legacy smoke, root integration, capture runner); their assertions passed. The other suites, including legacy regression, passed the strict gate. These measurements apply only to the earlier revision and do not establish subjective sound quality.

Added explicit mixer-drain teardown for affected suites, stopping playback before freeing nodes and giving the audio thread time to release resources. Added isolated exhaust-bus capture checks (including idle signal) to prevent ambience from concealing a silent engine, and optional stereo 16-bit PCM audition export via `ASTER_AUDIO_CAPTURE_DIR`. Run `ASTER_AUDIO_CAPTURE_DIR=/absolute/path/to/captures bash tests/integration/audio_qa/run_all.sh` on a Linux checkout with the pinned Godot executable. WAVs are local outputs, not committed assets; no new captured WAVs have been auditioned. Chassis and environment now honor the root gain controls, ambience fades in and is no longer substituted as a duplicate aerodynamic wind layer. All source recordings and vehicle physics are unchanged. New revision requires CI revalidation. Main untouched; PR #37 remains draft.



## Recorded audio fidelity pass 4 (`fix/recorded-audio-mix`, 2026-11-24)

Collision loudness now estimates velocity change across a contact step instead of treating road speed as impact speed. This is an approximation of impulse per unit mass, not measured contact force. Suspension and impact cooldowns advance on one clock, not both render and physics ticks. Landings retain pre-contact downward velocity, prioritize touchdown over spring events, and clear stale spring histories when wheels leave contact. The QA jump telemetry includes descending velocity. Added regression checks for these cases.

Actual GitHub Actions run 45440889812 (job 138611409832, prior revision 033a48d): checkout, checksum-pinned Godot 4.7.2 installation, offline asset check (35/35), project import, engine tests, mix (61/61), chassis and chassis/mix suites executed. Tire assertions passed but leaked resources at exit; synthetic smoke and regression also leaked resources; regression logged detached-node global transform errors. Root integration failed because it inspected newly attached audio nodes before SceneTree readiness and hung until the run was cancelled by the newer revision. Capture had not executed. These are actual log observations, not a passing CI result.

Fixed the observed failures by deferring root integration/tire/capture initialization, freeing test-owned nodes synchronously, detaching capture effect after tests, and handling detached Node3D basis in telemetry. Revalidation on the new revision is required; no claim of successful runtime or acoustic audition yet. Original assets and vehicle physics are unchanged. PR #37 stays draft, main untouched.



## Recorded audio fidelity pass 3 (`fix/recorded-audio-mix`, 2026-11-24)

Engine loops now use private PCM16 copies with a bounded two-millisecond raised-cosine endpoint correction on each side of a discontinuity. The existing files, frame counts, asset hashes and attribution remain unchanged; compressed fallback streams cannot be conditioned. Exhaust reflection voices share the conditioned sample and start at the direct voice's playback position only while the anchor is active; the wet delay stays enabled in open space to prevent dry leakage. Chassis raycasts exclude the actual vehicle RID; unbound test rigs retain simulated wall distances. Engine torque-cut follows GEVP's shift-active edge and recovers after the actual transmission shift; motor-pedal telemetry is correct in reverse without breaking the legacy pedal contract.

Independent PCM checks using actual GitHub WAV bytes for the three largest seam jumps in each of the three banks (nine files): endpoint jumps of 290–1706 signed PCM16 counts became zero; no new clipping; unchanged sample counts; maximum absolute RMS difference 0.0098 dB. This checks the algorithm on real recordings, not the Godot runtime, or perceived loop quality.

Corrected QA runner: loads the actual requested profile instead of relabeling it; paces the 31-second telemetry bench in real time, exercises camera and reflection state, rejects empty or silent scenarios, insufficient frames and discarded capture frames, and requires telemetry coverage. Added seam, reflection routing and actual shift regressions. Added `tests/integration/audio_qa/run_all.sh` and a dedicated read-only GitHub Actions workflow using the previously repository-pinned Godot installer. The new workflow was committed; no run was returned by the connector at the time of writing. No local Godot executable or private checkout available. Runtime import, all new Godot assertions, audible reflections and subjective mix quality remain unverified. Existing historic capture results are not proof for this revision.

Next: resolve any failures from the new CI workflow; capture the three cars and audition the bank transitions. Obtain verified, genuinely different idle/load/coast/induction recordings rather than treating current field-recording banks as final-quality assets. Spatial traffic and detailed environmental beds are still outstanding.



## Recorded audio fidelity pass 2 (`fix/recorded-audio-mix`, 2026-11-24)

Calibrated Orion's manifest by -13 dB: the existing asset ledger estimates its source RMS near -8 dBFS versus -19 to -25 dBFS for the other banks; trimmed Orion RMS is -21.11 to -21.02 dBFS. PCM and attribution are unchanged. Adjacent RPM loops now crossfade only in the interval where both can match nominal firing frequency (default pitch ratio 0.65–1.55), using a shared runtime/diagnostic constant-power function. A 420 Hz high-pass on the derived intake layer reduces duplication of exhaust fundamentals; it is not a genuine induction recording. Synthetic voices are no longer allocated or processed in recorded mode. Tire envelopes advance once per actual physics tick, retain wheel surface proportions, and reduce paved squeal on gravel/grass. Aerodynamic and camera low-pass controls no longer share a filter instance.

Independent numeric sweep against all three actual manifests: 2,727 points across 27 adjacent anchor pairs, max nominal pitch error below 0.000001 RPM and max power-sum error below 0.000001. These are formula and ledger checks, not measured waveforms. Added engine and tire regression cases, not executed in Godot. No local Godot binary/private checkout; PR #37 remains draft pending import and audio playback/capture tests. Genuine idle/coast/intake recordings, Orion replacement, loop seam audition, actual reflection signal routing, traffic spatial sound and final listening/mastering remain open. The supplied samples are candidate field recordings with estimated RPM tags, not measured dyno banks; high-end racing audio quality cannot be certified from these tests.



## Recorded audio mix correction (`fix/recorded-audio-mix`, 2026-11-24)

Follow-up to PR #33 (`audio-swarm-pass1`), not a replacement of the asset bank. Recorded engine and chassis own their respective shift, lift-off, impact and suspension events; the old synthetic event pool no longer doubles them. The low-RPM engine mix uses the lowest ON recording at restrained gain when no suitable OFF recording exists, transitioning smoothly into the coast bank near its first anchor. Limiter cuts require applied throttle. Ambient wind now routes through SFX in both the saved and generated layouts. Legacy regressions explicitly select synthetic mode; additional checks cover Kestrel idle/coast blending and recorded event ownership. No new external assets or dependencies.

Godot and the private repository's local checkout are not available in the editing session. Changes and regression assertions are committed, but Godot import, runtime suites, captured waveform quality, and manual audition have not been re-run. The previous audio-swarm QA report is historical evidence for its original commit, not verification of this branch. Existing banks remain audition candidates; Orion remains a temporary pitched recording fallback. Next: run the audio integration and engine/mix/chassis/legacy suites listed in `docs/AUDIO_HANDOFF.md`, then listen to all three cars during idle, acceleration, shifts, lift-off and gravel driving before accepting the PR.


Last updated: 2026-11-23

## Recorded vehicle and environment audio overhaul (`audio-swarm-pass1`)

Resolved root silence issues across the game (isolated nested subproject configuration, missing player vehicle attachment, unconfigured AudioServer bus layout, and missing AudioListener3D). Upgraded audio to full multi-track modular recorded runtime:
- **Mix & Buses (Track A)**: Canonical 10-bus layout with Master compressor (-16 dB, 2:1, 15ms attack, 120ms release) and limiter (-1.0 dB ceiling). SFX submix routing cleanly connects pause and settings menu volume sliders. Dynamic `AsterCameraMixController` provides 200ms smoothed transitions between chase clarity and cockpit cabin muffling (LPF to 1800 Hz, -4 dB exterior cut, +6 dB intake boost).
- **Engine Sound (Track B)**: `RecordedEngineController` driven by manifest JSON for Vela GT (flat-six), Kestrel XR (V8), and Orion RS (four-cylinder). Constant-power cos/sin anchor blending, RPM/throttle smoothing, ON/OFF load crossfading, rev limiter 20 Hz stutter, gear shift clunk/torque-cut (110ms), and overrun backfire crackles. Instant idle sound starts immediately on spawn across all 3 cars.
- **Tire Acoustics (Track C)**: `RecordedTireController` managing seamless roll loops for asphalt, gravel, and grass with speed-dependent pitch/gain, airborne fade-out, moderate slip scrub (0.15-0.45), screech (>0.45 with 0.38 hysteresis), asymmetric attack/release (80ms/180ms), and stationary speed gating (<1.5 m/s).
- **Chassis & Environment (Track D)**: `ChassisAudioController` featuring exponential wind noise onset at ~22 m/s, mountain wind bed on Ambience bus, spring compression delta / dt landing thumps with 0.16s cooldown, collision impacts with velocity scaling and 0.12s cooldown, and 3-way acoustic raycasts mapping wall distance to 15-120ms delay and wet reflection gain.
- **Root Integration & QA (Track E & Root)**: Wired directly into `PlayerCarFactory.create()`, `aster_valley_drive.gd`, `driving_test.gd`, and `project.godot`. Headless AudioEffectCapture runner passed all 42 asset validations and 3/3 car profiles across 11 driving regimes with 0 clipped samples, 0 hard flats, and -9.83 dBFS overall peak (9.83 dB minimum headroom). All unit and integration suites pass 100%.

## Water crossings, roadside detail and instruments (`feat/local-showroom-dashboard`)

Eastwater Viaduct, Alder Creek Bridge and Needle Pass Trestle carry existing routes over new water at lake, valley and mountain elevations. Five corridors have wider pavement with tapered approaches. The bridge decks, rails and shoulder surfaces participate in driving collision. The root game loads a separate roadworks heightfield while the standalone runtime can still load the canonical world. The scenery layer accounts for 12 placements displaced by the new banks.

Rebuilt trees use tapering branches, textured foliage, two levels of detail and nearby shadow casting. Camera-local batches stream from 235,686 terrain-aligned placements, including thicker conifer stands, road-edge grass, wildflowers and rocks. Alder houses, barns and workshops have new materials and facade details. The driving HUD shows a heading-up contour map with the new water and an open RPM dial with live gear and MPH.

`content/scenery/tools/bake_roadworks.py` writes the roadworks profile and heightfield to a staging directory. Run `content/scenery/tools/bake_vegetation.py` with the same project and output arguments to regenerate vegetation and the map atlas against that heightfield.

Godot 4.7.2 verified all five widened sections with collision rays and drove the live chassis over all three spans. The garage-world regression passed, and the standalone world passed all 642 road rays. Forward+ captures covered the crossings, all five regions and the HUD at 1600×900 and 1280×720. At a fixed Cedar Woods camera on the RTX 4050 Laptop GPU, the vegetation-enabled run measured 5.74 ms median and 6.01 ms 99th-percentile GPU time. Presented frames hovered around 60 in the test window, and uncapped frame rate remains unverified.

## Valley scenery and instruments (`feat/local-showroom-dashboard`)

The five regions now share 110,099 baked, visual-only placements for groves, meadow cover, wildflowers and boulders. Camera-local MultiMesh cells load the ground cover, nearby canopy casts real sun shadows, and the graphics preset adjusts active coverage. Photogrammetry meadow, leaf litter and mossy rock textures distinguish the terrain. A bounded leaf pool uses gravity and wind to land leaves on the surface. The driving HUD uses contour relief, water, a rotating compass, and region names alongside a segmented RPM bar, gear display and MPH readout.

Godot 4.7.2 imports and the garage-to-world integration passed. The Forward+ run captured all five regions, exercised live speed and gear, and checked leaves settling, terrain shadows, and quality changes. At 1600×900 on the RTX 4050 Laptop GPU, a fixed Cedar Woods camera measured 3.22 ms median GPU render time with supplemental vegetation visible and 2.93 ms with it hidden. The respective presented frame-rate readings were 61 and 119 FPS in that short sample. This was a scene-specific measurement. Low and High coverage changes were also checked headlessly.

## Home, garage, driving HUD and rendering (`feat/local-showroom-dashboard`)

Home and Settings share an original color treatment and bundled Barlow typography. Settings keeps the offline profile, exposes the live controller steering response, and supports directional focus through Display, Controls and Audio. The garage keeps its live turntable, and the pause screen now leaves the world visible. Free roam shows live MPH, gear, engine RPM, and a heading-up minimap built from the canonical road data.

The viewport uses native TAA on Medium. Low uses an 85 percent 3D scale and FXAA, and High adds 2× MSAA to native TAA. Road, terrain, and water textures now import with mipmaps and VRAM compression. Duplicate same-facing triangles were removed from the three hero car GLBs, and preview and driving materials use smoother paint and glass reflections. Tire smoke and dust use a shared soft alpha texture at 14 particles per emitter.

Godot 4.7.2 import, 53 shell checks, the garage-world integration suite, and Forward+ checks of settings focus, live telemetry, parked car switching and off-road dust passed. At 1600×900 on the RTX 4050 Laptop GPU, the repeated showcase reported about 446 MiB peak video memory versus about 649 MiB before the overhaul. The North Ridge route with the HUD averaged 60.9 presented FPS on Medium, with a 4.97 ms median and 8.18 ms 99th-percentile GPU render time. All tested quality configurations hovered around 60 presented FPS in that run. Physical controller and uncapped FPS validation remain open.

## Forza visual fidelity overhaul (`feat/forza-fidelity-overhaul`)

Upgraded all three hero vehicles (`vela_gt.glb` Porsche 911, `orion_rs.glb` Khronos CarConcept, `kestrel_xr.glb` Porsche 918 Spyder Weissach), environment/building models, 2K Poly Haven CC0 PBR terrain/road/water shaders (distance-attenuated normals, 2x MSAA + FXAA + debanding + 16x Aniso + smooth SSAO, SSIL off), HDRI outdoor & garage studio lighting, Forza-style `DriftController` + Xbox Series controller + right-stick look-around camera, and `VehicleVisualFX`. Pass 6 Godot 4.7.2 Forward+ QA (RTX 4050 Laptop GPU, scenery on) passed with 0 failures across all 5 headless suites (`game_shell` 53/53, `core/smoke`, `steering_camera`, `drift_and_controller`, `world_runtime -- --full-world` 642/642 road rays) and graphical suites (`garage_world.gd`, `vehicle_world.gd`, `forza_showcase_qa.gd` 88.1 FPS mean at 1600x900, 648.9 MiB VRAM). See [CURATED_BUILD_QA.md](../tests/integration/CURATED_BUILD_QA.md) and [ASSET_LICENSES.md](ASSET_LICENSES.md).

## Curated vehicle and scenery integration

The root game enters the garage and menu, and launches canonical free roam with the selected Vela GT, Orion RS or Kestrel XR. Curated GLBs follow the existing chassis and wheel mounts. The five-region scenery layer can be disabled independently of the world collision. Godot 4.7.2 import, the full-world road sweep, the graphical garage and driving flows, and selection recovery after restart passed. The [build validation report](../tests/integration/CURATED_BUILD_QA.md) records commands, performance, screenshots and visual limitations. Physical controller checks and production vehicle-art integration remain open.

## Vehicle and world integration

The free-roam integration branch boots the full canonical Aster Valley terrain and roads with the corrected Vela GT. Import, the full-world collision sweep, Core regressions, and three integrated headless and Forward+ routes passed on Godot 4.7.2. See the [vehicle/world validation report](../tests/integration/VEHICLE_WORLD_QA.md) for performance, screenshots, and remaining handling checks.

## Confirmed
- GitHub repository Anshuman-Arun/driving-game exists and is private.
- Design documents, initial prompt, and shared agent workflow are committed on main.
- Target software stack and scope have been selected for a compatibility proof.

## Not yet done / do not claim otherwise
- No Godot project.godot, scene, imported addons or working executable exists yet.
- No Terrain3D + Road Generator + Easy Vehicle Physics integration has been performed.
- No driving performance, controller operation, FPS or visual quality has been tested.

## Next milestone: P0, then P1 if viable
Open the GitHub clone in Antigravity; use prompts/FIRST_EXECUTION_PROMPT.md to create the first playable 500x500 m driving scene. Verify the plugins individually and in combination. Stop and report any incompatibility.

## Report template for future agent updates
Date and branch:
Commit or PR:
What now works:
Tests and measured results:
Not tested:
Dependencies and asset licenses:
Known blockers:
Next task:

Do not mark a phase complete on the basis of code generation alone.
