# CI validation: independent PR workstreams

This directory and `.github/workflows/` are the **only** files owned by the CI branch. CI does not merge other PRs or edit their sources.

## Workflows and branch isolation

`validate-workstreams.yml` creates **five separate matrix job instances**. Each checks out the CI scripts from this PR and independently checks out the feature branch below into `worktree/` (never from `main`):

| Job | Checked-out branch | Fatal validation gates |
| --- | --- | --- |
| Core | `feat/core-driving` (#6) | Godot 4.7.2 editor import/parse; `tests/core/smoke.gd` physics smoke |
| Racing | `feat/racing-systems` (#5) | Godot editor import/parse; `modules/racing/tests/run_tests.gd` |
| Traffic | `feat/traffic-systems` (#4) | Python fixture unit tests, 90-second numerical reference flow, Godot import + GDScript suite |
| World | `feat/worldgen` (#3) | Node graph/turn tests, generator replay, no changes to committed world data/previews |
| Art | `feat/art-pipeline` (#7) | Node structural validator, evidence/license manifest check, supplementary regeneration byte check, preview/environment/texture regeneration and tracked diff check, second structural pass, disposable Godot import project |

A test failure, missing expected file, missing branch, required engine download/hash mismatch, or import/parser error **fails** that job. Workstream branches are never merged with each other in CI. The checkouts have read-only GitHub token permissions and `persist-credentials: false`. The workflow does not accept fork-controlled PR code with elevated privileges or use `pull_request_target`.

The standard Linux x86_64 Godot 4.7.2 stable editor is downloaded only from `godotengine/godot-builds` and checked against the official release SHA-256 `cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4`. Node 22.16.0, Python 3.12.12 and Actions dependencies are pinned. Jobs run on `ubuntu-24.04`.

All command output is streamed to the Actions log and to named `ci-out/*.log` files; `SUMMARY.md` is added to the Actions job summary. Uploads run even on failure and are retained for 14 days. Initial checkout/setup failures have Actions step logs even if no artifact is yet present.

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
