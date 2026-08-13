#!/usr/bin/env bash
set -euo pipefail

package_path=${1:?package path is required}
godot_bin=${2:-godot}
repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
project_dir=$(mktemp -d /tmp/godot-framework-macos-export.XXXXXX)
export_dir=$(mktemp -d /tmp/godot-framework-macos-build.XXXXXX)
trap 'rm -rf "$project_dir" "$export_dir"' EXIT

python3 "$repository_root/scripts/verify_addon_package.py" "$package_path"
rsync -a "$repository_root/tests/package_install_project/" "$project_dir/"
unzip -q "$package_path" -d "$project_dir"

NO_COLOR=1 "$godot_bin" --headless --editor --quit --path "$project_dir" > "$project_dir/editor.log" 2>&1
NO_COLOR=1 "$godot_bin" --headless --path "$project_dir" --export-release macOS "$export_dir/GodotFrameworkTest.app" > "$project_dir/export.log" 2>&1
executable="$export_dir/GodotFrameworkTest.app/Contents/MacOS/Godot Framework Package Install Test"
test -x "$executable"
(
	cd "$export_dir"
	NO_COLOR=1 "$executable" --headless --verbose > "$project_dir/export-run.log" 2>&1
)

grep -F "[EXPORT TEST] PASS: packaged addon starts and stops all modules in release export" "$project_dir/export-run.log"
if grep -E "SCRIPT ERROR|Parse Error|^ERROR:|ObjectDB instances leaked|instances were leaked|resources still in use" \
	"$project_dir/editor.log" "$project_dir/export.log" "$project_dir/export-run.log"; then
	exit 1
fi
