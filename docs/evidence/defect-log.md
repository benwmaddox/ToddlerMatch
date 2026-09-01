# Capture defect log

| Revision | Evidence | Finding | Severity | Resolution |
|---|---|---|---|---|
| HTML baseline | `reference/html-phone-menu.png`, `reference/html-phone-level4.png` | Reference behavior and visual hierarchy captured before migration. | evidence | Preserved as immutable source-hash-linked baseline. |
| First Stasis capture | `engine/desktop/frame-000004.png` | Headless recorder treats requested 1440x1000 dimensions as logical dimensions, so a direct non-Web desktop recording does not prove the packaged fixed-logical presentation. | major evidence defect | Rejected as desktop proof; retained to document the issue. |
| Corrected final | `engine/web-phone-menu.png`, `engine/web-phone-level4.png`, `engine/web-desktop-level4.png`, `engine/phone/frame-000004.png` | Packaged Web canvas preserves a 900x2000 portrait playfield at phone and desktop CSS sizes; real-engine framebuffer is exactly 900x2000. | pass | Accepted as runtime evidence. |
| Independent review | `visual-review.md` | No blocker/major; three polish minors remain. | minor | Accepted for this migration; listed as future visual polish without changing gameplay identity. |

