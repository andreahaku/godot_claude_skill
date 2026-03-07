#!/usr/bin/env bun

import { mkdir, open, readdir, readFile, rename, rm, writeFile } from "node:fs/promises";
import { existsSync, unlinkSync } from "node:fs";

const BROKER_VERSION = "1.1.0";
const BROKER_DIR = process.env.GODOT_BROKER_DIR || "/tmp/godot_claude_ws_broker";
const HEARTBEAT_PATH = `${BROKER_DIR}/heartbeat.json`;
const LOCK_PATH = `${BROKER_DIR}/broker.lock`;
const WS_URL = process.env.GODOT_WS_URL || "ws://127.0.0.1:9080";
const WS_CONNECT_TIMEOUT_MS = parseInt(process.env.GODOT_BROKER_CONNECT_TIMEOUT || "1200", 10);
const WS_CONNECT_RETRIES = parseInt(process.env.GODOT_BROKER_CONNECT_RETRIES || "20", 10);
const WS_CONNECT_RETRY_DELAY_MS = parseInt(process.env.GODOT_BROKER_CONNECT_RETRY_DELAY_MS || "500", 10);
const REQUEST_TIMEOUT_MS = parseInt(process.env.GODOT_BROKER_REQUEST_TIMEOUT || "45000", 10);
const IDLE_EXIT_MS = parseInt(process.env.GODOT_BROKER_IDLE_EXIT_MS || "900000", 10);
const SCAN_INTERVAL_MS = 100;
const HEARTBEAT_INTERVAL_MS = 2000;

interface BrokerRequest {
  client_id: string;
  command: string;
  params: Record<string, unknown>;
}

interface GodotResponse {
  id: string;
  success: boolean;
  result?: unknown;
  error?: string;
  code?: string;
}

interface PendingRequest {
  responsePath: string;
  timer: Timer;
  processingPath: string;
}

let ws: WebSocket | null = null;
let wsReady = false;
let connectPromise: Promise<void> | null = null;
let idleTimer: Timer | null = null;
let lockHandle: Awaited<ReturnType<typeof open>> | null = null;
const pending = new Map<string, PendingRequest>();
const activeFiles = new Set<string>();

function log(message: string) {
  console.error(`[ws_broker] ${message}`);
}

async function ensureBrokerDir() {
  await mkdir(BROKER_DIR, { recursive: true });
}

function isPidAlive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

async function acquireLock(): Promise<boolean> {
  await ensureBrokerDir();
  try {
    lockHandle = await open(LOCK_PATH, "wx");
    await lockHandle.writeFile(JSON.stringify({ pid: process.pid, created_at: Date.now() }));
    return true;
  } catch {
    if (!existsSync(LOCK_PATH)) {
      return false;
    }
    try {
      const info = JSON.parse(await readFile(LOCK_PATH, "utf8")) as { pid?: number };
      if (!info.pid || !isPidAlive(info.pid)) {
        await rm(LOCK_PATH, { force: true });
        lockHandle = await open(LOCK_PATH, "wx");
        await lockHandle.writeFile(JSON.stringify({ pid: process.pid, created_at: Date.now() }));
        return true;
      }
    } catch {
      await rm(LOCK_PATH, { force: true });
      lockHandle = await open(LOCK_PATH, "wx");
      await lockHandle.writeFile(JSON.stringify({ pid: process.pid, created_at: Date.now() }));
      return true;
    }
    return false;
  }
}

async function releaseLock() {
  if (lockHandle) {
    try {
      await lockHandle.close();
    } catch {
      // ignore
    }
    lockHandle = null;
  }
  await rm(LOCK_PATH, { force: true });
}

async function writeHeartbeat() {
  await writeFile(HEARTBEAT_PATH, JSON.stringify({
    version: BROKER_VERSION,
    pid: process.pid,
    ws_url: WS_URL,
    ws_connected: wsReady && ws?.readyState === WebSocket.OPEN,
    updated_at: Date.now(),
  }));
}

function touchIdleTimer() {
  if (idleTimer) clearTimeout(idleTimer);
  idleTimer = setTimeout(() => {
    if (pending.size === 0) {
      log("Idle timeout reached, exiting");
      process.exit(0);
    }
    touchIdleTimer();
  }, IDLE_EXIT_MS);
}

async function writeResponse(responsePath: string, payload: object) {
  await writeFile(responsePath, `${JSON.stringify(payload)}\n`);
}

async function failAllPending(error: string, code = "BROKER_WS_DISCONNECTED") {
  for (const [id, req] of pending) {
    clearTimeout(req.timer);
    await writeResponse(req.responsePath, { id, success: false, error, code });
    await rm(req.processingPath, { force: true });
  }
  pending.clear();
}

async function ensureWsConnected(): Promise<void> {
  if (ws && wsReady && ws.readyState === WebSocket.OPEN) {
    return;
  }
  if (connectPromise) {
    return connectPromise;
  }

  connectPromise = (async () => {
    let lastError: unknown = null;
    for (let attempt = 1; attempt <= WS_CONNECT_RETRIES; attempt++) {
      try {
        log(`Upstream connect attempt ${attempt}/${WS_CONNECT_RETRIES}`);
        await connectWsOnce();
        return;
      } catch (error) {
        lastError = error;
        log(`Upstream connect failed: ${String(error)}`);
        if (attempt < WS_CONNECT_RETRIES) {
          await Bun.sleep(WS_CONNECT_RETRY_DELAY_MS);
        }
      }
    }
    throw lastError ?? new Error(`Failed to connect to ${WS_URL}`);
  })().finally(() => {
    connectPromise = null;
  });

  return connectPromise;
}

