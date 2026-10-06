# fonts/

## ui_symbols.ttf

Four glyphs — ✓ U+2713, ✕ U+2715, ↑ U+2191, ↓ U+2193 — and nothing else.

Godot's built-in UI face is Open Sans SemiBold, which has no Dingbats and no
arrows. On desktop that goes unnoticed: Godot borrows the missing glyphs from a
system font. The web export has no system fonts to borrow from, so the checklist
ticks and the whole debrief mark vocabulary rendered as tofu boxes in the SCORM
package. This file is registered as a fallback on the default font so those four
characters resolve; everything else still comes from Open Sans, unchanged.

It is a subset of **DejaVu Sans**, cut to those four codepoints with fontTools.
The DejaVu licence (Bitstream Vera) permits redistribution, including
commercially, but reserves the names "DejaVu" and "Bitstream Vera" for the
originals — so the subset is renamed to "LVR UI Symbols". The upstream copyright
and licence records are preserved inside the file (name IDs 0, 13, 14).

- Copyright (c) 2003 Bitstream, Inc.; (c) 2006 Tavmjong Bah. DejaVu changes are
  in the public domain.
- Licence: http://dejavu.sourceforge.net/wiki/index.php/License

To regenerate, subset DejaVuSans.ttf to U+2713, U+2715, U+2191, U+2193 and
rename name IDs 1, 2, 4, 6, 16, 17.
