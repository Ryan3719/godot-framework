# Research And Design Decisions

Research was performed against repository state available on 2026-08-12. Star counts are discovery signals, not architectural evidence.

## Sources

### Unity

- [GameFramework](https://github.com/EllanJiang/GameFramework): manager interfaces, independent components, explicit update/shutdown, event, FSM, pool, resource, scene, settings, localization, sound, network, download, and procedure modules.
- [UnityGameFramework](https://github.com/EllanJiang/UnityGameFramework): Unity integration layer for GameFramework.
- [QFramework](https://github.com/liangxiegame/QFramework): architecture container, model/system/utility boundaries, commands, queries, and events.

### Godot

- [Godot Engine 4.4.1 source](https://github.com/godotengine/godot/tree/4.4.1-stable): `ResourceLoader` user-token lifecycle, `SceneTree` scene replacement timing, and object-disabled Variant decoding in `FileAccess` were checked against the engine implementation rather than inferred from API names.
- [GodotGameFramework](https://github.com/nuoyanruoshui/GodotGameFramework): a C# adaptation of Unity GameFramework with Godot-specific resource loading and Luban-based tables.
- [Maaack's Game Template](https://github.com/Maaack/Godot-Game-Template): practical autoload-based scene loading, settings, audio, menu, and project-template integration.
- [GodotGame](https://github.com/chickensoft-games/GodotGame): a C# project template emphasizing dependency injection, state machines, testing, coverage, and continuous integration.
- [Comedot](https://github.com/InvadingOctopus/comedot): a reusable, component-oriented Godot project foundation.
- [Godot documentation](https://docs.godotengine.org/en/stable/tutorials/best_practices/scene_organization.html): scenes, loosely coupled nodes, and project organization guidance.

The Godot ecosystem has many domain frameworks and templates. It has fewer general-purpose, engine-wide frameworks than Unity. That distinction matters: a template assembles a starting application, while this repository targets reusable infrastructure that can be added to different applications.

## Adopted

| Source idea | Framework adaptation |
| --- | --- |
| GameFramework components | Dependency-aware `GFModule` lifecycle |
| GameFramework manager contracts | Services registered under stable IDs |
| QFramework command/query/event separation | `GFMessageBus` plus `GFEventBus` |
| QFramework architecture container | Small explicit service container, without reflection |
| Godot templates using autoloads | One host autoload instead of one global per subsystem |
| Godot Resource workflows | Typed framework and module configuration |
| Godot signals | Public asynchronous module events |

The resource module calls `load_threaded_get()` for every accepted threaded request, including during framework shutdown, because the engine retains a user load token until that result is collected. The scene module treats the caller scene as invalid immediately after a successful change request; the engine queues the old scene for deletion as part of `change_scene_to_packed()`. Storage uses `get_var(false)` so decoded data cannot instantiate serialized objects.

## Rejected Or Deferred

### Unity-style component wrappers

Godot already provides `Node`, `SceneTree`, signals, groups, Resources, threaded loading, and filesystem APIs. Wrapping all of them behind Unity-shaped interfaces would increase indirection and hide engine behavior. Modules expose policy and coordination, not replacement engine types.

### Procedure as a core module

UnityGameFramework's Procedure component is a finite-state machine used for application flow. The generic FSM belongs in the framework; concrete boot, login, lobby, battle, and result states belong to the game.

### Entity manager as a universal abstraction

Godot scenes already compose runtime entities. A universal entity manager would conflict with scene ownership for many game types. Projects can build entity, ECS, or actor modules on top of pools and services.

### Full IOC/reflection container

GDScript lacks C#'s compile-time interface guarantees and broad reflection-based injection would move errors to runtime. Stable IDs and explicit registration keep dependencies visible and work in exported builds.

### Asset hot update in v0.1

Godot resource loading is implemented. PCK delivery, signing, version manifests, CDN fallback, rollback, and platform export constraints form a separate release system and must not be implied by a cache wrapper. They are a later milestone.

### Networking protocol in core

TCP, WebSocket, ENet, HTTP, Steam, rollback, and authoritative multiplayer need different contracts. A future transport-agnostic module should be designed from concrete use cases; no fake universal API is included now.

### Generic UI framework in core

UI navigation, modal policy, transitions, input focus, safe areas, and screen history are useful but touch application presentation. They will be an optional module with project-provided views, never a core dependency.
