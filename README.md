# Godot Claude Skill

A comprehensive Claude Code skill for controlling the Godot game engine editor in real-time via WebSocket. **161 commands across 25 categories** with full undo/redo support, AI asset generation, runtime bridge for true game introspection, and structured script patching.

## Architecture

```
┌─────────────────┐     WebSocket      ┌──────────────────────┐
│   Claude Code   │◄──────────────────►│  Godot Editor Plugin │
│                 │  ws://127.0.0.1    │                      │
│  skill/         │     :9080          │  godot-plugin/       │
│  ws_send.ts     │                    │  godot_claude.gd     │
│  generate_asset │  JSON commands     │  command_router.gd   │
└─────────────────┘                    │  24 handlers         │
                                       │  bridge_server.gd    │
                                       └──────────┬───────────┘
                                                   │ ws://127.0.0.1:9081
                                       ┌───────────▼───────────┐
                                       │   Running Game        │
                                       │   runtime_bridge.gd   │
                                       │   (autoload)          │
                                       └───────────────────────┘
```

The plugin runs **inside the Godot editor** as an EditorPlugin with a WebSocket server. Claude Code sends JSON commands via `ws_send.ts`, and the plugin executes them with full access to the editor API.

A separate **runtime bridge** (port 9081) connects the running game process back to the editor, enabling true game-side introspection — scene tree inspection, property manipulation, input injection, and screenshot capture from the actual game viewport.

## Prerequisites

- **Godot 4.6+** (tested with 4.6.1)
- **Bun** runtime (for the WebSocket client `ws_send.ts`)
- **Claude Code** CLI
- **Python 3 + Pillow** (optional, for asset post-processing: `pip install Pillow`)
- **API key** (optional, for asset generation): Google AI (`GOOGLE_AI_API_KEY`) or OpenAI (`OPENAI_API_KEY`)

## Quick Start

```bash
# 1. Install plugin into your Godot project
bash /path/to/godot_claude_skill/skill/install.sh /path/to/your/godot/project

# 2. Open the project in Godot, enable the plugin in Project > Project Settings > Plugins

# 3. Test the connection
bun /path/to/godot_claude_skill/skill/ws_send.ts list_commands

# 4. Start building!
bun /path/to/godot_claude_skill/skill/ws_send.ts get_scene_tree
```

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
├── handlers/               # 24 handler files (one per category)
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
│   └── ... (analysis, asset, export, profiling, resource, testing)
├── bridge_server.gd        # Editor-side bridge server (port 9081)
├── runtime_bridge.gd       # Game-side autoload for runtime introspection
└── utils/
    ├── command_helper.gd   # Centralized validation utilities
    ├── node_finder.gd      # Shared node lookup with fuzzy matching
    ├── scan_helper.gd      # Debounced filesystem scan
    ├── type_parser.gd      # Smart type parsing (Vector2, Color, etc.)
    └── undo_helper.gd      # UndoRedo wrapper for Godot 4.6
```

### Step 2: Enable the Plugin in Godot

1. Open your project in the Godot editor
2. Go to **Project → Project Settings → Plugins** tab
3. Find **GodotClaudeSkill** in the list and check **Enable**
4. Check the **Output** panel — you should see:
   ```
   [GodotClaude] Ready! 161 commands available on ws://127.0.0.1:9080
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

This gives Claude Code the `/godot` slash command with full documentation of all 161 commands.

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

## Features (25 Categories, 161 Commands)