async function connectWsOnce(): Promise<void> {
  return await new Promise<void>((resolve, reject) => {
    let settled = false;
    const candidate = new WebSocket(WS_URL);
    const timeout = setTimeout(() => {
      if (settled) return;
      settled = true;
      try {
        candidate.close();
      } catch {
        // ignore
      }
      reject(new Error(`Timed out connecting to ${WS_URL}`));
    }, WS_CONNECT_TIMEOUT_MS);

    candidate.addEventListener("open", () => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      ws = candidate;
      wsReady = true;
      bindWs(candidate);
      log(`Connected to ${WS_URL}`);
      resolve();
    });

    candidate.addEventListener("error", () => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      reject(new Error(`Failed to connect to ${WS_URL}`));
    });

    candidate.addEventListener("close", () => {
      if (!settled) {
        settled = true;
        clearTimeout(timeout);
        reject(new Error(`Closed while connecting to ${WS_URL}`));
      }
    });
  });
}

function bindWs(socket: WebSocket) {
  socket.addEventListener("message", async (event) => {
    let parsed: GodotResponse;
    try {
      parsed = JSON.parse(String(event.data)) as GodotResponse;
    } catch {
      return;
    }

    const req = pending.get(parsed.id);
    if (!req) {
      return;
    }

    clearTimeout(req.timer);
    pending.delete(parsed.id);
    await writeResponse(req.responsePath, parsed);
    await rm(req.processingPath, { force: true });
    touchIdleTimer();
  });

  socket.addEventListener("close", async () => {
    wsReady = false;
    ws = null;
    await failAllPending("Godot WebSocket connection closed");
  });

  socket.addEventListener("error", () => {
    wsReady = false;
    ws = null;
  });
}

async function handleRequestFile(fileName: string) {
  if (!fileName.endsWith(".request.json")) {
    return;
  }
  const requestPath = `${BROKER_DIR}/${fileName}`;
  if (activeFiles.has(requestPath)) {
    return;
  }
  activeFiles.add(requestPath);

  const processingPath = requestPath.replace(".request.json", ".processing.json");
  try {
    await rename(requestPath, processingPath);
  } catch {
    activeFiles.delete(requestPath);
    return;
  }

  try {
    const request = JSON.parse(await readFile(processingPath, "utf8")) as BrokerRequest;
    const responsePath = `${BROKER_DIR}/${request.client_id}.response.json`;

    if (request.command === "__broker_ping__") {
      await writeResponse(responsePath, {
        success: true,
        result: { version: BROKER_VERSION, ws_url: WS_URL },
      });
      await rm(processingPath, { force: true });
      activeFiles.delete(requestPath);
      return;
    }

    if (!request.client_id || !request.command) {
      await writeResponse(responsePath, {
        success: false,
        error: "client_id and command are required",
        code: "BROKER_MISSING_PARAM",
      });
      await rm(processingPath, { force: true });
      activeFiles.delete(requestPath);
      return;
    }

    await ensureWsConnected();
    if (!ws || ws.readyState !== WebSocket.OPEN) {
      throw new Error("Godot WebSocket is not open");
    }

    const timer = setTimeout(async () => {
      pending.delete(request.client_id);
      await writeResponse(responsePath, {
        id: request.client_id,
        success: false,
        error: "Broker request timed out",
        code: "BROKER_TIMEOUT",
      });
      await rm(processingPath, { force: true });
    }, REQUEST_TIMEOUT_MS);

    pending.set(request.client_id, { responsePath, timer, processingPath });
    ws.send(JSON.stringify({
      id: request.client_id,
      command: request.command,
      params: request.params || {},
    }));
    touchIdleTimer();
  } catch (error) {
    try {
      const request = JSON.parse(await readFile(processingPath, "utf8")) as BrokerRequest;
      await writeResponse(`${BROKER_DIR}/${request.client_id}.response.json`, {
        id: request.client_id,
        success: false,
        error: String(error),
        code: "BROKER_CONNECT_FAILED",
      });
    } catch {
      // ignore secondary failures
    }
    await rm(processingPath, { force: true });
  } finally {
    activeFiles.delete(requestPath);
  }
}

async function scanLoop() {
  await ensureBrokerDir();
  await cleanupStaleFiles();
  await writeHeartbeat();
  setInterval(async () => {
    await writeHeartbeat();
  }, HEARTBEAT_INTERVAL_MS);
  void ensureWsConnected().catch(() => {});

  while (true) {
    const files = await readdir(BROKER_DIR);
    for (const file of files) {
      void handleRequestFile(file);
    }
    await Bun.sleep(SCAN_INTERVAL_MS);
  }
}

async function cleanupStaleFiles() {
  const files = await readdir(BROKER_DIR);
  for (const file of files) {
    if (file.endsWith(".processing.json") || file.endsWith(".response.json")) {
      await rm(`${BROKER_DIR}/${file}`, { force: true });
    }
  }
}

async function main() {
  await ensureBrokerDir();
  const acquired = await acquireLock();
  if (!acquired) {
    log(`Broker already active in ${BROKER_DIR}`);
    process.exit(0);
  }

  touchIdleTimer();
  await scanLoop();
}

main().catch((error) => {
  log(`Fatal error: ${error}`);
  releaseLock().catch(() => {});
  process.exit(1);
});

process.on("SIGINT", async () => {
  await releaseLock();
  process.exit(0);
});

process.on("SIGTERM", async () => {
  await releaseLock();
  process.exit(0);
});

process.on("exit", () => {
  try {
    unlinkSync(LOCK_PATH);
  } catch {
    // ignore cleanup errors
  }
});
