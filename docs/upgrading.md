# Upgrading

## General Procedure

1. Read [CHANGELOG.md](../CHANGELOG.md) for behavior and API changes between the pinned and target versions.
2. Keep the project's `GFFrameworkConfig` and module settings outside `addons/godot_framework`.
3. Replace the complete `addons/godot_framework` directory with the target release package. Do not merge individual addon files across versions.
4. Open the project in the minimum supported Godot version and let the editor import scripts and resources.
5. Run the configuration validator and the project's own headless tests before shipping.

```bash
godot --headless --editor --quit --path .
godot --headless --verbose --path . tests/config_validation_runner.tscn
```

The repository's validation scene is a development aid. A consuming project may copy its small runner or invoke `GFFrameworkValidator.validate_path()` from its own test harness.

## Upgrading To 0.5 Development

Every project-owned `GFModuleDefinition` must now set `declared_id` and `declared_dependencies`. These values must exactly match the module's `module_id()` and `dependencies()` results. Set `expected_settings_class` when the module uses a typed settings resource.

`GFEventBus.queue()` now returns `Error`. Existing calls that ignore the result continue to enqueue while capacity is available. Code that cannot tolerate a dropped queued event must handle `ERR_OUT_OF_MEMORY` and choose an application policy such as retry, backpressure, or durable storage.

Review `GFFrameworkConfig.max_queued_events` after upgrading. Its default is `8192`, while `max_queued_events_per_frame` remains the independent per-frame dispatch budget.

The 0.5 development defaults also bound pending threaded resource requests, in-flight downloads, retained HTTP/download terminal metadata, and unresolved correlation requests. Projects that previously accumulated unbounded work should handle the existing rejection sentinels (`ERR_OUT_OF_MEMORY` or ID `0`) and consume terminal metadata before automatic oldest-first eviction.
