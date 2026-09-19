#!/usr/bin/env node

import { createRequire } from "node:module";
import { createServer } from "node:http";
import { promises as fs, createReadStream } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const LOGICAL_WIDTH = 900;
const LOGICAL_HEIGHT = 2000;

// These coordinates mirror the source-owned logical rectangles. Keep them in
// one place so a browser receipt records which contract it exercised.
const GEOMETRY = {
  menu: { x: 795, y: 105, rect: { x: 730, y: 40, w: 130, h: 130 }, source: "src/main.stasis:handle_pointer" },
  help: { x: 450, y: 435, rect: { x: 330, y: 390, w: 240, h: 90 }, source: "src/main.stasis:draw_levels/help_menu_link_at" },
  settingsDone: { x: 450, y: 1315, rect: { x: 220, y: 1240, w: 460, h: 150 }, source: "src/main.stasis:handle_pointer" },
  level1: { x: 450, y: 625, rect: { x: 80, y: 500, w: 740, h: 250 }, source: "src/main.stasis:handle_pointer" },
  level2: { x: 450, y: 935, rect: { x: 80, y: 810, w: 740, h: 250 }, source: "src/main.stasis:handle_pointer" },
  level3: { x: 450, y: 1245, rect: { x: 80, y: 1120, w: 740, h: 250 }, source: "src/main.stasis:handle_pointer" },
  // The packaged main resets the deterministic browser seed to 395. These
  // are the match positions rendered by the release-332 source contract:
  // level 2 has matches at options 0 and 4, while level 3 matches at option 0. The helper
  // clicks each matching card before the source-backed wrong option so the
  // receipt proves retirement and the later shuffle independently.
  correctCardLevel2: { x: 450, y: 1550, rect: { x: 330, y: 1390, w: 240, h: 320 }, source: "src/game.stasis:option_x/option_y/option_at level 2 index 4 (seed 395)" },
  correctCardLevel3: { x: 174, y: 1190, rect: { x: 54, y: 1030, w: 240, h: 320 }, source: "src/game.stasis:option_x/option_y/option_at level 3 index 0 (seed 395)" },
  wrongCard: { x: 450, y: 1190, rect: { x: 330, y: 1030, w: 240, h: 320 }, source: "src/game.stasis:option_x/option_y/option_at index 1" }
};

const MIME_TYPES = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".wasm": "application/wasm",
  ".svg": "image/svg+xml",
  ".ttf": "font/ttf",
  ".mp3": "audio/mpeg",
  ".ico": "image/x-icon"
};

function parseArgs(argv) {
  const args = {
    packageDir: path.resolve(REPO_ROOT, "dist", "web"),
    outDir: path.resolve(REPO_ROOT, "output", "playwright", "maddox-652"),
    browser: "chromium",
    browserExecutable: "",
    playwrightModule: "",
    headless: true,
    noSandbox: false,
    port: 0,
    waitMs: 900,
    helpCycles: 3
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = () => {
      if (i + 1 >= argv.length) {
        throw new Error(`Missing value for ${arg}`);
      }
      i += 1;
      return argv[i];
    };
    if (arg === "--package-dir") args.packageDir = path.resolve(next());
    else if (arg === "--out") args.outDir = path.resolve(next());
    else if (arg === "--browser") args.browser = next();
    else if (arg === "--browser-executable") args.browserExecutable = path.resolve(next());
    else if (arg === "--playwright-module") args.playwrightModule = path.resolve(next());
    else if (arg === "--headful") args.headless = false;
    else if (arg === "--no-sandbox") args.noSandbox = true;
    else if (arg === "--port") args.port = Number(next());
    else if (arg === "--wait-ms") args.waitMs = Number(next());
    else if (arg === "--help-cycles") args.helpCycles = Number(next());
    else if (arg === "--help" || arg === "-h") {
      console.log(`Usage: node tools/maddox-652-browser-regression.mjs [options]

Options:
  --package-dir PATH          Packaged Web directory (default: dist/web)
  --out PATH                  PNG and JSON output directory
  --browser chromium|firefox  Playwright browser type (default: chromium)
  --browser-executable PATH   Optional browser executable override
  --playwright-module PATH    Playwright package directory when not installed locally
  --headful                   Run a headed browser (Linux CI requires Xvfb)
  --no-sandbox                Pass --no-sandbox to Chromium (for restricted runners)
  --port NUMBER               HTTP port (default: ephemeral)
  --wait-ms NUMBER            Delay after each logical click (default: 900)
  --help-cycles NUMBER        Help/menu reopen cycles (default: 3)`);
      process.exit(0);
    } else {
      throw new Error(`Unknown option: ${arg}`);
    }
  }
  if (!Number.isInteger(args.port) || args.port < 0 || args.port > 65535) throw new Error("--port must be 0..65535");
  if (!Number.isFinite(args.waitMs) || args.waitMs < 100) throw new Error("--wait-ms must be at least 100");
  if (!Number.isInteger(args.helpCycles) || args.helpCycles < 0) throw new Error("--help-cycles must be non-negative");
  if (!['chromium', 'firefox'].includes(args.browser)) throw new Error("--browser must be chromium or firefox");
  return args;
}

