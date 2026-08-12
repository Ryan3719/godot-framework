# Performance And Budgets

## Runtime Budgets

The framework bounds cross-frame work where untrusted production rates could otherwise grow memory or monopolize a frame:

| Area | Budget |
| --- | --- |
| Queued events | `max_queued_events` total and `max_queued_events_per_frame` dispatches per frame |
| HTTP | active plus queued request count, queued body bytes, response bytes, and timeout |
| WebSocket | packets per frame, packet bytes, send high/low watermarks, and lifecycle timeouts |
| Threaded resources | `max_pending_threaded_requests` total and `max_threaded_requests_per_frame` polls per frame |
| Downloads | `max_in_flight_tasks`, active concurrency, retained terminal history, retry count, and streamed temporary files |
| Correlation tracking | `request_max_pending` unresolved request records |

Defaults are conservative starting points, not universal tuning values. Profile realistic project payloads and exported target platforms before changing them.

HTTP and download services retain terminal metadata so callers can inspect results after signals return. `http_max_finished_requests` and `max_finished_tasks` bound that history; once full, the oldest terminal records are evicted. Set either limit to zero when callers consume all results synchronously from signals. `clear_finished()` remains available for explicit earlier cleanup.

## Benchmark Runner

Run:

```bash
godot --headless --verbose --path . tests/performance_runner.tscn
```

The runner reports JSON for event publish, command/query dispatch, service resolution, request tracking, and a synthetic module dependency chain. The output is useful for comparing the same machine, Godot version, and build configuration over time.

CI uses only a 30-second-per-case catastrophic regression threshold and correctness checks. It deliberately does not enforce tight millisecond limits because shared runners, operating systems, debug builds, and engine versions are not comparable enough for an honest latency SLA. Allocation counts are not asserted because GDScript does not expose a stable allocation counter across the supported engine versions; bounded queue and byte limits provide the enforceable memory contracts instead.
