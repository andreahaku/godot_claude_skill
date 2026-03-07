# Final E2E Audit

Date: 2026-03-07
Target project: `/Users/niccolo/Development/Godot/pacman-test-claude-skill/pacman-test-claude-skill`
Plugin version tested: `1.1.0`
Godot version: `4.6.1`

## Status

Core runtime/testing coverage is in good shape.

Latest verification completed:

- `validate_spritesheet` now respects `columns` and `frame_count`
- `export_project` now returns `NO_PRESETS` when no export presets are configured
- a real `export_presets.cfg` was added to the Pacman test project and the export CLI path completed successfully
- the exported Linux artifact was produced successfully at `/tmp/pacman-test.x86_64`
- shader workflow was covered end-to-end on `Player/Sprite`
- provider-side audio generation completed successfully for:
  - `list_voices`
  - `voice_line`
  - `sfx` (MP3 path)
- SFX format handling now saves the real file type and reports:
  - `asset_path` (authoritative path)
  - `requested_asset_path` (original request, if different)
  - `format`
  - `mime_type`
- Godot-side integration completed for generated audio assets:
  - import
  - manifest inspection
  - bus creation
  - player creation
  - attach stream
- immediate `generate -> import_audio_asset` retry path was verified live:
  - fresh SFX import succeeded in 3 attempts
  - fresh voice import succeeded in 3 attempts
- animation workflow was covered end-to-end:
  - `add_node` for `AnimationPlayer`
  - `list_animations`
  - `create_animation`
  - `add_animation_track`
  - `set_animation_keyframe`
  - `get_animation_info`
  - `remove_animation`
  - `delete_node`
- tilemap workflow was covered end-to-end using a temporary `TileMapLayer` plus a generated `TileSet`:
  - `create_tileset_from_image`
  - `tilemap_set_tileset`
  - `tilemap_get_info`
  - `tilemap_set_cell`
  - `tilemap_get_cell`
  - `tilemap_fill_rect`
  - `tilemap_get_used_cells`
  - `tilemap_clear`
  - cleanup via `delete_node`
- animation tree workflow was covered end-to-end using temporary nodes:
  - `create_animation_tree`
  - `get_animation_tree_structure`
  - `add_state_machine_state`
  - `add_state_machine_transition`
  - `set_tree_parameter`
  - `remove_state_machine_transition`
  - `remove_state_machine_state`
  - cleanup via `delete_node`

The remaining work is now mostly in:

- operational stability around reload / long sessions
- broader category coverage outside runtime/testing

## New Open Findings

### 1. Reload / session stability is still fragile

Severity: Medium

Observed during E2E:

- more than once, reload/update flow left Godot in a bad operational state
- at one point the editor/plugin stopped responding and only recovered after you manually restarted Godot
- some earlier reloads left stale in-memory behavior active before manual disable/enable
- during the `animation_tree` pass, rapid-fire CLI requests caused transient `9080` connection failures; the same commands passed when paced sequentially
- after hardening, `9080` still shows flaky connection establishment for one-shot CLI calls after reload and under repeated reconnect patterns
- importantly, once a single WebSocket connection is established, batched commands on that connection succeed reliably
- after an additional server cleanup pass (TCP-aware stale peer pruning) and client heartbeat support, the conclusion did not change:
  - `bun skill/ws_send.ts <command>` remains unreliable in live testing
  - `bun skill/ws_send.ts --batch` remains reliable in live testing

Important nuance:

- I did not prove that a specific asset/audio/export command caused the freeze
- the strongest correlation is still around plugin reload / long-lived session state, not one single handler command

What to do:

1. Add a dedicated smoke path for plugin reload:
   - disable
   - enable
   - `get_version`
   - `doctor`
   - `get_bridge_status`
2. Add lightweight health telemetry:
   - last successful command time
   - count of pending bridge requests
   - whether plugin is currently in play mode transition
3. Prefer persistent WebSocket usage (`--batch` / `--listen`) for rapid command bursts until one-shot connection establishment is hardened further
4. Avoid relying on `reload_plugin` alone during development unless it is hardened
5. Treat one-shot CLI calls as best-effort for now; the validated stable path is a persistent WebSocket session
6. Product decision: support `--batch`, `--listen`, and manual broker mode only

