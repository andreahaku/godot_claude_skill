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

import { mkdir, readFile, rename, rm, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";

const CLIENT_VERSION = "1.1.0";
const WS_URL = process.env.GODOT_WS_URL || "ws://127.0.0.1:9080";
const TIMEOUT_MS = parseInt(process.env.GODOT_TIMEOUT || "30000", 10);
const CONNECT_RETRIES = parseInt(process.env.GODOT_CONNECT_RETRIES || "10", 10);
const CONNECT_RETRY_DELAY_MS = parseInt(process.env.GODOT_CONNECT_RETRY_DELAY_MS || "500", 10);
const BROKER_DIR = process.env.GODOT_BROKER_DIR || "/tmp/godot_claude_ws_broker";
const BROKER_HEARTBEAT_PATH = `${BROKER_DIR}/heartbeat.json`;
const BROKER_TIMEOUT_MS = parseInt(process.env.GODOT_BROKER_TIMEOUT || "45000", 10);
const USE_BROKER = process.env.GODOT_USE_BROKER === "1";

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

interface BatchResult {
  command: string;
  success: boolean;
  error?: string;
  response: ResponseMsg;
}

let verbose = false;

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function log_verbose(direction: ">>>" | "<<<", data: string) {
  if (verbose) {
    console.error(`${direction} ${data}`);
  }
}

async function sendSingle(command: string, params: Record<string, unknown>, compact: boolean) {
  if (USE_BROKER) {
    try {
      const data = await sendViaBroker(command, params);
      if (compact) {
        console.log(data.success ? "OK" : `FAIL: ${data.error || "unknown"}`);
      } else {
        console.log(JSON.stringify(data, null, 2));
      }
      process.exit(data.success ? 0 : 1);
    } catch (err) {
      console.error(JSON.stringify({
        success: false,
        error: String(err),
        broker_dir: BROKER_DIR,
        help: "Start the broker manually with `bun skill/ws_broker.ts`, then retry with GODOT_USE_BROKER=1.",
      }));
      process.exit(1);
    }
  }

  let lastError: unknown = null;

  for (let attempt = 1; attempt <= CONNECT_RETRIES; attempt++) {
    try {
      const results = await sendCommandsOverSingleConnection([{
        id: crypto.randomUUID(),
        command,
        params,
      }]);
      const data = results[0].response;
      if (compact) {
        console.log(data.success ? "OK" : `FAIL: ${data.error || "unknown"}`);
      } else {
        console.log(JSON.stringify(data, null, 2));
      }
      process.exit(data.success ? 0 : 1);
    } catch (err) {
      lastError = err;
      if (attempt < CONNECT_RETRIES) {
        await sleep(CONNECT_RETRY_DELAY_MS);
        continue;
      }
    }
  }

  console.error(JSON.stringify({
    success: false,
    error: String(lastError || "WebSocket connection failed"),
    url: WS_URL,
    attempts: CONNECT_RETRIES,
  }));
  process.exit(1);
}

async function sendViaBroker(command: string, params: Record<string, unknown>): Promise<ResponseMsg> {
  await ensureBrokerRunning();
  await mkdir(BROKER_DIR, { recursive: true });
  const id = crypto.randomUUID();
  const requestPath = `${BROKER_DIR}/${id}.request.json`;
  const tempPath = `${BROKER_DIR}/${id}.request.tmp`;
  const responsePath = `${BROKER_DIR}/${id}.response.json`;

  await writeFile(tempPath, JSON.stringify({ client_id: id, command, params }));
  await rename(tempPath, requestPath);

  const deadline = Date.now() + BROKER_TIMEOUT_MS;
  while (Date.now() < deadline) {
    if (existsSync(responsePath)) {
      try {
        const data = JSON.parse(await readFile(responsePath, "utf8")) as ResponseMsg;
        await rm(responsePath, { force: true });
        return data;
      } finally {
        await rm(requestPath, { force: true });
      }
    }
    await sleep(100);
  }

  await rm(requestPath, { force: true });
  throw new Error("Broker request timeout");
}

async function ensureBrokerRunning() {
  for (let attempt = 1; attempt <= 3; attempt++) {
    if (await heartbeatFresh()) {
      return;
    }
    await sleep(500);
  }
  throw new Error(`Broker not running in ${BROKER_DIR}. Start it manually with: bun skill/ws_broker.ts`);
}

async function heartbeatFresh(): Promise<boolean> {
  if (!existsSync(BROKER_HEARTBEAT_PATH)) {
    return false;
  }
  try {
    const info = JSON.parse(await readFile(BROKER_HEARTBEAT_PATH, "utf8")) as { updated_at?: number };
    return !!info.updated_at && Date.now() - info.updated_at < 5000;
  } catch {
    return false;
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

  const results = await sendCommandsOverSingleConnection(commands);
  if (compact) {
    for (let i = 0; i < results.length; i++) {
      const result = results[i];
      const status = result.success ? "OK" : `FAIL: ${result.error || "unknown"}`;
      console.log(`[${i + 1}/${results.length}] ${result.command}: ${status}`);
    }
  } else {
    const succeeded = results.filter((r) => r.success).length;
    const failed = results.filter((r) => !r.success).length;
    console.log(JSON.stringify({
      total: results.length,
      succeeded,
      failed,
      results: results.map((r) => ({ command: r.command, success: r.success, error: r.error })),
    }, null, 2));
  }
  process.exit(results.some((r) => !r.success) ? 1 : 0);
}

async function sendCommandsOverSingleConnection(commands: CommandMsg[]): Promise<BatchResult[]> {
  return await new Promise<BatchResult[]>((resolve, reject) => {
    const ws = new WebSocket(WS_URL);
    const pending = new Map<string, CommandMsg>();
    const results: BatchResult[] = [];
    let sent = 0;
    let settled = false;

    const timeout = setTimeout(() => {
      settled = true;
      ws.close();
      reject(new Error("Batch timeout"));
    }, TIMEOUT_MS * 2);

    ws.addEventListener("open", () => {
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
        if (!cmd) return;

        pending.delete(data.id);
        results.push({
          command: cmd.command,
          success: data.success,
          error: data.success ? undefined : data.error,
          response: data,
        });

        if (sent < commands.length) {
          sendNext();
        }

        if (results.length >= commands.length) {
          clearTimeout(timeout);
          settled = true;
          ws.close();
          resolve(results);
        }
      } catch {
        // ignore parse errors
      }
    });

    ws.addEventListener("error", () => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      reject(new Error("WebSocket connection failed"));
    });

    ws.addEventListener("close", () => {
      if (settled) return;
      clearTimeout(timeout);
      if (results.length >= commands.length) {
        return;
      }
      settled = true;
      reject(new Error("WebSocket closed before all responses were received"));
    });
  });
}

