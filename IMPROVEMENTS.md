# Godot Claude Skill — Improvement Tracker

Comprehensive improvement plan from full project review (2026-03-06).

## Phase 1 — Robustness (P0 + key P1)

Error handling, crash prevention, undo gaps.

- [x] **1.1** Add try/catch around handler execution in `command_router.gd:41` — if handler crashes, send error response instead of hanging client
- [x] **1.2** Add undo support to handlers that mutate state without it:
  - [x] `animation_tree_handler.gd` — add/remove states, transitions, blend tree nodes, parameters
  - [x] `particles_handler.gd` — set_particle_material, set_particle_color_gradient, apply_particle_preset
  - [x] `shader_handler.gd` — assign_shader_material, set_shader_param (now receives UndoHelper)
  - [x] `theme_handler.gd` — set_theme_color, set_theme_constant, set_theme_font_size, set_theme_stylebox
  - [x] `tilemap_handler.gd` — tilemap_set_cell, tilemap_fill_rect, tilemap_clear
  - N/A `audio_handler.gd` — AudioServer is a global singleton, not undoable via EditorUndoRedo
  - N/A `resource_handler.gd` — file-based saves, not undoable via EditorUndoRedo
- [x] **1.3** Wrap `Color.html()` in type_parser.gd in a validity check to prevent crash on invalid hex
- [x] **1.4** Add depth limit to `value_to_json()` in `type_parser.gd` — bail at depth 32
- [x] **1.5** Add max message size limit in `ws_server.gd` — reject messages over 16MB
- [x] **1.6** Add max connection limit in `ws_server.gd` — cap at 10 peers, reject excess
- [x] **1.7** Add fetch timeout to `generate_asset.ts` — `AbortSignal.timeout(120000)` on all API calls
- [x] **1.8** Add progress output to `generate_asset.ts` — print status to stderr during generation and post-processing
- [x] **1.9** Standardize error codes across all handlers — fixed `SAVE_FAILED` → `SAVE_ERROR`
- [x] **1.10** Add command execution logging in `command_router.gd` — log slow commands (>1s) + crash errors

## Phase 2 — Completeness (P1 docs + P2)

Missing commands, param consistency, documentation.

- [ ] **2.1** Add missing inspection commands:
  - [ ] AnimationTreeHandler: `get_state_machine_states` to list states
  - [ ] ParticlesHandler: return material params in `get_particle_info`
  - [ ] AudioHandler: `remove_audio_bus` command
- [ ] **2.2** Fix inconsistent parameter naming across handlers — audit `name` vs `node_name`, document conventions
- [ ] **2.3** Add property existence check in `node_handler.gd:update_property` before calling `node.set()`
- [ ] **2.4** Add `max_depth` / `max_results` params to `script_handler.gd:list_scripts`
- [ ] **2.5** Fix `batch_set_property` to validate all nodes/properties before creating undo action
- [ ] **2.6** Extract shared path normalization utility — `if not path.begins_with("res://")` used in 10+ handlers
- [ ] **2.7** Use `crypto.randomUUID()` instead of `Date.now()` for temp files in `generate_asset.ts`
- [ ] **2.8** Add batch progress output in `ws_send.ts` — show `[3/10]` counter during batch execution
- [ ] **2.9** Expand `godot.md` skill docs:
  - [ ] Add full param details for Animation, TileMap, 3D Scene sections
  - [ ] Document all error codes
  - [ ] Clarify batch vs batch_execute usage
  - [ ] Document all `create_sprite_frames` params (frame_count, columns)
- [ ] **2.10** Fix `install.sh` example command path (line 52) and add Godot version check
- [ ] **2.11** Add quick-start section to README — single copy-paste from install to first command
- [ ] **2.12** Fix `TypeParser` silent parse failures — distinguish "parsed null" from "parse error"

## Phase 3 — Polish (P3)

Performance, DX, code quality.

- [ ] **3.1** Add short-lived cache to `NodeFinder` — avoid re-resolving same path multiple times per command
- [ ] **3.2** Optimize `TypeParser` — use match/dictionary dispatch instead of linear if-chain
- [ ] **3.3** Refactor `godot_claude.gd` constructor — loop-based handler init with error handling per handler
- [ ] **3.4** Add handler schema/introspection — handlers declare param names + types for auto-doc
- [ ] **3.5** Add prerequisite check to `godot.sh` — verify bun is installed with actionable error
- [ ] **3.6** Expand `ProfilingHandler` — add history tracking and trend analysis
- [ ] **3.7** Add `--verbose` flag to `ws_send.ts` for debugging (show raw messages)
- [ ] **3.8** Add connection reuse / persistent mode to `ws_send.ts` for interactive use

## Status

| Phase | Status | Items | Done |
|-------|--------|-------|------|
| Phase 1 — Robustness | **Done** | 10 | 10 |
| Phase 2 — Completeness | Not started | 12 | 0 |
| Phase 3 — Polish | Not started | 8 | 0 |
