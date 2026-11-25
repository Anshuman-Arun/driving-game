# Professional source-native supercar audio — playable local installation

**Technical validation:** Both real original recordings were acquired and cut into 17 samples per vehicle, then played through the actual Godot 4.7.2 GEVP vehicle controller in [run 45552767921](https://github.com/Anshuman-Arun/driving-game/actions/runs/45552767921) at revision 50c317a. Neither car fell back to bundled audio. Source-native plans are frozen to those exact timestamps in `modules/audio/tools/professional_plans/`. RPM and load labels are signal estimates, not measured telemetry; subjective listening acceptance still required.

## Install and play (Windows)

From the repository root, with Python 3.11+ and FFmpeg on PATH, after reading the [Sonniss GDC EULA](https://sonniss.com/gdc-bundle-license/):

```powershell
python modules/audio/tools/install_verified_banks.py --accept-license
```

Launch the game normally. The game automatically selects the valid installed banks. No environment variable or manual annotation is required. For a legacy A/B comparison only, set `$env:ASTER_NATIVE_AUDIO="0"` before launching, then remove the variable to return to the professional banks. Re-running the installer verifies the existing banks and does not overwrite; if an older/different bank exists, move the named folder aside before installation.

The installer caches the verified originals under LocalAppData/AsterAudioSources and writes banks to the Godot user-data folder (AppData/Roaming/Godot/app_userdata/Aster Valley — Free Roam/native_engine_banks). Linux/macOS paths use the corresponding standard user data/cache directories. Optional --source-dir / --bank-dir overrides exist for isolated tests. It requires no numpy/scipy and installs no dependencies automatically. No network is required once installed.

## Source and audio treatment

- Aventador: 2014 Lamborghini Aventador Pole Position Production onboard right exhaust, 527.787 s, SHA-256 92986d10dd09f45cda5b57cca3805387e25c7235154741234f1aed60a5355a54.
- McLaren: 2019 McLaren 720S Spider SSG onboard left exhaust, 533.737 s, SHA-256 06b730e76a0987cf782bb47f472b3f87515ef7c00556b83cb3ef418a23fb24d2. Related V8 recording, not exact Senna; owner approved proxy.
- Official source archive URLs and exact member names: professional_reference.py. The [current Sonniss GDC EULA](https://sonniss.com/gdc-bundle-license/) allows game synchronization, not supplying standalone sample packs. Source and derived PCM stay on the installation machine; no loose WAVs uploaded to Git. No commercial-game rips or AI training.
- Cuts are native pitch and original waveform, converted to mono 48 kHz PCM16, with a single common downward playback trim. The existing phase-grain runtime provides continuous RPM/load interpolation; native mode disables legacy tonal suppression. No added synthetic harmonics. Runtime resampling and phase alignment remain.

## Real-source QA

| Vehicle | On/off | Max motor RPM | Speed m/s | Shifts | Buffer underruns | Maximum digital gap | Peak |
|---|---:|---:|---:|---:|---:|---:|---:|
| Aventador | 9/8 | 8635.2 | 29.32 | 2 | 0 | 0.023 ms | 0.3180 |
| McLaren | 9/8 | 7961.5 | 32.36 | 2 | 0 | 0.136 ms | 0.2672 |

Both passed all live-drive checks, including actual native bank selection, acceleration, coast, shifts, RPM following, headroom and continuity. The subsequent pinned-installer workflow tests the same windows, the standard user-data install path, repeat install, and default activation without an opt-in variable. It does not upload raw or derived audio. Final manual listening and Windows desktop execution must be verified by the user.

## Research and manual override

The preceding automated selection and manual annotation pipeline remain available for future alternative sources; use the tested frozen plans for normal installation. See earlier commits for research commands. Source labels and inferred load are deliberately not represented as measured.
