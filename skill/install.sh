#!/usr/bin/env bash
# Install script for GodotClaudeSkill
# Copies the plugin to a Godot project's addons directory
#
# Usage:
#   install.sh /path/to/godot/project           Basic install (plugin only)
#   install.sh /path/to/godot/project --full     Full setup (plugin + skill + CLAUDE.md + bridge)
#   install.sh /path/to/godot/project --uninstall  Remove plugin

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$SCRIPT_DIR/../godot-plugin"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGIN_VERSION="1.1.0"

# Parse arguments
PROJECT_DIR=""
FULL_INSTALL=false
UNINSTALL=false

for arg in "$@"; do
    case "$arg" in
        --full) FULL_INSTALL=true ;;
        --uninstall) UNINSTALL=true ;;
        *) PROJECT_DIR="$arg" ;;
    esac
done

if [ -z "$PROJECT_DIR" ]; then
    echo "Usage: install.sh /path/to/godot/project [--full] [--uninstall]"
    echo ""
    echo "Options:"
    echo "  --full       Full setup: plugin + skill file + CLAUDE.md + bridge autoload"
    echo "  --uninstall  Remove the plugin from the project"
    echo ""
    echo "The Godot editor must be closed when installing."
    exit 1
fi

if [ ! -f "$PROJECT_DIR/project.godot" ]; then
    echo "Error: $PROJECT_DIR is not a valid Godot project (no project.godot found)"
    exit 1
fi

DEST="$PROJECT_DIR/addons/godot_claude_skill"

# Handle uninstall
if [ "$UNINSTALL" = true ]; then
    echo "Uninstalling GodotClaudeSkill..."

    if [ -d "$DEST" ]; then
        rm -rf "$DEST"
        echo "  [OK] Removed $DEST"
    else
        echo "  [--] Plugin directory not found (already removed?)"
    fi

    # Remove autoload entry from project.godot
    if grep -q 'GodotClaudeRuntimeBridge' "$PROJECT_DIR/project.godot"; then
        sed -i.bak '/GodotClaudeRuntimeBridge/d' "$PROJECT_DIR/project.godot"
        rm -f "$PROJECT_DIR/project.godot.bak"
        echo "  [OK] Removed runtime bridge autoload from project.godot"
    fi

    # Remove runtime bridge autoload file
    if [ -f "$PROJECT_DIR/autoload/runtime_bridge.gd" ]; then
        rm -f "$PROJECT_DIR/autoload/runtime_bridge.gd"
        # Remove autoload dir if empty
        rmdir "$PROJECT_DIR/autoload" 2>/dev/null || true
        echo "  [OK] Removed autoload/runtime_bridge.gd"
    fi

    echo ""
    echo "Plugin uninstalled. You may also want to remove:"
    echo "  - .claude/commands/godot.md"
    echo "  - ./godot_send (if created)"
    echo "  - Godot Integration section from CLAUDE.md"
    exit 0
fi

# Check Godot version (requires 4.6+)
if grep -q 'config_version=' "$PROJECT_DIR/project.godot"; then
    CONFIG_VER=$(grep 'config_version=' "$PROJECT_DIR/project.godot" | head -1 | cut -d'=' -f2)
    if [ "$CONFIG_VER" -lt 5 ] 2>/dev/null; then
        echo "Warning: This plugin requires Godot 4.6+ (config_version >= 5)"
        echo "  Found config_version=$CONFIG_VER in project.godot"
    fi
fi

