# Meno identity

The supplied sage mark, ink-on-paper app icon, and sage wordmark are the
approved production identity. Meno uses the artwork directly rather than
reconstructing it in code.

## Production files

- `meno-mark-sage-source.png` — untouched transparent mark master.
- `meno-app-icon-source.png` — untouched ink mark on `#F4F0E8` master.
- `meno-wordmark-sage-source.png` — untouched transparent wordmark master.
- `meno-mark-sage.png` and `meno-wordmark-sage.png` — tightly cropped runtime
  assets made from those masters.

The platform launcher and launch-screen images are generated from these files.

## Earlier concept study

Meno's mark is the **Open Loop**: one calm, deliberately uneven line that forms
a lowercase `m` and remains open at its end. It represents an unfinished
thought and the journal entry still to come.

## Recommended direction

The concept sheet explores six closely related rhythms. **03 · Quiet Rise** is
the production master because its unequal arches remain recognizable at 16 px,
its open terminal is clear without becoming a flourish, and its silhouette does
not read like a typeset glyph.

## Files

- `meno-concepts.svg` — six studies, size checks, app-icon context, and lockup.
- `meno-mark.svg` — transparent, single-color vector master.
- `meno-app-icon.svg` — ink mark on the warm paper field.
- `meno-lockup.svg` — primary horizontal lockup.
- `meno-lockup-reversed.svg` — paper-colored lockup on ink.
- `png/meno-concepts-1600.png` — review-ready concept sheet.
- `png/meno-mark-{16,32,64,512,1024}.png` — transparent size exports.
- `png/meno-app-icon-1024.png` — warm-paper launcher source.
- `png/meno-lockup*-preview-1024.png` — review previews; use the SVGs as
  production lockup masters.

## Usage

- Ink: `#262923`
- Paper: `#FFFCF5`
- Supporting background: `#F7F6F1`
- Supporting sage: `#AAB6A8` (never required to reproduce the logo)
- Keep clear space around the mark equal to at least half the first arch width.
- Use the standalone mark at 16 px or larger. Below 16 px, use the solid mark
  without the wordmark and verify it on the actual display.
- The lockup uses Georgia with Times New Roman and generic serif fallbacks.
  Preserve the supplied font stack and `2` SVG-unit tracking when editing live
  text. Convert the wordmark to outlines before sending to a production vendor
  that cannot guarantee Georgia.
- Do not add gradients, shadows, outlines, texture, enclosing rings, or extra
  symbols. Do not algorithmically randomize the stroke.

The Open Loop SVGs below are retained as an earlier exploration and are not used
by the application.
