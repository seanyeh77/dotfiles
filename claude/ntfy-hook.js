#!/usr/bin/env node
// Claude Code hook (Stop and Notification events): push a message to ntfy (https://ntfy.sh, or
// your own server). install.sh copies it to ~/.config/dotfiles/claude-ntfy.js and adds it to
// ~/.claude/settings.json; the server, topic and token are in ~/.config/dotfiles/ntfy (never in
// the repo). The environment variables of the same names override that file.
//
//   NTFY_URL          server, default https://ntfy.sh
//   NTFY_TOPIC        topic (anyone who knows it can read it: make it hard to guess)
//   NTFY_TOKEN        access token, for a server that needs one (optional)
//
// It never holds Claude up: the message is sent by a detached curl, and any error is ignored.
const fs = require("fs");
const os = require("os");
const path = require("path");
const cp = require("child_process");

const cfgFile = path.join(process.env.XDG_CONFIG_HOME || path.join(os.homedir(), ".config"), "dotfiles", "ntfy");
const cfg = {};
try {
  for (const line of fs.readFileSync(cfgFile, "utf8").split("\n")) {
    const m = line.match(/^\s*(NTFY_[A-Z_]+)=(.*)$/);
    if (m) cfg[m[1]] = m[2].trim().replace(/^(["'])(.*)\1$/, "$2");
  }
} catch {}
const get = (k, d = "") => process.env[k] || cfg[k] || d;

const topic = get("NTFY_TOPIC");
if (!topic) process.exit(0);

let input = {};
try {
  input = JSON.parse(fs.readFileSync(0, "utf8") || "{}");
} catch {}

// Claude's last text in the session transcript (JSON lines)
function lastText(file) {
  let lines = [];
  try {
    lines = fs.readFileSync(file, "utf8").trim().split("\n");
  } catch {
    return "";
  }
  for (let i = lines.length - 1; i >= 0; i--) {
    let e;
    try {
      e = JSON.parse(lines[i]);
    } catch {
      continue;
    }
    const content = e.message && e.message.content;
    if (e.type === "assistant" && Array.isArray(content)) {
      const text = content.filter((c) => c.type === "text").map((c) => c.text).join("\n").trim();
      if (text) return text;
    }
  }
  return "";
}

const ev = input.hook_event_name;
const dir = (input.cwd || process.cwd()).replace(os.homedir(), "~");
const where = `${os.hostname().split(".")[0]}:${dir}`;
let msg;
if (ev === "Notification") {
  // "Claude is waiting for your input" comes a minute after every turn: the Stop message already said so
  if (input.notification_type === "idle_prompt" || /waiting for your input/i.test(input.message || "")) process.exit(0);
  msg = { title: `Claude needs you · ${where}`, message: input.message || "Claude is waiting for you", priority: 4, tags: ["bell"] };
} else if (ev === "Stop") {
  // Every finished turn (stop_hook_active: Claude is already continuing because of a Stop hook)
  if (input.stop_hook_active) process.exit(0);
  let text = input.last_assistant_message || lastText(input.transcript_path) || "Finished";
  if (text.length > 400) text = text.slice(0, 400) + "…";
  msg = { title: `Claude is done · ${where}`, message: text, priority: 3, tags: ["white_check_mark"] };
} else {
  process.exit(0);
}

// JSON publishing (POST to the server root) keeps titles and text in UTF-8
const body = JSON.stringify({ topic, ...msg });
const args = ["-fsS", "-m", "15", "-H", "Content-Type: application/json", "-d", body];
const token = get("NTFY_TOKEN");
if (token) args.push("-H", `Authorization: Bearer ${token}`);
args.push(get("NTFY_URL", "https://ntfy.sh").replace(/\/+$/, ""));
try {
  cp.spawn(process.env.NTFY_CURL || "curl", args, { detached: true, stdio: "ignore" }).unref();
} catch {}
