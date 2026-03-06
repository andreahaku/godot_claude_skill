#!/usr/bin/env bun
/**
 * WebSocket client for communicating with the GodotClaudeSkill plugin.
 *
 * Single command:
 *   bun ws_send.ts <command> [json_params]
 *
 * Batch mode (reads JSON lines from stdin):
 *   echo '{"command":"add_node","params":{"node_name":"Foo","node_type":"Node2D"}}' | bun ws_send.ts --batch
 *   cat commands.jsonl | bun ws_send.ts --batch
 *
 * Compact output (only success/fail, no full JSON):
 *   bun ws_send.ts --compact add_node '{"node_name":"Foo","node_type":"Node2D"}'
 *
 * Verbose mode (show raw WebSocket messages):
 *   bun ws_send.ts --verbose add_node '{"node_name":"Foo","node_type":"Node2D"}'
 *
 * Listen mode (keep connection open, read commands from stdin interactively):
 *   bun ws_send.ts --listen
 */

const WS_URL = process.env.GODOT_WS_URL || "ws://127.0.0.1:9080";
const TIMEOUT_MS = parseInt(process.env.GODOT_TIMEOUT || "30000", 10);

interface CommandMsg {
  id: string;
  command: string;
  params: Record<string, unknown>;
}

interface ResponseMsg {
  id: string;
  success: boolean;
  result?: unknown;
  error?: string;
}

let verbose = false;

function log_verbose(direction: ">>>" | "<<<", data: string) {
  if (verbose) {
    console.error(`${direction} ${data}`);
  }
}

async function sendSingle(command: string, params: Record<string, unknown>, compact: boolean) {
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
      log_verbose(">>>", message);
      ws.send(message);
    });

    ws.addEventListener("message", (event) => {
      clearTimeout(timeout);
      log_verbose("<<<", event.data as string);
      try {
        const data = JSON.parse(event.data as string) as ResponseMsg;
        if (data.id === id) {
          if (compact) {
            console.log(data.success ? "OK" : `FAIL: ${data.error || "unknown"}`);
          } else {
            console.log(JSON.stringify(data, null, 2));
          }
          ws.close();
          process.exit(data.success ? 0 : 1);
        }
      } catch {
        console.log(event.data);
        ws.close();
      }
    });

    ws.addEventListener("error", () => {
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
    console.error(JSON.stringify({ success: false, error: `Connection failed: ${err}` }));
    process.exit(1);
  }
}

async function sendBatch(compact: boolean) {
  // Read all lines from stdin
  const input = await Bun.stdin.text();
  const lines = input.trim().split("\n").filter((l) => l.trim());

  if (lines.length === 0) {
    console.error("No commands provided on stdin");
    process.exit(1);
  }

  // Parse all commands
  const commands: CommandMsg[] = [];
  for (const line of lines) {
    try {
      const parsed = JSON.parse(line);
      commands.push({
        id: crypto.randomUUID(),
        command: parsed.command,
        params: parsed.params || {},
      });
    } catch {
      console.error(`Invalid JSON: ${line}`);
      process.exit(1);
    }
  }

  return new Promise<void>((resolvePromise) => {
    const ws = new WebSocket(WS_URL);
    const pending = new Map<string, CommandMsg>();
    const results: { command: string; success: boolean; error?: string }[] = [];
    let sent = 0;

    const timeout = setTimeout(() => {
      console.error(JSON.stringify({ success: false, error: "Batch timeout" }));
      ws.close();
      process.exit(1);
    }, TIMEOUT_MS * 2);

    ws.addEventListener("open", () => {
      // Send commands sequentially — Godot processes them in order
      sendNext();
    });

    function sendNext() {
      if (sent >= commands.length) return;
      const cmd = commands[sent];
      pending.set(cmd.id, cmd);
      const msg = JSON.stringify(cmd);
      log_verbose(">>>", msg);
      ws.send(msg);
      sent++;
    }

    ws.addEventListener("message", (event) => {
      log_verbose("<<<", event.data as string);
      try {
        const data = JSON.parse(event.data as string) as ResponseMsg;
        const cmd = pending.get(data.id);
        if (cmd) {
          pending.delete(data.id);
          results.push({
            command: cmd.command,
            success: data.success,
            error: data.success ? undefined : (data.error as string),
          });

          if (compact) {
            const status = data.success ? "OK" : `FAIL: ${data.error || "unknown"}`;
            console.log(`[${results.length}/${commands.length}] ${cmd.command}: ${status}`);
          }

          // Send next command
          if (sent < commands.length) {
            sendNext();
          }

          // All done?
          if (results.length >= commands.length) {
            clearTimeout(timeout);
            if (!compact) {
              const succeeded = results.filter((r) => r.success).length;
              const failed = results.filter((r) => !r.success).length;
              console.log(JSON.stringify({ total: results.length, succeeded, failed, results }, null, 2));
            }
            ws.close();
            const hasFailure = results.some((r) => !r.success);
            process.exit(hasFailure ? 1 : 0);
          }
        }
      } catch {
        // ignore parse errors
      }
    });

    ws.addEventListener("error", () => {
      clearTimeout(timeout);
      console.error(JSON.stringify({
        success: false,
        error: "WebSocket connection failed",
      }));
      process.exit(1);
    });
  });
}

