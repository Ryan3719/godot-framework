#!/usr/bin/env python3

import argparse
import pathlib
import re
import subprocess
import sys
import time


PACKAGE_NAME = "com.ryan3719.godotframeworktest"
PASS_MARKER = "[EXPORT TEST] PASS: packaged addon starts and stops all modules in release export"
FAILURE_PATTERN = re.compile(
    r"SCRIPT ERROR|Parse Error|(?:^|\s)ERROR:|ObjectDB instances leaked|"
    r"instances were leaked|resources still in use|FATAL EXCEPTION|Fatal signal",
    re.IGNORECASE | re.MULTILINE,
)


def command(*args, check=True):
    result = subprocess.run(args, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if check and result.returncode != 0:
        raise RuntimeError("Command failed (%d): %s\n%s" % (result.returncode, " ".join(args), result.stdout))
    return result


def read_logcat(adb):
    godot = command(adb, "logcat", "-d", "-v", "brief", "-s", "godot", check=False).stdout
    android_runtime = command(adb, "logcat", "-d", "-v", "brief", "-s", "AndroidRuntime", check=False).stdout
    crash = command(adb, "logcat", "-d", "-v", "brief", "-b", "crash", check=False).stdout
    return godot + "\n" + android_runtime + "\n" + crash


def package_is_installed(adb):
    result = command(adb, "shell", "pm", "path", PACKAGE_NAME, check=False)
    return result.returncode == 0 and "package:" in result.stdout


def main():
    parser = argparse.ArgumentParser(description="Run the Android release-export fixture on an already booted emulator.")
    parser.add_argument("apk", type=pathlib.Path)
    parser.add_argument("--adb", default="adb")
    parser.add_argument("--timeout-seconds", type=float, default=60.0)
    args = parser.parse_args()

    apk = args.apk.resolve()
    if not apk.is_file() or apk.suffix.lower() != ".apk":
        raise RuntimeError("APK does not exist: %s" % apk)
    if args.timeout_seconds <= 0:
        raise RuntimeError("Timeout must be positive.")

    installed = False
    try:
        command(args.adb, "wait-for-device")
        if package_is_installed(args.adb):
            raise RuntimeError("Refusing to overwrite an existing test package: %s" % PACKAGE_NAME)
        command(args.adb, "logcat", "-c")
        command(args.adb, "install", str(apk))
        installed = True
        command(
            args.adb,
            "shell",
            "monkey",
            "-p",
            PACKAGE_NAME,
            "-c",
            "android.intent.category.LAUNCHER",
            "1",
        )

        deadline = time.monotonic() + args.timeout_seconds
        logcat = ""
        while time.monotonic() < deadline:
            logcat = read_logcat(args.adb)
            failure = FAILURE_PATTERN.search(logcat)
            if failure:
                raise RuntimeError("Android runtime reported an error:\n%s" % logcat)
            if PASS_MARKER in logcat:
                print("[ANDROID EXPORT TEST] PASS: signed release APK ran on the emulator")
                return
            time.sleep(0.5)
        raise RuntimeError("Timed out waiting for the exported runtime pass marker:\n%s" % logcat)
    finally:
        if installed:
            command(args.adb, "uninstall", PACKAGE_NAME)


if __name__ == "__main__":
    try:
        main()
    except RuntimeError as error:
        print("[ANDROID EXPORT TEST] %s" % error, file=sys.stderr)
        sys.exit(1)
