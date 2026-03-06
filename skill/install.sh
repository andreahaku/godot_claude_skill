#!/usr/bin/env bash
# Install script for GodotClaudeSkill
# Copies the plugin to a Godot project's addons directory
#
# Usage: install.sh /path/to/godot/project

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$SCRIPT_DIR/../godot-plugin"

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
echo "To test: bun $(dirname "$SCRIPT_DIR")/skill/ws_send.ts ping"
