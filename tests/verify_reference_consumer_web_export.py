#!/usr/bin/env python3

import argparse
import pathlib
import shutil
import subprocess
import sys
import tempfile
import zipfile

from verify_web_export import (
    find_chromedriver,
    run_browser,
    run_logged,
    scan_log,
)


PASS_TITLE = "GF_REFERENCE_CONSUMER_EXPORT_PASS"
FAIL_TITLE = "GF_REFERENCE_CONSUMER_EXPORT_FAIL"
PASS_LOG_MARKER = (
    "[REFERENCE CONSUMER EXPORT] PASS: project integration paths succeeded in release export"
)


def verify(package_path, godot_bin, chromedriver, timeout_seconds):
    repository_root = pathlib.Path(__file__).resolve().parents[1]
    fixture = repository_root / "examples" / "reference_consumer"
    package_verifier = repository_root / "scripts" / "verify_addon_package.py"
    verification = subprocess.run(
        [sys.executable, str(package_verifier), str(package_path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    if verification.returncode != 0:
        raise RuntimeError(f"addon package verification failed:\n{verification.stdout}")

    with tempfile.TemporaryDirectory(prefix="godot-framework-reference-web-export-") as temp_dir:
        work_dir = pathlib.Path(temp_dir)
        project_dir = work_dir / "project"
        export_dir = work_dir / "build"
        shutil.copytree(fixture, project_dir)
        export_dir.mkdir()
        with zipfile.ZipFile(package_path, "r") as archive:
            archive.extractall(project_dir)
        (project_dir / "project.godot.template").rename(project_dir / "project.godot")

        editor_log = work_dir / "editor.log"
        export_log = work_dir / "export.log"
        run_logged(
            [godot_bin, "--headless", "--editor", "--quit", "--path", str(project_dir)],
            editor_log,
        )
        run_logged(
            [
                godot_bin,
                "--headless",
                "--path",
                str(project_dir),
                "--export-release",
                "Web",
                str(export_dir / "index.html"),
            ],
            export_log,
        )
        for required_path in ("index.html", "index.js", "index.wasm", "index.pck"):
            if not (export_dir / required_path).is_file():
                raise RuntimeError(f"Web export did not create {required_path}")
        scan_log(editor_log)
        scan_log(export_log)
        run_browser(
            export_dir,
            chromedriver,
            timeout_seconds,
            work_dir,
            pass_title=PASS_TITLE,
            fail_title=FAIL_TITLE,
            pass_log_marker=PASS_LOG_MARKER,
        )


def main():
    parser = argparse.ArgumentParser(
        description="Export the package-installed reference consumer for Web and execute it in headless Chrome."
    )
    parser.add_argument("package", type=pathlib.Path)
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--chromedriver")
    parser.add_argument("--timeout-seconds", type=float, default=45.0)
    args = parser.parse_args()
    package_path = args.package.resolve()
    if not package_path.is_file():
        raise RuntimeError(f"addon package does not exist: {package_path}")
    chromedriver = find_chromedriver(args.chromedriver)
    verify(package_path, args.godot, chromedriver, args.timeout_seconds)
    print("[REFERENCE CONSUMER EXPORT] PASS: project integration paths succeeded in Web release export")


if __name__ == "__main__":
    main()
