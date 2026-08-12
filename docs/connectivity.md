# Connectivity

## Service Shape

Enable the `connectivity` module in a project-owned `GFFrameworkConfig`, assign a project-owned `GFConnectivitySettings`, then resolve:

```gdscript
var connectivity := GodotFramework.get_service(GFServiceIds.CONNECTIVITY) as GFConnectivityService
```

The service exposes three separate capabilities:

- `http`: bounded request/response tasks through `GFHTTPService`
- `websockets`: named long-lived channels through `GFWebSocketService`
- `requests`: protocol-neutral correlation lifetimes through `GFRequestTracker`

They share one module lifecycle, but they do not pretend HTTP and WebSocket have the same semantics.

## HTTP

`GFHTTPService.request()` accepts an HTTP(S) URL, Godot `HTTPClient.Method`, raw headers, a raw byte body, an optional timeout, a tag, and optional `TLSOptions`. It returns a monotonic request ID or `0` when validation or queue admission fails.

The configured limits cover active concurrency, total in-flight request count, per-request body bytes, total waiting-body bytes, response body bytes, timeout, redirects, and threaded operation. A successful transport emits `request_completed` for every HTTP status code. The framework does not classify application statuses such as `404`, `409`, `429`, or `503`; project adapters own that policy.

Use `cancel(id)` for one request or `cancel_tag(tag)` for an owned group. Terminal task metadata remains available through `task_info()` until `clear_finished()` is called or the bounded `http_max_finished_requests` history evicts the oldest record. Response bytes are held in that metadata, so applications should clear finished tasks after consuming results instead of relying on automatic eviction.

## WebSocket

Each `GFWebSocketChannelDefinition` owns one endpoint and transport policy:

- handshake headers and subprotocols
- connect/close timeouts and optional auto-connect
- bounded exponential reconnect schedule
- native ping control-frame interval
- inbound/outbound buffer sizes and queued packet limit
- maximum application frame size and per-frame receive budget
- outbound high/low watermarks

`send()` and `send_text()` accept only raw application frames. When the next frame would exceed the high watermark, sending returns `ERR_BUSY` and emits `send_blocked`. The channel stays blocked until polling observes the low watermark and emits `channel_writable`. This hysteresis prevents callers from filling the engine buffer again immediately.

Unexpected disconnects can create a fresh backend according to reconnect policy. Frames are never automatically replayed. Reliable delivery requires an application protocol with sequence or correlation IDs, acknowledgements, idempotent operations, and an explicit retry policy.

A graceful close keeps polling for the peer close frame. If the configured close timeout expires, the service force-closes the peer so a channel cannot remain in `CLOSING` forever.

Godot 4.4 implements `heartbeat_interval` with WebSocket ping control frames on native platforms. Web exports ignore it because browser WebSocket APIs do not expose ping frames. Browser-compatible liveness checks therefore require an application-protocol heartbeat.

## Correlation

`GFRequestTracker` allocates monotonic IDs and owns resolve, timeout, and cancellation state. `request_max_pending` bounds unresolved records; `begin()` returns `0` when capacity is exhausted. It stores optional opaque context but does not create an envelope or send anything. Applications decide how a correlation ID is encoded in JSON, MessagePack, Protobuf, or another protocol.

A timeout of `0` means indefinite lifetime. Call `resolve(id, response)` when the application adapter receives a matching response, or `cancel(id)` when the owner ends. Shutdown cancels all remaining tracked requests.

## Explicit Boundaries

The module does not provide authentication flows, token refresh, JSON mapping, RPC method names, generated message types, matchmaking, rollback networking, authoritative simulation, offline queues, packet encryption above TLS, reliable WebSocket replay, or an ENet abstraction. Those contracts differ by application and transport and should be implemented as optional adapters outside the framework kernel.
