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

- [x] **2.1** Add missing inspection commands:
  - N/A AnimationTreeHandler: `get_state_machine_states` — already covered by `get_animation_tree_structure`
  - [x] ParticlesHandler: return material params in `get_particle_info` for 2D
  - [x] AudioHandler: `remove_audio_bus` command
- [x] **2.2** Document parameter naming conventions in godot.md (`name` vs `node_name`)
- [x] **2.3** Add property existence check in `node_handler.gd:update_property` before calling `node.set()`
- [x] **2.4** Add `max_results` param to `script_handler.gd:list_scripts` (default 500, with truncation flag)
- [x] **2.5** Fix `batch_set_property` to validate all nodes/properties before creating undo action
- [x] **2.6** Extract shared `normalize_res_path()` utility in NodeFinder
- [x] **2.7** Use `crypto.randomUUID()` instead of `Date.now()` for temp files in `generate_asset.ts`
- [x] **2.8** Add batch progress output in `ws_send.ts` — show `[3/10]` counter during batch execution
- [x] **2.9** Expand `godot.md` skill docs:
  - [x] Add full param details for all 15 handler categories
  - [x] Document all error codes
  - [x] Clarify batch vs batch_execute usage
  - [x] Document parameter naming conventions
- [x] **2.10** Fix `install.sh` example command path and add Godot version check
- [x] **2.11** Add quick-start section to README
- [x] **2.12** Add `TypeParser.parse_value_strict()` — returns `{value, parsed}` to distinguish parse failures; used in `update_property`

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
| Phase 2 — Completeness | **Done** | 12 | 12 |
| Phase 3 — Polish | Not started | 8 | 0 |
