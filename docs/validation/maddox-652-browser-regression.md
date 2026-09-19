# Maddox #652 packaged-browser regression

The optimized Web package must be exercised through the generated `index.html` so the WASM runtime, renderer, input mapping, and resource loading are covered together. The reusable runner is [`tools/maddox-652-browser-regression.mjs`](../../tools/maddox-652-browser-regression.mjs).

Build a fresh package with the pinned release SDK, then run the runner from the repository root:

```powershell
& .release-toolchain/stasis.exe package --target web --out output/maddox-652-web-332
node tools/maddox-652-browser-regression.mjs `
  --package-dir output/maddox-652-web-332 `
  --out output/playwright/maddox-652-332 `
  --playwright-module <Playwright package directory> `
  --browser chromium
```

The runner serves only the selected package on an ephemeral localhost port. It records a JSON report and screenshots for the Help flow, settings, level 1 play, and Help reopened after play. It also starts fresh pages for levels 2 and 3, clicks the deterministic source-backed matching card, then clicks option 1 to exercise the later-level wrong-card shuffle. Each scenario requires continuing host frames, no page errors, no failed requests, and no guest or GPU stop. The report records the logical rectangles from `handle_pointer`, `help_menu_link_at`, and `option_at` that each click exercised.

The release-332 validation identity is `nightly-20260917-332`, compiler SHA-256 `5d38df801c85d2dcebd70d9dab28cfd8fe95fcee7d31047e7181bb6bbbc2f81a`, and vendor tree SHA-256 `d5cd9dcf9976306a65380cedd71e517c14cf3bb79206377a30038f7b86406318`. Record the package hashes and browser report path alongside each validation receipt. Firefox runs use the same package and runner with `--browser firefox`; a run is counted only when the requested browser actually starts and produces the report.

The PR workflow job `packaged-browser-acceptance` installs Playwright `1.58.2` and its pinned Chromium and Firefox browser dependencies on Ubuntu, builds a fresh package with the manifest release, and runs the helper once for each browser. A failed browser launch or missing report fails the job; the uploaded artifact contains both JSON reports, PNG captures, and the package SHA-256 list.
