# Toddler Match

Toddler Match is a touch-first Stasis game migrated from the original MaddoxLabs browser experience. A child matches one large target by color, shape, or number, with immediate audio/visual feedback and unhurried five-second round transitions.

## Levels

- Level 1: numbers 1–6, four colors, five shapes, six choices; wrong cards shake.
- Level 2: Level 1 range; wrong cards shuffle the remaining choices.
- Level 3: numbers 1–15 plus black and the curvy line; wrong cards shuffle.
- Level 4: Level 3 range with nine choices.

Every round is deterministic from the root RNG state and always contains at least one match. The game window, render layout, and authoritative pointer contract are exactly **900×2000 logical pixels** on Web, desktop, and Android. Packaged hosts fit that portrait canvas into the available surface.

## Build

This repository pins the complete immutable Stasis release `nightly-20260831-270` (source tag commit `8414904107c0a370504ff5dedb4311b9c7e85504`) and checks in its source-only vendor snapshot.

```powershell
stasis fmt --check
stasis check
stasis test
./tools/promote-vector-assets.ps1 -Check
stasis package --target web --out dist/web
stasis package --target desktop --out dist/desktop
stasis package-mobile --target android-arm64 --out dist/android
```

`src/game.stasis` owns deterministic model, level generation, matching, shuffle, progression, settings state, input geometry, and audio events. `src/main.stasis` owns host input binding, persistent Voice Over volume, the three static prompt voiceovers, bounded procedural feedback audio, the 34-entry SVG cache, and rendering. Rendering never advances gameplay, and opening Settings freezes round timers.

The gear button opens a toddler-friendly Voice Over volume control on both screens. The generated prompt clips and their non-secret provenance live under `assets/audio/`; rerun `./tools/generate-voiceovers.ps1 -Force` with `ELEVENLABS_API_KEY` in the process environment or `D:\code\ChessTD\.env` to recreate them.

The project design framework under `docs/` records the source behavior map, design provenance, asset contracts, and runtime ownership boundaries.

## Releases

Pull requests restore the pinned toolchain and run formatting, compiler, deterministic tests, SVG promotion audits, and a Web package smoke test at the exact head SHA. The Friday/manual weekly workflow resolves one complete immutable Stasis nightly and publishes Windows x64, Linux x64, macOS arm64, Web, and Android arm64 artifacts with `SHA256SUMS.txt` and `BUILD-MANIFEST.json`. Manual runs are force builds; scheduled runs skip only when neither source nor Stasis changed.

## Application icons and branded packages

The game has its own Android launcher icon and browser favicon in `branding/`.
Stage packages with the project helper so the icon is applied after Stasis
generates its host shell:

```powershell
./tools/package-branded.ps1 -Target android-arm64 -StasisPath stasis -Out dist/android
./tools/package-branded.ps1 -Target web -StasisPath stasis -Out dist/web
```

For Android, build the staged `dist/android/android` Gradle project with the
normal Android SDK/NDK and signing configuration. The helper stages the project;
it does not install or publish an APK. Existing installed copies receive the icon
when an updated build is installed. Direct `stasis package-mobile` or `stasis
package` calls bypass project branding; use `tools/apply-branding.ps1` afterward
if generating packages manually. See `branding/README.md` for regeneration and
`branding/provenance.json` for the original artwork prompt.

## License

Game code is MIT licensed. `assets/fonts/Basic-Regular.ttf` is licensed separately under SIL OFL 1.1; its source and license are beside the file.
