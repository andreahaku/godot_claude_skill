# Godot Claude Skill

A comprehensive Claude Code skill for controlling the Godot game engine editor in real-time via WebSocket. **149 commands across 23 categories** with full undo/redo support.

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

The plugin runs **inside the Godot editor** as an EditorPlugin with a WebSocket server. Claude Code sends JSON commands via `ws_send.ts`, and the plugin executes them with full access to the editor API.

## Prerequisites

- **Godot 4.6+** (tested with 4.6.1)
- **Bun** runtime (for the WebSocket client `ws_send.ts`)
- **Claude Code** CLI

## Setup

### Step 1: Install the Godot Plugin

Clone this repo (or download it) somewhere accessible:

```bash
git clone https://github.com/your-user/godot_claude_skill.git
```

Then install the plugin into your Godot project:

```bash
bash /path/to/godot_claude_skill/skill/install.sh /path/to/your/godot/project
```

This copies all plugin files to `your-project/addons/godot_claude_skill/`.

**What gets installed:**

```
addons/godot_claude_skill/
├── plugin.cfg              # Plugin descriptor
├── godot_claude.gd         # Main EditorPlugin entry point
├── ws_server.gd            # WebSocket server (TCPServer + WebSocketPeer)
├── command_router.gd       # Routes commands to handlers
├── handlers/               # 23 handler files (one per category)
│   ├── animation_handler.gd
│   ├── animation_tree_handler.gd
│   ├── audio_handler.gd
│   ├── batch_handler.gd
│   ├── editor_handler.gd
│   ├── input_handler.gd
│   ├── navigation_handler.gd
│   ├── node_handler.gd
│   ├── particles_handler.gd
│   ├── physics_handler.gd
│   ├── runtime_handler.gd
│   ├── scene_3d_handler.gd
│   ├── scene_handler.gd
│   ├── script_handler.gd
│   ├── shader_handler.gd
│   ├── theme_handler.gd
│   ├── tilemap_handler.gd
│   └── ... (analysis, export, profiling, resource, testing)
└── utils/
    ├── node_finder.gd      # Shared node lookup utility
    ├── type_parser.gd      # Smart type parsing (Vector2, Color, etc.)
    └── undo_helper.gd      # UndoRedo wrapper for Godot 4.6
```

### Step 2: Enable the Plugin in Godot

1. Open your project in the Godot editor
2. Go to **Project → Project Settings → Plugins** tab
3. Find **GodotClaudeSkill** in the list and check **Enable**
4. Check the **Output** panel — you should see:
   ```
   [GodotClaude] Ready! 149 commands available on ws://127.0.0.1:9080
   ```

If you don't see this message, check:
- The plugin appears in the Plugins list (if not, your `addons/` structure is wrong)
- No GDScript errors in the Output panel (click the **Debugger** tab at bottom)

### Step 3: Configure Claude Code

Claude Code needs two things to control Godot:

#### 3a. The Skill Command File

Copy (or symlink) the skill command file into your project's `.claude/commands/` directory:

```bash
# From your Godot project directory:
mkdir -p .claude/commands
cp /path/to/godot_claude_skill/.claude/commands/godot.md .claude/commands/godot.md
```

This gives Claude Code the `/godot` slash command with full documentation of all 149 commands.

#### 3b. Add CLAUDE.md Instructions (optional but recommended)

Create or add to your project's `CLAUDE.md`:

```markdown
# Godot Project

This project uses the GodotClaudeSkill plugin for real-time editor control.

## Godot Integration

- Send commands to the running Godot editor via WebSocket:
  `bun /path/to/godot_claude_skill/skill/ws_send.ts <command> '<json_params>'`
- The Godot editor must be open with the plugin enabled (ws://127.0.0.1:9080)
- All scene mutations support Undo (Ctrl+Z in editor)
- Always check `get_scene_tree` before modifying the scene
- Use `get_editor_errors` after script changes to verify compilation
```

### Step 4: Verify the Connection

Make sure Godot is running with the plugin enabled, then test:

```bash
# Test connectivity
bun /path/to/godot_claude_skill/skill/ws_send.ts list_commands

# Get project info
bun /path/to/godot_claude_skill/skill/ws_send.ts get_project_info

# See the scene tree
bun /path/to/godot_claude_skill/skill/ws_send.ts get_scene_tree
```

You should get JSON responses. If you get a connection error:
- Verify Godot is running and the plugin is enabled
- Check port 9080 is not in use by another application
- Look for errors in Godot's Output panel

### Step 5: Use with Claude Code

Now you can use Claude Code to control Godot. Example interactions:

```
You: /godot Create a 2D platformer scene with a player sprite and a ground

Claude: (sends multiple ws_send.ts commands to create nodes, set properties, etc.)

You: Add a script to the player with basic movement

Claude: (creates GDScript, attaches it to the player node)
```

