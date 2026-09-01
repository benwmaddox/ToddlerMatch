# Migrated reference behavior

The original MaddoxLabs page chooses one target and one rule (`color`, `shape`, or `number`), guarantees at least one matching choice, and retires each correct choice until all matches are found. Correct selections play a short bright tone. A wrong Level 1 choice shakes in place; wrong choices in Levels 2–4 shuffle the remaining unmatched cards. Completing a round hides the prompt, plays a three-note win cue, bounces choices away in order, waits five seconds, and fades in a new prompt.

| Level | Numbers | Colors | Shapes | Choices | Wrong answer |
|---|---:|---|---|---:|---|
| 1 | 1–6 | red, green, blue, yellow | circle, square, triangle, hexagon, star | 6 | shake selected card |
| 2 | 1–6 | same | same | 6 | shuffle unmatched cards |
| 3 | 1–15 | adds black | adds curvy line | 6 | shuffle unmatched cards |
| 4 | 1–15 | same as Level 3 | same as Level 3 | 9 | shuffle unmatched cards |

The Stasis migration keeps this loop while replacing browser speech synthesis with an immediate, platform-consistent three-tone prompt motif. Tapping the prompt replays that motif. Dynamic labels and all numbers remain runtime text rendered from the checked-in Basic font.

Theory mapping: pointer-up becomes one bounded intent; deterministic rules update the root state once; audio events are queued from accepted intents; rendering reads state without advancing it. The closest tempting alternative—letting render timers or host randomness decide the next round—would make replay, recreation, and tests diverge. A future fifth level belongs in `configure_level` and the tested generation bounds, not in input or rendering.

