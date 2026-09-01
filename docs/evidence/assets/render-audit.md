# SVG render audit

The representative sheet `contrast-actual-size.png` renders six independent canonical components at 112 logical pixels over white and `#202633` backgrounds. It covers primitive, concave, complex, multicolor, and stroked-path assets. All silhouettes remain structurally intact with genuine transparent backgrounds; no raster matte or clipping appears.

Colored shapes remain readable on both backgrounds. The dark number goal intentionally has low contrast on the dark audit row because black is a gameplay color and the runtime contract always places target, goal, and choice assets on opaque white cards. Packaged Web and exact-framebuffer captures confirm that required consumer context. The audit therefore records palette behavior without changing the reference-faithful black asset.

Actual gameplay display sizes (goal 152 logical pixels; shapes up to 218 logical pixels) were reviewed in the phone and desktop engine captures listed by the parent evidence index.