### 2. Optional OGG post-processing is environment-dependent

Severity: Low

Observed:

- the local FFmpeg build fails with:
  - `Unknown encoder 'libvorbis'`
- `convert_to: "ogg"` now fails explicitly instead of silently keeping a fallback file
- this is now safe and predictable, but still depends on the local FFmpeg build if real OGG output is desired

What to do:

1. Either require a FFmpeg build with Vorbis support for `convert_to: "ogg"`
2. Or keep the current hard-fail behavior and document OGG conversion as environment-dependent

## Verified But Still Worth Watching

These passed, but are still worth keeping in mind:

### Asset workflow

Passed:

- `get_image_info`
- `validate_spritesheet`
- `set_texture_import_preset`
- `create_sprite_frames`
- `set_sprite_texture`

Watch item:

- asset mutations did not reproduce a freeze after your manual Godot restart, but reload/session fragility remains an open operational risk

### Audio workflow

Passed:

- local WAV creation
- `import_audio_asset`
- `get_audio_asset_info`
- `create_audio_bus_if_missing`
- `add_audio_player`
- `attach_audio_stream`
- `get_audio_info`
- `list_voices`
- `voice_line`
- `sfx` (valid MP3 path)
- `inspect` on generated manifests

Watch item:

- immediate import after generation can race the filesystem scan; a short retry/delay was required in live testing
- the built-in retry now covers this race successfully for fresh generated MP3 assets
- optional OGG conversion still depends on local FFmpeg capabilities

### Shader workflow

Passed:

- `create_shader`
- `read_shader`
- `assign_shader_material`
- `set_shader_param`
- `get_shader_params`

Watch item:

- no issue surfaced in the sequential pass; the only earlier miss was from a parallel test race, not from the shader handler itself

### Animation workflow

Passed:

- created a temporary `AnimationPlayer`
- created a looping animation on `Player/Sprite:modulate`
- added a value track
- inserted multiple keyframes
- verified track/keyframe structure with `get_animation_info`
- removed the animation
- deleted the temporary `AnimationPlayer`

Watch item:

- the only confusing read was caused by a parallel test race; sequential reads were correct

### TileMap workflow

Passed:

- created a temporary `TileMapLayer`
- generated a real `TileSet` from `maze_tiles.png`
- assigned it with the dedicated `tilemap_set_tileset` command
- wrote and read back individual cells
- filled a rectangle and verified used-cell growth
- cleared cells and verified the clear path
- cleaned up temporary nodes

Watch item:

- the only inconsistent tilemap reads happened when I intentionally overlapped reads with write/delete operations in parallel; sequential reads were correct

### AnimationTree workflow

Passed:

- created a temporary `AnimationPlayer` with `idle` and `blink` animations
- created a temporary `AnimationTree` with `state_machine` root
- added two states bound to those animations
- added and removed a transition `idle -> blink`
- verified transition introspection through `get_animation_tree_structure`
- set a condition parameter with `set_tree_parameter`
- cleaned up the temporary container node

Watch item:

- `get_animation_tree_structure` is intentionally minimal for state machines and exposes transitions rather than a rich state dump; tests should verify observable mutations, not expect deep introspection

## Remaining Coverage Gaps

The following categories still need meaningful E2E coverage if you want broader confidence:

- 3D scene tools
- navigation
- particles
- themes
- batch execution semantics
- scene editing + undo/redo validation

## Recommended Next Steps

### Priority 1

Harden operational stability:

1. add reload smoke checks
2. add plugin health diagnostics
3. isolate what causes the occasional Godot stall

### Priority 2

Extend E2E coverage:

1. one additional non-runtime category:
   - 3D scene tools
   - navigation
   - particles
   - themes

## Short Worklist

If you want a strict implementation queue, this is the order I would use:

1. Fix one-shot WebSocket connection establishment reliability on `9080`
2. Add reload/health smoke tooling
3. Decide whether OGG conversion should remain environment-dependent or become a documented hard requirement
4. Expand into one more editor category beyond runtime/audio/assets/shader/animation/tilemap/animation_tree
