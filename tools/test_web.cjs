// Run after Export.ps1 and Start.ps1 -Test. Test-only dependency:
// npm install --prefix build/web-tests --no-audit --no-fund --ignore-scripts playwright-core
const { chromium } = require('../build/web-tests/node_modules/playwright-core');
const assert = require('node:assert/strict');
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const output = path.join(root, 'test-results');
const scene = fs.readFileSync(path.join(output, 'roundtrip.railway'));
const expected = JSON.parse(scene);
const requests = [];
const checks = [];
const errors = [];
const prefix = '/nested/railway/app/';
const mime = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css', '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.png': 'image/png' };
function check(value, description) { assert.ok(value, description); checks.push(description); console.log('PASS: ' + description); }
function listen(server) { return new Promise(resolve => server.listen(0, '127.0.0.1', resolve)); }
const server = http.createServer((req, res) => {
  const pathname = new URL(req.url, 'http://localhost').pathname;
  requests.push(pathname);
  if (pathname === '/nested/railway/layouts/demo.railway') return res.writeHead(200, { 'Content-Type': 'application/json' }).end(scene);
  if (pathname.endsWith('/slow.railway')) {
    const timer = setTimeout(() => res.writeHead(200).end(scene), 3000);
    req.on('close', () => clearTimeout(timer));
    return;
  }
  if (!pathname.startsWith(prefix)) return res.writeHead(404).end('not found');
  const relative = pathname.slice(prefix.length) || 'index.html';
  const filename = path.resolve(root, 'web-dist', relative);
  if (!filename.startsWith(path.join(root, 'web-dist') + path.sep) || !fs.existsSync(filename) || !fs.statSync(filename).isFile()) return res.writeHead(404).end('not found');
  res.writeHead(200, { 'Content-Type': mime[path.extname(filename)] || 'application/octet-stream' });
  fs.createReadStream(filename).pipe(res);
});
const crossOrigin = http.createServer((req, res) => {
  if (req.url === '/cors.railway') res.setHeader('Access-Control-Allow-Origin', '*');
  res.writeHead(200, { 'Content-Type': 'application/json' }).end(scene);
});
let browser;
(async () => {
  await listen(server);
  await listen(crossOrigin);
  const base = 'http://127.0.0.1:' + server.address().port + prefix;
  const remote = 'http://127.0.0.1:' + crossOrigin.address().port;
  const executablePath = process.env.CHROME_PATH || 'C:/Program Files/Google/Chrome/Application/chrome.exe';
  browser = await chromium.launch({ executablePath, headless: true, args: ['--enable-unsafe-swiftshader'] });
  const page = await browser.newPage({ viewport: { width: 1600, height: 1000 }, acceptDownloads: true });
  page.setDefaultTimeout(30000);
  page.on('pageerror', error => errors.push(String(error)));
  page.on('console', entry => {
    if (/SCRIPT ERROR:|^ERROR:/.test(entry.text())) errors.push(entry.text());
  });
  await page.goto(base);
  await page.locator('#status').waitFor({ state: 'detached', timeout: 60000 });
  check(await page.evaluate(() => GODOT_CONFIG.executable === 'index' && !crossOriginIsolated), 'nested directory starts without isolation headers');

  async function open() {
    await page.mouse.click(774, 52);
    await page.locator('#scene-dialog').waitFor({ state: 'visible' });
  }
  async function download() {
    const pending = page.waitForEvent('download');
    await page.mouse.click(708, 52);
    const file = await pending;
    check(file.suggestedFilename().endsWith('.railway'), 'save downloads a .railway file');
    return JSON.parse(fs.readFileSync(await file.path(), 'utf8'));
  }
  async function upload(content, name = 'layout.railway') {
    await open();
    await page.locator('#scene-file').setInputFiles({ name, mimeType: 'application/json', buffer: Buffer.from(content) });
  }
  async function url(value) {
    if (!(await page.locator('#scene-dialog').isVisible())) await open();
    await page.locator('#scene-url').fill(value);
    await page.locator('#scene-load').click();
  }
  async function errorMessage(pattern) {
    await page.waitForFunction(source => new RegExp(source).test(document.getElementById('scene-message').textContent), pattern);
    check(await page.locator('#scene-dialog').isVisible(), 'failed load leaves dialog available for retry');
  }
  const blank = await download();
  check(blank.parts.length === 0 && blank.trains.length === 0, 'blank startup exports a valid empty scene');
  await upload(scene, '本地铁路.railway');
  await page.locator('#scene-dialog').waitFor({ state: 'hidden' });
  const imported = await download();
  check(imported.parts.length === 48 && imported.trains.length === 2, 'local upload restores 48 tracks and two trains');
  check(imported.scenery.some(item => item.definition === 'alpine:water_tower'), 'bundled Mod and GLB scenery survive export and import');
  check(imported.camera.yaw === expected.camera.yaw, 'import restores the saved camera');
  await page.screenshot({ path: path.join(root, 'screenshots/web-scene.png') });

  await page.mouse.click(925, 52);
  await page.keyboard.press('h');
  await page.waitForTimeout(1800);
  await page.mouse.click(925, 52);
  const running = await download();
  check(running.trains[0].distance_m > imported.trains[0].distance_m, 'browser simulation resumes, advances trains, and pauses');
  await upload(scene);
  await page.locator('#scene-dialog').waitFor({ state: 'hidden' });

  await upload('invalid json');
  await errorMessage('不是有效场景文件');
  await page.locator('#scene-cancel').click();
  assert.deepEqual(await download(), imported);
  check(true, 'malformed upload leaves the scene unchanged');
  const badRoute = structuredClone(expected);
  badRoute.trains[0].route[0].edge = '99999:0';
  await upload(JSON.stringify(badRoute));
  await errorMessage('不存在的轨道');
  await page.locator('#scene-cancel').click();
  assert.deepEqual(await download(), imported);
  check(true, 'invalid train route leaves the scene unchanged');

  await url('../layouts/demo.railway');
  await page.locator('#scene-dialog').waitFor({ state: 'hidden' });
  check((await download()).parts.length === 48, 'relative URL resolves from the deployed subdirectory');
  await url(remote + '/cors.railway');
  await page.locator('#scene-dialog').waitFor({ state: 'hidden' });
  check((await download()).trains.length === 2, 'cross-origin URL with CORS loads successfully');
  await url(remote + '/blocked.railway');
  await errorMessage('CORS');
  await url('./missing.railway');
  await errorMessage('HTTP 404');
  await url('file:///C:/scene.railway');
  await errorMessage('只支持 HTTP/HTTPS');
  await page.screenshot({ path: path.join(root, 'screenshots/web-import-dialog.png') });
  await url('./slow.railway');
  await page.locator('#scene-cancel').click();
  await upload(JSON.stringify(blank));
  await page.locator('#scene-dialog').waitFor({ state: 'hidden' });
  await page.waitForTimeout(3500);
  check((await download()).parts.length === 0, 'cancelled URL cannot replace a later local upload');

  const previousRequests = requests.length;
  await page.goto(base + '?scene=' + encodeURIComponent('../layouts/demo.railway'));
  await page.locator('#status').waitFor({ state: 'detached', timeout: 60000 });
  await page.waitForFunction(() => document.getElementById('scene-message').textContent.includes('场景已打开'));
  check((await download()).parts.length === 48, 'scene query parameter loads automatically on startup');
  check(requests.slice(previousRequests).some(url => url.endsWith('/layouts/demo.railway')), 'query parameter requests the resolved scene URL');
  check(requests.filter(url => /\.(js|css|wasm|pck|png)$/.test(url)).every(url => url.startsWith(prefix)), 'all runtime asset requests stay under the deployment subdirectory');
  check(errors.length === 0, 'no JavaScript or Godot runtime errors');
})().catch(error => {
  errors.push(String(error.stack || error));
  console.error(error);
  process.exitCode = 1;
}).finally(async () => {
  if (browser) await browser.close();
  server.close();
  crossOrigin.close();
  fs.writeFileSync(path.join(output, 'web.json'), JSON.stringify({ checks: checks.length, failures: errors.length, passed: checks, errors, requests }, null, 2));
});
