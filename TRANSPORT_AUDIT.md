# Transport Layer Audit

Date: 2026-03-08

## Problem Statement

The one-shot WebSocket path (`bun ws_send.ts <command>`) is unreliable against a live Godot editor. Connections frequently fail with `close code 1006` before the WebSocket handshake completes. Longer-lived connection paths (`--batch`, `--listen`, broker) work reliably.

## Diagnosis (Partial)

One contributing factor was identified: the plugin's `godot_claude.gd._process()` was manually calling `_ws.poll()` and `_bridge_server.poll()` on every frame. This created a bottleneck:

1. The plugin's `_process` also checked game state for event bus notifications
2. Any delay in `_process` (editor rendering, imports, other frame work) delayed WebSocket polling
3. The WebSocket handshake requires multiple `poll()` calls to advance through TCP accept → WS upgrade → STATE_OPEN
4. Short-lived one-shot clients would time out before the handshake completed if poll frequency dropped

The fix (committed in `49b8ee7`) moved polling into each server's own `_process()`:
- `ws_server.gd` now has its own `_process()` → `poll()`
- `bridge_server.gd` now has its own `_process()` → `poll()`
- Both use `set_process(true/false)` gated on start/stop

This ensures WebSocket state machine advancement happens independently of the main plugin's frame work.

## Remaining Gap

**The self-polling refactor improved the situation but did not fully resolve one-shot failures.**

Live verification after the fix showed:
- Sequential one-shot: **10/10 FAILED** (close code 1006)
- Batch mode: **PASSED**
- Listen mode: **PASSED**

The root cause of one-shot unreliability is not fully understood. Possible factors still under investigation:
1. Bun process lifecycle — the client may exit before the server processes the response
2. Godot's WebSocket server implementation — may not handle rapid connect/send/disconnect gracefully
3. Editor main thread contention — even with self-polling, `_process` is still tied to the editor frame rate
4. TCP socket reuse / TIME_WAIT — rapid reconnections to the same port may hit OS-level socket state issues

## Architecture Decision

**Batch (`--batch`) is the recommended transport mode for programmatic use.**

This is the correct choice because:
1. Batch opens one persistent WebSocket connection, sends all commands, then closes — the handshake happens once
2. Batch is 100% reliable in all testing
3. Claude can use batch via stdin JSONL in a single `Bash` invocation
4. Even single commands can be sent via batch (just one JSONL line)

Single one-shot remains available as a **best-effort** convenience path, with conservative retry settings (10 retries, 500ms delay) to maximize its chances. It is not guaranteed to succeed.

## Transport Mode Status

| Mode | Status | Use case |
|------|--------|----------|
| **Batch** | Recommended | Multiple commands in one connection (`--batch` via stdin JSONL) |
| **Single** | Best-effort | One command per process (`bun ws_send.ts <cmd> '<params>'`) |
| **Listen** | Supported | Interactive human sessions (`--listen`) |
| **Broker** | Optional | Persistent connection proxy (`GODOT_USE_BROKER=1`) |

## Changes Made

### Plugin (`49b8ee7`)
- `ws_server.gd` and `bridge_server.gd` self-poll via their own `_process()`
- `godot_claude.gd` no longer calls `_ws.poll()` or `_bridge_server.poll()` manually

### Client (`skill/ws_send.ts`)
- Version bumped to 1.2.0
- Retry defaults: 10 retries, 500ms delay (conservative, matching pre-audit values)
- Simplified trace event names (removed `single_` prefix)
- Removed unused `traceLabel`/`traceMeta` parameters from batch internals
- Cleaner usage help output with version
- Extracted `outputResponse()` helper to deduplicate compact/JSON output logic
- Header documentation updated: batch = recommended, single = best-effort

### Documentation
- `README.md`: Transport Modes table updated (batch = Recommended, single = Best-effort)
- `.claude/commands/godot.md`: Workflow tips updated to recommend batch for programmatic use

## What Is NOT Supported

- Auto-starting the broker from `ws_send.ts` — the broker must be started manually if used
- Silent fallback between transport modes — if broker mode is requested and the broker isn't running, an explicit error is returned
- Connection pooling or keep-alive across process invocations — each one-shot opens and closes cleanly

## Residual Risks

1. **One-shot reliability**: The single one-shot path fails frequently. Until the root cause is fully diagnosed, batch should be used for all programmatic workflows.

2. **Editor under extreme load**: If the Godot editor is completely blocked (e.g., importing a very large asset, shader compilation), all transport paths will be affected. The 30s timeout handles this.

3. **MAX_CONNECTIONS (32)**: If more than 32 simultaneous WebSocket connections are attempted, excess connections will be rejected by the server.

## Performance Characteristics

| Scenario | Latency |
|----------|---------|
| Batch (10 commands, one connection) | ~1.1s total (~110ms/cmd) |
| Single one-shot command (when it works) | ~200ms |
