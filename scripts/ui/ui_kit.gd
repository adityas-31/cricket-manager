class_name UIKit
extends RefCounted
## Shared look for every screen: an FM24-style dark palette tinted with the club colour,
## the app theme, and helpers for the cards and tables the screens are built from.

const BG := Color("14161b")
const SIDEBAR := Color("1a1d23")
const PANEL := Color("22262e")
const PANEL_HEADER := Color("2b3039")
const ROW_ALT := Color("272b34")
const LINE := Color("343a45")
const TEXT := Color("e8eaed")
const TEXT_DIM := Color("9aa0a6")
const POSITIVE := Color("3ecf8e")
const NEGATIVE := Color("ef5350")
const FOUR := Color("42a5f5")
const SIX := Color("b388ff")
const WARNING := Color("ffca28")


## FM-style attribute colouring for the 1-20 scale.
static func attr_colour(v: float) -> Color:
	if v >= 15.5:
		return Color("3ecf8e")
	if v >= 10.5:
		return Color("b5d957")
	if v >= 5.5:
		return Color("e8b04b")
	return Color("e0605d")


static func symbol_colour(symbol: String) -> Color:
	match symbol:
		"W":
			return NEGATIVE
		"4":
			return FOUR
		"6":
			return SIX
		"•":
			return TEXT_DIM
	return WARNING if symbol.begins_with("wd") or symbol.begins_with("nb") else TEXT


static func flat(colour: Color, radius := 4, pad_x := 10.0, pad_y := 6.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = colour
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad_x
	s.content_margin_right = pad_x
	s.content_margin_top = pad_y
	s.content_margin_bottom = pad_y
	return s


static func make_theme(accent: Color) -> Theme:
	var t := Theme.new()
	t.default_font_size = 14
	t.set_color("font_color", "Label", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	t.set_stylebox("panel", "PanelContainer", flat(PANEL, 4, 0, 0))
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())

	for type in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type, flat(PANEL_HEADER, 3))
		t.set_stylebox("hover", type, flat(PANEL_HEADER.lightened(0.08), 3))
		t.set_stylebox("pressed", type, flat(accent.darkened(0.25), 3))
		t.set_stylebox("hover_pressed", type, flat(accent.darkened(0.15), 3))
		t.set_stylebox("disabled", type, flat(PANEL, 3))
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, Color.WHITE)
		t.set_color("font_disabled_color", type, TEXT_DIM.darkened(0.3))

	# The big club-coloured Continue button in the top bar.
	t.set_type_variation("AccentButton", "Button")
	t.set_stylebox("normal", "AccentButton", flat(accent, 3, 22, 10))
	t.set_stylebox("hover", "AccentButton", flat(accent.lightened(0.12), 3, 22, 10))
	t.set_stylebox("pressed", "AccentButton", flat(accent.darkened(0.15), 3, 22, 10))
	t.set_font_size("font_size", "AccentButton", 16)

	# Sidebar navigation: flat rows, the current screen marked with a club-coloured edge.
	t.set_type_variation("NavButton", "Button")
	var nav_on := flat(Color(accent, 0.18), 0, 16, 9)
	nav_on.border_width_left = 4
	nav_on.border_color = accent
	t.set_stylebox("normal", "NavButton", flat(Color.TRANSPARENT, 0, 20, 9))
	t.set_stylebox("hover", "NavButton", flat(Color(1, 1, 1, 0.05), 0, 20, 9))
	t.set_stylebox("pressed", "NavButton", nav_on)
	t.set_stylebox("hover_pressed", "NavButton", nav_on)
	t.set_stylebox("disabled", "NavButton", flat(Color.TRANSPARENT, 0, 20, 9))
	t.set_color("font_color", "NavButton", TEXT_DIM)

	# Sub-navigation tabs under the screen title.
	t.set_type_variation("SubNavButton", "Button")
	var sub_on := flat(Color.TRANSPARENT, 0, 14, 8)
	sub_on.border_width_bottom = 3
	sub_on.border_color = accent
	t.set_stylebox("normal", "SubNavButton", flat(Color.TRANSPARENT, 0, 14, 8))
	t.set_stylebox("hover", "SubNavButton", flat(Color(1, 1, 1, 0.05), 0, 14, 8))
	t.set_stylebox("pressed", "SubNavButton", sub_on)
	t.set_stylebox("hover_pressed", "SubNavButton", sub_on)
	t.set_color("font_color", "SubNavButton", TEXT_DIM)

	t.set_stylebox("panel", "PopupMenu", flat(PANEL_HEADER, 3, 4, 4))
	t.set_stylebox("hover", "PopupMenu", flat(accent.darkened(0.25), 2))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)

	var track := flat(LINE, 2, 0, 2)
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", flat(accent, 2, 0, 2))
	t.set_stylebox("grabber_area_highlight", "HSlider", flat(accent.lightened(0.1), 2, 0, 2))

	t.set_stylebox("scroll", "VScrollBar", flat(PANEL, 3, 3, 0))
	t.set_stylebox("grabber", "VScrollBar", flat(LINE, 3))
	t.set_stylebox("grabber_highlight", "VScrollBar", flat(LINE.lightened(0.15), 3))
	t.set_stylebox("grabber_pressed", "VScrollBar", flat(accent, 3))
	return t


