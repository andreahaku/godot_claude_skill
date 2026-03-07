# Godot Claude Skill

A comprehensive Claude Code skill for controlling the Godot game engine editor in real-time via WebSocket. **185 commands across 27 categories** with full undo/redo support, AI asset/audio generation, runtime bridge for true game introspection, event subscriptions, and structured script patching.

## Architecture

```
┌─────────────────┐     WebSocket      ┌──────────────────────┐
│   Claude Code   │◄──────────────────►│  Godot Editor Plugin │
│                 │  ws://127.0.0.1    │                      │
│  skill/         │     :9080          │  godot-plugin/       │
│  ws_send.ts     │                    │  godot_claude.gd     │
│  generate_asset │  JSON commands     │  command_router.gd   │
│  generate_audio │                    │  26 handlers         │
└─────────────────┘                    │  bridge_server.gd    │
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
- **ElevenLabs API key** (optional, for audio generation): `ELEVENLABS_API_KEY`

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
├── handlers/               # 26 handler files (one per category)
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
   [GodotClaude] Ready! 185 commands available on ws://127.0.0.1:9080
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

This gives Claude Code the `/godot` slash command with full documentation of all 185 commands.

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

## Features (27 Categories, 185 Commands)

| Category | Count | Highlights |
|---|---|---|
| **Project** | 7 | Metadata, file tree, search, settings, UID management |
| **Scene** | 9 | Live hierarchy, create/open/save/delete, play/stop, instancing |
| **Node** | 12 | Add/delete/rename/duplicate/move, properties, resources, signals, auto-connect |
| **Script** | 10 | List/read/create/edit/patch, attach, validate, diagnostics |
| **Editor** | 14 | Errors, screenshots, visual diff, execute GDScript, signals, node bounds, scene summary, viewport info, git status/diff |
| **Input Simulation** | 5 | Keyboard, mouse, InputActions, multi-event sequences with waits |
| **Runtime Analysis** | 16 | Live game tree via runtime bridge, properties, execute code, capture frames, recording, bridge status |
| **Animation** | 6 | Create/edit animations, tracks, keyframes |
| **AnimationTree** | 8 | State machines, transitions, blend trees, parameters |
| **TileMap** | 7 | Set/get cells, fill rects, tile set info, create tileset from image |
| **3D Scene** | 6 | Meshes, lighting presets, PBR materials, environment, cameras |
| **Physics** | 6 | Collision shapes, layers, raycasts, body config, collision audit |
| **Particles** | 5 | GPU particles 2D/3D, presets (fire, smoke, rain, snow, sparks) |
| **Navigation** | 5 | Regions, mesh baking, agents, layers, navigation audit |
| **Audio** | 12 | Bus layout, add/remove buses, effects, audio players, import/attach/inspect assets, randomizer |
| **Theme & UI** | 6 | Create themes, colors, constants, font sizes, styleboxes |
| **Shader** | 6 | Create/edit GLSL, assign materials, set/get uniforms |
| **Resource** | 3 | Read/edit/create .tres files of any type |
| **Batch & Refactoring** | 6 | Find by type, audit signals, bulk property changes, cross-scene |
| **Testing & QA** | 5 | Automated test scenarios, assertions, stress testing |
| **Code Analysis** | 7 | Unused resources, signal flow, complexity, circular deps, ClassDB lookup |
| **Profiling** | 4 | FPS, memory, render metrics, snapshot history with trend analysis |
| **Asset Management** | 7 | Sprite textures, sprite frames, atlas textures, import presets, NinePatch, spritesheet validation |
| **Debug** | 4 | Output log, runtime errors, breakpoint navigation, clear breakpoints |
| **Export** | 3 | Presets, export commands, template info |
| **Templates** | 3 | Scene templates (12 prefabs), GDScript scaffolding (10 script templates), list templates |
| **Meta** | 12 | List/describe/search commands, health check, doctor, version, batch execute, event subscriptions |

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

### Scene Templates & Script Scaffolding

Create complete node hierarchies from templates instead of adding nodes one at a time:

```bash
# Create a full platformer player (CharacterBody2D + Sprite2D + CollisionShape2D + AnimationPlayer + Camera2D)
bun ws_send.ts create_from_template '{"template":"platformer_player","name":"Player"}'

