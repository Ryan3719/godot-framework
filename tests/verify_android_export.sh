#!/usr/bin/env bash
set -euo pipefail

package_path=${1:?package path is required}
godot_bin=${2:?Godot editor path is required}
java_sdk_path=${3:?Java SDK path is required}
android_sdk_path=${4:?Android SDK path is required}
output_apk=${5:?signed APK output path is required}
repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work_dir=$(mktemp -d /tmp/godot-framework-android-export.XXXXXX)
project_dir="$work_dir/project"
settings_dir="$work_dir/settings"
unsigned_apk="$work_dir/unsigned.apk"
aligned_apk="$work_dir/aligned.apk"
keystore_path="$work_dir/test-signing.jks"

cleanup() {
	rm -rf "$work_dir"
}
trap cleanup EXIT

fail() {
	echo "[ANDROID EXPORT] $*" >&2
	exit 1
}

require_file() {
	test -f "$1" || fail "Required file does not exist: $1"
}

require_executable() {
	test -x "$1" || fail "Required executable does not exist: $1"
}

require_file "$package_path"
require_executable "$godot_bin"
require_executable "$java_sdk_path/bin/java"
require_executable "$java_sdk_path/bin/keytool"
require_executable "$android_sdk_path/platform-tools/adb"

build_tools_version=$(find "$android_sdk_path/build-tools" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | LC_ALL=C sort | tail -1)
test -n "$build_tools_version" || fail "Android SDK does not contain build-tools."
build_tools_dir="$android_sdk_path/build-tools/$build_tools_version"
zipalign_bin="$build_tools_dir/zipalign"
apksigner_bin="$build_tools_dir/apksigner"
aapt_bin="$build_tools_dir/aapt"
require_executable "$zipalign_bin"
require_executable "$apksigner_bin"
require_executable "$aapt_bin"
java_env=(env JAVA_HOME="$java_sdk_path" PATH="$java_sdk_path/bin:$PATH")

python3 "$repository_root/scripts/verify_addon_package.py" "$package_path"
mkdir -p "$project_dir"
rsync -a "$repository_root/tests/package_install_project/" "$project_dir/"
unzip -q "$package_path" -d "$project_dir"
mkdir -p "$project_dir/addons/godot_framework_android_export_settings"
rsync -a "$repository_root/tests/fixtures/android_export_settings/" \
	"$project_dir/addons/godot_framework_android_export_settings/"
cp "$repository_root/tests/fixtures/android_export_settings/project.godot" "$project_dir/project.godot"

configure_env=(env NO_COLOR=1)
if [[ "$(uname -s)" == "Darwin" ]]; then
	original_home=${HOME:?HOME is required on macOS}
	test_home="$settings_dir/home"
	mkdir -p "$test_home/Library/Application Support/Godot"
	ln -s "$original_home/Library/Application Support/Godot/export_templates" \
		"$test_home/Library/Application Support/Godot/export_templates"
	configure_env+=(HOME="$test_home")
else
	configure_env+=(XDG_CONFIG_HOME="$settings_dir/config")
fi

"${configure_env[@]}" "$godot_bin" --headless --editor --path "$project_dir" \
	-- --java-sdk-path="$java_sdk_path" --android-sdk-path="$android_sdk_path" > "$work_dir/configure.log" 2>&1
grep -F "[ANDROID EXPORT] Editor settings configured." "$work_dir/configure.log"

if grep -E "SCRIPT ERROR|Parse Error|^ERROR:|ObjectDB instances leaked|instances were leaked|resources still in use" \
	"$work_dir/configure.log"; then
	exit 1
fi

cp "$repository_root/tests/package_install_project/project.godot" "$project_dir/project.godot"
rm -rf "$project_dir/addons/godot_framework_android_export_settings"

"${configure_env[@]}" "$godot_bin" --headless --editor --quit --path "$project_dir" > "$work_dir/editor.log" 2>&1
"${configure_env[@]}" "$godot_bin" --headless --path "$project_dir" --export-release Android "$unsigned_apk" > "$work_dir/export.log" 2>&1
require_file "$unsigned_apk"

if "${java_env[@]}" "$apksigner_bin" verify --verbose "$unsigned_apk" > "$work_dir/unsigned-signature.log" 2>&1; then
	fail "Godot produced a signed APK although package/signed=false."
fi

"$zipalign_bin" -f 4 "$unsigned_apk" "$aligned_apk"
test_password=$(openssl rand -hex 16)
"$java_sdk_path/bin/keytool" -genkeypair -noprompt -storetype JKS \
	-keystore "$keystore_path" -storepass "$test_password" -keypass "$test_password" \
	-alias godot-framework-test -dname "CN=Godot Framework Test" -keyalg RSA -keysize 2048 \
	-validity 1 > "$work_dir/keytool.log" 2>&1
mkdir -p "$(dirname "$output_apk")"
"${java_env[@]}" "$apksigner_bin" sign --ks "$keystore_path" --ks-key-alias godot-framework-test \
	--ks-pass "pass:$test_password" --key-pass "pass:$test_password" --out "$output_apk" "$aligned_apk"
"$zipalign_bin" -c -v 4 "$output_apk" > "$work_dir/zipalign.log" 2>&1
"${java_env[@]}" "$apksigner_bin" verify --verbose --print-certs "$output_apk" > "$work_dir/signature.log" 2>&1
grep -F "package: name='com.ryan3719.godotframeworktest'" <("$aapt_bin" dump badging "$output_apk")

abis=$(unzip -Z1 "$output_apk" | sed -n 's#^lib/\([^/]*\)/.*#\1#p' | sort -u)
test "$abis" = "x86_64" || fail "APK must contain only x86_64 native libraries; found: ${abis:-none}"

if grep -E "SCRIPT ERROR|Parse Error|^ERROR:|ObjectDB instances leaked|instances were leaked|resources still in use" \
	"$work_dir/editor.log" "$work_dir/export.log"; then
	exit 1
fi

echo "[ANDROID EXPORT] PASS: signed release APK built at $output_apk"