## Features (23 Categories, 149 Commands)

| Category | Count | Highlights |
|---|---|---|
| **Project** | 7 | Metadata, file tree, search, settings, UID management |
| **Scene** | 9 | Live hierarchy, create/open/save/delete, play/stop, instancing |
| **Node** | 11 | Add/delete/rename/duplicate/move, properties, resources, signals |
| **Script** | 6 | List/read/create/edit, attach to nodes, editor awareness |
| **Editor** | 9 | Errors, screenshots, visual diff, execute GDScript, signals |
| **Input Simulation** | 5 | Keyboard, mouse, InputActions, multi-event sequences with waits |
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

## Key Features

### Full Undo/Redo

Every scene mutation goes through Godot's `EditorUndoRedoManager`. This means:
- All changes can be undone with **Ctrl+Z** in the editor
- The undo history is properly named (e.g., "Add Node: Player", "Set Position")
- Batch operations create single undo actions

### Smart Type Parsing

String values in command params are automatically parsed into Godot types:

| Input String | Godot Type |
|---|---|
| `Vector2(100, 200)` | `Vector2` |
| `Vector3(1, 2, 3)` | `Vector3` |
| `Color(1, 0, 0)` | `Color` |
| `#ff0000`, `#ff0000ff` | `Color` |
| `Rect2(0, 0, 100, 200)` | `Rect2` |
| `Quaternion(0, 0, 0, 1)` | `Quaternion` |
| `NodePath("Player/Sprite2D")` | `NodePath` |
| `^Player/Sprite2D` | `NodePath` |
| `true`, `false` | `bool` |
| `42`, `3.14` | `int`, `float` |

### Input Simulation & Recording

Simulate keyboard, mouse, and input actions in the running game. Supports multi-step sequences with waits:

```bash
bun ws_send.ts simulate_sequence '{"steps":[
  {"type":"key","key":"RIGHT","pressed":true},
  {"type":"wait","duration":1.0},
  {"type":"key","key":"SPACE","pressed":true}
]}'
```

### Runtime Analysis

Inspect and modify the running game in real-time:
- `get_game_scene_tree` — live scene hierarchy
- `monitor_properties` — track property changes over time
- `execute_game_script` — run arbitrary GDScript in the game context
- `capture_frames` — multi-frame screenshot capture

## Command Protocol

Commands are sent as JSON over WebSocket:

```json
{
  "id": "unique-uuid",
  "command": "add_node",
  "params": {
    "parent_path": "",
    "node_type": "Sprite2D",
    "node_name": "Player",
    "properties": {
      "position": "Vector2(100, 200)"
    }
  }
}
```

Responses:

```json
{
  "id": "same-uuid",
  "success": true,
  "result": {
    "node_path": "Player",
    "node_type": "Sprite2D",
    "node_name": "Player"
  }
}
```

Error responses:

```json
{
  "id": "same-uuid",
  "success": false,
  "error": "Node not found: NonExistent",
  "code": "NODE_NOT_FOUND",
  "suggestions": []
}
```

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `GODOT_WS_URL` | `ws://127.0.0.1:9080` | WebSocket URL for the plugin |
| `GODOT_TIMEOUT` | `30000` | Connection timeout in ms |

## Troubleshooting

### Plugin doesn't appear in Project Settings

- Verify `addons/godot_claude_skill/plugin.cfg` exists
- Check that the file contains `[plugin]` with `script="godot_claude.gd"`
- Restart the Godot editor

### WebSocket connection refused

- Make sure the Godot editor is running with the plugin enabled
- Check that port 9080 is not blocked or in use
- Look at the Godot Output panel for `[GodotClaude] Ready!` message

### Commands return errors

- Use `list_commands` to verify the command name exists
- Check `get_scene_tree` first — many commands require an open scene
- Node paths are relative to the scene root (e.g., `"Player/Sprite2D"`, not `/root/Main/Player/Sprite2D`)

### GDScript errors after install

- This plugin requires **Godot 4.6+** (uses `EditorUndoRedoManager.callv()`)
- If you see `Invalid call` errors, your Godot version may be too old

## Project Structure

```
godot_claude_skill/
├── .claude/
│   └── commands/
│       └── godot.md           # Claude Code skill definition (149 commands documented)
├── godot-plugin/              # Source files for the Godot EditorPlugin
│   ├── plugin.cfg
│   ├── godot_claude.gd        # Main plugin entry point
│   ├── ws_server.gd           # WebSocket server
│   ├── command_router.gd      # Command routing
│   ├── handlers/              # 23 handler files
│   └── utils/                 # Shared utilities
├── skill/
│   ├── install.sh             # Installation script
│   └── ws_send.ts             # Bun WebSocket client
└── README.md
```

## License

MIT