# Create a UI menu with buttons
bun ws_send.ts create_from_template '{"template":"ui_menu","parent_path":"UI"}'

# Generate and attach a movement script
bun ws_send.ts scaffold_script '{"node_path":"Player","template":"platformer_movement","params":{"speed":250,"jump_force":-450}}'

# List all available templates
bun ws_send.ts list_templates
```

12 scene templates: `platformer_player`, `top_down_player`, `enemy_basic`, `ui_hud`, `ui_menu`, `rigid_body_2d`, `area_trigger`, `audio_manager`, `camera_follow`, `parallax_bg`, `character_3d`, `lighting_3d`

10 script templates: `platformer_movement`, `top_down_movement`, `state_machine`, `health_system`, `inventory`, `dialogue_trigger`, `enemy_patrol`, `camera_shake`, `save_load`, `audio_manager`

### Signal Auto-Wiring

Automatically connect common signals and create method stubs:

```bash
# Scan children and auto-connect Button.pressed, Area2D.body_entered, Timer.timeout
bun ws_send.ts auto_connect_signals '{"node_path":"UI"}'

# Dry run — see what would be connected without making changes
bun ws_send.ts auto_connect_signals '{"node_path":"","dry_run":true}'
```

### ClassDB Lookup

Query Godot's built-in class documentation directly:

```bash
# Get properties, methods, signals for a class
bun ws_send.ts lookup_class '{"class_name":"CharacterBody2D"}'

# Look up a specific property
bun ws_send.ts lookup_class '{"class_name":"Sprite2D","property":"texture"}'

# Include inherited members
bun ws_send.ts lookup_class '{"class_name":"Button","include_inherited":true}'
```

### Event Subscriptions

Subscribe to editor events via WebSocket for push-based notifications:

```bash
# Subscribe to events — receive push notifications when they fire
bun ws_send.ts subscribe '{"events":["filesystem_changed","node_added","game_started","game_stopped"]}'

# Unsubscribe from all events
bun ws_send.ts unsubscribe

# Check current subscriptions
bun ws_send.ts get_subscriptions
```

Available events: `filesystem_changed`, `node_added`, `node_removed`, `game_started`, `game_stopped`. Supports `"*"` wildcard for all events.

### Debug Tools

Inspect the Godot output log and runtime errors:

```bash
# Get last 50 lines of the output log
bun ws_send.ts get_output_log '{"lines":100}'

# Get runtime errors from the log
bun ws_send.ts get_runtime_errors

# Navigate to a specific line in a script (for breakpoint setting)
bun ws_send.ts set_breakpoint '{"script_path":"res://player.gd","line":42}'
```

### Version Control Awareness

Query git status directly from the editor:

```bash
# Get modified files (git status)
bun ws_send.ts get_modified_files

# Get diff for a scene file
bun ws_send.ts get_scene_diff '{"scene_path":"res://scenes/main.tscn"}'
```

### Spritesheet Validation & Tileset Creation

```bash
# Validate spritesheet dimensions and detect empty frames
bun ws_send.ts validate_spritesheet '{"path":"res://assets/knight_walk.png","frame_width":32,"frame_height":32}'

# Create a TileSet from an image with auto-slicing
bun ws_send.ts create_tileset_from_image '{"image_path":"res://assets/tileset.png","tile_size":16,"save_path":"res://tilesets/terrain.tres"}'
```

## AI Asset Generation

The skill includes an AI-powered asset generator that uses **structured JSON prompting** internally for dramatically improved image quality. Each aspect (subject, composition, style, technical constraints) is isolated during prompt construction to prevent concept bleeding — adjectives stay tied to their target elements instead of leaking across the image.

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
| `quality` | `string` | `"draft"`, `"standard"` (default), or `"final"` (premium quality modifiers) |
| `style_notes` | `string` | Additional style guidance (e.g., `"desaturated forest tones"`) |
| `style_reference` | `string` | Path to reference image for style consistency |
| `color_palette` | `string[]` | Hex colors to constrain palette (e.g., `["#2d5a27", "#8b4513"]`) |
| `no_manifest` | `boolean` | Skip creating `.asset.json` manifest (default: false) |

### Asset Caching

Generated assets are cached by prompt+options hash to avoid redundant API calls:

```bash
# First call generates and caches the asset
bun skill/generate_asset.ts "pixel art knight" '{"output":"res://knight.png","project":".","style":"pixel_art"}'

