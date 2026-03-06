#!/usr/bin/env bash
# Install script for GodotClaudeSkill
# Copies the plugin to a Godot project's addons directory
#
# Usage: install.sh /path/to/godot/project

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$SCRIPT_DIR/../godot-plugin"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -z "$1" ]; then
  echo "Usage: install.sh /path/to/godot/project"
  echo ""
  echo "Copies the GodotClaudeSkill plugin to the project's addons/ directory."
  exit 1
fi

PROJECT_DIR="$1"

if [ ! -f "$PROJECT_DIR/project.godot" ]; then
  echo "Error: $PROJECT_DIR is not a valid Godot project (no project.godot found)"
  exit 1
fi

# Check Godot version (requires 4.6+)
if grep -q 'config_version=' "$PROJECT_DIR/project.godot"; then
  CONFIG_VER=$(grep 'config_version=' "$PROJECT_DIR/project.godot" | head -1 | cut -d'=' -f2)
  if [ "$CONFIG_VER" -lt 5 ] 2>/dev/null; then
    echo "Warning: This plugin requires Godot 4.6+ (config_version >= 5)"
    echo "  Found config_version=$CONFIG_VER in project.godot"
  fi
fi

DEST="$PROJECT_DIR/addons/godot_claude_skill"

echo "Installing GodotClaudeSkill plugin..."
echo "  Source: $PLUGIN_DIR"
echo "  Destination: $DEST"

mkdir -p "$DEST/handlers"
mkdir -p "$DEST/utils"

# Copy all plugin files
cp "$PLUGIN_DIR/plugin.cfg" "$DEST/"
cp "$PLUGIN_DIR/godot_claude.gd" "$DEST/"
cp "$PLUGIN_DIR/ws_server.gd" "$DEST/"
cp "$PLUGIN_DIR/command_router.gd" "$DEST/"
cp "$PLUGIN_DIR/handlers/"*.gd "$DEST/handlers/"
cp "$PLUGIN_DIR/utils/"*.gd "$DEST/utils/"

echo ""
echo "Plugin installed successfully!"
echo ""
echo "Next steps:"
echo "  1. Open the Godot editor for your project"
echo "  2. Go to Project > Project Settings > Plugins"
echo "  3. Enable 'GodotClaudeSkill'"
echo "  4. The WebSocket server will start on ws://127.0.0.1:9080"
echo ""
echo "To test: bun $REPO_DIR/skill/ws_send.ts list_commands"