| Category | Count | Highlights |
|---|---|---|
| **Project** | 7 | Metadata, file tree, search, settings, UID management |
| **Scene** | 9 | Live hierarchy, create/open/save/delete, play/stop, instancing |
| **Node** | 11 | Add/delete/rename/duplicate/move, properties, resources, signals |
| **Script** | 10 | List/read/create/edit/patch, attach, validate, diagnostics |
| **Editor** | 9 | Errors, screenshots, visual diff, execute GDScript, signals |
| **Input Simulation** | 5 | Keyboard, mouse, InputActions, multi-event sequences with waits |
| **Runtime Analysis** | 16 | Live game tree via runtime bridge, properties, execute code, capture frames, recording, bridge status |
| **Animation** | 6 | Create/edit animations, tracks, keyframes |
| **AnimationTree** | 8 | State machines, transitions, blend trees, parameters |
| **TileMap** | 6 | Set/get cells, fill rects, tile set info |
| **3D Scene** | 6 | Meshes, lighting presets, PBR materials, environment, cameras |
| **Physics** | 6 | Collision shapes, layers, raycasts, body config, collision audit |
| **Particles** | 5 | GPU particles 2D/3D, presets (fire, smoke, rain, snow, sparks) |
| **Navigation** | 5 | Regions, mesh baking, agents, layers, navigation audit |
| **Audio** | 7 | Bus layout, add/remove buses, effects (reverb, delay, etc.), audio players |
| **Theme & UI** | 6 | Create themes, colors, constants, font sizes, styleboxes |
| **Shader** | 6 | Create/edit GLSL, assign materials, set/get uniforms |
| **Resource** | 3 | Read/edit/create .tres files of any type |
| **Batch & Refactoring** | 6 | Find by type, audit signals, bulk property changes, cross-scene |
| **Testing & QA** | 5 | Automated test scenarios, assertions, stress testing |
| **Code Analysis** | 6 | Unused resources, signal flow, complexity, circular deps |
| **Profiling** | 4 | FPS, memory, render metrics, snapshot history with trend analysis |
| **Asset Management** | 6 | Sprite textures, sprite frames from spritesheets, atlas textures, import presets, NinePatch |
| **Export** | 3 | Presets, export commands, template info |
| **Meta** | 9 | List/describe/search commands, health check, doctor, version info, batch execute |

## Key Features

### Full Undo/Redo

Every scene mutation goes through Godot's `EditorUndoRedoManager`. This means:
- All changes can be undone with **Ctrl+Z** in the editor
- The undo history is properly named (e.g., "Add Node: Player", "Set Position")
- Batch operations support `atomic_if_supported` mode for single undo actions

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

### Batch & Compact Modes

`ws_send.ts` supports batch execution and compact output for faster workflows:

```bash
# Compact output — prints OK or FAIL instead of full JSON
bun skill/ws_send.ts --compact add_node '{"node_name":"Foo","node_type":"Node2D"}'
# Output: OK

# Batch mode — send multiple commands via stdin (JSONL format)
printf '{"command":"add_node","params":{"node_name":"A","node_type":"Node2D"}}
{"command":"add_node","params":{"node_name":"B","node_type":"Sprite2D","parent_path":"A"}}
' | bun skill/ws_send.ts --batch --compact
# Output:
# [1/2] add_node: OK
# [2/2] add_node: OK

# Server-side batch with mode — fail_fast stops on first error
bun skill/ws_send.ts batch_execute '{"mode":"fail_fast","commands":[
  {"command":"add_node","params":{"node_name":"A","node_type":"Node2D"}},
  {"command":"update_property","params":{"node_path":"A","property":"position","value":"Vector2(100,200)"}}
]}'

# Dry run — validate commands without executing
bun skill/ws_send.ts batch_execute '{"mode":"dry_run","commands":[...]}'

# Atomic — wrap in single undo action, rollback on failure
bun skill/ws_send.ts batch_execute '{"mode":"atomic_if_supported","commands":[...]}'

# Verbose mode — show raw WebSocket messages (useful for debugging)
bun skill/ws_send.ts --verbose get_scene_tree

# Listen mode — interactive persistent connection (REPL)
bun skill/ws_send.ts --listen
# > get_scene_tree
# > add_node {"node_name":"Foo","node_type":"Node2D"}
```

### Runtime Bridge

The runtime bridge provides true game-side introspection by running an autoload script inside the game process that connects back to the editor via WebSocket (port 9081):

- `get_game_scene_tree` — live scene hierarchy from the actual game process
- `get_game_node_properties` / `set_game_node_properties` — read/write game node state
- `monitor_properties` — track property changes over time
- `execute_game_script` — run arbitrary GDScript in the game context
- `capture_frames` — screenshot from the game viewport (not the editor)
- `find_ui_elements` / `click_button_by_text` — interact with game UI
- `get_bridge_status` — check bridge connection status