async function listenMode() {
  const ws = new WebSocket(WS_URL);
  const pending = new Map<string, string>();
  let heartbeatTimer: Timer | null = null;

  ws.addEventListener("open", () => {
    console.error(`Connected to ${WS_URL} — type commands as: command_name {"param":"value"}`);
    console.error("Press Ctrl+C to exit.\n");
    heartbeatTimer = setInterval(() => {
      if (ws.readyState !== WebSocket.OPEN) return;
      const id = crypto.randomUUID();
      pending.set(id, "ping");
      ws.send(JSON.stringify({ id, command: "ping", params: {} }));
    }, 5000);
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
    if (heartbeatTimer) clearInterval(heartbeatTimer);
    console.error("WebSocket connection failed. Is Godot running?");
    process.exit(1);
  });

  ws.addEventListener("close", () => {
    if (heartbeatTimer) clearInterval(heartbeatTimer);
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

  if (args.includes("--version")) {
    console.log(`ws_send.ts v${CLIENT_VERSION}`);
    process.exit(0);
  }

  if (args.length === 0) {
    console.error(`Usage:
  bun ws_send.ts <command> [json_params]           Single command
  bun ws_send.ts --compact <command> [json_params]  Compact output (OK/FAIL)
  bun ws_send.ts --verbose <command> [json_params]  Show raw WebSocket messages
  bun ws_send.ts --listen                           Interactive persistent connection
  bun ws_send.ts --version                          Print version and exit
  echo '{"command":"x","params":{}}' | bun ws_send.ts --batch    Batch from stdin
  cat commands.jsonl | bun ws_send.ts --batch --compact          Batch compact`);
    process.exit(1);
  }

  verbose = args.includes("--verbose");
  const compact = args.includes("--compact");
  const batch = args.includes("--batch");
  const listen = args.includes("--listen");

  if (verbose) {
    console.error(`ws_send.ts v${CLIENT_VERSION} | ${WS_URL} | timeout=${TIMEOUT_MS}ms`);
  }
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
