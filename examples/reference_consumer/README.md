# Reference Consumer

This is a small Godot project that consumes the addon without adding gameplay or application-domain rules to it. It owns the framework configuration, persistent paths, input setup, localized messages, and a concrete `GFUIView` scene.

The project enables the resource, scene, storage, settings, pool, state-machine, UI, input, and localization modules. It intentionally does not configure download, content, tables, audio, or connectivity because those capabilities need project-specific assets, backends, or protocols.

To run this checkout directly, copy `addons/godot_framework` into this directory, then rename `project.godot.template` to `project.godot`. The repository verifier performs those steps from a deterministic addon ZIP, so it also proves clean-package installation:

```bash
python3 scripts/package_addon.py
bash tests/verify_reference_consumer.sh dist/godot-framework-0.5.0-dev.zip "$(command -v godot)"
```

When launched interactively, the project opens its configured route. In an automated run it verifies resource ownership, settings persistence, recoverable storage, input profile round-trip, owned translations, UI route lifecycle, configuration validation, and framework shutdown.
