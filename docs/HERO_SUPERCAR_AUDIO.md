# Aventador SVJ and McLaren Senna: hero audio handoff

## Priority

These two cars are the player's preferred driving models. Direct new recordings, ear-based adjustments, and detailed runtime testing toward them first. Keep other cars functional; do not spend equal tuning effort across the roster.

Branch starts at scenic supercars PR #36 commit 65b729f (the exact six-car garage and model integration), not the older three-car branch. The prior audio PR #37 revision 5c93d16 passed all ten strict audio runtime suites, asset checks, and three real-time captures in run 45508597597. The job failed only during upload-artifact because repository artifact storage quota was exhausted. It did not validate this new combined branch. No captures could be downloaded from that run.

## Current tuning (provisional listening starting point, not manufacturer sound data)

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