# Check for existing installation and version comparison
if [ -f "$DEST/.plugin_version" ]; then
    INSTALLED_VER=$(cat "$DEST/.plugin_version")
    if [ "$INSTALLED_VER" = "$PLUGIN_VERSION" ]; then
        echo "GodotClaudeSkill v$PLUGIN_VERSION is already installed."
        echo "Reinstalling..."
    else
        echo "Existing installation found: v$INSTALLED_VER"
        echo "Upgrading to: v$PLUGIN_VERSION"

        # Show what's new between versions
        INSTALLED_MAJOR=$(echo "$INSTALLED_VER" | cut -d. -f1)
        INSTALLED_MINOR=$(echo "$INSTALLED_VER" | cut -d. -f2)
        NEW_MAJOR=$(echo "$PLUGIN_VERSION" | cut -d. -f1)
        NEW_MINOR=$(echo "$PLUGIN_VERSION" | cut -d. -f2)

        if [ "$NEW_MAJOR" -gt "$INSTALLED_MAJOR" ] 2>/dev/null; then
            echo ""
            echo "  ** Major version upgrade -- review changelog for breaking changes **"
        elif [ "$NEW_MINOR" -gt "$INSTALLED_MINOR" ] 2>/dev/null; then
            echo ""
            echo "  New in v$PLUGIN_VERSION:"
            echo "    - Full install mode (--full) with CLAUDE.md, skill file, bridge autoload"
            echo "    - Plugin versioning and upgrade detection"
            echo "    - Uninstall support (--uninstall)"
            echo "    - Prerequisite validation"
        fi
    fi
    echo ""
fi

echo "Installing GodotClaudeSkill v$PLUGIN_VERSION..."
echo "  Source: $PLUGIN_DIR"
echo "  Destination: $DEST"
echo ""

# Create directories
mkdir -p "$DEST/handlers"
mkdir -p "$DEST/utils"

# Copy all plugin files
cp "$PLUGIN_DIR/plugin.cfg" "$DEST/"
cp "$PLUGIN_DIR/godot_claude.gd" "$DEST/"
cp "$PLUGIN_DIR/ws_server.gd" "$DEST/"
cp "$PLUGIN_DIR/command_router.gd" "$DEST/"
cp "$PLUGIN_DIR/bridge_server.gd" "$DEST/"
cp "$PLUGIN_DIR/runtime_bridge.gd" "$DEST/"
cp "$PLUGIN_DIR/handlers/"*.gd "$DEST/handlers/"
cp "$PLUGIN_DIR/utils/"*.gd "$DEST/utils/"

# Write version file
echo "$PLUGIN_VERSION" > "$DEST/.plugin_version"

echo "  [OK] Plugin files installed"

# Always copy skill command file
mkdir -p "$PROJECT_DIR/.claude/commands"
cp "$REPO_DIR/.claude/commands/godot.md" "$PROJECT_DIR/.claude/commands/godot.md"
echo "  [OK] Skill file copied to .claude/commands/godot.md"

# Full install extras
if [ "$FULL_INSTALL" = true ]; then
    echo ""
    echo "Running full setup..."

    # 1. Create/append CLAUDE.md
    CLAUDE_MD="$PROJECT_DIR/CLAUDE.md"
    # Use a heredoc to avoid quoting issues
    GODOT_SECTION="## Godot Integration

