// Renders the README images from the HTML sources in this folder.
//
//   node docs/images/src/render.mjs            (needs Playwright: npm i -g playwright && npx playwright install chromium)
//
// Each <name>.html becomes docs/images/<name>.png at 2x resolution. The element with id="shot" is captured.
import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

// Use a local Playwright if there is one, otherwise the globally installed one.
const require = createRequire(import.meta.url);
let playwright;
try { playwright = require('playwright'); }
catch { playwright = require(path.join(execSync('npm root -g').toString().trim(), 'playwright')); }
const { chromium } = playwright;

const srcDir = path.dirname(fileURLToPath(import.meta.url));
const outDir = path.resolve(srcDir, '..');
const only = process.argv.slice(2);

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1400, height: 1000 }, deviceScaleFactor: 2 });

for (const file of fs.readdirSync(srcDir).filter((f) => f.endsWith('.html'))) {
  const name = path.basename(file, '.html');
  if (only.length && !only.includes(name)) continue;
  await page.goto(pathToFileURL(path.join(srcDir, file)).href);
  await page.evaluate(() => document.fonts.ready);
  const shot = page.locator('#shot');
  const out = path.join(outDir, `${name}.png`);
  await shot.screenshot({ path: out, omitBackground: true });
  console.log(`rendered ${path.relative(process.cwd(), out)}`);
}

// The app icon (used by the Claude Desktop extension and the Claude Code plugin).
if (!only.length || only.includes('icon')) {
  const iconSvg = path.resolve(srcDir, '../../../packaging/mcpb/icon.svg');
  const iconPage = await browser.newPage({ viewport: { width: 512, height: 512 }, deviceScaleFactor: 1 });
  await iconPage.goto(pathToFileURL(iconSvg).href);
  for (const out of ['packaging/mcpb/icon.png', 'plugin/.claude-plugin/icon.png']) {
    const target = path.resolve(srcDir, '../../..', out);
    await iconPage.screenshot({ path: target, omitBackground: true, clip: { x: 0, y: 0, width: 512, height: 512 } });
    console.log(`rendered ${out}`);
  }
}

await browser.close();
