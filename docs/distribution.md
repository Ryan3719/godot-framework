# Distribution

## Package Layout

The distributable ZIP contains only `addons/godot_framework/**`, including a copy of the MIT license. It can be extracted at a Godot project root and enabled through **Project > Project Settings > Plugins**. No test scene, repository workflow, or project-level setting is included in the archive.

This layout is compatible with Godot Asset Library addon packages. Compatibility does not mean the package has already been submitted or approved in the Asset Library.

## Build And Verify

```bash
python3 scripts/package_addon.py
python3 scripts/verify_addon_package.py dist/godot-framework-0.5.0-dev.zip
bash tests/verify_addon_package.sh dist/godot-framework-0.5.0-dev.zip "$(command -v godot)"
bash tests/verify_linux_export.sh dist/godot-framework-0.5.0-dev.zip "$(command -v godot)"
bash tests/verify_macos_export.sh dist/godot-framework-0.5.0-dev.zip "$(command -v godot)"
python3 tests/verify_web_export.py dist/godot-framework-0.5.0-dev.zip --godot "$(command -v godot)"
```

On Windows, run the corresponding PowerShell verifier:

```powershell
./tests/verify_windows_export.ps1 -PackagePath dist/godot-framework-0.5.0-dev.zip -GodotBin (Get-Command godot).Source
```

The builder sorts paths and normalizes timestamps, permissions, and compression. The repository enforces LF checkout bytes through `.gitattributes`, and CI compares SHA-256 checksums from Linux, macOS, and Windows package builds on both supported Godot versions. The installation test extracts the package into a temporary clean project, lets the editor import it, and verifies the six enabled foundation modules plus all disabled optional modules. Release export tests then use the same clean project and matching official templates, execute the exported ELF, app bundle, Windows console wrapper, single-threaded Web build in headless Chrome, or Android APK on an API 35 x86_64 emulator, verify the same runtime boundary outside the editor, and confirm the EditorPlugin, validation dock, and plugin metadata were excluded. Export output is written outside the project so `all_resources` cannot ingest a partially generated artifact.

The Web verifier requires ChromeDriver, accepts `--chromedriver`, and also checks `CHROMEWEBDRIVER` plus the current `PATH`. It serves the exported files only on loopback, requires both the exported runtime pass marker and a browser-visible completion title, and rejects browser console errors.

The Windows test fixture disables PE resource editing because it does not ship application metadata and should not depend on the external `rcedit` tool. Production projects that modify icons or version resources must configure and validate their own Windows export toolchain.

The macOS CI artifact uses Godot's ad-hoc signing mode. This validates bundle creation and execution on the hosted runner; it does not validate Developer ID signing, notarization, entitlements, or Mac App Store submission.

Android CI exports an unsigned APK, verifies that state, aligns it, signs it with an ephemeral test JKS, verifies the package name, signature, and x86_64 ABI, then installs, starts, and removes it on an API 35 emulator. The test uses the supported `swangle` software graphics mode because the emulator's deprecated indirect graphics modes do not provide a reliable Godot Compatibility renderer. This is execution evidence for the default six-module runtime boundary only, not a production signing workflow.

These export checks validate packaging and the default runtime modules. Optional content-delivery and connectivity modules still require platform-specific exported integration in a consuming project. Threaded Web, optional-module mobile integration, AAB generation, Play publishing, production Android signing, and iOS exports are not covered.

Generated `dist/` output is not source and should not be committed.

## Release Tags

The release workflow accepts tags matching `v*`, then enforces an exact match with `plugin.cfg` and rejects `-dev` versions. A maintainer release therefore requires:

1. Change `plugin.cfg` from a development version such as `0.5.0-dev` to `0.5.0`.
2. Update the changelog and run the full test matrix.
3. Commit the release state and create tag `v0.5.0` on that commit.
4. Push the tag. GitHub Actions rebuilds, verifies, installs, and attaches the ZIP and checksum to the release.

Do not create a release tag from a dirty worktree or hand-edit the generated ZIP.
