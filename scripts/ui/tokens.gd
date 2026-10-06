class_name Tokens
## Design tokens for the whole exercise - screens, HUD and the in-world CPR
## panel all pull from here so the product reads as one surface.
##
## The look is frosted glass: translucent white cards floating over the 3D
## room, generously rounded, with a brighter-than-fill white rim that catches
## the eye as a highlight and a soft dark drop shadow that lifts the card off
## the scene. Dark slate ink for text. Semantic colour only where it means
## something.
##
## Static only - never instantiated. Use as `Tokens.ACCENT`, `Tokens.style_button(...)`.

# --- Glass surfaces ---------------------------------------------------------
## Card background. Translucent white: the room stays legible through the
## panel, but the ink on it keeps full contrast.
##
## Was 0.82, and 0.62 for the soft variant. Playtest: "increase the opacity a
## bit on all diegetics." The diegetic surfaces are the ones that earn it - a
## body pill or the CPR card is read over a lit concrete floor, dark switchgear
## and a red hi-vis jacket in the same frame, and at 0.82 the thing behind a
## pill sets how legible it is. Raised rather than made solid: every one of
## these still floats in the room and has to read as glass.
const GLASS_FILL       := Color(1.0, 1.0, 1.0, 0.92)
## Quieter variant for inset rows, quiet chips and secondary buttons.
const GLASS_FILL_SOFT  := Color(1.0, 1.0, 1.0, 0.76)
## The rim. Deliberately *less* translucent than the fill - a bright, almost
## solid white edge that reads as light catching the top of the glass.
const GLASS_BORDER     := Color(1.0, 1.0, 1.0, 0.95)
## Soft ambient shadow under cards and chips.
const GLASS_SHADOW     := Color(0.05, 0.09, 0.17, 0.30)
## Shadow under interactive elements - lighter, because it sits closer.
const CHIP_SHADOW      := Color(0.05, 0.09, 0.17, 0.22)

# --- Solid card surfaces ----------------------------------------------------
## The two full-screen assessment panels are NOT frosted. They are opaque white
## cards on a dimmed room, because reading seven full sentences through the
## switchroom behind them is what made them hard to read. Everything diegetic
## stays glass - that idiom exists so the panel belongs to the room, and these
## two deliberately do not.
const CARD_FILL     := Color(1.0, 1.0, 1.0, 1.0)
## Inset rows on a white card. Slate 100 - enough to separate a row from the
## card without becoming a colour that means something.
const CARD_ROW      := Color("#f1f5f9")
## The card's own edge. Slate 200: a white rim would vanish into the fill.
const CARD_BORDER   := Color("#e2e8f0")
## A row's edge, one step quieter than the card's.
const CARD_ROW_EDGE := Color("#dbe3ec")

# --- Ink (text on glass) ----------------------------------------------------
const INK       := Color("#1e293b")  # Slate 800 - primary text
const INK_MUTED := Color("#475569")  # Slate 600 - secondary text
## Slate 500. Kept solid: at 65% alpha over white glass it blended to a wash
## hints were hard to read, and it has no use that needs to be fainter than
## INK_MUTED — just quieter.
const INK_FAINT := Color("#64748b")  # hints, footnotes

# --- Semantic ----------------------------------------------------------------
## Brand blue, matches the loader bar. Solid-fill buttons and highlights.
const ACCENT       := Color("#125b71")
const ACCENT_HOVER := Color("#1a6f8a")
## Good-on-glass variants: darker than a dark-theme pick so they still read
## on a white surface.
const SUCCESS      := Color("#16a34a")  # Green 600
const WARNING      := Color("#b45309")  # Amber 700 - readable on white
const DANGER       := Color("#dc2626")  # Red 600
const DANGER_HOVER := Color("#b91c1c")  # Red 700

