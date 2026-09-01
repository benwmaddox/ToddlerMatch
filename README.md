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

`src/game.stasis` owns deterministic model, level generation, matching, shuffle, progression, input geometry, and audio events. `src/main.stasis` owns host input binding, bounded procedural audio presentation, the 33-entry SVG cache, and rendering. Rendering never advances gameplay.

The project design framework under `docs/` records the source behavior map, design provenance, asset contracts, and runtime ownership boundaries.

## Releases

Pull requests restore the pinned toolchain and run formatting, compiler, deterministic tests, SVG promotion audits, and a Web package smoke test at the exact head SHA. The Friday/manual weekly workflow resolves one complete immutable Stasis nightly and publishes Windows x64, Linux x64, macOS arm64, Web, and Android arm64 artifacts with `SHA256SUMS.txt` and `BUILD-MANIFEST.json`. Manual runs are force builds; scheduled runs skip only when neither source nor Stasis changed.

## License

Game code is MIT licensed. `assets/fonts/Basic-Regular.ttf` is licensed separately under SIL OFL 1.1; its source and license are beside the file.
