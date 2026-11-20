#!/usr/bin/env node
// Launcher for the dayone-mcp server inside the Claude Code plugin.
//
// On first run it downloads the server binary that matches this plugin's version and this
// computer (from the GitHub release), checks it against the release's SHA256SUMS.txt, and keeps
// it in the plugin's persistent data folder. Then it runs the binary, passing MCP stdio through.
//
//   node dayone-mcp.mjs              run the MCP server (used by .mcp.json)
//   node dayone-mcp.mjs --prefetch   only download the binary if needed (used by the SessionStart hook)
//   node dayone-mcp.mjs --check      run the server's own health check
//
// IMPORTANT: stdout belongs to the MCP protocol, so this script only ever writes to stderr.

import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = 'kachihro/dayone-mcp';
const here = path.dirname(fileURLToPath(import.meta.url));
const log = (msg) => process.stderr.write(`[dayone-mcp] ${msg}\n`);

function fail(msg) {
  log(msg);
  process.exit(1);
}

const version = JSON.parse(fs.readFileSync(path.join(here, '..', '.claude-plugin', 'plugin.json'), 'utf8')).version;

const RIDS = {
  'win32-x64': 'win-x64',
  'win32-arm64': 'win-x64', // runs under Windows' x64 emulation (the Day One CLI is x64-only on Windows too)
  'darwin-arm64': 'osx-arm64',
  'darwin-x64': 'osx-x64',
  'linux-x64': 'linux-x64',
  'linux-arm64': 'linux-arm64',
};
const rid = RIDS[`${process.platform}-${process.arch}`];
const isWindows = process.platform === 'win32';
const assetName = `dayone-mcp-${rid}${isWindows ? '.exe' : ''}`;

const dataDir = process.env.CLAUDE_PLUGIN_DATA || path.join(os.homedir(), '.dayone-mcp');
const binDir = path.join(dataDir, 'bin');
const exePath = path.join(binDir, version, isWindows ? 'DayOneMcp.exe' : 'DayOneMcp');
const downloadBase = (process.env.DAYONE_MCP_DOWNLOAD_BASE || `https://github.com/${REPO}/releases/download`).replace(/\/$/, '');

async function fetchOk(url) {
  const res = await fetch(url, { redirect: 'follow', headers: { 'User-Agent': 'dayone-mcp-launcher' } });
  if (!res.ok) throw new Error(`${url} returned HTTP ${res.status}`);
  return res;
}

async function ensureBinary() {
  if (fs.existsSync(exePath)) return exePath;
  if (!rid) throw new Error(`Unsupported platform: ${process.platform}-${process.arch}`);

  const base = `${downloadBase}/v${version}`;
  log(`Downloading dayone-mcp ${version} for ${rid} (one-off, about 40 MB)...`);

  // Expected checksum from the release.
  const sums = await (await fetchOk(`${base}/SHA256SUMS.txt`)).text();
  const line = sums.split(/\r?\n/).find((l) => l.trim().split(/\s+/)[1]?.replace(/^\*/, '') === assetName);
  if (!line) throw new Error(`${assetName} is not listed in SHA256SUMS.txt for v${version}`);
  const expected = line.trim().split(/\s+/)[0].toLowerCase();

  const bytes = Buffer.from(await (await fetchOk(`${base}/${assetName}`)).arrayBuffer());
  const actual = createHash('sha256').update(bytes).digest('hex');
  if (actual !== expected) throw new Error(`Checksum mismatch for ${assetName} (expected ${expected}, got ${actual})`);

  // Write to a temp file, then rename, so a half-finished download is never used.
  fs.mkdirSync(path.dirname(exePath), { recursive: true });
  const tmp = `${exePath}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, bytes, { mode: 0o755 });
  try {
    fs.renameSync(tmp, exePath);
  } catch (err) {
    fs.rmSync(tmp, { force: true });
    if (!fs.existsSync(exePath)) throw err; // otherwise another process (e.g. the hook) won the race
  }
  log(`Installed to ${exePath}`);

  // Tidy up binaries from older plugin versions (ignore any that are still running).
  for (const dir of fs.readdirSync(binDir)) {
    if (dir === version) continue;
    try { fs.rmSync(path.join(binDir, dir), { recursive: true, force: true }); } catch { /* still in use; next time */ }
  }
  return exePath;
}

const args = process.argv.slice(2);

if (typeof fetch !== 'function') {
  fail(`Node.js 18 or newer is needed (you have ${process.version}). Install the LTS version from https://nodejs.org`);
}

let exe;
try {
  exe = process.env.DAYONE_MCP_EXE || (await ensureBinary());
} catch (err) {
  fail(`Could not get the dayone-mcp server: ${err.message}. Check your internet connection, or see https://github.com/${REPO}#troubleshooting`);
}

if (args.includes('--prefetch')) process.exit(0);

const child = spawn(exe, args, { stdio: 'inherit', windowsHide: true });
child.on('error', (err) => fail(`Could not start ${exe}: ${err.message}`));
child.on('exit', (code, signal) => {
  if (signal) process.kill(process.pid, signal);
  else process.exit(code ?? 0);
});
for (const sig of ['SIGINT', 'SIGTERM']) {
  process.on(sig, () => child.kill(sig));
}
