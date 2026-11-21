#!/usr/bin/env bash
# Official Godot 4.7.2 stable standard Linux x86_64 editor; integrity-pinned.
set -Eeuo pipefail
install_dir="${1:?Usage: install_godot.sh INSTALL_DIRECTORY}"
version="4.7.2-stable"
archive="Godot_v${version}_linux.x86_64.zip"
digest="cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4"
url="https://github.com/godotengine/godot-builds/releases/download/${version}/${archive}"
mkdir -p "$install_dir"
zip_path="${RUNNER_TEMP:-/tmp}/$archive"
curl --fail --location --show-error --silent --retry 3 --retry-delay 3 --connect-timeout 20 --max-time 300 "$url" -o "$zip_path"
printf '%s  %s\n' "$digest" "$zip_path" | sha256sum --check --status || {
  echo "::error::Godot download SHA-256 mismatch (official godotengine/godot-builds release)" >&2
  exit 1
}
unzip -oq "$zip_path" -d "$install_dir"
engine="$install_dir/Godot_v${version}_linux.x86_64"
test -f "$engine" || { echo "::error::Godot executable missing from verified archive" >&2; exit 1; }
chmod +x "$engine"
ln -sfn "$engine" "$install_dir/godot"
actual="$("$install_dir/godot" --headless --version)"
printf 'Godot engine: %s\n' "$actual"
[[ "$actual" == 4.7.2.stable* ]] || {
  echo "::error::Unexpected Godot version: $actual" >&2
  exit 1
}
if [[ -n "${GITHUB_PATH:-}" ]]; then printf '%s\n' "$install_dir" >> "$GITHUB_PATH"; fi