async function listenMode() {
  const ws = new WebSocket(WS_URL);
  const pending = new Map<string, string>();

  ws.addEventListener("open", () => {
    console.error(`Connected to ${WS_URL} — type commands as: command_name {"param":"value"}`);
    console.error("Press Ctrl+C to exit.\n");
    readLines();
  });

  ws.addEventListener("message", (event) => {
    log_verbose("<<<", event.data as string);
    try {
      const data = JSON.parse(event.data as string) as ResponseMsg;
      const cmdName = pending.get(data.id) || "?";
      pending.delete(data.id);
      if (data.success) {
        console.log(JSON.stringify(data.result, null, 2));
      } else {
        console.error(`FAIL [${cmdName}]: ${data.error}`);
      }
    } catch {
      console.log(event.data);
    }
    process.stdout.write("> ");
  });

  ws.addEventListener("error", () => {
    console.error("WebSocket connection failed. Is Godot running?");
    process.exit(1);
  });

  ws.addEventListener("close", () => {
    console.error("\nConnection closed.");
    process.exit(0);
  });

  async function readLines() {
    process.stdout.write("> ");
    const reader = Bun.stdin.stream().getReader();
    const decoder = new TextDecoder();
    let buffer = "";

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split("\n");
      buffer = lines.pop() || "";
      for (const line of lines) {
        const trimmed = line.trim();
        if (!trimmed) continue;

        const spaceIdx = trimmed.indexOf(" ");
        const command = spaceIdx === -1 ? trimmed : trimmed.slice(0, spaceIdx);
        let params: Record<string, unknown> = {};
        if (spaceIdx !== -1) {
          try {
            params = JSON.parse(trimmed.slice(spaceIdx + 1));
          } catch {
            console.error("Invalid JSON params");
            process.stdout.write("> ");
            continue;
          }
        }

        const id = crypto.randomUUID();
        pending.set(id, command);
        const msg = JSON.stringify({ id, command, params });
        log_verbose(">>>", msg);
        ws.send(msg);
      }
    }
  }
}

async function main() {
  const args = process.argv.slice(2);

  if (args.length === 0) {
    console.error(`Usage:
  bun ws_send.ts <command> [json_params]           Single command
  bun ws_send.ts --compact <command> [json_params]  Compact output (OK/FAIL)
  bun ws_send.ts --verbose <command> [json_params]  Show raw WebSocket messages
  bun ws_send.ts --listen                           Interactive persistent connection
  echo '{"command":"x","params":{}}' | bun ws_send.ts --batch    Batch from stdin
  cat commands.jsonl | bun ws_send.ts --batch --compact          Batch compact`);
    process.exit(1);
  }

  verbose = args.includes("--verbose");
  const compact = args.includes("--compact");
  const batch = args.includes("--batch");
  const listen = args.includes("--listen");
  const filteredArgs = args.filter((a) => !a.startsWith("--"));

  if (listen) {
    await listenMode();
    return;
  }

  if (batch) {
    await sendBatch(compact);
    return;
  }

  if (filteredArgs.length === 0) {
    console.error("No command specified");
    process.exit(1);
  }

  const command = filteredArgs[0];
  let params: Record<string, unknown> = {};

  if (filteredArgs[1]) {
    try {
      params = JSON.parse(filteredArgs[1]);
    } catch {
      console.error("Invalid JSON params:", filteredArgs[1]);
      process.exit(1);
    }
  }

  await sendSingle(command, params, compact);
}

main();