static func label(text: String, size := 14, colour := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	return l


## A titled card like FM's panels. Add children to UIKit.content(card).
static func card(title: String) -> PanelContainer:
	var c := PanelContainer.new()
	c.add_theme_stylebox_override("panel", flat(PANEL, 4, 0, 0))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	c.add_child(v)
	var head := PanelContainer.new()
	var head_style := flat(PANEL_HEADER, 0, 12, 7)
	head_style.corner_radius_top_left = 4
	head_style.corner_radius_top_right = 4
	head.add_theme_stylebox_override("panel", head_style)
	head.add_child(label(title.to_upper(), 12, TEXT_DIM))
	v.add_child(head)
	var body := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		body.add_theme_constant_override("margin_" + side, 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	body.add_child(content)
	c.set_meta("content", content)
	return c


static func content(card_node: PanelContainer) -> VBoxContainer:
	return card_node.get_meta("content")


static func clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


## FM-style data table. columns: [{title, width (0 = stretch), align: "left"|"center"|"right"}].
## A cell is plain text or {text, colour, size}. on_click(row_index) makes rows clickable.
static func table(columns: Array, rows: Array, on_click := Callable(), selected := -1) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var header := []
	for c in columns:
		header.append({"text": str(c.title).to_upper(), "colour": TEXT_DIM, "size": 11})
	box.add_child(_row(columns, header, PANEL_HEADER.darkened(0.15)))
	for i in rows.size():
		var bg := ROW_ALT if i % 2 == 1 else PANEL
		if i == selected:
			bg = LINE.lightened(0.05)
		var row := _row(columns, rows[i], bg)
		if on_click.is_valid():
			row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			row.gui_input.connect(func(ev: InputEvent):
				if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
					on_click.call(i))
		box.add_child(row)
	return box


static func _row(columns: Array, cells: Array, bg: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", flat(bg, 0, 10, 5))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	panel.add_child(h)
	for i in columns.size():
		var col: Dictionary = columns[i]
		var cell = cells[i] if i < cells.size() else ""
		var data: Dictionary = cell if cell is Dictionary else {"text": str(cell)}
		var l := label(str(data.text), data.get("size", 14), data.get("colour", TEXT))
		l.clip_text = true
		l.horizontal_alignment = {"left": HORIZONTAL_ALIGNMENT_LEFT, "center": HORIZONTAL_ALIGNMENT_CENTER,
			"right": HORIZONTAL_ALIGNMENT_RIGHT}[col.get("align", "left")]
		var width: float = col.get("width", 0)
		if width > 0:
			l.custom_minimum_size.x = width
		else:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
	return panel


## FM-style horizontal meter. fraction is 0..1.
static func meter(title: String, fraction: float, colour: Color, value_text := "") -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var l := label(title, 12, TEXT_DIM)
	l.custom_minimum_size.x = 80
	h.add_child(l)
	var bar := ProgressBar.new()
	bar.max_value = 1.0
	bar.step = 0.001
	bar.value = clampf(fraction, 0.0, 1.0)
	bar.show_percentage = false
	bar.custom_minimum_size.y = 8
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_theme_stylebox_override("background", flat(LINE, 3, 0, 0))
	bar.add_theme_stylebox_override("fill", flat(colour, 3, 0, 0))
	h.add_child(bar)
	var v := label(value_text, 12, colour)
	v.custom_minimum_size.x = 70
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(v)
	return h


static func condition_colour(condition: float) -> Color:
	if condition >= 75.0:
		return POSITIVE
	return Color("e8b04b") if condition >= 50.0 else NEGATIVE


static func confidence_colour(confidence: float) -> Color:
	if confidence >= 65.0:
		return POSITIVE
	return Color("8ab4f8") if confidence >= 40.0 else NEGATIVE


static func confidence_text(confidence: float) -> String:
	if confidence >= 75.0:
		return "In the zone"
	if confidence >= 60.0:
		return "Confident"
	if confidence >= 40.0:
		return "Settled"
	return "Shaky" if confidence >= 25.0 else "Rattled"


## Intent runs from -1 (block) to 1 (all-out attack).
static func intent_colour(intent: float) -> Color:
	return Color("42a5f5").lerp(NEGATIVE, (intent + 1.0) / 2.0)


static func intent_text(intent: float) -> String:
	if intent < -0.5:
		return "Blocking"
	if intent < -0.15:
		return "Careful"
	if intent < 0.25:
		return "Balanced"
	return "Aggressive" if intent < 0.6 else "All out"


static func pressure_text(pressure: float) -> String:
	if pressure < 20.0:
		return "Low"
	if pressure < 45.0:
		return "Building"
	return "High" if pressure < 70.0 else "Intense"


## Form (0-100) shown as the rating a player is playing to, FM-style: {text, colour}.
static func form_rating(form: float) -> Dictionary:
	var r := 3.0 + form / 100.0 * 7.0
	var colour := POSITIVE if r >= 7.2 else (NEGATIVE if r < 6.0 else TEXT)
	return {"text": "%.1f" % r, "colour": colour}


static func ordinal(n: int) -> String:
	return Season.ordinal(n)


static func result_colour(letter: String) -> Color:
	return {"W": POSITIVE, "L": NEGATIVE, "T": WARNING}.get(letter, TEXT_DIM)


## Recent results as FM-style W/L/T chips, oldest first.
static func form_chips(results: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 3)
	for r in results:
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", flat(result_colour(r), 3, 6, 1))
		chip.add_child(label(r, 11, Color.BLACK))
		h.add_child(chip)
	return h


static func wrapped(text: String, size := 12, colour := TEXT_DIM) -> Label:
	var l := label(text, size, colour)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## FM-style sub-navigation tabs. Calls on_select(name) and returns the bar.
static func sub_nav(names: Array, on_select: Callable) -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	var group := ButtonGroup.new()
	for n in names:
		var b := Button.new()
		b.text = n
		b.theme_type_variation = "SubNavButton"
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = n == names[0]
		b.pressed.connect(on_select.bind(n))
		bar.add_child(b)
	return bar


## Building blocks for tables whose rows hold buttons or pickers (UIKit.table only holds text).
## grid_row returns the row's HBox; add cells to it, then add get_parent() (the row) to a list.
static func grid_row(index: int) -> HBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", flat(ROW_ALT if index % 2 == 1 else PANEL, 0, 10, 3))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	panel.add_child(h)
	return h


## A header row; columns are [title, width] pairs (width 0 stretches).
static func grid_header(columns: Array) -> Control:
	var h := grid_row(0)
	h.get_parent().add_theme_stylebox_override("panel", flat(PANEL_HEADER.darkened(0.15), 0, 10, 5))
	for c in columns:
		h.add_child(grid_cell(str(c[0]).to_upper(), c[1], TEXT_DIM, c[1] > 0 and c[1] < 50, 11))
	return h.get_parent()


static func grid_cell(text: String, width: float, colour := TEXT, centred := false, size := 14) -> Label:
	var l := label(text, size, colour)
	l.clip_text = true
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if centred:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if width > 0:
		l.custom_minimum_size.x = width
	else:
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func small_button(text: String, action: Callable, disabled := false, width := 64.0) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = disabled
	b.custom_minimum_size.x = width
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(action)
	return b


## A "Label ...... value" line, as used in FM's info panels.
static func stat_row(name: String, value: String, colour := TEXT) -> HBoxContainer:
	var h := HBoxContainer.new()
	var n := label(name, 13, TEXT_DIM)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(n)
	h.add_child(label(value, 13, colour))
	return h