# Second call with same prompt+options returns cached version instantly
bun skill/generate_asset.ts "pixel art knight" '{"output":"res://knight.png","project":".","style":"pixel_art"}'

# Force regeneration (skip cache)
bun skill/generate_asset.ts "pixel art knight" '{"output":"res://knight.png","project":".","style":"pixel_art","no_cache":true}'
```

Cache is stored in `.godot_claude_cache/assets/` in the project root (add to `.gitignore`).

### Asset Manifests

Every generated image automatically gets a sidecar `.asset.json` manifest with the full prompt, style, provider, structured prompt data, and post-processing details. This enables:
- Regenerating variations with the same parameters
- Tracking how assets were produced
- Batch-updating assets later

```bash
# knight.png → knight.asset.json
# Contents: {prompt, style, provider, model, timestamp, structured_prompt, options, post_processing}
```

### Style Consistency

Use `style_reference` and `color_palette` to maintain consistent art across assets:

```bash
# Generate first asset
bun skill/generate_asset.ts "knight character" \
  '{"output":"res://sprites/knight.png","style":"pixel_art_character","project":"."}'

# Generate matching enemy with same palette
bun skill/generate_asset.ts "skeleton enemy" \
  '{"output":"res://sprites/skeleton.png","style":"pixel_art_character","project":".","style_reference":"res://sprites/knight.png","color_palette":["#8b4513","#d2691e","#f5deb3"]}'
```

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

## AI Audio Generation

The skill includes AI-powered audio generation using **ElevenLabs** for voice lines (TTS) and sound effects (SFX). Generated audio files are saved to the Godot project with sidecar `.audio.json` manifests for regeneration and traceability.

### Setup

```bash
# Set your ElevenLabs API key
export ELEVENLABS_API_KEY="your-elevenlabs-api-key"
```

Get an API key at [elevenlabs.io/app/settings/api-keys](https://elevenlabs.io/app/settings/api-keys).

### Voice Lines

```bash
# Generate a spoken voice line
bun skill/generate_audio.ts voice_line \
  '{"text":"Halt! State your business.","voice_id":"JBFqnCBsd6RMkjVDRZzb","output":"res://audio/voice/guard_alert.mp3","project":"."}'

# With voice settings and tags
bun skill/generate_audio.ts voice_line \
  '{"text":"We need to move now!","voice_id":"JBFqnCBsd6RMkjVDRZzb","output":"res://audio/voice/npc_urgent.mp3","project":".","voice_settings":{"stability":0.4,"similarity_boost":0.8},"tags":["dialogue","guard","combat"]}'
```

### Sound Effects

```bash
# Generate a one-shot SFX
bun skill/generate_audio.ts sfx \
  '{"text":"Short metallic sword impact with bright ring","output":"res://audio/sfx/sword_hit.mp3","project":".","duration_seconds":1.2}'

# Generate a loopable ambient sound
bun skill/generate_audio.ts sfx \
  '{"text":"Night forest ambience with crickets and wind","output":"res://audio/ambience/forest_night.mp3","project":".","duration_seconds":15,"loop":true,"prompt_influence":0.35}'
```

### Voice Presets

Use human-readable names instead of voice IDs:

```bash
# Use preset name instead of voice_id
bun skill/generate_audio.ts voice_line \
  '{"text":"Halt! Who goes there?","voice_id":"adam","output":"res://audio/voice/guard.mp3","project":"."}'

# List all voice presets
bun skill/generate_audio.ts list_presets
```

Available presets: `adam` (deep male), `alice` (warm female), `aria` (expressive female), `bill` (older male), `brian` (narrator), `charlie` (casual male), `charlotte` (elegant female), `chris` (casual male), `daniel` (British male), `eric` (friendly male), `george` (warm male), `jessica` (young female), `laura` (soft female), `lily` (light female), `roger` (middle-aged male), `sarah` (gentle female).

### Audio Post-Processing

Post-process generated audio with ffmpeg (requires ffmpeg installed):

```bash
# Convert to OGG Vorbis for Godot
bun skill/generate_audio.ts voice_line \
  '{"text":"Hello","voice_id":"brian","output":"res://audio/hello.ogg","project":".","convert_to":"ogg"}'

