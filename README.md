# Godot Claude Skill

A comprehensive Claude Code skill for controlling the Godot game engine editor in real-time. **162 commands across 23 categories** — matching the feature set of Godot MCP Pro.

## Architecture

```
┌─────────────────┐     WebSocket      ┌──────────────────────┐
│   Claude Code   │◄──────────────────►│  Godot Editor Plugin │
│                 │   ws://127.0.0.1   │                      │
│  skill/         │      :9080         │  godot-plugin/       │
│  ws_send.ts     │                    │  godot_claude.gd     │
│                 │  JSON commands     │  23 handlers          │
└─────────────────┘                    └──────────────────────┘
```

The plugin runs **inside the Godot editor** as an EditorPlugin with a WebSocket server. Claude Code sends commands via `ws_send.ts`, and the plugin executes them with full access to:

- **EditorInterface** — open/save scenes, play/stop, screenshots
- **UndoRedo** — every mutation is undoable with Ctrl+Z
- **SceneTree** — live scene hierarchy, node manipulation
- **Smart Type Parsing** — `Vector2(100,200)`, `#ff0000`, `Color(1,0,0)` auto-parsed

## Quick Start

### 1. Install the plugin into your Godot project

```bash
bash skill/install.sh /path/to/your/godot/project
```

This copies the plugin to `addons/godot_claude_skill/`.

### 2. Enable the plugin in Godot

1. Open your project in Godot editor
2. Go to **Project → Project Settings → Plugins**
3. Enable **GodotClaudeSkill**
4. You should see: `[GodotClaude] Ready! 164 commands available on ws://127.0.0.1:9080`

### 3. Test the connection

```bash
bun skill/ws_send.ts ping
bun skill/ws_send.ts list_commands
bun skill/ws_send.ts get_project_info
```

### 4. Use with Claude Code

The `.claude/commands/godot.md` file provides Claude Code with full documentation of all 162 commands. Claude can control Godot by running:

```bash
bun /path/to/godot_claude_skill/skill/ws_send.ts <command> '<json_params>'
```

## Features (23 Categories, 162 Tools)

| Category | Tools | Highlights |
|---|---|---|
| **Project** | 7 | Metadata, file tree, search, settings, UID management |
| **Scene** | 9 | Live hierarchy, create/open/save/delete, play/stop, instancing |
| **Node** | 11 | Add/delete/rename/duplicate/move, properties, resources, signals |
| **Script** | 6 | List/read/create/edit, attach to nodes, editor awareness |
| **Editor** | 9 | Errors, screenshots, visual diff, execute GDScript, signals |
| **Input Simulation** | 5 | Keyboard, mouse, InputActions, multi-event sequences |
| **Runtime Analysis** | 15 | Live game tree, properties, execute code, capture frames, recording |
| **Animation** | 6 | Create/edit animations, tracks, keyframes |
| **AnimationTree** | 8 | State machines, transitions, blend trees, parameters |
| **TileMap** | 6 | Set/get cells, fill rects, tile set info |
| **3D Scene** | 6 | Meshes, lighting presets, PBR materials, environment, cameras |
| **Physics** | 6 | Collision shapes, layers, raycasts, body config, collision audit |
| **Particles** | 5 | GPU particles 2D/3D, presets (fire, smoke, rain, snow, sparks) |
| **Navigation** | 5 | Regions, mesh baking, agents, layers, navigation audit |
| **Audio** | 6 | Bus layout, effects (reverb, delay, compressor), audio players |
| **Theme & UI** | 6 | Create themes, colors, constants, font sizes, styleboxes |
| **Shader** | 6 | Create/edit GLSL, assign materials, set/get uniforms |
| **Resource** | 3 | Read/edit/create .tres files of any type |
| **Batch & Refactoring** | 6 | Find by type, audit signals, bulk property changes, cross-scene |
| **Testing & QA** | 5 | Automated test scenarios, assertions, stress testing |
| **Code Analysis** | 6 | Unused resources, signal flow, complexity, circular deps |
| **Profiling** | 2 | FPS, memory, physics, render metrics |
| **Export** | 3 | Presets, export commands, template info |

## Key Advantages

- **Full Undo/Redo** — Every mutation goes through Godot's UndoRedo system
- **Smart Type Parsing** — `Vector2(100,200)`, `#ff0000`, `Color(1,0,0)` auto-parsed
- **Signal Management** — Connect, disconnect, and inspect signals
- **Input Simulation & Recording** — Let AI play your game with keyboard/mouse/actions
- **Runtime Analysis** — Inspect and modify the running game in real-time
- **Production WebSocket** — Heartbeat, auto-reconnect, structured error responses

## Requirements

- **Godot 4.x** (tested with 4.2+)
- **Bun** runtime (for ws_send.ts client)
- **Claude Code** CLI

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `GODOT_WS_URL` | `ws://127.0.0.1:9080` | WebSocket URL for the plugin |
| `GODOT_TIMEOUT` | `30000` | Connection timeout in ms |

## License

MIT