function loadPlaywright(moduleDir) {
  const requireFromHere = createRequire(import.meta.url);
  if (!moduleDir) {
    try {
      return requireFromHere("playwright");
    } catch (error) {
      throw new Error("Playwright is not installed. Install it or pass --playwright-module PATH to its package directory.", { cause: error });
    }
  }
  const packageRequire = createRequire(path.join(moduleDir, "package.json"));
  return packageRequire(".");
}

async function startPackageServer(packageDir, requestedPort) {
  const root = path.resolve(packageDir);
  const server = createServer(async (request, response) => {
    try {
      const requestPath = decodeURIComponent((request.url || "/").split("?", 1)[0]);
      const relative = requestPath === "/" ? "index.html" : requestPath.replace(/^\/+/, "");
      const filePath = path.resolve(root, relative);
      if (filePath !== root && !filePath.startsWith(`${root}${path.sep}`)) {
        response.writeHead(403);
        response.end("Forbidden");
        return;
      }
      const stat = await fs.stat(filePath);
      if (!stat.isFile()) throw new Error("not a file");
      response.writeHead(200, { "Content-Type": MIME_TYPES[path.extname(filePath).toLowerCase()] || "application/octet-stream", "Cache-Control": "no-store" });
      createReadStream(filePath).pipe(response);
    } catch {
      response.writeHead(404);
      response.end("Not found");
    }
  });
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(requestedPort, "127.0.0.1", resolve);
  });
  const address = server.address();
  return { server, url: `http://127.0.0.1:${address.port}/` };
}

function pointInRect(point, rect) {
  return point.x >= rect.x && point.x <= rect.x + rect.w && point.y >= rect.y && point.y <= rect.y + rect.h;
}

function verifyGeometry() {
  const checks = [
    ["menu", GEOMETRY.menu],
    ["help", GEOMETRY.help],
    ["settingsDone", GEOMETRY.settingsDone],
    ["level1", GEOMETRY.level1],
    ["level2", GEOMETRY.level2],
    ["level3", GEOMETRY.level3],
    ["correctCardLevel2", GEOMETRY.correctCardLevel2],
    ["correctCardLevel3", GEOMETRY.correctCardLevel3],
    ["wrongCard", GEOMETRY.wrongCard]
  ];
  const failures = checks.filter(([, point]) => !pointInRect(point, point.rect)).map(([name]) => name);
  if (failures.length > 0) throw new Error(`Source-backed coordinate is outside its source rectangle: ${failures.join(", ")}`);
  return checks.map(([name, point]) => ({ name, point: { x: point.x, y: point.y }, rect: point.rect, source: point.source }));
}

