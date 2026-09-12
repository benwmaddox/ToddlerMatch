# Standalone validation evidence

Validated 2026-09-04 from ToddlerMatch source commit `0120d5993abb487e85082339957be53081093f2e` plus the documented standalone worktree changes.

## Toolchain and commands

- Pinned release: `nightly-20260831-270`; `.release-toolchain/stasis.exe --version` reported `stasis 0.1.0`; executable SHA-256 `0325917cf08a316e1d3635516e917e1b1d1b927525e2a7d8c8a828047bad9d34`.
- `stasis vendor update --workspace <repo>` restored source-only stdlib content and recorded official snapshot SHA-256 `0796f6b89883c2f578c5618e9b6c53427a3b34e9887e3b59866d9b5fc4d5ed89`; final `vendor status` reported current.
- `stasis fmt --check`, `stasis check`, and `stasis test` passed. Tests: 14 passed, including deterministic generation, matched-slot-preserving shuffle movement, reset/replay behavior, async prompt-presentation retry, procedural-cue commit behavior, transition pacing, bounded state, and inclusive 900x2000 mapping boundaries.
- `tools/promote-vector-assets.ps1 -Check` passed for 32 vector-origin SVGs (5,659 canonical bytes; optimizer config SHA-256 `7ef16b603d12085671be1e90a8198d7f8a30f21f4724ae2d91cca2f2b4b3ef52`). The game-svg-generation audit reported 4,890 deterministic-gzip bytes, 5 paths, 15 approximate commands, and no forbidden tags or external references.
- `stasis package --target web --out dist/final-web` and `stasis package --target desktop --out dist/final-desktop` passed. `stasis package-mobile --target android-arm64 --out dist/final-android-post-audio --workspace <repo>` passed and emitted the final post-audio AOT Gradle project with namespace and application ID `com.maddoxlabs.toddlermatch` plus `abiFilters 'arm64-v8a'`.

## Package measurements

| Output | Files | Bytes | Representative SHA-256 |
|---|---:|---:|---|
| Web package | 42 | 339,791 | `game.js` `df53cace773fc2cfab11e0053bd23ae00f94b6388a89d7539373dff5ed1eeeca`; `game.wasm` `ce3a49fc3e5fa3e2d76ad687a4970b9dae3fcd0485d7fdc5bff27557b62fd8cb`; `index.html` `dbf015ec688c592ff93a006bc7c6a9eaeb7ebfb9e9c4e6d8894c88bde3d7f6b5` |
| Windows desktop package | 41 | 2,795,896 | `ToddlerMatch.exe` `749741fddab5a8bbeeb6b5c00f0227f65714bf210970a3b7599c4620c4276908` |
| Android arm64 project/AOT output | 275 | 2,934,325 | Final post-audio architecture, namespace, application ID, and ABI contract audited from generated Gradle/AOT files; no APK was produced locally. |

Publication into MaddoxLabs is deferred by human direction. The standalone package remains in this repository, no generated package or wrapper is copied into Labs, and the legacy MaddoxLabs match route remains unchanged.

## Captures and inspection

- `legacy-baseline-1440x900.png` is a Playwright capture of the Git baseline legacy HTML blob `5446d7a8521eb47d814ebbd6c5eb4d577bf0c17f` (26,795 bytes), served from a temporary archive. Capture SHA-256: `d0cd8de9ac0183a23962529f627db15bc37dc907555504d0426eb767dd6ffdf4`.
- `final-level4-900x2000.png` and `final-settings-900x2000.png` are losslessly compressed frame 30 outputs from deterministic Stasis recording scripts. SHA-256: `3d00586909ef6988767e45004a54f87ec7f44577f7c1e5be6531e5bd1c51942d` and `b65bcbc0fd2a4f38a747bb29549ab59155cb82b8f62fa3562a6cb68e6fa2febf`.
- `web-level4-desktop-1440x900.png` and `web-settings-desktop-1440x900.png` are Playwright captures of `dist/final-web` served directly over localhost with no wrapper. SHA-256: `7687dec639f5f8ca679177975b2b997b1b377c5beb2773b602bfb4ac422d828c` and `e5d2fe7bb68407bb09bc25811afd0f6671095423520c39f47b3851fce9b0820b`.

Semantic review confirmed the level-four target, prompt, 3x3 option grid, and runtime `MENU` control; the settings overlay, 80% slider, and `DONE` control were centered and readable. At the direct 1440x900 viewport, Playwright measured the fitted standalone canvas at 405x900 pixels (9:20), centered at x=517.5 with no Labs shell or iframe. The served package reported zero console errors and every requested resource returned HTTP 200, including WebAssembly, all 32 SVGs, and all three prompt MP3s. Chromium logged one expected autoplay-policy warning before the first user gesture; no failed resource or game error was reported. Headless Chromium exposed no audio output source, so audible playback was not claimed; the two deterministic presentation tests prove that pending prompt revisions retry while procedural cues commit immediately. The legacy capture logged one expected favicon 404 and no game-resource error.

The requested first-Stasis-revision capture could not truthfully be produced. After repairing vendor from the pinned release, the pre-correction HEAD source did not compile because it imported the removed root `host_frame.stasis`, used the removed `HostFrame.refresh` wrapper, and called the removed `draw_sprite` helper. Those compatibility defects had to be corrected before the real engine could render; no pre-correction framebuffer is claimed.

## Android limitation

The local SDK 36, JDK 17, and `apksigner` prerequisites were present. A signed APK audit could not be completed because `vendor/android-deps/gradle-8.11.1` was absent and, decisively, the stable `WEEKLY_ANDROID_DEBUG_KEYSTORE_PATH` secret material was unavailable locally. The weekly workflow provisions both pinned dependencies and the stable base64 keystore secret before building, then verifies the signer digest and presence of `lib/arm64-v8a/*.so`.
