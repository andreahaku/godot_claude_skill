#!/usr/bin/env bun
/**
 * WebSocket client for communicating with the GodotClaudeSkill plugin.
 * Usage: bun ws_send.ts <command> [json_params]
 *
 * Sends a command to the Godot editor plugin and prints the response.
 */

const WS_URL = process.env.GODOT_WS_URL || "ws://127.0.0.1:9080";
const TIMEOUT_MS = parseInt(process.env.GODOT_TIMEOUT || "30000", 10);

async function main() {
  const args = process.argv.slice(2);
  if (args.length === 0) {
    console.error("Usage: bun ws_send.ts <command> [json_params]");
    process.exit(1);
  }

  const command = args[0];
  let params: Record<string, unknown> = {};

  if (args[1]) {
    try {
      params = JSON.parse(args[1]);
    } catch {
      console.error("Invalid JSON params:", args[1]);
      process.exit(1);
    }
  }

  const id = crypto.randomUUID();
  const message = JSON.stringify({ id, command, params });

  try {
    const ws = new WebSocket(WS_URL);

    const timeout = setTimeout(() => {
      console.error(JSON.stringify({ success: false, error: "Connection timeout" }));
      ws.close();
      process.exit(1);
    }, TIMEOUT_MS);

    ws.addEventListener("open", () => {
      ws.send(message);
    });

    ws.addEventListener("message", (event) => {
      clearTimeout(timeout);
      try {
        const data = JSON.parse(event.data as string);
        if (data.id === id) {
          console.log(JSON.stringify(data, null, 2));
          ws.close();
          process.exit(data.success ? 0 : 1);
        }
      } catch {
        console.log(event.data);
        ws.close();
      }
    });

    ws.addEventListener("error", (event) => {
      clearTimeout(timeout);
      console.error(JSON.stringify({
        success: false,
        error: "WebSocket connection failed. Is the Godot editor running with GodotClaudeSkill plugin enabled?",
        url: WS_URL,
      }));
      process.exit(1);
    });

    ws.addEventListener("close", () => {
      clearTimeout(timeout);
    });
  } catch (err) {
    console.error(JSON.stringify({
      success: false,
      error: `Connection failed: ${err}`,
    }));
    process.exit(1);
  }
}

main();