function numberFromDataset(dataset, key) {
  const value = Number(dataset[key] || 0);
  return Number.isFinite(value) ? value : 0;
}

async function screenshotPixels(page, points, screenshot = undefined) {
  const png = screenshot || await page.screenshot({ type: "png", fullPage: true });
  return page.evaluate(async ({ encoded, sample }) => {
    const image = new Image();
    image.src = `data:image/png;base64,${encoded}`;
    await image.decode();
    const canvas = document.createElement("canvas");
    canvas.width = image.width;
    canvas.height = image.height;
    const context = canvas.getContext("2d", { willReadFrequently: true });
    context.drawImage(image, 0, 0);
    return sample.map((point) => {
      const x = Math.max(0, Math.min(image.width - 1, Math.round(point.x)));
      const y = Math.max(0, Math.min(image.height - 1, Math.round(point.y)));
      return Array.from(context.getImageData(x, y, 1, 1).data);
    });
  }, { encoded: png.toString("base64"), sample: points });
}

async function screenshotPixel(page, point, screenshot = undefined) {
  return (await screenshotPixels(page, [point], screenshot))[0];
}

function pixelDistance(left, right) {
  return left.reduce((distance, value, index) => distance + Math.abs(value - right[index]), 0);
}

function cardProbePoints(point) {
  return [-90, 0, 90].flatMap((dx) => [-100, 0, 100].map((dy) => ({ x: point.x + dx, y: point.y + dy })));
}

async function snapshot(page) {
  return page.locator("body").evaluate((body) => ({ ...body.dataset }));
}

function diagnostics(page) {
  const state = { pageErrors: [], consoleErrors: [], requestFailures: [] };
  page.on("pageerror", (error) => state.pageErrors.push(String(error.stack || error)));
  page.on("console", (message) => {
    if (message.type() === "error") state.consoleErrors.push(message.text());
  });
  page.on("requestfailed", (request) => state.requestFailures.push({ url: request.url(), error: request.failure()?.errorText || "unknown" }));
  return state;
}

function diagnosticsHealthy(state) {
  return state.pageErrors.length === 0 && state.consoleErrors.length === 0 && state.requestFailures.length === 0;
}

function guestUnhealthy(state) {
  // gpuError is historical diagnostic state: sprite publication can record a
  // transient error before the renderer recovers. waitReady, frame progress,
  // screenshots, and browser diagnostics provide the live health evidence.
  return state.guestStopped === "true";
}

async function startupEvidence(page, diag) {
  const browser = await page.evaluate(() => {
    const canvas = document.getElementById("stasis-canvas");
    const loading = document.getElementById("stasis-loading");
    const loadingStatus = document.getElementById("stasis-loading-status");
    const error = document.getElementById("stasis-error");
    let webgl2 = false;
    let webgl2Error = "";
    try {
      webgl2 = !!canvas?.getContext?.("webgl2");
    } catch (cause) {
      webgl2Error = String(cause?.stack || cause);
    }
    return {
      dataset: { ...(document.body?.dataset || {}) },
      loading: loadingStatus?.textContent || loading?.textContent || "",
      error: error?.textContent || "",
      fontStatus: document.fonts?.status || "unavailable",
      webgl2,
      webgl2Error,
      userAgent: navigator.userAgent
    };
  });
  return { browser, diagnostics: diag };
}

async function waitReady(page, diag) {
  try {
    await page.waitForFunction(() => {
      const ready = document.body?.dataset.ready;
      return ready === "true" || ready === "false";
    }, undefined, { timeout: 15000 });
  } catch (cause) {
    const evidence = await startupEvidence(page, diag);
    throw new Error(`Packaged runtime did not publish readiness: ${JSON.stringify(evidence)}`, { cause });
  }
  const evidence = await startupEvidence(page, diag);
  if (evidence.browser.dataset.ready !== "true") {
    throw new Error(`Packaged runtime startup failed: ${JSON.stringify(evidence)}`);
  }
}

