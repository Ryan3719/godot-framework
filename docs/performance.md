# Performance And Budgets

## Runtime Budgets

The framework bounds cross-frame work where untrusted production rates could otherwise grow memory or monopolize a frame:

| Area | Budget |
| --- | --- |
| Queued events | `max_queued_events` total and `max_queued_events_per_frame` dispatches per frame |
| HTTP | active plus queued request count, queued body bytes, response bytes, and timeout |
| WebSocket | packets per frame, packet bytes, send high/low watermarks, and lifecycle timeouts |
| Downloads | active concurrency, retry count, and streamed temporary files |

Defaults are conservative starting points, not universal tuning values. Profile realistic project payloads and exported target platforms before changing them.

## Benchmark Runner

Run:

```bash
godot --headless --verbose --path . tests/performance_runner.tscn
```

The runner reports JSON for event publish, command/query dispatch, service resolution, request tracking, and a synthetic module dependency chain. The output is useful for comparing the same machine, Godot version, and build configuration over time.

CI uses only a 30-second-per-case catastrophic regression threshold and correctness checks. It deliberately does not enforce tight millisecond limits because shared runners, operating systems, debug builds, and engine versions are not comparable enough for an honest latency SLA. Allocation counts are not asserted because GDScript does not expose a stable allocation counter across the supported engine versions; bounded queue and byte limits provide the enforceable memory contracts instead.
