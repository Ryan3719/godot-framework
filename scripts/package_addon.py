#!/usr/bin/env python3

import argparse
import hashlib
import pathlib
import re
import zipfile


ROOT = pathlib.Path(__file__).resolve().parents[1]
ADDON_ROOT = ROOT / "addons" / "godot_framework"
PLUGIN_CONFIG = ADDON_ROOT / "plugin.cfg"
FIXED_TIMESTAMP = (1980, 1, 1, 0, 0, 0)


def addon_version():
    text = PLUGIN_CONFIG.read_text(encoding="utf-8")
    match = re.search(r'^version="([^"]+)"$', text, re.MULTILINE)
    if match is None:
        raise RuntimeError("plugin.cfg does not declare a version")
    return match.group(1)


def source_entries():
    entries = []
    for path in ADDON_ROOT.rglob("*"):
        if path.is_symlink():
            raise RuntimeError(f"addon source contains a symbolic link: {path}")
        if not path.is_file():
            continue
        if path.name == ".DS_Store" or "__pycache__" in path.parts or path.suffix == ".pyc":
            raise RuntimeError(f"addon source contains a generated file: {path}")
        archive_path = path.relative_to(ROOT).as_posix()
        if archive_path == "addons/godot_framework/LICENSE":
            continue
        entries.append((archive_path, path.read_bytes()))
    entries.append(("addons/godot_framework/LICENSE", (ROOT / "LICENSE").read_bytes()))
    return sorted(entries, key=lambda entry: entry[0])


def write_package(output_path):
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output_path, "w", compression=zipfile.ZIP_STORED) as archive:
        for archive_path, data in source_entries():
            info = zipfile.ZipInfo(archive_path, FIXED_TIMESTAMP)
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            info.compress_type = zipfile.ZIP_STORED
            archive.writestr(info, data)
    digest = hashlib.sha256(output_path.read_bytes()).hexdigest()
    checksum_path = output_path.with_suffix(output_path.suffix + ".sha256")
    checksum_path.write_text(f"{digest}  {output_path.name}\n", encoding="ascii")
    return digest, checksum_path


def main():
    parser = argparse.ArgumentParser(description="Build a deterministic Godot Framework addon ZIP.")
    parser.add_argument("--output", type=pathlib.Path)
    args = parser.parse_args()
    version = addon_version()
    output = (args.output or ROOT / "dist" / f"godot-framework-{version}.zip").resolve()
    if output == ADDON_ROOT or ADDON_ROOT in output.parents:
        raise RuntimeError("package output must be outside the addon source directory")
    digest, checksum = write_package(output)
    print(f"version={version}")
    print(f"package={output.resolve()}")
    print(f"sha256={digest}")
    print(f"checksum={checksum}")


if __name__ == "__main__":
    main()