async function clickLogical(page, point, waitMs) {
  await page.mouse.click(point.x, point.y);
  await page.waitForTimeout(waitMs);
}

async function waitForFrameProgress(page, before, timeoutMs = 4000) {
  try {
    await page.waitForFunction((minimum) => Number(document.body?.dataset.frames || 0) > minimum, before, { timeout: timeoutMs });
    return true;
  } catch {
    return false;
  }
}

async function newPage(browser) {
  const context = await browser.newContext({ viewport: { width: LOGICAL_WIDTH, height: LOGICAL_HEIGHT }, deviceScaleFactor: 1 });
  const page = await context.newPage();
  return { context, page };
}

async function runHelpScenario(browser, url, outDir, args) {
  const { context, page } = await newPage(browser);
  const diag = diagnostics(page);
  const phases = [];
  try {
    await page.goto(url, { waitUntil: "networkidle" });
    await waitReady(page, diag);
    let state = await snapshot(page);
    phases.push({ name: "initial-levels", state });
    await clickLogical(page, GEOMETRY.help, args.waitMs);
    state = await snapshot(page);
    phases.push({ name: "help-initial", state });
    await page.screenshot({ path: path.join(outDir, "help-initial.png"), fullPage: true });
    for (let cycle = 1; cycle <= args.helpCycles; cycle += 1) {
      await clickLogical(page, GEOMETRY.menu, args.waitMs / 2);
      await clickLogical(page, GEOMETRY.help, args.waitMs);
      state = await snapshot(page);
      phases.push({ name: `help-reopen-${cycle}`, state });
    }
    await clickLogical(page, GEOMETRY.menu, args.waitMs / 2);
    await clickLogical(page, GEOMETRY.menu, args.waitMs);
    state = await snapshot(page);
    phases.push({ name: "settings", state });
    await page.screenshot({ path: path.join(outDir, "settings.png"), fullPage: true });
    const settingsFrame = numberFromDataset(state, "frames");
    await clickLogical(page, GEOMETRY.settingsDone, args.waitMs);
    state = await snapshot(page);
    phases.push({ name: "levels-after-settings", state });
    const settingsProgressed = numberFromDataset(state, "frames") > settingsFrame;
    await clickLogical(page, GEOMETRY.level1, args.waitMs);
    state = await snapshot(page);
    phases.push({ name: "level1-play", state });
    await page.screenshot({ path: path.join(outDir, "level1-play.png"), fullPage: true });
    await clickLogical(page, GEOMETRY.menu, args.waitMs / 2);
    await clickLogical(page, GEOMETRY.help, args.waitMs);
    state = await snapshot(page);
    phases.push({ name: "help-after-play", state });
    await page.screenshot({ path: path.join(outDir, "help-after-play.png"), fullPage: true });
    const healthy = diagnosticsHealthy(diag);
    if (!healthy) throw new Error("Help/settings/menu flow emitted browser diagnostics");
    if (!settingsProgressed) throw new Error("Settings DONE did not advance host frames");
    const stoppedPhases = phases.filter((phase) => guestUnhealthy(phase.state));
    if (stoppedPhases.length > 0) {
      const details = stoppedPhases.map((phase) => `${phase.name}(guestStopped=${phase.state.guestStopped || "false"}, gpuError=${phase.state.gpuError || "none"})`).join(", ");
      throw new Error(`Help flow stopped the guest: ${details}`);
    }
    return { status: "pass", phases, diagnostics: diag, settingsProgressed };
  } finally {
    await context.close();
  }
}

