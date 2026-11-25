# Source-native supercar audio (local audition)

This follows PR #39 rather than editing its moving branch. PRs #11 and #19 are the synthesized legacy system; #31 supplied the first field samples; #33 integrates recorded audio; #37 refines it; #39 has a phase-grain renderer and current supercar IDs. Keep those systems, but replace pitch-flattened source material when a reviewed full-coverage bank exists.

## Verified originals
Both professional WAVs were actually downloaded by the prior branch's [run 45527198610](https://github.com/Anshuman-Arun/driving-game/actions/runs/45527198610), job 138913472572:
- 2014 Aventador onboard exhaust: 527.787 s, 153148216 bytes.
- 2019 McLaren 720S Spider onboard exhaust: 533.737 s, 155002642 bytes. Related V8 family, not an exact Senna.
- Original file names, official archive URLs and ZIP offsets are in professional_reference.py. The new tool pins both verified SHA-256 hashes.
- The [current Sonniss GDC EULA](https://sonniss.com/gdc-bundle-license/) allows game synchronization and sharing within a project team, not standalone sample redistribution. Download yourself, accept terms and keep all source/derived WAVs outside Git. Do not use commercial-game rips. The game audio work is not AI model training.

## Windows local workflow
From the repository root, with Python 3.11+ and FFmpeg installed:
1. Download the originals with `python modules/audio/tools/source_native_bank.py fetch aventador_svj D:/AsterAudioSources` and repeat for `mclaren_senna`. Read the EULA before downloading.
2. Listen to the actual takes, annotate steady windows throughout the RPM range, both loaded and coast, in a JSON file. The previous spectral report contains candidate timestamps, not confirmed tachometer/load data. Do not convert harmonic ambiguity into fictional RPM labels. Require >=6 per layer, <=1500 RPM gaps, loaded idle and near-redline coverage, and genuinely identified load.
3. Plan shape: {"profile":"aventador_svj","rpm_basis":"explain the evidence","anchors":[{"rpm":1000,"layer":"on","start_s":0.0,"end_s":0.8,"rpm_basis":"explain measurement","load_basis":"explain load evidence"}]}. The single row is only a schema example, not an actual source annotation; a complete plan is required.
4. Build using `python modules/audio/tools/source_native_bank.py build plan.json D:/AsterAudioSources/aventador_svj.wav "<Godot user data directory>/native_engine_banks"`. Open the actual user data directory from Godot's Project menu. The tool rejects repository output and existing target banks; move old audition folders aside.
5. In PowerShell set `$env:ASTER_NATIVE_AUDIO = "1"` before launching the editor/game. The runtime uses the verified local bank if available, and logs selection. Unset the variable for baseline. Missing/invalid banks keep the bundled audio. No WAVs are shared via Git.
6. A/B with same car, throttle, gears and route. Compare sustained idle/part throttle/high RPM, lift-off, downshifts and rapid throttle changes; require owner listening acceptance. Current original-take annotations are not complete, so no replacement bank is installed by this PR.

The new pipeline only cuts the source, converts to mono 48 kHz PCM16, and uses one shared downward playback trim. It does not flatten pitch, normalize each clip, generate harmonics or seam-edit the source WAV. Existing runtime phase-grain blending and private loop seam handling remain; tonal suppression is disabled for the native bank. It is still a sampled/grain engine, not literal uninterrupted video playback.

## Validation
`python -m unittest discover -s modules/audio/tests -p test_source_native_bank.py -v` checks coverage rejection and a sample-exact native PCM cut with a test-only fixture. Godot import/runtime, real source annotation, actual bank integration and listening remain pending. No source audio is committed here.
