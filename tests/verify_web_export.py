#!/usr/bin/env python3

import argparse
import contextlib
import functools
import http.server
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
import zipfile


FAILURE_PATTERN = re.compile(
    r"SCRIPT ERROR|Parse Error|^ERROR:|ObjectDB instances leaked|"
    r"instances were leaked|resources still in use",
    re.MULTILINE,
)
PASS_TITLE = "GF_EXPORT_TEST_PASS"
FAIL_TITLE = "GF_EXPORT_TEST_FAIL"
PASS_LOG_MARKER = "[EXPORT TEST] PASS: packaged addon runs in release export"
DIRECT_URL_OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/favicon.ico":
            self.send_response(http.HTTPStatus.NO_CONTENT)
            self.end_headers()
            return
        super().do_GET()

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, _format, *_args):
        pass


def run_logged(command, log_path, cwd=None):
    result = subprocess.run(
        command,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    log_path.write_text(result.stdout, encoding="utf-8")
    if result.returncode != 0:
        raise RuntimeError(
            f"command failed with exit code {result.returncode}: {command[0]}\n"
            f"{result.stdout}"
        )


def scan_log(path):
    content = path.read_text(encoding="utf-8", errors="replace")
    match = FAILURE_PATTERN.search(content)
    if match is not None:
        raise RuntimeError(f"framework error or leak marker found in {path}: {match.group(0)}")


def find_chromedriver(explicit_path):
    candidates = []
    if explicit_path:
        candidates.append(pathlib.Path(explicit_path))
    environment_path = os.environ.get("CHROMEWEBDRIVER", "")
    if environment_path:
        environment_candidate = pathlib.Path(environment_path)
        candidates.append(
            environment_candidate / "chromedriver"
            if environment_candidate.is_dir()
            else environment_candidate
        )
    discovered = shutil.which("chromedriver")
    if discovered:
        candidates.append(pathlib.Path(discovered))
    candidates.append(pathlib.Path("/usr/local/share/chromedriver-linux64/chromedriver"))
    for candidate in candidates:
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return candidate.resolve()
    raise RuntimeError("ChromeDriver was not found; pass --chromedriver or set CHROMEWEBDRIVER")


def webdriver_request(base_url, method, path, payload=None, timeout=10):
    data = None
    headers = {}
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json; charset=utf-8"
    request = urllib.request.Request(
        base_url + path,
        data=data,
        headers=headers,
        method=method,
    )
    try:
        with DIRECT_URL_OPENER.open(request, timeout=timeout) as response:
            body = response.read()
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"WebDriver {method} {path} failed: {body}") from error
    return json.loads(body) if body else {}


def wait_for_webdriver(log_path, process, timeout_seconds):
    deadline = time.monotonic() + timeout_seconds
    last_error = None
    base_url = ""
    while time.monotonic() < deadline:
        if process.poll() is not None:
            log = log_path.read_text(encoding="utf-8", errors="replace")
            raise RuntimeError(
                f"ChromeDriver exited before becoming ready: {process.returncode}\n{log}"
            )
        log = log_path.read_text(encoding="utf-8", errors="replace")
        match = re.search(r"started successfully on port (\d+)", log)
        if match is not None:
            base_url = f"http://127.0.0.1:{match.group(1)}"
            try:
                status = webdriver_request(base_url, "GET", "/status", timeout=1)
                if status.get("value", {}).get("ready", False):
                    return base_url
            except (OSError, RuntimeError, json.JSONDecodeError) as error:
                last_error = error
        time.sleep(0.1)
    log = log_path.read_text(encoding="utf-8", errors="replace")
    raise RuntimeError(f"ChromeDriver did not become ready: {last_error}\n{log}")


def create_session(base_url):
    response = webdriver_request(
        base_url,
        "POST",
        "/session",
        {
            "capabilities": {
                "alwaysMatch": {
                    "browserName": "chrome",
                    "goog:chromeOptions": {
                        "args": [
                            "--headless=new",
                            "--disable-dev-shm-usage",
                            "--enable-unsafe-swiftshader",
                            "--no-sandbox",
                            "--window-size=1280,720",
                        ]
                    },
                    "goog:loggingPrefs": {"browser": "ALL"},
                }
            }
        },
        timeout=30,
    )
    session_id = response.get("value", {}).get("sessionId") or response.get("sessionId")
    if not session_id:
        raise RuntimeError(f"ChromeDriver did not return a session ID: {response}")
    return session_id


def read_web_result(base_url, session_id):
    response = webdriver_request(
        base_url,
        "POST",
        f"/session/{session_id}/execute/sync",
        {
            "script": "return document.title || null;",
            "args": [],
        },
    )
    return response.get("value")


