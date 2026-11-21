# CI validation: independent PR workstreams

This directory and `.github/workflows/` are the **only** files owned by the CI branch. CI does not merge other PRs or edit their sources.

## Workflows and branch isolation

`validate-workstreams.yml` runs on pushes to `main` and `feat/ci-validation`, and on pull requests targeting `main` (not just changes to CI scripts). It creates **five separate matrix job instances**. Each checks out the CI scripts from this PR and independently checks out the feature branch below into `worktree/` (never from `main`):

| Job | Checked-out branch | Fatal validation gates |
| --- | --- | --- |
| Core | `feat/core-driving` (#6) | Godot 4.7.2 editor import/parse; `tests/core/smoke.gd` physics smoke |
| Racing | `feat/racing-systems` (#5) | Godot editor import/parse; `modules/racing/tests/run_tests.gd` |
| Traffic | `feat/traffic-systems` (#4) | Python fixture unit tests, 90-second numerical reference flow, Godot import + GDScript suite |
| World | `feat/worldgen` (#3) | Node graph/turn tests, generator replay, no changes to committed world data/previews |
| Art | `feat/art-pipeline` (#7) | Node structural validator, evidence/license manifest check, supplementary regeneration byte check, preview/environment/texture regeneration and tracked diff check, second structural pass, disposable Godot import project |

A test failure, missing expected file, missing branch, required engine download/hash mismatch, or import/parser error **fails** that job. Workstream branches are never merged with each other in CI. The checkouts have read-only GitHub token permissions and `persist-credentials: false`. The workflow does not accept fork-controlled PR code with elevated privileges or use `pull_request_target`.

The standard Linux x86_64 Godot 4.7.2 stable editor is downloaded only from `godotengine/godot-builds` and checked against the official release SHA-256 `cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4`. Node 22.16.0, Python 3.12.12 and Actions dependencies are pinned. Jobs run on `ubuntu-24.04`.

All command output is streamed to the Actions log and to named `ci-out/*.log` files; `SUMMARY.md` is added to the Actions job summary. Uploads run even on failure and are retained for 14 days **when repository storage quota permits**. On artifact-upload failure (the repository currently reports a full quota), the upload is best-effort so it does not mask a passing or failing validation gate; the workflow issues an explicit warning and appends log tails to the job summary. Full command output remains in the Actions job logs. Initial checkout/setup failures also have Actions step logs.

## Manually rerun on a selected existing branch

After this PR is merged into **main**, open **Actions → Manually validate an existing branch → Run workflow**. Select the test suite and optionally enter a branch name. Empty branch uses that suite's default branch above; a nonexisting branch fails on checkout. The dispatcher and tests have no write permission.

GitHub normally requires a `workflow_dispatch` workflow to be present on the default branch before manual invocation is offered. While this PR remains unmerged, the automatic **push** and **PR** validation runs provide verification of this CI branch; do not claim the manual dispatcher was exercised unless there is a logged dispatch run.

## Run the same scripts on a checkout

Provide a locally checked-out feature repository, an output directory, and the CI script directory:

```bash
bash tools/ci/install_godot.sh /tmp/godot/bin   # official release download, checksum, version
export PATH="/tmp/godot/bin:$PATH"
bash tools/ci/run_workstream.sh world /path/to/world-branch /tmp/world-logs "$PWD/tools/ci"
bash tools/ci/run_workstream.sh traffic /path/to/traffic-branch /tmp/traffic-logs "$PWD/tools/ci"
```

`run_workstream.sh` assumes the relevant pinned Node/Python runtime is installed. Its commands are copied from the five PRs' own TEST_REPORT/README instructions. It fails on data changes induced by regeneration rather than silently committing regenerated content.

## Evidence classification and limits

- **PASS:** the exact recorded headless/CLI command exited zero and, for Godot imports, logged no parser/import errors. The output records the independently checked-out source commit.
- **FAIL:** a required test, source checkout, binary integrity check, parser/import check or regeneration comparison failed; inspect the named log.
- **NOT EXECUTED:** branch checkout, download or setup prevented test execution. A missing result must never be called a pass.
- **NOT TESTED BY CI:** interactive driving quality, keyboard/gamepad hardware feel, Windows export, GPU FPS, rendered appearance, 10–20 traffic vehicles' actual visual behavior, and integrated multi-branch gameplay. A successful headless test is not evidence of these.

Neither the five source PRs nor this CI PR should be merged on the strength of these standalone checks alone. Follow up with real integrated engine and hardware playtests. `docs/PROJECT_STATUS.md` is intentionally not modified here because it is outside the assigned ownership scope.

## Expansion on `feat/ci-expansion` (base: `feat/ci-validation`)

The original `validate-workstreams.yml` remains unchanged: its five jobs still assess the exact original Core, Racing, Traffic, World and Art feature branches, including known upstream failures. **Do not interpret the red original Core gate as the result for the corrected PR #9/#15 branch.** The original manual dispatcher also remains intact.

The new `expanded-validation.yml` tests six *additional, independent* source branches on GitHub Actions push to `feat/ci-expansion` and PRs targeting `feat/ci-validation`, without merging them:

| Expanded gate | Exact source ref | Mandatory CLI/engine tests |
| --- | --- | --- |
| Corrected Core | `fix/steering-camera-smoothing` (#15, based on #9) | Godot 4.7.2 import, Core smoke at fixed 60 FPS, steering/camera regression at fixed 30, 60, 83, 144 FPS |
| Corrected World Runtime | `fix/world-runtime-qa` (#16) + `feat/worldgen` (#3) | Copy immutable World JSON and R16 into disposable ignored cache; Node reference geometry; Godot editor import, preview collider smoke, full-world collider smoke |
| Corrected Game Shell | `fix/game-shell-runtime-qa` (#17) | Standalone Godot import and native `tests/run_tests.gd` (53 assertions per PR QA documentation) |
| Audio | `feat/audio` (#11) | Python WAV unit tests; synth regeneration and tracked WAV byte comparison; standalone Godot import and native GDScript smoke |
| Production Race Content | `feat/race-content` (#10) + `feat/worldgen` (#3) | Node author `--check` and native independent `test_author.js` against the actual World graph (not fixtures) |
| Racing production | `feat/production-racing-readiness` | Reuse strict original Racing Godot import and native GDScript gates; never infer a pass from a branch name |

An availability-aware extra job observes `feat/world-traffic-content` and dynamically checks out `feat/worldgen` and `feat/traffic-systems` as read-only dependencies. If the content branch is missing or empty it explicitly records **NOT EXECUTED**, never a test pass. Once actual content exists, it executes `node content/traffic/tests/validate_content.js <World graph>` and creates a disposable root Godot project containing the actual content, simulation, and canonical World data. It then runs the production native GDScript `run_world_scenarios.gd` in both `--smoke` (15 s/case) and `--full` (90 s/case) modes. Missing required real test files or failures fail the gate; the original `modules/traffic/` suite remains independent.

`integration-smoke.yml` independently checks out the corrected Core project and the World data, corrected World Runtime, corrected Game Shell, Audio, production Race Content, production Racing, Traffic and Art branches. `stage_integration.sh` stages **only the owned paths** inside the throwaway runner checkout. `check_integration.py` flags duplicate `class_name` declarations and missing *literal* `res://` paths. Godot 4.7.2 editor import and a Core physics smoke then probe real combined-project parser/import and runtime problems. Stage, static, import and smoke outcomes are evaluated separately: a failure remains a failure. This is a **diagnostic integration probe**, not a merged branch, gameplay quality result or production-ready binary. Dynamic resource construction and graphical/physical controller behavior need additional tests.

These new workflows use read-only `contents: read` credentials, SHA-pinned official Actions, version-pinned Node/Python and a SHA-256 verified Godot executable. Each checkout's exact **commit SHA** (and the World data SHA where relevant) is printed into the job summary; moving branch names alone are insufficient provenance. No new job attempts artifact upload because repository Actions artifact storage is exhausted. The existing baseline's upload remains best-effort.

### Reproduce locally with separate branches

Check out each source branch independently, never merge its PR:

```bash
bash tools/ci/install_godot.sh /tmp/godot/bin
export PATH="/tmp/godot/bin:$PATH"
bash tools/ci/run_expanded.sh core-qa /path/to/steering-camera-checkout /tmp/core-ci "$PWD/tools/ci"
bash tools/ci/run_expanded.sh world-runtime /path/to/world-runtime-qa /tmp/world-ci "$PWD/tools/ci" /path/to/worldgen-checkout
bash tools/ci/run_expanded.sh race-content /path/to/race-content /tmp/race-ci "$PWD/tools/ci" /path/to/worldgen-checkout
bash tools/ci/run_expanded.sh game-shell /path/to/game-shell-qa /tmp/shell-ci "$PWD/tools/ci"
bash tools/ci/run_expanded.sh audio /path/to/audio /tmp/audio-ci "$PWD/tools/ci"
bash tools/ci/run_expanded.sh racing-production /path/to/racing-production /tmp/racing-ci "$PWD/tools/ci"
```

For the integration preflight, use a **disposable** rooted Core QA checkout (not a developer's working tree) and a sibling staging directory with subcheckouts named `worldgen`, `world-runtime`, `game-shell`, `audio`, `race-content`, `racing`, `traffic`, and `art`. Then run `bash tools/ci/stage_integration.sh /tmp/integrated /tmp/staging /tmp/integration-logs`, followed by `python tools/ci/check_integration.py /tmp/integrated` and Godot import/smoke from `/tmp/integrated`. Never run staging on a real game or source-feature worktree.

**Evidence rules:** "PASS" only if the named real command and its strict Godot logs succeeded; "FAIL" for failing upstream checks or CI setup; "NOT EXECUTED" for missing branch/content or infrastructure before tests. Runner headless tests do not validate rendered gameplay, 10–20-car behavior, Windows export, FPS, or gamepad hardware. Consult the particular Actions run and source SHAs for current observed results; these branches can move.
