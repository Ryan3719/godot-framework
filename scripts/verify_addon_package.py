#!/usr/bin/env python3

import argparse
import pathlib
import stat
import zipfile


PREFIX = "addons/godot_framework/"
REQUIRED = {
    PREFIX + "LICENSE",
    PREFIX + "plugin.cfg",
    PREFIX + "plugin.gd",
    PREFIX + "runtime/framework_host.gd",
    PREFIX + "config/default_framework_config.tres",
}
FIXED_TIMESTAMP = (1980, 1, 1, 0, 0, 0)


def verify(path):
    with zipfile.ZipFile(path, "r") as archive:
        infos = archive.infolist()
        names = [info.filename for info in infos]
        if names != sorted(names):
            raise RuntimeError("archive entries are not sorted")
        if len(names) != len(set(names)):
            raise RuntimeError("archive contains duplicate paths")
        if not REQUIRED.issubset(names):
            missing = sorted(REQUIRED.difference(names))
            raise RuntimeError(f"archive is missing required files: {missing}")
        for info in infos:
            if not info.filename.startswith(PREFIX):
                raise RuntimeError(f"archive path escapes addon root: {info.filename}")
            if "\\" in info.filename:
                raise RuntimeError(f"archive path uses a platform-dependent separator: {info.filename}")
            parts = pathlib.PurePosixPath(info.filename).parts
            if ".." in parts or info.filename.startswith("/"):
                raise RuntimeError(f"archive path is unsafe: {info.filename}")
            if info.is_dir():
                raise RuntimeError(f"archive contains an unnecessary directory entry: {info.filename}")
            if info.date_time != FIXED_TIMESTAMP:
                raise RuntimeError(f"archive timestamp is not deterministic: {info.filename}")
            if info.compress_type != zipfile.ZIP_STORED:
                raise RuntimeError(f"archive compression is not deterministic: {info.filename}")
            mode = info.external_attr >> 16
            if stat.S_IFMT(mode) != stat.S_IFREG:
                raise RuntimeError(f"archive entry is not a regular file: {info.filename}")
            if mode & 0o777 != 0o644:
                raise RuntimeError(f"archive permissions are not normalized: {info.filename}")


def main():
    parser = argparse.ArgumentParser(description="Verify a Godot Framework addon ZIP.")
    parser.add_argument("package", type=pathlib.Path)
    args = parser.parse_args()
    verify(args.package.resolve())
    print(f"[PACKAGE TEST] PASS: {args.package.resolve()}")


if __name__ == "__main__":
    main()
