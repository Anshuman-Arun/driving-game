#!/usr/bin/env bash
# Assemble a TEMPORARY Godot import tree from independent PR source checkouts.
# This uses path-specific copies only. No git merge, commit or push is performed.
set -Eeuo pipefail
integrated="$(cd "${1:?Core QA checkout required}" && pwd)"
staging="$(cd "${2:?Staging checkouts directory required}" && pwd)"
out="${3:?Output directory required}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
manifest="$out/INTEGRATION_SOURCES.md"
test -f "$integrated/project.godot"

printf '## Temporary multi-branch integration smoke\n\n' > "$manifest"
printf 'Core QA base (fix/steering-camera-smoothing): `%s`\n\n' "$(git -C "$integrated" rev-parse HEAD)" >> "$manifest"
printf '| Independent source | SHA | Staged path |\n| --- | --- | --- |\n' >> "$manifest"

stage() {
  local source="$1" path="$2" src="$staging/$1/$2" dst="$integrated/$2" sha
  test -d "$staging/$source/.git" || { echo "::error::Missing staging checkout $source"; exit 2; }
  test -e "$src" || { echo "::error::Missing required owned path $src"; exit 2; }
  # Even compatible module branches must not silently replace another module's files.
  if [[ -e "$dst" ]]; then
    echo "::error::Integration path collision: $dst" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$dst")"
  cp -a "$src" "$dst"
  sha="$(git -C "$staging/$source" rev-parse HEAD)"
  printf '| %s | `%s` | `%s` |\n' "$source" "$sha" "$path" >> "$manifest"
  echo "Staged $source@$sha -> $path"
}

stage worldgen data/world
stage world-runtime modules/world_runtime
stage game-shell modules/game_shell
stage audio modules/audio
stage race-content content/races
stage racing modules/racing
stage traffic modules/traffic
stage art assets/curated

# Standalone World Runtime's loader expects an explicitly staged immutable dataset.
# This is a disposable copy of the exact same World worktree files.
mkdir -p "$integrated/modules/world_runtime/.world_source"
for file in world_metadata_v1.json road_graph_v1.json terrain_height_r16le.bin; do
  cp "$integrated/data/world/$file" "$integrated/modules/world_runtime/.world_source/$file"
done

printf '\nNo source PRs were merged or modified. All copies exist only in this disposable CI checkout.\n' >> "$manifest"
cat "$manifest"
