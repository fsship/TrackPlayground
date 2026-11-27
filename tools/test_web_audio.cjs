// Actual Web Audio destination measurements, not just player state or console errors.
// Uses the same test-only playwright-core dependency as test_web.cjs.
const { chromium } = require('../build/web-tests/node_modules/playwright-core');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const results = [];
const errors = [];
const server = http.createServer((req, res) => {
  const relative = new URL(req.url, 'http://localhost').pathname.slice(1) || 'index.html';
  const file = path.resolve(root, 'web-dist', relative);
  if (!file.startsWith(path.join(root, 'web-dist') + path.sep) || !fs.existsSync(file) || !fs.statSync(file).isFile()) return res.writeHead(404).end();
  const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.wasm': 'application/wasm' };
  res.writeHead(200, { 'Content-Type': types[path.extname(file)] || 'application/octet-stream' });
  fs.createReadStream(file).pipe(res);
});
let browser;
(async () => {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  browser = await chromium.launch({
    executablePath: process.env.CHROME_PATH || 'C:/Program Files/Google/Chrome/Application/chrome.exe',
    headless: true,
    args: ['--enable-unsafe-swiftshader'],
  });
  const page = await browser.newPage({ viewport: { width: 1600, height: 1000 } });
  page.on('pageerror', error => errors.push(String(error)));
  page.on('console', entry => { if (/SCRIPT ERROR:|^ERROR:/.test(entry.text())) errors.push(entry.text()); });
  await page.addInitScript(() => {
    const connect = AudioNode.prototype.connect;
    const disconnect = AudioNode.prototype.disconnect;
    const contexts = new Map();
    function meter(context) {
      if (!contexts.has(context)) {
        const analyser = context.createAnalyser();
        analyser.fftSize = 2048;
        connect.call(analyser, context.destination);
        contexts.set(context, { analyser, data: new Float32Array(2048), peak: 0, rms: 0, reads: 0 });
      }
      return contexts.get(context);
    }
    // Interpose only at the final output. Disconnecting a source still disconnects
    // it from the meter, so a broken bus graph stays broken and measures silence.
    AudioNode.prototype.connect = function (destination, ...args) {
      return connect.call(this, destination === this.context.destination ? meter(this.context).analyser : destination, ...args);
    };
    AudioNode.prototype.disconnect = function (...args) {
      if (args[0] === this.context.destination) args[0] = meter(this.context).analyser;
      return disconnect.apply(this, args);
    };
    setInterval(() => {
      for (const record of contexts.values()) {
        record.analyser.getFloatTimeDomainData(record.data);
        let energy = 0;
        for (const value of record.data) { record.peak = Math.max(record.peak, Math.abs(value)); energy += value * value; }
        record.rms = Math.max(record.rms, Math.sqrt(energy / record.data.length));
        record.reads++;
      }
    }, 10);
    window.audioProbe = {
      reset() { for (const record of contexts.values()) { record.peak = 0; record.rms = 0; record.reads = 0; } },
      read() { return [...contexts].map(([context, record]) => ({ state: context.state, peak: record.peak, rms: record.rms, reads: record.reads })); },
    };
  });
  await page.goto(process.env.WEB_URL || 'http://127.0.0.1:' + server.address().port + '/');
  await page.locator('#status').waitFor({ state: 'detached', timeout: 60000 });
  async function measure(name, audible, action, duration = 600) {
    await page.evaluate(() => audioProbe.reset());
    if (action) await action();
    await page.waitForTimeout(duration);
    const data = await page.evaluate(() => audioProbe.read());
    const peak = Math.max(0, ...data.map(x => x.peak));
    const rms = Math.max(0, ...data.map(x => x.rms));
    const valid = data.some(x => x.state === 'running' && x.reads > 0) && (audible ? rms > 0.0001 : peak < 0.0001);
    results.push({ name, valid, peak, rms, contexts: data });
    console.log(JSON.stringify(results.at(-1)));
    // Continue after a failed measurement to distinguish whole-output silence
    // from failures limited to one channel or transport.
  }
  await measure('first interaction / operation sound', true, () => page.mouse.click(774, 52));
  await page.locator('#scene-file').setInputFiles(path.join(root, 'test-results/roundtrip.railway'));
  await page.locator('#scene-dialog').waitFor({ state: 'hidden' });
  await page.waitForTimeout(700);
  await measure('paused scene', false);
  await measure('3D horn while paused', true, () => page.keyboard.press('h'), 1200);
  await page.waitForTimeout(1000);
  await measure('running train loops', true, () => page.mouse.click(925, 52), 1600);
  await page.mouse.click(925, 52);
  await page.waitForTimeout(700);
  await measure('pause stops train loops', false);
  await page.mouse.click(840, 52);
  await page.waitForTimeout(250);
  await page.mouse.click(955, 344);
  await page.mouse.click(800, 656);
  await page.waitForTimeout(300);
  await measure('mute blocks effects, horn, and loops', false, async () => {
    await page.mouse.click(925, 52);
    await page.keyboard.press('h');
  });
  await page.mouse.click(840, 52);
  await measure('unmute restores running loops', true, () => page.mouse.click(955, 344));
  await page.mouse.click(620, 428);
  await page.waitForTimeout(300);
  await measure('zero master volume silences output', false);
  await measure('raising master volume restores output', true, () => page.mouse.click(850, 428));
  await page.mouse.click(620, 578);
  await page.waitForTimeout(300);
  await measure('zero train volume silences running loops', false);
  await page.mouse.click(800, 656);
  await measure('effects still audible with train channel muted', true, () => page.mouse.click(774, 52));
  await page.locator('#scene-dialog').waitFor({ state: 'visible' });
  assert.equal(errors.length, 0, errors.join('\n'));
  assert.ok(results.every(result => result.valid), 'Web Audio destination checks failed');
})().catch(error => { errors.push(String(error.stack || error)); console.error(error); process.exitCode = 1; }).finally(async () => {
  if (browser) await browser.close();
  server.close();
  fs.writeFileSync(path.join(root, 'test-results/web-audio.json'), JSON.stringify({ results, errors }, null, 2));
});
