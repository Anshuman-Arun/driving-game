# Project status — single current-state log

## Piano-like acceleration and deceleration: player-reported quality failure (2026-11-24)

The owner reports that acceleration and lift-off sound like piano notes. This supersedes prior technical acceptance; no subjective sign-off. Independently downloaded the exact 6609c6b capture artifact (run 45511642256, artifact 14976710538). Analyzed both 44.1 kHz stereo WAVs, 30.65 seconds each. During the full-throttle sweep (1.25–4.7 s), the dominant spectral bin within 40–4500 Hz occupied median 33.1% (Aventador) and 37.4% (Senna) of measured band energy, with 90th percentiles 61.6% and 65.7% (2048-sample spectrogram, 1792 overlap). These are concentration diagnostics, not a listening score. Aventador dominant peaks repeatedly alternate harmonic orders. The current upstream banks were deliberately pitch-flattened from spotter clips for a hybrid synth/sample app, not a purpose-built continuous ramp renderer.

Research: Playground's official FH6 feature notes (https://forza.net/news/forza-horizon-6-features) describe new recordings/remastered audio, upgraded turbo/backfire layers, improved surface and cockpit responses, and Triton spatial reverb. FH5 official July update (https://forza.net/news/forza-horizon-5-road-to-mexico-july-update) and lead audio designer Fraser Strachan's interview (https://www.asoundeffect.com/forza-5-game-audio/) explain live track acceleration/deceleration sweeps, granular synthesis and separate shift/limiter/idle material. Exact FH6 playback internals are proprietary; no copied game audio.

Immediate diagnostic revision isolates real exhaust for both hero cars: disabled the duplicate ON-bank pseudo-intake voice and generic synthetic shift/pops, preserving physical shift torque cuts, actual ON/OFF recordings and active-loop performance. This is not a proven cure for the tonal source itself. Added isolated exhaust WAV and synchronized RPM/throttle trace export to the capture runner for direct A/B and harmonic tracking.

Added experimental offline continuous-sweep research script and separate CI workflow. It downloads the original source Opus recordings from the attributed Commons URLs, tracks multiple harmonics with continuity penalties, proposes contiguous ascending/descending segments, and makes phase-referenced overlap-add audition previews from individual segments. It includes a synthetic chirp algorithm test. No preview is automatically promoted; source identity, actual RPM/load, timbre, coverage and listening require review. Source access is blocked by local DNS; CI attempt pending. Existing game still uses loops, not a real-time granular renderer. New runtime CI pending. Local user build may differ: check branch/commit and dedicated manifest presence before comparing. Preserve main, scenic models and physics.


## Private-build recorded banks installed (2026-11-24)

The owner requested the two preferred hero cars receive the overwhelming majority of sound-tuning work and authorized private-build audition. Added 26 real field-recorded loops obtained from the public supercar-engine-sound repository (upstream sample banks `svj` and `765lt`). Each 48 kHz mono PCM16 file was checked for valid format, exact Git blob identity, nonzero signal and zero clipped samples before the commit. Original PCM is unchanged; runtime seam conditioning applies. Source provenance, authors, declared CC BY 3.0 license, original URLs, upstream edit descriptions and per-loop waveform metrics are in each dedicated manifest. Independent Commons license review is pending; this is an audition build, not a public-distribution clearance.

| Bank | Acceleration | Coast | Source character |
|---|---|---|---|
| Aventador SVJ | 8 anchors, 950–8000 RPM | 6 anchors, 2000–8000 RPM | Aventador/SV/SVJ family V12 |
| Senna | 7 anchors, 1000–7000 RPM | 5 anchors, 3000–7000 RPM | McLaren 765LT/600LT/720S family V8, not actual Senna |
 
The RPM and load labels are estimates from upstream, not verified dyno telemetry. These are multiple field-recording sessions; several coast loops are short (shortest about 0.15 s), and high-RPM timbral consistency must be auditioned. No new turbo whistle, mechanical or gearshift recordings yet. The prior proxy banks remain emergency fallback only; both factory and capture tests now require the dedicated bank. Hero idle gain changed from 0.40 to 0.58/0.60 (approximately +3.2/+3.5 dB before the rest of the mix), with existing independent shift/intake response retained. No vehicle physics changes.

The previous hero branch revision 4c14c99 passed 10/10 strict runtime suites (run 45509600859), both isolated exhaust captures and zero clipped samples. Proxy-bank stable idle RMS was -29.91 and -31.26 dBFS, respectively. The upload step could not store the WAVs due to GitHub Actions artifact quota. The new recorded-bank revision is awaiting fresh CI. There is no listening or in-world performance sign-off yet.

A scoped .gitattributes exception stores only the two small hero WAV directories as normal Git binary blobs because the connector cannot upload Git LFS objects. All other LFS rules are untouched. Offline verification now checks each hero file's Git blob identity as well as PCM format and clipping, and the runtime verifier checks the new manifests. Export preset already includes engine manifests.



## Hero supercar audio priority (`feat/hero-supercar-audio`, 2026-11-24)

User prioritizes Aventador SVJ and McLaren Senna from scenic PR #36. Created separate audio branch from exact model integration; each now selects a dedicated voicing and actual factory RPM limits. Adopted verified prior runtime fixes while retaining scenic active-loop decoder optimization. Initial profiles deliberately reuse existing Vela and Kestrel recorded proxy banks; no authentic V12/Senna bank has been cleared and installed yet. Per-car intake response, throttle/RPM smoothing, shift interruption and event gains are separately tunable. Dedicated two-car capture and factory tests added. Prior PR #37 revision 5c93d16 passed 10/10 strict audio suites in run 45508597597; artifact upload failed due to storage quota, not a runtime failure. New scenic-derived revision is unverified, and listening/performance approval remains open. See [hero audio handoff](HERO_SUPERCAR_AUDIO.md).



Last updated: 2026-11-24

## Scenic driving and exact supercars (`feat/aster-scenic-supercars`)

The garage has six cars, including BlackCube's Aventador SVJ and Black Snow's McLaren Senna. The supplied meshes share the normal showroom and driving entry points, with measured wheel locations, separate rolling and brake parts, and distinct AWD and RWD presets. The visual pass removes intense road glare, fixes sideways guardrails, adds distant ridges and differentiates meadow and woodland materials. The premium pack now supplies Alder's fuel station and lamps and the Eastwater pier. See [scenic and vehicle QA](SCENIC_SUPERCARS_QA.md).

## Premium world repair and vehicle art (`feat/world-visual-premium-overhaul`)

The root game checks vegetation, authored props and static obstacles against the actual rendered road and shoulder triangles. The secondary scatter layer that placed malformed foliage over pavement has been replaced in the live scene by the validated vegetation layer and converted, UV-matched premium meshes. All 16 corridors and three bridges passed representative live driving checks. Solace GT joins the three existing roster entries and uses the same vehicle physics and versioned save format. The [visual QA report](WORLD_VISUAL_QA.md) records matched 1080p captures, performance, source provenance and regression details.

## Premium graphics asset acquisition (`feat/gfx-premium-assets`)

Added a curated CC0 source catalog, a hash-checked, staged Poly Haven glTF/PBR downloader and a graphics-swarm asset handoff under `assets/premium_world/`. Existing assets, rendering, scenes and gameplay remain unchanged. Direct download and Godot runtime validation are not available in the ChatGPT container; payload acquisition, mesh optimization, visual integration and performance QA remain pending until confirmed. See `assets/premium_world/README.md`.

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
