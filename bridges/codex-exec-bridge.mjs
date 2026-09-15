#!/usr/bin/env node
// Minimal stdio MCP server that fronts a single `codex exec` call.
//
// Why this exists: as of Codex CLI 0.154.0, `codex mcp-server` (Codex
// exposing itself as an MCP server) was removed — Codex now only ships
// `codex mcp` (Codex as an MCP *client*) and `codex app-server` (its own
// JSON-RPC protocol, not MCP). `codex exec` — one-shot, non-interactive,
// still present — is the only thing left that fits "Claude Code calls
// Codex and gets an answer back". This script is the missing adapter: it
// speaks MCP on stdio to Claude Code, and shells out to `codex exec` per
// call.
//
// One MCP tool: `codex_exec`. Which Codex profile it uses comes from the
// CODEX_BRIDGE_PROFILE env var set per `.mcp.json` entry (qa/security) —
// never hardcoded here, so this one file backs both bridges.

import { spawn } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createInterface } from "node:readline";

const PROFILE = process.env.CODEX_BRIDGE_PROFILE;
const ROLE = process.env.CODEX_BRIDGE_ROLE || PROFILE || "codex";
const DEFAULT_TIMEOUT_MS = 600_000;

function send(message) {
  process.stdout.write(JSON.stringify(message) + "\n");
}

function replyResult(id, result) {
  if (id === undefined) return; // notification, no reply expected
  send({ jsonrpc: "2.0", id, result });
}

function replyError(id, code, message) {
  if (id === undefined) return;
  send({ jsonrpc: "2.0", id, error: { code, message } });
}

function runCodexExec(prompt, { cwd, timeoutMs } = {}) {
  return new Promise((resolve, reject) => {
    if (!PROFILE) {
      reject(new Error("CODEX_BRIDGE_PROFILE is not set for this bridge instance"));
      return;
    }

    let workDir;
    try {
      workDir = mkdtempSync(join(tmpdir(), "codex-bridge-"));
    } catch (err) {
      reject(err);
      return;
    }
    const outFile = join(workDir, "last-message.txt");
    const args = ["exec", "--profile", PROFILE, "--json", "-o", outFile, prompt];

    const child = spawn("codex", args, {
      cwd: cwd || process.cwd(),
      stdio: ["ignore", "pipe", "pipe"],
    });

    let stderr = "";
    let stdout = "";
    child.stdout.on("data", (d) => (stdout += d));
    child.stderr.on("data", (d) => (stderr += d));

    const timer = setTimeout(() => {
      child.kill("SIGKILL");
    }, timeoutMs || DEFAULT_TIMEOUT_MS);

    child.on("error", (err) => {
      clearTimeout(timer);
      rmSync(workDir, { recursive: true, force: true });
      reject(new Error(`failed to launch codex: ${err.message}`));
    });

    child.on("close", (code, signal) => {
      clearTimeout(timer);
      if (signal === "SIGKILL") {
        rmSync(workDir, { recursive: true, force: true });
        reject(new Error(`codex exec timed out after ${timeoutMs || DEFAULT_TIMEOUT_MS}ms`));
        return;
      }
      if (code !== 0) {
        rmSync(workDir, { recursive: true, force: true });
        reject(new Error(`codex exec exited ${code}\n${stderr.slice(-4000)}`));
        return;
      }
      let finalMessage;
      try {
        finalMessage = readFileSync(outFile, "utf8");
      } catch {
        finalMessage = stdout || "(codex exec produced no output)";
      }
      rmSync(workDir, { recursive: true, force: true });
      resolve(finalMessage);
    });
  });
}

const TOOLS = [
  {
    name: "codex_exec",
    description:
      `Run a single non-interactive Codex turn (\`codex exec --profile ${PROFILE || "<unset>"}\`) ` +
      `acting as the ${ROLE} role, and return its final message. Each call is an independent ` +
      `process — no session/conversation state carries between calls.`,
    inputSchema: {
      type: "object",
      properties: {
        prompt: { type: "string", description: "The full prompt/task for Codex to run." },
        cwd: { type: "string", description: "Working directory for the Codex run. Defaults to this server's cwd." },
        timeout_seconds: { type: "number", description: "Override the default 600s timeout." },
      },
      required: ["prompt"],
    },
  },
];

async function handleRequest(msg) {
  const { id, method, params } = msg;
  try {
    switch (method) {
      case "initialize":
        replyResult(id, {
          protocolVersion: params?.protocolVersion || "2025-06-18",
          capabilities: { tools: {} },
          serverInfo: { name: `codex-exec-bridge:${ROLE}`, version: "0.1.0" },
        });
        return;
      case "notifications/initialized":
        return; // no reply for notifications
      case "ping":
        replyResult(id, {});
        return;
      case "tools/list":
        replyResult(id, { tools: TOOLS });
        return;
      case "tools/call": {
        const { name, arguments: args } = params || {};
        if (name !== "codex_exec") {
          replyError(id, -32602, `Unknown tool: ${name}`);
          return;
        }
        const prompt = args?.prompt;
        if (!prompt || typeof prompt !== "string") {
          replyError(id, -32602, "Missing required string argument: prompt");
          return;
        }
        try {
          const timeoutMs = args?.timeout_seconds ? Number(args.timeout_seconds) * 1000 : undefined;
          const text = await runCodexExec(prompt, { cwd: args?.cwd, timeoutMs });
          replyResult(id, { content: [{ type: "text", text }] });
        } catch (err) {
          replyResult(id, { content: [{ type: "text", text: String(err?.message || err) }], isError: true });
        }
        return;
      }
      default:
        replyError(id, -32601, `Method not found: ${method}`);
    }
  } catch (err) {
    replyError(id, -32603, String(err?.message || err));
  }
}

const rl = createInterface({ input: process.stdin, terminal: false });
rl.on("line", (line) => {
  const trimmed = line.trim();
  if (!trimmed) return;
  let msg;
  try {
    msg = JSON.parse(trimmed);
  } catch {
    return; // ignore unparseable lines rather than crashing the server
  }
  handleRequest(msg);
});