# Normalize audio levels
bun skill/generate_audio.ts sfx \
  '{"text":"explosion","output":"res://audio/boom.mp3","project":".","normalize":true}'

# Trim silence from beginning and end
bun skill/generate_audio.ts voice_line \
  '{"text":"...pause... Hello!","voice_id":"alice","output":"res://audio/hi.mp3","project":".","trim_silence":true}'
```

### Inspect & Regenerate

```bash
# Inspect an audio asset and its manifest
bun skill/generate_audio.ts inspect '{"file":"res://audio/sfx/sword_hit.mp3","project":"."}'

# Regenerate from manifest (same settings, new output)
bun skill/generate_audio.ts regenerate '{"file":"res://audio/sfx/sword_hit.mp3","project":"."}'

# List available ElevenLabs voices
bun skill/generate_audio.ts list_voices
```

### Godot Integration

After generating audio, use Godot plugin commands to import and wire it into scenes:

```bash
# 1. Import the audio asset (triggers Godot rescan)
bun skill/ws_send.ts import_audio_asset '{"audio_path":"res://audio/sfx/sword_hit.mp3"}'

# 2. Ensure the SFX bus exists
bun skill/ws_send.ts create_audio_bus_if_missing '{"name":"SFX"}'

# 3. Attach to an audio player node
bun skill/ws_send.ts attach_audio_stream '{"node_path":"Player/HitSfx","audio_path":"res://audio/sfx/sword_hit.mp3","bus":"SFX"}'

# 4. Create an AudioStreamRandomizer from multiple SFX variants
bun skill/ws_send.ts create_audio_randomizer '{"name":"FootstepSfx","parent_path":"Player","audio_paths":["res://audio/sfx/step_01.mp3","res://audio/sfx/step_02.mp3","res://audio/sfx/step_03.mp3"],"bus":"SFX"}'

# 5. Inspect audio asset details
bun skill/ws_send.ts get_audio_asset_info '{"audio_path":"res://audio/sfx/sword_hit.mp3"}'
```

### Audio Manifests

Every generated audio file gets a sidecar `.audio.json` manifest:

```
sword_hit.mp3 → sword_hit.audio.json
```

Contains: type, provider, source text, voice settings, model, format, bus assignment, tags, and regeneration history.

### Environment Variables for Audio Generation

| Variable | Default | Description |
|---|---|---|
| `ELEVENLABS_API_KEY` | — | ElevenLabs API key (required) |
| `AUDIO_GEN_DEFAULT_FORMAT` | `mp3_44100_128` | Output format |
| `AUDIO_GEN_DEFAULT_VOICE_MODEL` | `eleven_flash_v2_5` | TTS model |
| `AUDIO_GEN_DEFAULT_SFX_MODEL` | `eleven_text_to_sound_v2` | SFX model |

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
│       └── godot.md           # Claude Code skill definition (185 commands documented)
├── godot-plugin/              # Source files for the Godot EditorPlugin
│   ├── plugin.cfg
│   ├── godot_claude.gd        # Main plugin entry point
│   ├── ws_server.gd           # WebSocket server
│   ├── command_router.gd      # Command routing with category tracking
│   ├── handlers/              # 26 handler files (one per category)
│   └── utils/                 # Shared utilities (NodeFinder, TypeParser, UndoHelper, EventBus)
├── skill/
│   ├── install.sh             # Installation script (with Godot version check)
│   ├── godot.sh               # Shell wrapper (with bun prerequisite check)
│   ├── ws_send.ts             # Bun WebSocket client (single, batch, compact, verbose, listen)
│   ├── generate_asset.ts      # AI asset generator (Gemini/Imagen, DALL-E) with caching
│   ├── generate_audio.ts      # AI audio generator (ElevenLabs TTS/SFX)
│   └── audio_provider_elevenlabs.ts  # ElevenLabs API with voice presets
└── README.md
```

## License

MIT
