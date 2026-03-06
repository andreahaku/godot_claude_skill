#!/usr/bin/env bash
# GodotClaudeSkill - Shell wrapper for sending commands to the Godot plugin
# Usage: godot.sh <command> [json_params]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS_SEND="$SCRIPT_DIR/ws_send.ts"

if [ -z "$1" ]; then
  echo "Usage: godot.sh <command> [json_params]"
  echo ""
  echo "Examples:"
  echo "  godot.sh list_commands"
  echo "  godot.sh get_project_info"
  echo "  godot.sh get_scene_tree"
  echo "  godot.sh add_node '{\"parent_path\":\"\",\"node_type\":\"Sprite2D\",\"node_name\":\"Player\"}'"
  exit 1
fi

exec bun "$WS_SEND" "$@"
