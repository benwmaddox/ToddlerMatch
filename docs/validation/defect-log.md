# Migration defect log

| Defect | Resolution/evidence |
|---|---|
| Checked-in vendor snapshot differed from pinned nightly. | Ran pinned vendor update; `stasis.json` now records official snapshot hash `0796f6b8...5ed89`; vendor status is current. |
| Restored stdlib removed stale HostFrame and sprite helpers. | Runtime now reads compiler-owned host snapshot accessors and emits scaled sprites with `gfx_cmd_sprite`; `stasis check` passes. |
| Browser audio could initialize only after startup, leaving prompt MP3 requests unsubmitted. | First successful `audio_init`, including a pointer unlock, now submits all three bounded prompt assets; prompt replay uses the loaded goal asset. |
| Web audio presentation committed a prompt revision before asynchronous MP3 decode completed, permanently dropping that prompt. | Prompt revisions now remain pending until the current asset is ready and `audio_play` returns a voice; deterministic tests exercise the pending/retry path while procedural cues retain immediate commit semantics. |
| Number goal and settings identity used source-less SVGs. | Deleted both SVGs and manifest/runtime references; number goal uses current runtime number text and settings uses runtime geometry plus `MENU`. |
| Shuffle test asserted only a revision counter. | Added deterministic card-identity assertions proving unmatched movement and matched-slot preservation. |
| PR CI restored an arbitrary newest nightly and ran only vendor/check. | CI checks out the exact PR head, restores `stasis.json`'s pinned release, then runs vendor, fmt, check, test, SVG audit, and Web package smoke. |
| First-Stasis pre-correction capture requested. | Blocked: after correct vendor restoration that source does not compile against the pinned immutable nightly. No mislabeled capture was created. |
| Signed Android APK audit requested. | Android arm64 packaging/AOT passed; local APK completion blocked by unavailable stable keystore and absent pinned Gradle dependency checkout. |
| Publication into MaddoxLabs was previously described as complete. | Publication is deferred by human direction. Standalone Web evidence now comes directly from `dist/final-web`; no Labs wrapper or package copy is part of this delivery, and the legacy Labs route remains unchanged. |
