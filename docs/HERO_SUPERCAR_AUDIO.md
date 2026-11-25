# Aventador SVJ and McLaren Senna: hero audio handoff

## Piano-like acceleration and deceleration: player-reported quality failure (2026-11-24)

The owner reports that acceleration and lift-off sound like piano notes. This supersedes prior technical acceptance; no subjective sign-off. Independently downloaded the exact 6609c6b capture artifact (run 45511642256, artifact 14976710538). Analyzed both 44.1 kHz stereo WAVs, 30.65 seconds each. During the full-throttle sweep (1.25–4.7 s), the dominant spectral bin within 40–4500 Hz occupied median 33.1% (Aventador) and 37.4% (Senna) of measured band energy, with 90th percentiles 61.6% and 65.7% (2048-sample spectrogram, 1792 overlap). These are concentration diagnostics, not a listening score. Aventador dominant peaks repeatedly alternate harmonic orders. The current upstream banks were deliberately pitch-flattened from spotter clips for a hybrid synth/sample app, not a purpose-built continuous ramp renderer.

Research: Playground's official FH6 feature notes (https://forza.net/news/forza-horizon-6-features) describe new recordings/remastered audio, upgraded turbo/backfire layers, improved surface and cockpit responses, and Triton spatial reverb. FH5 official July update (https://forza.net/news/forza-horizon-5-road-to-mexico-july-update) and lead audio designer Fraser Strachan's interview (https://www.asoundeffect.com/forza-5-game-audio/) explain live track acceleration/deceleration sweeps, granular synthesis and separate shift/limiter/idle material. Exact FH6 playback internals are proprietary; no copied game audio.

Immediate diagnostic revision isolates real exhaust for both hero cars: disabled the duplicate ON-bank pseudo-intake voice and generic synthetic shift/pops, preserving physical shift torque cuts, actual ON/OFF recordings and active-loop performance. This is not a proven cure for the tonal source itself. Added isolated exhaust WAV and synchronized RPM/throttle trace export to the capture runner for direct A/B and harmonic tracking.

Added experimental offline continuous-sweep research script and separate CI workflow. It downloads the original source Opus recordings from the attributed Commons URLs, tracks multiple harmonics with continuity penalties, proposes contiguous ascending/descending segments, and makes phase-referenced overlap-add audition previews from individual segments. It includes a synthetic chirp algorithm test. No preview is automatically promoted; source identity, actual RPM/load, timbre, coverage and listening require review. Source access is blocked by local DNS; CI attempt pending. Existing game still uses loops, not a real-time granular renderer. New runtime CI pending. Local user build may differ: check branch/commit and dedicated manifest presence before comparing. Preserve main, scenic models and physics.

## Phase-synchronous hero engine playback and defect detection (2026-11-25)

The owner asked to continue until blocked, with priority on the piano-like acceleration/deceleration. The clean-loop revision 76f8b1d passed all ten Godot suites, but isolated exhaust spectra still showed high harmonic concentration (median dominant FFT-bin power fraction 0.284 Aventador / 0.399 Senna in sustained sweep, 40–4500 Hz, 2048-sample STFT). This is not a subjective quality score.

Implemented PhaseGrainEngine: extracts six varied, 16-firing-cycle grains per anchor from the existing real PCM, fits a bounded fractional period, aligns starting phase, overlaps complementary windows and uses a single sample-clock firing phase for RPM and load blending. Both hero cars use the new renderer; older cars retain legacy loops. No artificial oscillator or copied game audio. The original continuous-take research is a separate candidate pipeline, not yet the installed source bank.

First renderer revision f69eeaa, actual Godot 4.7.2 run 45514601359: 61/61 recorded asset checks, all ten runtime suites, both dedicated banks, zero clipped samples. Offline real-PCM rendering regression: 1 second of sample generation in 19.1 ms on CI runner, peak 0.195, max sample delta 0.090; hero preparation 130–150 ms. **Actual downloaded capture was NOT accepted**: 331 exact-zero runs >2 ms per car, longest about 31.9 ms, caused by a 2048-sample generator queue being drained by the 4096-frame headless mixer quantum. This defect escaped the older peak-only gate.

Changed buffer sizing to use at least 4096 source frames in headless mode, and reported device latency plus margin for normal drivers; added underrun/push-failure telemetry and strict independent PCM gap detection. New validation requires zero post-warmup generator skips and no >=2 ms exact-zero runs, and checks complete RPM trace. Shortened test timeouts so a failed assertion cannot stall QA for 15 minutes. New revision not verified yet.

Continuous recording research run 45514601347 failed before decoding because ffmpeg was absent; numpy/scipy installed correctly. Pinned Python analysis dependencies and bundled imageio-ffmpeg fallback. Local independently executed chirp-tracker fixture with faster spectral background filter gave median frequency error 0.338%, valid sweep and nonzero overlap-add output. Not a real-car result. Original source download still needs CI verification. No user listening sign-off or in-world performance validation.

## Priority

These two cars are the player's preferred driving models. Direct new recordings, ear-based adjustments, and detailed runtime testing toward them first. Keep other cars functional; do not spend equal tuning effort across the roster.

Branch starts at scenic supercars PR #36 commit 65b729f (the exact six-car garage and model integration), not the older three-car branch. The prior audio PR #37 revision 5c93d16 passed all ten strict audio runtime suites, asset checks, and three real-time captures in run 45508597597. The job failed only during upload-artifact because repository artifact storage quota was exhausted. It did not validate this new combined branch. No captures could be downloaded from that run.

## Private-build recorded banks installed (2026-11-24)

The owner requested the two preferred hero cars receive the overwhelming majority of sound-tuning work and authorized private-build audition. Added 26 real field-recorded loops obtained from the public supercar-engine-sound repository (upstream sample banks `svj` and `765lt`). Each 48 kHz mono PCM16 file was checked for valid format, exact Git blob identity, nonzero signal and zero clipped samples before the commit. Original PCM is unchanged; runtime seam conditioning applies. Source provenance, authors, declared CC BY 3.0 license, original URLs, upstream edit descriptions and per-loop waveform metrics are in each dedicated manifest. Independent Commons license review is pending; this is an audition build, not a public-distribution clearance.

| Bank | Acceleration | Coast | Source character |
|---|---|---|---|
| Aventador SVJ | 8 anchors, 950–8000 RPM | 6 anchors, 2000–8000 RPM | Aventador/SV/SVJ family V12 |
| Senna | 7 anchors, 1000–7000 RPM | 5 anchors, 3000–7000 RPM | McLaren 765LT/600LT/720S family V8, not actual Senna |
 
The RPM and load labels are estimates from upstream, not verified dyno telemetry. These are multiple field-recording sessions; several coast loops are short (shortest about 0.15 s), and high-RPM timbral consistency must be auditioned. No new turbo whistle, mechanical or gearshift recordings yet. The prior proxy banks remain emergency fallback only; both factory and capture tests now require the dedicated bank. Hero idle gain changed from 0.40 to 0.58/0.60 (approximately +3.2/+3.5 dB before the rest of the mix), with existing independent shift/intake response retained. No vehicle physics changes.

The previous hero branch revision 4c14c99 passed 10/10 strict runtime suites (run 45509600859), both isolated exhaust captures and zero clipped samples. Proxy-bank stable idle RMS was -29.91 and -31.26 dBFS, respectively. The upload step could not store the WAVs due to GitHub Actions artifact quota. The new recorded-bank revision is awaiting fresh CI. There is no listening or in-world performance sign-off yet.

A scoped .gitattributes exception stores only the two small hero WAV directories as normal Git binary blobs because the connector cannot upload Git LFS objects. All other LFS rules are untouched. Offline verification now checks each hero file's Git blob identity as well as PCM format and clipping, and the runtime verifier checks the new manifests. Export preset already includes engine manifests.

## Initial tuning (historical proxy-bank starting point, not manufacturer sound data)

| Parameter | Aventador SVJ | McLaren Senna |
|---|---:|---:|
| Actual factory idle / redline | 900 / 8700 RPM | 980 / 8000 RPM |
| Source bank until cleared replacement | vela_gt (flat-six proxy) | kestrel_xr (recorded V8 proxy) |
| RPM smoothing | 35 ms | 42 ms |
| Throttle smoothing | 60 ms | 75 ms |
| Intake build time | 60 ms | 165 ms |
| Legacy shift fallback duration | 125 ms | 85 ms |
| Shift cut gain | 0.22 | 0.42 |
| Shift one-shot gain | 0.32 | 0.20 |
| Overrun one-shot gain | 0.37 | 0.23 |

The Aventador target is a direct, progressively bright high-RPM naturally aspirated character with a distinct but controlled shift interruption. Senna target is a denser V8 tone, a smoother/faster gear change, and a slower-building induction layer. Delayed induction is a voicing approximation, not measured turbo pressure or a new turbo recording. No vehicle dynamics are retuned. The factory now selects unique audio profile IDs, dedicated manifests are preferred if present, and capture records the actual bank and proxy flag. Existing bank source PCM and original attribution remain intact.

## Source sourcing gates

- Exact Aventador SVJ, Aventador SV and McLaren 765LT / 600LT field audio found on Wikimedia Commons, but the files checked are explicitly pending license review. Do not add these unreviewed recordings as new redistribution-safe banks. See https://commons.wikimedia.org/wiki/File:Lamborghini_Aventador_SVJ_-_engine_and_exhaust_sound_(YouTube_zqv9zLtHsUM).opus and https://commons.wikimedia.org/wiki/File:McLaren_765LT_-_engine_and_exhaust_sound_(YouTube_5oSRv66QFW0).opus.
- The source creator's explicit license and original recording must be checked. CC0 Performance Cars (https://muted.io/performance-cars/) remains a candidate, not acquired or auditioned.
- Attempted to retrieve four other CC0 reference previews via EngineLab mirror: binary paths returned 404. No new sound bank imported. Do not claim proxy recordings are authentic V12 or Senna recordings.
- Aim for continuous idle, light load, full load, steady speed, lift and shift events from one recording session; broad RPM coverage and consistent microphone position beat exact badge matching. Source notes, SHA-256, annotation basis and individual loop metrics are required before promotion.

## Validation

Run `bash tests/integration/audio_qa/run_all.sh` from the scenic-derived branch. Dedicated factory integration checks verify the actual two car IDs, idle/redline, selected bank, active voice count and event routing. The real-time capture runner prioritizes the two hero cars across eleven scenarios; older cars retain unit tests. The branch preserves active-loop playback instead of starting all engine decoders. GPU/frame pacing and manual ear-based testing are still needed on the scenic world. The optional CI upload may fail due to quota; strict runtime gates remain mandatory.

For manual listening with Godot 4.7.2, set ASTER_AUDIO_CAPTURE_DIR to an absolute directory and run the capture suite. Compare each car at idle, slow rolling, 25/50/100% load, repeated 2–3 and 3–4 shifts, coasting, redline, chase/cockpit and wall proximity. Listen for tonal discontinuities, loop clicks, doubled fundamentals, fake pops, overly quiet/harsh idle, and high-RPM pitch that does not track acceleration. Change one control at a time and compare level-matched A/B recordings. Do not declare premium quality from zero clipping alone.