# --- World (drawn over the 3D scene, not on glass) ---------------------------
## Amber 400 - hover outline on 3D objects and pulses that sit on the scene,
## where the brighter pick is the readable one.
const ATTENTION   := Color("#fbbf24")
## Dim behind blocking dialogs. Lighter than it used to be: the glass cards
## carry their own contrast now, and a lighter dim keeps the room visible.
const OVERLAY_DIM := Color(0.07, 0.10, 0.15, 0.55)
## Text that floats directly over the 3D view (toasts, prompts on scene).
const SCENE_TEXT       := Color(1, 1, 1)
const SCENE_TEXT_MUTED := Color(1, 1, 1, 0.72)
const SCENE_TEXT_DIM   := Color(1, 1, 1, 0.4)

# --- Scale -------------------------------------------------------------------
const RADIUS_SM := 6
const RADIUS_MD := 10
const RADIUS_LG := 18
const RADIUS_XL := 24

const FONT_SM := 12
const FONT_MD := 16
const FONT_LG := 24
const FONT_XL := 32


# =============================================================================
# Panels
# =============================================================================
## The standard frosted card: translucent white fill, shiny white rim, soft
## shadow, rounded corners.
static func glass_panel(radius: int = RADIUS_LG, fill: Color = GLASS_FILL) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(1)
	sb.border_color = GLASS_BORDER
	sb.shadow_color = GLASS_SHADOW
	sb.shadow_size = 18
	sb.anti_aliasing = true
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 20
	sb.content_margin_bottom = 20
	return sb


## Small glass slab for HUD readouts floating over the scene - same family,
## tighter margins, lighter shadow so it does not weigh more than a card.
static func glass_chip(radius: int = RADIUS_MD) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = GLASS_FILL
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(1)
	sb.border_color = GLASS_BORDER
	sb.shadow_color = CHIP_SHADOW
	sb.shadow_size = 10
	sb.anti_aliasing = true
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


## The opaque card behind a full-screen assessment panel. Same geometry as the
## glass family so the two read as one product; the only difference is that the
## room does not come through it.
static func card_panel(radius: int = RADIUS_XL) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD_FILL
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(1)
	sb.border_color = CARD_BORDER
	sb.shadow_color = GLASS_SHADOW
	sb.shadow_size = 24
	sb.anti_aliasing = true
	return sb


## One row on that card: opaque, quiet, and never a colour that means anything.
static func card_row(radius: int = RADIUS_LG, fill: Color = CARD_ROW) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(1)
	sb.border_color = CARD_ROW_EDGE
	sb.anti_aliasing = true
	return sb


## Back-compat alias: everything that said `Tokens.panel()` now gets glass.
static func panel(bg: Color = GLASS_FILL, radius: int = RADIUS_LG) -> StyleBoxFlat:
	return glass_panel(radius, bg)


## Back-compat alias for the HUD readout slab.
static func hud_panel() -> StyleBoxFlat:
	return glass_chip()


# =============================================================================
# Buttons
# =============================================================================
## Button face with the shared geometry: rounded, hairline rim, no shadow
## (buttons are frequent and small - shadows on every one turn to noise).
static func button(bg: Color, radius: int = RADIUS_MD) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.55) if bg.a < 0.95 else Color(1, 1, 1, 0.28)
	sb.anti_aliasing = true
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