def read_browser_log(base_url, session_id):
    response = webdriver_request(
        base_url,
        "POST",
        f"/session/{session_id}/se/log",
        {"type": "browser"},
    )
    entries = response.get("value", [])
    return entries if isinstance(entries, list) else []


def validate_browser_log(entries, log_path, require_pass_marker=False):
    lines = []
    severe = []
    for entry in entries:
        level = str(entry.get("level", "UNKNOWN"))
        message = str(entry.get("message", ""))
        line = f"[{level}] {message}"
        lines.append(line)
        if level == "SEVERE" or FAILURE_PATTERN.search(message):
            severe.append(line)
    log_path.write_text("\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")
    if severe:
        raise RuntimeError("browser reported errors:\n" + "\n".join(severe))
    if require_pass_marker and not any(PASS_LOG_MARKER in line for line in lines):
        raise RuntimeError("browser log did not contain the exported runtime pass marker")


def run_browser(export_dir, chromedriver, timeout_seconds, work_dir):
    handler = functools.partial(QuietHandler, directory=str(export_dir))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    server_thread = threading.Thread(target=server.serve_forever, daemon=True)
    server_thread.start()

    driver_log_path = work_dir / "chromedriver.log"
    browser_log_path = work_dir / "browser.log"
    session_id = None
    driver_url = ""
    process = None
    try:
        with driver_log_path.open("w", encoding="utf-8") as driver_log:
            process = subprocess.Popen(
                [str(chromedriver), "--port=0"],
                stdout=driver_log,
                stderr=subprocess.STDOUT,
                text=True,
            )
            driver_url = wait_for_webdriver(driver_log_path, process, 15)
            session_id = create_session(driver_url)
            page_url = f"http://127.0.0.1:{server.server_port}/index.html"
            webdriver_request(
                driver_url,
                "POST",
                f"/session/{session_id}/url",
                {"url": page_url},
                timeout=30,
            )
            deadline = time.monotonic() + timeout_seconds
            result = None
            while time.monotonic() < deadline:
                result = read_web_result(driver_url, session_id)
                if result == PASS_TITLE:
                    break
                if result == FAIL_TITLE:
                    entries = read_browser_log(driver_url, session_id)
                    validate_browser_log(entries, browser_log_path)
                    browser_log = browser_log_path.read_text(
                        encoding="utf-8", errors="replace"
                    )
                    raise RuntimeError(
                        "exported Web runtime reported a failed contract\n" + browser_log
                    )
                time.sleep(0.1)
            else:
                entries = read_browser_log(driver_url, session_id)
                validate_browser_log(entries, browser_log_path)
                browser_log = browser_log_path.read_text(encoding="utf-8", errors="replace")
                raise RuntimeError(
                    f"timed out waiting for exported Web runtime: {result!r}\n{browser_log}"
                )
            time.sleep(0.1)
            validate_browser_log(
                read_browser_log(driver_url, session_id),
                browser_log_path,
                require_pass_marker=True,
            )
    except Exception as error:
        diagnostics = ""
        if driver_log_path.is_file():
            diagnostics = driver_log_path.read_text(encoding="utf-8", errors="replace")
        if browser_log_path.is_file():
            diagnostics += "\n" + browser_log_path.read_text(
                encoding="utf-8", errors="replace"
            )
        raise RuntimeError(f"{error}\n{diagnostics}") from error
    finally:
        if session_id is not None and driver_url:
            with contextlib.suppress(Exception):
                webdriver_request(driver_url, "DELETE", f"/session/{session_id}")
        if process is not None:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=10)
        server.shutdown()
        server.server_close()
        server_thread.join(timeout=10)
    if process is not None and process.returncode not in (0, -15):
        driver_log = driver_log_path.read_text(encoding="utf-8", errors="replace")
        raise RuntimeError(f"ChromeDriver exited with code {process.returncode}:\n{driver_log}")


def verify(package_path, godot_bin, chromedriver, timeout_seconds):
    repository_root = pathlib.Path(__file__).resolve().parents[1]
    fixture = repository_root / "tests" / "package_install_project"
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
    with tempfile.TemporaryDirectory(prefix="godot-framework-web-export-") as temp_dir:
        work_dir = pathlib.Path(temp_dir)
        project_dir = work_dir / "project"
        export_dir = work_dir / "build"
        shutil.copytree(fixture, project_dir)
        export_dir.mkdir()
        with zipfile.ZipFile(package_path, "r") as archive:
            archive.extractall(project_dir)

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
        run_browser(export_dir, chromedriver, timeout_seconds, work_dir)


def main():
    parser = argparse.ArgumentParser(
        description="Export the packaged addon for Web and execute it in headless Chrome."
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
    print("[EXPORT TEST] PASS: packaged addon runs in Web release export")


if __name__ == "__main__":
    main()