When the bridge is not connected, commands fall back to the editor tree with a `_fallback` flag.

### Structured Script Patching

The `patch_script` command provides safe, structured script editing with stale-edit detection:

```bash
bun ws_send.ts patch_script '{"path":"res://player.gd","operations":[
  {"type":"replace_exact_block","search":"var speed = 100","replace":"var speed = 200"},
  {"type":"insert_after_marker","marker":"extends CharacterBody2D","content":"\\n@export var jump_force := 400.0"}
]}'
```

Operations: `replace_range`, `replace_exact_block`, `insert_before_marker`, `insert_after_marker`, `append_to_class`. Supports `expected_hash` for conflict detection.

### Script Validation

Validate scripts for compilation errors:
- `validate_script` — check a single script
- `validate_scripts` — batch validate all scripts under a path
- `get_script_diagnostics` — detailed diagnostics (dependencies, warnings, hash)

### Testing with Assertion Operators

Enhanced test scenarios with 10 step types and rich assertions:

```bash
bun ws_send.ts run_test_scenario '{"name":"Jump Test","steps":[
  {"type":"input_action","action":"jump","pressed":true},
  {"type":"wait","duration":0.5},
  {"type":"assert_property","node_path":"Player","property":"position.y","operator":"<","expected":0},
  {"type":"assert_exists","node_path":"Player/JumpParticles"},
  {"type":"assert_text","text":"Score:"}
]}'
```

Operators: `==`, `!=`, `>`, `>=`, `<`, `<=`, `contains`, `matches` (regex), `approx`. Nested property paths supported (`position.x`, `velocity.y`).

### Command Discovery & Schemas

All commands have declarative schemas with descriptions, typed parameters, and metadata:

```bash
# Search for commands by keyword
bun ws_send.ts search_commands '{"query":"animation"}'

# Get full schema for a command
bun ws_send.ts describe_command '{"command":"add_node"}'

# List all commands in a category with schemas
bun ws_send.ts describe_category '{"category":"scene_handler"}'

# List all commands with descriptions
bun ws_send.ts list_commands '{"include_schemas":true}'
```

Required parameters are auto-validated by the router before handlers are called.

### Health Check & Doctor

```bash
# Quick status — version, scene, bridge, handler counts
bun ws_send.ts health_check

# Prerequisite validation — checks plugin, WS, bridge, scene
bun ws_send.ts doctor
```

### Smart Node Lookup

NodeFinder supports multiple path formats:
- Standard paths: `Player/Sprite2D`
- Unique name (`%`): `%Player` (searches entire tree)
- Type-qualified: `Player:CharacterBody2D` (validates type)
- Fuzzy matching: on failure, suggests similar node names

### Install Script

```bash
# Basic install — copy plugin files
bash skill/install.sh /path/to/godot/project

# Full install — plugin + CLAUDE.md + skill file + wrapper script + runtime bridge
bash skill/install.sh --full /path/to/godot/project

# Uninstall
bash skill/install.sh --uninstall /path/to/godot/project
```

## AI Asset Generation

The skill includes an AI-powered asset generator that creates sprites, textures, tilesets, and other game art using image generation APIs.

### Setup

Set one of these environment variables (e.g., in your shell profile or `.env`):

```bash
# Google AI (Gemini/Imagen) — recommended
export GOOGLE_AI_API_KEY="your-google-ai-api-key"

# OR OpenAI (DALL-E 3)
export OPENAI_API_KEY="your-openai-api-key"
```

