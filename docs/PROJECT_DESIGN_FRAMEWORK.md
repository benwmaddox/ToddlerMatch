# Toddler Match project design framework

```yaml
project:
  id: toddler-match-stasis-v1
  product_world_intent: A calm, immediate sorting table where one big example and a small set of choices make the matching rule obvious.
  emotional_tone: cheerful, calm, chunky, encouraging, legible
  translation_intent: reference-faithful
  reference_fidelity_targets: Preserve the HTML game's six silhouettes, four/five-color identity, target-over-options hierarchy, high-contrast white cards, chunky shadows, and single-rule prompts.
  mockup_reference: The original 520px portrait HTML experience at MaddoxLabs src/toddler-games/match/index.html; it is behavior/design evidence only and is never shipped or embedded.
  source_behavior_provenance: The original MaddoxLabs HTML game defines the behavior and design baseline; this repository preserves that mapping in this framework and in the deterministic game model and tests.
  component_inventory:
    - owner: assets/shapes/<shape>-<color>.svg
      source_route: vector-origin from the existing inline SVG geometry
      bounds_anchors: 100x100 transparent canvas; centered anchor; occupied bounds follow the original points/path
      reuse_sites: target card and every option card
      interaction_state_variants: color is a separate canonical asset; matched/shake/bounce are runtime transforms and alpha
      assembly_order: card shadow, card face, number text, shape sprite
    - owner: assets/goals/color.svg and assets/goals/shape.svg
      source_route: vector-origin for color and shape; runtime text for number
      bounds_anchors: 100x100 transparent canvas; centered
      reuse_sites: prompt button
      interaction_state_variants: none; prompt fade is runtime alpha
      assembly_order: prompt face, goal mark, runtime prompt text
  component_extraction_evidence: Not applicable; the authoritative inputs are inline vectors rather than raster crops.
  deliverable_roles: Independently owned svg_direct shape/color-goal/shape-goal runtime assets; runtime owns all text, numbers, the settings button identity, cards, controls, hit targets, animations, safe areas, and layout.
  screen_asset_contract: none; no whole-screen asset is permitted
  budget_envelope: Each component <= 2 KiB raw and <= 1 KiB deterministic gzip; full canonical SVG kit <= 48 KiB raw. Path count is diagnostic under the vector-origin profile.
  asset_families:
    - name: match-shapes
      boundary: circle, square, triangle, hexagon, star, and curvy line in the level palette
    - name: goal-marks
      boundary: color and shape prompts use SVG; the number prompt and settings identity are runtime text
  camera_projection: flat orthographic 900x2000 logical canvas with no perspective
  palette_roles:
    ink: '#263238'
    red: '#ff5252'
    green: '#4caf50'
    blue: '#2196f3'
    yellow: '#f6d600'
    black: '#111111'
    card: '#ffffff'
    background: '#f0f4f8'
    shadow: '#c7d0d8'
  material_mapping: Flat paper/card surfaces; no texture, gradients, or lighting effects.
  shape_language: Bold centered primitives, generous negative space, square cards with softly rounded runtime corners.
  outline_hierarchy: Filled shapes have no outline; curvy line uses a 14-unit round stroke.
  lighting_convention: Flat color only; depth is communicated by runtime card shadows.
  rendering_dialect_calibration:
    anchors: Original HTML inline SVGs and white cards
    axes: exact silhouette, saturated palette, zero material shading, no contact shadow inside assets, sparse toddler-readable detail
    decision: Stop if any silhouette, color role, or actual-size readability differs materially from the HTML reference.
  source_profile: vector-origin
  palette_policy: locked_palette
  palette_warning_threshold: 128
  source_palette_limit: 8
  protected_color_families: red, green, blue, yellow, black, neutral-gray
  conversion_status: converted
  depth_render_order: card shadow, card face, runtime number, canonical SVG shape
  material_recipes: exact flat fills; curvy shape uses exact flat stroke
  shared_component_library: shared 100x100 viewBox and centered card placement contract
  detail_tiers: silhouettes and goal landmarks must read at 112px; no inspection-only micro-detail
  detail_readability_floor: 12 logical pixels at the smallest displayed goal mark; 30 logical pixels at shape display
  scale_footprint_padding: Shapes occupy at most 96% of 100x100; target display 220x220; option display 150x150 or 116x116 for nine choices.
  cohesion_reuse_rules:
    - Use identical geometry for every color variant.
    - Use only declared palette roles and transparent canvases.
  exclusions: [emoji, system-font-dependent identity, raster screen mockups, filters, masks, scripts, text in SVG, external references]
  reference_anchors: [circle r40, square 70x70, triangle 50/10-90/85-10/85, original hexagon/star point sets, original curvy cubic path]
  scene_comparison_gate: Render canonical assets on white and #263238 backgrounds at 48, 112, and 224 logical pixels; then exercise the real engine at its 900x2000 logical size and fitted desktop presentation.
```

Every SVG item uses `runtime_representation: svg_direct`, `stored_display_sizes: 100x100 SVG`, and `translation_intent: reference-faithful`. Shape anchors are centered; card collision and hit geometry are deliberately runtime-owned. The canonical assets are loaded once into a bounded 32-sprite cache (30 shape/color variants and two goal marks) and rasterized by Stasis at the declared logical size/device density. The asset manifest stays within Stasis's strict schema; ownership, anchor, footprint, palette, and provenance details live in this framework while hashes and encoded dimensions live in `assets/manifest.json`.