## Styles a button in one call. Consolidates the normal/hover/pressed/focus
## plus font-colour boilerplate that every screen used to repeat.
##
##   &"primary"  solid brand blue, white text - one per screen
##   &"neutral"  glass white, ink text - lists and secondary actions
##   &"dark"     solid slate, white text - the rejection option, "Stand up"
##   &"danger"   solid red, white text - destructive/armed actions
static func style_button(b: Button, kind: StringName) -> void:
	var normal: Color
	var hover: Color
	var pressed: Color
	var font: Color
	match kind:
		&"primary":
			normal = ACCENT
			hover = ACCENT_HOVER
			pressed = ACCENT.darkened(0.15)
			font = Color.WHITE
		&"neutral":
			normal = Color(1, 1, 1, 0.66)
			hover = Color(1, 1, 1, 0.92)
			pressed = Color(0.88, 0.92, 0.97, 0.95)
			font = INK
		&"dark":
			normal = Color("#334155")  # Slate 700
			hover = Color("#475569")
			pressed = Color("#1e293b")
			font = Color.WHITE
		&"danger":
			normal = DANGER
			hover = DANGER_HOVER
			pressed = DANGER.darkened(0.15)
			font = Color.WHITE
		_:
			push_warning("Tokens.style_button: unknown kind '%s'" % kind)
			return

	b.add_theme_stylebox_override("normal", button(normal))
	b.add_theme_stylebox_override("hover", button(hover))
	b.add_theme_stylebox_override("pressed", button(pressed))
	# Focus ring: transparent fill, accent hairline - the keyboard-focus
	# affordance must survive on a locked-down machine where the pointer
	# never reliably locks.
	var focus := button(normal)
	focus.set_border_width_all(2)
	focus.border_color = ACCENT if font == INK else Color(1, 1, 1, 0.85)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_color_override("font_color", font)
	b.add_theme_color_override("font_hover_color", font)
	b.add_theme_color_override("font_pressed_color", font)
	b.add_theme_color_override("font_focus_color", font)
	b.add_theme_color_override("font_disabled_color", INK_FAINT)


# =============================================================================
# Label factory
# =============================================================================
## Standard text on glass. Consolidates the font-size + colour override pair
## every screen used to set by hand.
static func make_label(text: String, size: int = FONT_MD, colour: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	return l


## A lighter cut of the UI font, built once and shared. The project ships no
## typeface of its own, so this thins the engine's fallback face through a
## FontVariation rather than swapping typefaces — enough to let dense lists
## (the debrief's two sequence columns) read as body text instead of as a wall
## of headings.
static var _light_font: FontVariation


static func light_font() -> FontVariation:
	if _light_font == null:
		_light_font = FontVariation.new()
		_light_font.base_font = ThemeDB.fallback_font
		_light_font.variation_embolden = -0.28
	return _light_font


## `make_label` in the lighter weight, for list rows and secondary text.
static func make_light_label(text: String, size: int = FONT_SM, colour: Color = INK) -> Label:
	var l := make_label(text, size, colour)
	l.add_theme_font_override("font", light_font())
	return l


static func status_color(status: StringName) -> Color:
	match status:
		&"ok": return SUCCESS
		&"error": return DANGER
		&"warning": return WARNING
		_: return INK


# --- Symbol fallback --------------------------------------------------------
## The engine's fallback face is Open Sans SemiBold, which carries no Dingbats
## and no arrows — so the checklist tick and the debrief's whole mark
## vocabulary (✓ ✕ ↑ ↓) have no glyph in it. On desktop that is invisible:
## Godot quietly borrows them from a system font. The web export has no system
## fonts to borrow from, so in the SCORM package every one of them rendered as
## a tofu box. This face carries those four characters and nothing else; every
## other glyph still comes from Open Sans, untouched. See fonts/README.md.
const SYMBOL_FONT := preload("res://fonts/ui_symbols.ttf")

static var _symbols_installed := false


## Registers the symbol face behind the UI font. Call once before any UI draws
## — main.gd does, first thing. Idempotent, so the tool scenes that build a HUD
## without going through main can call it too.
static func install_symbol_fallback() -> void:
	if _symbols_installed:
		return
	_symbols_installed = true
	# Both faces need it: a FontVariation does not inherit the fallback chain of
	# its base_font, so the light cut would still tofu if only the base were done.
	_append_fallback(ThemeDB.fallback_font)
	_append_fallback(light_font())


static func _append_fallback(f: Font) -> void:
	if f == null or SYMBOL_FONT in f.fallbacks:
		return
	var chain: Array[Font] = f.fallbacks.duplicate()
	chain.append(SYMBOL_FONT)
	f.fallbacks = chain