Get a Google AI API key at [aistudio.google.com](https://aistudio.google.com/).

### Usage

```bash
# Generate a pixel art character
bun skill/generate_asset.ts "knight character, side view, idle pose" \
  '{"output":"res://assets/sprites/knight.png","project":"/path/to/godot/project","style":"pixel_art"}'

# Generate a tileset
bun skill/generate_asset.ts "grass and dirt tiles, top-down RPG" \
  '{"output":"res://assets/tiles/terrain.png","project":"/path/to/project","style":"pixel_art_tileset","size":"1024x1024"}'

# Generate a UI panel background
bun skill/generate_asset.ts "wooden panel with ornate border" \
  '{"output":"res://assets/ui/panel.png","project":"/path/to/project","style":"ui"}'
```

### Post-Processing Options

Generated images can be automatically post-processed (requires Python 3 with Pillow):

```bash
# Remove white background, resize to 32x32
bun skill/generate_asset.ts "pixel art knight" \
  '{"output":"res://assets/knight.png","project":".","style":"pixel_art_character","remove_bg":true,"resize":"32x32"}'

# Trim whitespace and resize
bun skill/generate_asset.ts "game icon sword" \
  '{"output":"res://assets/sword.png","project":".","style":"icon","trim":true,"resize":"64x64"}'
```

| Option | Type | Description |
|---|---|---|
| `remove_bg` | `boolean` | Flood-fill remove white/light background from edges |
| `bg_threshold` | `number` | Brightness threshold for background removal (0-255, default 240) |
| `trim` | `boolean` | Trim transparent whitespace around the image |
| `resize` | `string` | Resize to `WxH` (e.g., `"32x32"`, `"64x64"`) |

### Full Workflow Example

```bash
# 1. Generate a character spritesheet
bun skill/generate_asset.ts "pixel art knight walk cycle, 4 frames, side view" \
  '{"output":"res://assets/knight_walk.png","project":".","style":"spritesheet"}'

# 2. Set pixel art import settings (no filtering)
bun skill/ws_send.ts set_texture_import_preset \
  '{"texture_path":"res://assets/knight_walk.png","preset":"2d_pixel"}'

# 3. Create an AnimatedSprite2D and assign frames from the spritesheet
bun skill/ws_send.ts add_node \
  '{"node_type":"AnimatedSprite2D","node_name":"Knight"}'

bun skill/ws_send.ts create_sprite_frames \
  '{"node_path":"Knight","spritesheet":"res://assets/knight_walk.png","frame_width":32,"frame_height":32,"animation":"walk","fps":8,"loop":true}'
```

### Style Presets

| Preset | Description |
|---|---|
| `pixel_art` | Retro pixel art, crisp pixels, transparent background |
| `pixel_art_character` | Pixel art character, side view |
| `pixel_art_tileset` | Pixel art tileset, top-down, seamless |
| `hand_drawn` | Hand-drawn illustration, vibrant colors |
| `realistic` | PBR-ready detailed textures |
| `ui` | Clean flat UI elements, transparent background |
| `tileset` | Seamless tileable patterns |
| `icon` | Game icons, clear silhouette |
| `character` | Character sprites, transparent background |
| `environment` | Game backgrounds, atmospheric |
| `spritesheet` | Multi-frame grid spritesheet |

### Environment Variables for Asset Generation

| Variable | Default | Description |
|---|---|---|
| `GOOGLE_AI_API_KEY` | — | Google AI API key (for Gemini/Imagen) |
| `OPENAI_API_KEY` | — | OpenAI API key (for DALL-E 3) |
| `ASSET_GEN_PROVIDER` | auto-detect | `gemini` or `openai` |
| `GEMINI_IMAGE_MODEL` | `imagen-4.0-generate-001` | Google image model |

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
│       └── godot.md           # Claude Code skill definition (161 commands documented)
├── godot-plugin/              # Source files for the Godot EditorPlugin
│   ├── plugin.cfg
│   ├── godot_claude.gd        # Main plugin entry point
│   ├── ws_server.gd           # WebSocket server
│   ├── command_router.gd      # Command routing with category tracking
│   ├── handlers/              # 24 handler files (one per category)
│   └── utils/                 # Shared utilities (NodeFinder, TypeParser, UndoHelper)
├── skill/
│   ├── install.sh             # Installation script (with Godot version check)
│   ├── godot.sh               # Shell wrapper (with bun prerequisite check)
│   ├── ws_send.ts             # Bun WebSocket client (single, batch, compact, verbose, listen)
│   └── generate_asset.ts      # AI asset generator (Gemini/Imagen, DALL-E)
└── README.md
```

## License

MIT