- Send commands to the running Godot editor via WebSocket:
  \`bun $REPO_DIR/skill/ws_send.ts <command> '<json_params>'\`
- The Godot editor must be open with the plugin enabled (ws://127.0.0.1:9080)
- All scene mutations support Undo (Ctrl+Z in editor)
- Always check \`get_scene_tree\` before modifying the scene
- Use \`validate_script\` after script changes to verify compilation
- Use \`describe_command\` to get parameter docs for any command
- Use \`search_commands\` to find commands by keyword"

    if [ -f "$CLAUDE_MD" ]; then
        if ! grep -q "Godot Integration" "$CLAUDE_MD"; then
            echo "" >> "$CLAUDE_MD"
            echo "$GODOT_SECTION" >> "$CLAUDE_MD"
            echo "  [OK] Appended Godot section to CLAUDE.md"
        else
            echo "  [--] CLAUDE.md already has Godot section (skipped)"
        fi
    else
        echo "# $(basename "$PROJECT_DIR")" > "$CLAUDE_MD"
        echo "" >> "$CLAUDE_MD"
        echo "$GODOT_SECTION" >> "$CLAUDE_MD"
        echo "  [OK] Created CLAUDE.md with Godot instructions"
    fi

    # 2. Create wrapper script
    WRAPPER="$PROJECT_DIR/godot_send"
    cat > "$WRAPPER" << WRAPPER_EOF
#!/usr/bin/env bash
# Wrapper for GodotClaudeSkill WebSocket client
# Usage: ./godot_send <command> [json_params]
exec bun "$REPO_DIR/skill/ws_send.ts" "\$@"
WRAPPER_EOF
    chmod +x "$WRAPPER"
    echo "  [OK] Created wrapper script: ./godot_send"

    # 3. Create .env.example
    ENV_EXAMPLE="$PROJECT_DIR/.env.example"
    if [ ! -f "$ENV_EXAMPLE" ]; then
        cat > "$ENV_EXAMPLE" << 'ENV_EOF'
# GodotClaudeSkill API Keys
# Copy this file to .env and fill in your keys

# Image generation (pick one)
GOOGLE_AI_API_KEY=
OPENAI_API_KEY=

# Audio generation (future)
ELEVENLABS_API_KEY=

# WebSocket configuration (optional)
# GODOT_WS_URL=ws://127.0.0.1:9080
# GODOT_TIMEOUT=30000
ENV_EOF
        echo "  [OK] Created .env.example"
    else
        echo "  [--] .env.example already exists (skipped)"
    fi

    # 4. Install runtime bridge autoload
    BRIDGE_DEST="$PROJECT_DIR/autoload"
    mkdir -p "$BRIDGE_DEST"
    cp "$PLUGIN_DIR/runtime_bridge.gd" "$BRIDGE_DEST/runtime_bridge.gd"

    # Add autoload to project.godot if not present
    if ! grep -q 'GodotClaudeRuntimeBridge' "$PROJECT_DIR/project.godot"; then
        # Find or create [autoload] section
        if grep -q '^\[autoload\]' "$PROJECT_DIR/project.godot"; then
            # Add after [autoload] line
            sed -i.bak '/^\[autoload\]/a\
GodotClaudeRuntimeBridge="*res://autoload/runtime_bridge.gd"' "$PROJECT_DIR/project.godot"
            rm -f "$PROJECT_DIR/project.godot.bak"
        else
            # Add new [autoload] section at end
            echo "" >> "$PROJECT_DIR/project.godot"
            echo "[autoload]" >> "$PROJECT_DIR/project.godot"
            echo "" >> "$PROJECT_DIR/project.godot"
            echo 'GodotClaudeRuntimeBridge="*res://autoload/runtime_bridge.gd"' >> "$PROJECT_DIR/project.godot"
        fi
        echo "  [OK] Runtime bridge autoload added to project.godot"
    else
        echo "  [--] Runtime bridge autoload already configured (skipped)"
    fi

    # 5. Validate prerequisites
    echo ""
    echo "Checking prerequisites..."

    if command -v bun > /dev/null 2>&1; then
        BUN_VER=$(bun --version 2>/dev/null)
        echo "  [OK] Bun $BUN_VER"
    else
        echo "  [!!] Bun not found -- required for ws_send.ts"
        echo "       Install: curl -fsSL https://bun.sh/install | bash"
    fi

    if command -v python3 > /dev/null 2>&1; then
        PY_VER=$(python3 --version 2>/dev/null)
        echo "  [OK] $PY_VER"
        if python3 -c "import PIL" 2>/dev/null; then
            echo "  [OK] Pillow (image post-processing)"
        else
            echo "  [--] Pillow not installed -- optional for asset post-processing"
            echo "       Install: pip install Pillow"
        fi
    else
        echo "  [--] Python 3 not found -- optional for asset post-processing"
    fi

    # Check for API keys
    if [ -n "$GOOGLE_AI_API_KEY" ]; then
        echo "  [OK] GOOGLE_AI_API_KEY set"
    else
        echo "  [--] GOOGLE_AI_API_KEY not set -- needed for image generation"
    fi
fi

echo ""
echo "Installation complete! (v$PLUGIN_VERSION)"
echo ""
echo "Next steps:"
echo "  1. Open the Godot editor for your project"
echo "  2. Go to Project > Project Settings > Plugins"
echo "  3. Enable 'GodotClaudeSkill'"
echo "  4. The WebSocket server will start on ws://127.0.0.1:9080"
echo ""
if [ "$FULL_INSTALL" = true ]; then
    echo "Quick test: ./godot_send list_commands"
else
    echo "Quick test: bun $REPO_DIR/skill/ws_send.ts list_commands"
    echo ""
    echo "Tip: Use --full for complete setup (skill file, CLAUDE.md, bridge autoload)"
fi