async function runShuffleScenario(browser, url, outDir, args, level) {
  const phases = [];
  const levelPoint = level === 2 ? GEOMETRY.level2 : GEOMETRY.level3;
  const correctPoint = level === 2 ? GEOMETRY.correctCardLevel2 : GEOMETRY.correctCardLevel3;
  const diagnosticsByFlow = { correct: { pageErrors: [], consoleErrors: [], requestFailures: [] }, wrong: { pageErrors: [], consoleErrors: [], requestFailures: [] } };

  // Use a fresh page for the matching card. Level 3 can have one match, so a
  // correct tap may legitimately enter PHASE_WON before the wrong-card flow.
  {
    const { context, page } = await newPage(browser);
    const diag = diagnostics(page);
    try {
      await page.goto(url, { waitUntil: "networkidle" });
      await waitReady(page, diag);
      await clickLogical(page, levelPoint, args.waitMs);
      let state = await snapshot(page);
      phases.push({ name: `level${level}-correct-before-input`, state });
      const correctBefore = numberFromDataset(state, "audioEvents");
      const correctProbe = { x: correctPoint.x - 100, y: correctPoint.y };
      const correctBeforePixel = await screenshotPixel(page, correctProbe);
      await clickLogical(page, correctPoint, args.waitMs / 2);
      state = await snapshot(page);
      phases.push({ name: `level${level}-after-correct-card`, state, sourceContract: correctPoint.source });
      const correctScreenshot = await page.screenshot({ path: path.join(outDir, `level${level}-after-correct-card.png`), fullPage: true });
      const correctAfterPixel = await screenshotPixel(page, correctProbe, correctScreenshot);
      const correctVisualChanged = pixelDistance(correctBeforePixel, correctAfterPixel) >= 10;
      phases[phases.length - 1].correctEvidence = {
        probe: correctProbe,
        beforePixel: correctBeforePixel,
        afterPixel: correctAfterPixel,
        pixelDistance: pixelDistance(correctBeforePixel, correctAfterPixel),
        visualChanged: correctVisualChanged,
        audioEventsBefore: correctBefore,
        audioEventsAfter: numberFromDataset(state, "audioEvents")
      };
      if (numberFromDataset(state, "audioEvents") <= correctBefore && !correctVisualChanged) throw new Error(`Source-backed level ${level} correct card did not commit a visible or audio event`);
      if (!diagnosticsHealthy(diag)) throw new Error(`Level ${level} correct-card flow emitted browser diagnostics`);
    } finally {
      Object.assign(diagnosticsByFlow.correct, diag);
      await context.close();
    }
  }

  // Reopen a fresh level so option 1 is guaranteed to be tested while the
  // round is active. This independently exercises the later-level shuffle.
  let frameProgressed = false;
  {
    const { context, page } = await newPage(browser);
    const diag = diagnostics(page);
    try {
      await page.goto(url, { waitUntil: "networkidle" });
      await waitReady(page, diag);
      await clickLogical(page, levelPoint, args.waitMs);
      let state = await snapshot(page);
      phases.push({ name: `level${level}-wrong-before-input`, state, sourceContract: GEOMETRY.wrongCard.source });
      const beforeWrongAudio = numberFromDataset(state, "audioEvents");
      const beforeWrong = numberFromDataset(state, "frames");
      const wrongProbes = cardProbePoints(GEOMETRY.wrongCard);
      const wrongBeforeScreenshot = await page.screenshot({ type: "png", fullPage: true });
      const wrongBeforePixels = await screenshotPixels(page, wrongProbes, wrongBeforeScreenshot);
      await clickLogical(page, GEOMETRY.wrongCard, args.waitMs);
      state = await snapshot(page);
      phases.push({ name: `level${level}-after-wrong-card`, state });
      const wrongScreenshot = await page.screenshot({ path: path.join(outDir, `level${level}-after-wrong-card.png`), fullPage: true });
      const wrongAfterPixels = await screenshotPixels(page, wrongProbes, wrongScreenshot);
      const wrongPixelDistances = wrongBeforePixels.map((pixel, index) => pixelDistance(pixel, wrongAfterPixels[index]));
      const wrongVisualChanged = wrongPixelDistances.some((distance) => distance >= 10);
      phases[phases.length - 1].wrongEvidence = {
        probes: wrongProbes,
        beforePixels: wrongBeforePixels,
        afterPixels: wrongAfterPixels,
        pixelDistances: wrongPixelDistances,
        visualChanged: wrongVisualChanged,
        audioEventsBefore: beforeWrongAudio,
        audioEventsAfter: numberFromDataset(state, "audioEvents")
      };
      const progressed = await waitForFrameProgress(page, numberFromDataset(state, "frames"), 4000);
      const afterWait = await snapshot(page);
      phases.push({ name: `level${level}-after-wrong-card-wait`, state: afterWait });
      if (numberFromDataset(state, "audioEvents") <= beforeWrongAudio && !wrongVisualChanged) throw new Error(`Source-backed level ${level} wrong card did not commit a visible or audio event`);
      if (!diagnosticsHealthy(diag)) throw new Error(`Level ${level} wrong-card flow emitted browser diagnostics`);
      if (guestUnhealthy(afterWait)) throw new Error(`Level ${level} stopped the guest`);
      if (numberFromDataset(afterWait, "frames") <= beforeWrong || !progressed) throw new Error(`Level ${level} frame counter stopped after wrong card`);
      frameProgressed = true;
    } finally {
      Object.assign(diagnosticsByFlow.wrong, diag);
      await context.close();
    }
  }
  return { status: "pass", phases, diagnostics: diagnosticsByFlow, frameProgressed };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const geometry = verifyGeometry();
  await fs.access(path.join(args.packageDir, "index.html"));
  await fs.access(path.join(args.packageDir, "game.js"));
  await fs.access(path.join(args.packageDir, "game.wasm"));
  await fs.mkdir(args.outDir, { recursive: true });
  const playwright = loadPlaywright(args.playwrightModule || process.env.PLAYWRIGHT_MODULE || "");
  const browserType = args.browser === "firefox" ? playwright.firefox : playwright.chromium;
  const launchOptions = { headless: args.headless };
  if (args.browser === "firefox") {
    // Hosted Linux runners do not expose a hardware GL device to headless
    // Firefox. Force its supported software WebGL path so this acceptance
    // still exercises the packaged WebGL2 renderer and game behavior.
    launchOptions.firefoxUserPrefs = {
      "webgl.force-enabled": true,
      "webgl.forbid-software": false
    };
  }
  if (args.browserExecutable) launchOptions.executablePath = args.browserExecutable;
  if (args.noSandbox && args.browser === "chromium") launchOptions.args = ["--no-sandbox"];
  const browser = await browserType.launch(launchOptions);
  const server = await startPackageServer(args.packageDir, args.port);
  const report = {
    packageDir: args.packageDir,
    browser: args.browser,
    browserExecutable: args.browserExecutable || null,
    url: server.url,
    viewport: { width: LOGICAL_WIDTH, height: LOGICAL_HEIGHT, deviceScaleFactor: 1 },
    geometry,
    scenarios: {},
    generatedAt: new Date().toISOString()
  };
  try {
    for (const [name, runner] of [
      ["help", () => runHelpScenario(browser, server.url, args.outDir, args)],
      ["level2", () => runShuffleScenario(browser, server.url, args.outDir, args, 2)],
      ["level3", () => runShuffleScenario(browser, server.url, args.outDir, args, 3)]
    ]) {
      try {
        report.scenarios[name] = await runner();
      } catch (error) {
        report.scenarios[name] = { status: "fail", error: String(error.stack || error) };
      }
    }
  } finally {
    await fs.writeFile(path.join(args.outDir, "maddox-652-browser-report.json"), JSON.stringify(report, null, 2));
    await new Promise((resolve) => server.server.close(resolve));
    await browser.close();
  }
  const failed = Object.entries(report.scenarios).filter(([, result]) => result.status !== "pass");
  console.log(JSON.stringify({ ...report, failed: failed.map(([name]) => name) }, null, 2));
  if (failed.length > 0) process.exitCode = 1;
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
