# Agent C — biome and procedural placement handoff

Base: 67023539e56e5e80d5efcd3f3239be9650c6f462 (verified identical to main at branch creation). Prompt revision: 3f1d1ce126ad680ee56af11c45124c3ac30ec6e6. Branch: feat/env-c-biomes.

## Delivered

Owned offline generator `content/scenery/environment_overhaul/bake_biomes.py`, pinned Python numerical dependencies, unit/synthetic/canonical tests, headless Godot sampler comparison. No root wiring, no new collisions, no canonical data writes.

The output directory is `content/scenery/environment_overhaul/masks/`. Generation writes:
* `manifest.json`: schema v1, 1000 x 1000, 2 m cells, origins -1000, RGBA, channels in order grass_suitability, woodland_weight, moisture, exposed_rock_weight; SHA-256 of raw mask, source SHA-256 map, seed, tuning, understory SHA-256 and surface probes.
* `biome_rgba8.bin`: 4,000,000 raw bytes, X fastest, Z ascending; cell (i,j) center (-999+2i,-999+2j). Byte offset 4*(1000*j+i). Channels are independent normalized ecological weights, not probabilities summing to one.
* `understory.json`: v1, source hashes, seed, placements with species_id, x,z,yaw_rad,scale,seed. No Y, no mature tree replacement. Coordinator samples exact surface, validates bounds, footprint, and exact road clearance and resolves licensed species assets. Skip missing assets.
* `statistics.json`: regional coverage, mean channels and slopes, eligible cell counts, placement counts, exclusions, rejection counts and source lane alignment error.

Manifest is replaced last; consumers must check dimensions and content hash and fail closed on a missing/corrupt file. Understory hash also checked by producer. Do not enable until the real files are generated and validated. No generated output is checked in yet.

## Reproduction from repository root

Python 3.11 or 3.12 recommended. Ensure real binaries are fetched (not LFS pointer text).

```sh
git lfs pull
python -m pip install -r content/scenery/environment_overhaul/requirements.txt
python -m py_compile content/scenery/environment_overhaul/bake_biomes.py content/scenery/environment_overhaul/test_biomes.py
python -m unittest discover -s content/scenery/environment_overhaul -p test_biomes.py -v
python content/scenery/environment_overhaul/bake_biomes.py --project . --output content/scenery/environment_overhaul/masks --seed 20261121
```

For fixture-only verification without canonical files:

```sh
cd content/scenery/environment_overhaul
python -m unittest test_biomes.UnitTests test_biomes.FixtureTests -v
```

Return to repository root. Install the checksum-pinned Godot 4.7.2 standard editor using the exact installation instructions in .github/workflows/map-regression.yml.

```sh
godot --headless --path . --editor --import
godot --headless --path . --script res://content/scenery/environment_overhaul/test_surface.gd
godot --headless --path . --fixed-fps 60 --script res://tests/integration/roadworks_check.gd
godot --headless --path . --fixed-fps 60 --script res://tests/integration/world_visual_qa.gd
godot --headless --path . --fixed-fps 60 --script res://tests/integration/garage_world.gd
godot --headless --path . --fixed-fps 60 --script res://tests/integration/vehicle_world.gd
node modules/world_runtime/tests/verify_world_data.mjs data/world
```

Also run map_width_check.gd if present on owner-selected base. Inspect exit code and SCRIPT ERROR, Parse Error, shader errors and FAIL text, not exit code alone. Existing map-regression.yml push filter targets feat/map-width-current-main, not this branch; no shared CI workflow edits allowed. Use the owned commands above or coordinator CI.

## Actual evidence and limitations

GitHub connector independently decoded 502002 canonical terrain bytes, height range 5.00–240.45 m, and compared 4846 graph points with canonical bilinear lane heights. Maximum difference 0.0005553262500086475 m, below 0.015 m. This proves the centered mapping and source lane alignment, not runtime execution. The production world_data.gd triangle formula was inspected and mirrored; headless comparison is supplied, not executed.

Source paths inspected: data/world/world_metadata_v1.json, road_graph_v1.json, terrain_height_r16le.bin, terrain_roadworks_r16le.bin, roadworks.json; scenery manifest, packs, water cells and gate reservations; legacy bake_vegetation.py, live valley_vegetation.gd and premium foliage runtime. Canonical graph Git blob 9bba378d68879df3baed2c97a4885c0adde88406; heightfield blob d951ce11a831dad5430b4c7157e2296f73c6b151; roadworks raster blob f8eda2d346cd2adb1224d68212af087416d6118c; roadworks JSON blob ead364b763da6dd0db75ee0bd066f8ac310942d2. Generated manifest records actual byte SHA-256 for every consumed file at bake time.

Connector returned empty content for vegetation.bin (blob 2aa8b11956042262c75d9f0c1c976c7abf9a1319); raw blob fetch failed UTF-8 decoding. Container Git cannot resolve github.com; no Godot executable on PATH. Thus real bake, output hash, actual ecology statistics, Python regression and Godot tests are unverified unless separately reported. Do not treat source inspections as Python or GPU acceptance.

Conservative maximum corridor half-width plus shoulder and buffer is used across the entire route, including bridges, rather than attempting exact deck/taper geometry. Junction hulls are buffered; this may over-exclude verges and tight junctions. Water cell exclusion is exact on the 2 m grid with an additional shoreline safety buffer. Authored manifest radii and existing vegetation approximations are not exact transformed footprints. Runtime exact triangle road clearance and swept plant AABB are mandatory, and coordinator must avoid duplicate retained foliage. Dense legacy grass class 2 is not used as an exclusion. Premium cache is used only to conservatively suppress new understory placements; no premium runtime resurrection. Terrain slope is a centered finite difference of triangle-sampled heights, not a physics normal. No graphical acceptance, GPU performance or real-road safety claim.

## Tuning and integration

Optional --tuning PATH takes a JSON object overriding documented DEFAULTS in the generator. Start with road_margin_m 2, sightline_m 12, water_margin_m 2, spacing_m 8, density .45, max_placements 12000. Try density .25/.45/.65 and spacing 6/8/12 m on matched local Cedar Woods and Green Valley captures. Never relax safety margins based solely on appearance. Rock slope thresholds, alpine start/full height, canopy grass penalty and maximum understory slope are adjustable. Regenerate after any owner-selected graph/width/roadworks or scenery change; preserve original source bytes and review new manifest hashes. Remove or disable overlapping legacy ground layers only during coordinator integration, not this branch.

## Ledger / project status proposed entries

ASSET_LICENSES: No new third-party asset payloads. Original procedural mask/placement algorithm uses existing project data; numerical dependencies NumPy (BSD-3-Clause) and SciPy (BSD-3-Clause), offline tools only. Existing source assets remain under their existing ledger.

PROJECT_STATUS: Agent C independent candidate implements deterministic 2 m RGBA ecological mask and optional understory generation, with unit, fixture, canonical and Godot terrain comparison tests. Independent connector source-alignment preflight passed (4846 points, max error 0.56 mm). Actual generated mask, Python/Godot execution and local graphical acceptance remain pending where no execution evidence is available. No production wiring or shared file changes.
