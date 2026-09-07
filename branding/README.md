# Application icon

`source.png` is the original opaque ImageGen artwork; `app-icon.png` is the
1024px application master. The exact prompt and source hash are in `provenance.json`.
`android/res` contains five legacy densities and an adaptive icon for Android 8+.
The adaptive foreground has 108dp bounds with motion overscan around the normal
72dp viewport, preserving the master composition under launcher masks.
`web` contains favicon sizes and an Apple touch icon. Icons are intentionally
outside the gameplay asset manifest, so they are not loaded as game textures.

Regenerate sizes with `python tools/generate-branding.py` (Pillow 12.3.0).
Normal packaging uses the committed derivatives and does not require Pillow.
Use `tools/package-branded.ps1` to stage Android or web packages with their icons.
To brand a project already staged by Stasis, run
`./tools/apply-branding.ps1 -AndroidRoot dist/android/android` or
`./tools/apply-branding.ps1 -WebRoot dist/web` before building or publishing it.
Direct Stasis packaging does not invoke the project branding hook.

Android sizing reference: https://developer.android.com/develop/ui/compose/system/icon_design_adaptive
