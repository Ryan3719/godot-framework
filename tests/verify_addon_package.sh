#!/usr/bin/env bash
set -euo pipefail

package_path=${1:?package path is required}
godot_bin=${2:-godot}
repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
project_dir=$(mktemp -d /tmp/godot-framework-package-install.XXXXXX)
trap 'rm -rf "$project_dir"' EXIT

python3 "$repository_root/scripts/verify_addon_package.py" "$package_path"
rsync -a "$repository_root/tests/package_install_project/" "$project_dir/"
unzip -q "$package_path" -d "$project_dir"

NO_COLOR=1 "$godot_bin" --headless --editor --quit --path "$project_dir" > "$project_dir/editor.log" 2>&1
NO_COLOR=1 "$godot_bin" --headless --verbose --path "$project_dir" > "$project_dir/run.log" 2>&1
grep -F "[PACKAGE TEST] PASS: packaged addon installs and stops all module services" "$project_dir/run.log"
if grep -E "SCRIPT ERROR|Parse Error|^ERROR:|ObjectDB instances leaked|instances were leaked|resources still in use" "$project_dir/editor.log" "$project_dir/run.log"; then
	exit 1
fi
