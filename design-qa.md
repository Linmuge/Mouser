# Mouser Native Design QA

## Comparison target

- Source visual truth: `design-demos/screenshots/precision-object-detailed/implementation-buttons-no-rules.png`, together with the user's direction that the title bar and content background should read as one continuous macOS window surface.
- Light implementation: `design-demos/screenshots/precision-object-detailed/implementation-shared-window-surface-light.png`.
- Dark implementation: `design-demos/screenshots/precision-object-detailed/implementation-shared-window-surface-dark.png`.
- Combined light comparison: `design-demos/screenshots/precision-object-detailed/comparison-window-surface-light-before-after.png`.
- Viewport: native compact window at 1052 x 652 points, captured at 1052 x 652 pixels (1x).
- State: MX Master 3S preview, button mapping selected; both light and dark appearance inspected.
- Density normalization: source and implementation use the same native window dimensions and capture density. No scaling was needed before comparison.

## Fidelity surfaces

- Fonts and typography: system font, weights, hierarchy, line height, and truncation are unchanged. Title-bar labels remain optically centered and legible in both appearances.
- Spacing and layout rhythm: title-bar height, content offsets, inspector geometry, stage composition, and bottom dock remain unchanged. Removing the extra title-bar layer does not shift controls or content.
- Colors and visual tokens: the title bar now exposes the same adaptive `PrecisionWindowSurface` as the workspace. The previous local gradient and ultra-thin material are gone, eliminating the light-mode tone jump and dark-mode overlay difference.
- Image quality and asset fidelity: the existing app icon and MX Master artwork are unchanged, sharp, correctly masked, and consistently scaled.
- Copy and content: all labels, controls, settings, and navigation destinations remain unchanged.

## Full-view comparison evidence

The combined light image places the earlier implementation on the left and the revised implementation on the right. In the earlier image, the top 58-point title-bar region has a brighter material treatment than the workspace beneath it. In the revised image, one adaptive surface extends continuously from the top edge through the content area, with no boundary or color step. The dark capture confirms the same treatment under dark appearance.

## Focused region comparison evidence

A separate crop was not needed: the defect spans the complete title-bar width, and the full-size 1052 x 652 side-by-side comparison shows the entire boundary at readable 1x density. Controls and typography were additionally inspected in the individual light and dark captures.

## Comparison history

1. Earlier P2: `PrecisionTitleBar` drew its own gradient over `.ultraThinMaterial`, while `PrecisionWindowSurface` drew a separate solid adaptive surface for the workspace.
   Impact: two independently composited surfaces created an obvious horizontal tone change below the title bar, especially in light appearance.
   Fix: removed the title bar's local background, gradient, material, and duplicate color-scheme token. The title bar now remains transparent over the single full-window surface.
   Post-fix evidence: `comparison-window-surface-light-before-after.png` and `implementation-shared-window-surface-dark.png`.

## Findings

- No actionable P0, P1, or P2 differences remain for the requested window-surface unification.
- P3: the purple screen-sharing indicator in the upper-left corner is a macOS overlay and is not part of Mouser.

## Interaction and accessibility checks

- Device menu, appearance menu, title, inspector controls, and bottom navigation remain present in the accessibility tree.
- Light and dark appearance changes render the same continuous surface structure.
- Traffic-light controls remain visible and retain native window behavior.
- No new focus, contrast, motion, clipping, or hit-target regressions were observed.

## Automated verification

- Focused native visual tests: 20 passed.
- Full native regression: 169 tests in 27 suites passed.

final result: passed
