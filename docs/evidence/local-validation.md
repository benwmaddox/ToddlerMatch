# Local validation record

Validated on Windows on 2026-08-31 against the freshly restored official Stasis `nightly-20260831-270` toolchain.

## Passing commands

- `stasis fmt --check`
- `stasis check`
- `stasis test` — 9/9 deterministic tests passed.
- `stasis package-web --output dist/final-web` — packaged Web output and 900x2000 manifest smoke passed.
- `stasis package-mobile --target android-arm64 --output dist/final-android` — generated the Android arm64 AOT host package.
- `tools/promote-vector-assets.ps1 -Check` — 33 canonical SVGs matched source, canonical bytes, manifests, and hashes.
- `audit_game_svg.py assets --profile vector-origin --fail-on-forbidden` — no forbidden elements or external references.
- packaged Web Playwright smoke — phone and desktop flows rendered with no page errors; pointer interaction advanced to Level 4.

The generated Android package was inspected for `applicationId 'com.maddoxlabs.toddlermatch'`, `versionName '1.0.0'`, `abiFilters 'arm64-v8a'`, and `android:screenOrientation="sensorPortrait"`. A local APK build was not attempted because the host does not have the required Android SDK/NDK components; the pinned CI job installs those components and builds/signs the APK.

## Bounded desktop packaging diagnosis

The exact local package attempt was run from a Visual Studio developer environment:

```text
stasis package --target windows-x64 --output dist/final-windows
```

The generated host's CMake configure stopped with:

```text
No CMAKE_C_COMPILER could be found.
No CMAKE_CXX_COMPILER could be found.
```

`cl.exe` was independently present in that same developer shell. No generated-host or Stasis runtime files were patched and no validation was weakened. The exact-head Windows GitHub Actions lane is the authoritative proof for Windows packaging because it provisions the supported MSVC environment on a clean runner.
