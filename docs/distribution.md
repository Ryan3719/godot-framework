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
```

The builder sorts paths and normalizes timestamps, permissions, and compression so identical source bytes produce an identical ZIP and SHA-256 checksum. The installation test extracts the package into a temporary clean project, lets the editor import it, and verifies the six enabled foundation modules plus all disabled optional modules. The Linux export test then uses the same clean project and the matching official release template, executes the exported binary, verifies the same runtime boundary outside the editor, and confirms the EditorPlugin, validation dock, and plugin metadata were excluded from the release PCK.

Generated `dist/` output is not source and should not be committed.

## Release Tags

The release workflow accepts tags matching `v*`, then enforces an exact match with `plugin.cfg` and rejects `-dev` versions. A maintainer release therefore requires:

1. Change `plugin.cfg` from a development version such as `0.5.0-dev` to `0.5.0`.
2. Update the changelog and run the full test matrix.
3. Commit the release state and create tag `v0.5.0` on that commit.
4. Push the tag. GitHub Actions rebuilds, verifies, installs, and attaches the ZIP and checksum to the release.

Do not create a release tag from a dirty worktree or hand-edit the generated ZIP.
