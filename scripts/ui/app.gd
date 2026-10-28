extends Control
## The game shell, laid out like FM24: a club-coloured top bar with the screen title and the
## Continue button, a navigation sidebar on the left, and the active screen in the middle.
##
## Screens are Controls that may implement title(), subtitle(), continue_label(),
## on_continue() and on_shown() (called every time the screen is opened).
##
## Continue works like FM's: it takes you to Match Day when the club plays today, otherwise
## it plays the day's other fixtures and moves the calendar to the next match day.
##
## Command-line extras (after `--`): --squad, --tactics, --fixtures, --competition or --match
## opens that screen; --demo opens Match Day and auto-plays quickly; --save=<path> uses
## another career file (e.g. user://test.json) instead of user://career.json.

const NAV := [
	{"id": "home", "label": "Home", "script": "res://scripts/ui/home_screen.gd"},
	{"id": "inbox", "label": "Inbox", "script": "res://scripts/ui/inbox_screen.gd"},
	{"id": "squad", "label": "Squad", "script": "res://scripts/ui/squad_screen.gd"},
	{"id": "tactics", "label": "Tactics", "script": "res://scripts/ui/tactics_screen.gd"},
	{"id": "match", "label": "Match Day", "script": "res://scripts/ui/match_screen.gd"},
	{"id": "fixtures", "label": "Fixtures", "script": "res://scripts/ui/fixtures_screen.gd"},
	{"id": "competition", "label": "Competition", "script": "res://scripts/ui/competition_screen.gd"},
	{"id": "scouting", "label": "Scouting"},
	{"id": "transfers", "label": "Transfers", "script": "res://scripts/ui/transfers_screen.gd"},
	{"id": "finances", "label": "Finances", "script": "res://scripts/ui/finances_screen.gd"},
]

var season: Season
var teams: Array = []
var club: CricketTeam

var _screens := {}
var _current: Control
var _nav_buttons := {}
var _title: Label
var _subtitle: Label
var _date: Label
var _continue: Button
var _content: MarginContainer


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save="):
			Season.save_path = arg.trim_prefix("--save=")
	season = Season.load_or_new()
	teams = season.teams
	club = season.club
	theme = UIKit.make_theme(club.colour)
	_build()
	var start := "home"
	var args := OS.get_cmdline_user_args()
	for id in ["squad", "tactics", "fixtures", "competition", "match", "transfers", "finances"]:
		if "--" + id in args:
			start = id
	if "--demo" in args:
		start = "match"
	show_screen(start)


func show_screen(id: String) -> void:
	if not _screens.has(id):
		var entry: Dictionary = NAV.filter(func(n): return n.id == id)[0]
		var screen: Control = load(entry.script).new()
		screen.set("app", self)
		screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_screens[id] = screen
		_content.add_child(screen)
	for key in _screens:
		_screens[key].visible = key == id
	_current = _screens[id]
	_nav_buttons[id].button_pressed = true
	if _current.has_method("on_shown"):
		_current.call("on_shown")
	refresh_header()


func refresh_header() -> void:
	if _current == null:
		return
	_title.text = _current.call("title") if _current.has_method("title") else ""
	_subtitle.text = _current.call("subtitle") if _current.has_method("subtitle") else ""
	_date.text = season.date_text()
	_continue.text = _current.call("continue_label") if _current.has_method("continue_label") else default_continue_label()


func default_continue_label() -> String:
	if season.user_match_pending():
		return "Match Day"
	return "Next Season" if season.is_over() else "Continue"


func _on_continue() -> void:
	if _current and _current.has_method("on_continue"):
		_current.call("on_continue")
	else:
		advance()


## Moves the game on: to Match Day if the club plays today, otherwise to the next day with
## fixtures (playing everyone else's matches on the way), or into the next season once the
## final has been played.
func advance() -> void:
	if season.user_match_pending():
		show_screen("match")
		return
	if season.is_over():
		season.start_next_season()
		show_screen("home")
		return
	season.advance()
	show_screen("match" if season.user_match_pending() else "home")


## Starts a new career with the given club, replacing the saved one.
func new_career(club_index: int) -> void:
	Season.new_career(club_index).save()
	get_tree().reload_current_scene()


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UIKit.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)
	root.add_child(_build_top_bar())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	root.add_child(body)
	body.add_child(_build_sidebar())

	_content = MarginContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		_content.add_theme_constant_override("margin_" + side, 14)
	body.add_child(_content)


func _build_top_bar() -> Control:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UIKit.flat(club.colour.darkened(0.45), 0, 16, 10))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	bar.add_child(h)

	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(46, 46)
	var badge_style := UIKit.flat(club.colour, 23, 0, 0)
	badge_style.border_color = Color.WHITE
	badge_style.set_border_width_all(2)
	badge.add_theme_stylebox_override("panel", badge_style)
	var badge_text := UIKit.label(club.short_name, 13, Color.WHITE)
	badge_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(badge_text)
	h.add_child(badge)

	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title = UIKit.label("", 22, Color.WHITE)
	_subtitle = UIKit.label("", 13, Color(1, 1, 1, 0.65))
	titles.add_child(_title)
	titles.add_child(_subtitle)
	h.add_child(titles)

	_date = UIKit.label("", 14, Color(1, 1, 1, 0.8))
	_date.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_date)

	_continue = Button.new()
	_continue.theme_type_variation = "AccentButton"
	_continue.custom_minimum_size = Vector2(170, 0)
	_continue.add_theme_stylebox_override("normal", _continue_style(club.colour.lightened(0.1)))
	_continue.add_theme_stylebox_override("hover", _continue_style(club.colour.lightened(0.25)))
	_continue.pressed.connect(_on_continue)
	h.add_child(_continue)
	return bar


func _continue_style(colour: Color) -> StyleBoxFlat:
	var s := UIKit.flat(colour, 3, 22, 10)
	s.border_color = Color(1, 1, 1, 0.35)
	s.set_border_width_all(1)
	return s


func _build_sidebar() -> Control:
	var side := PanelContainer.new()
	side.custom_minimum_size.x = 210
	side.add_theme_stylebox_override("panel", UIKit.flat(UIKit.SIDEBAR, 0, 0, 12))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	side.add_child(v)

	var club_name := UIKit.label(club.name.to_upper(), 12, UIKit.TEXT_DIM)
	club_name.custom_minimum_size.y = 34
	club_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(club_name)

	var group := ButtonGroup.new()
	for entry in NAV:
		var b := Button.new()
		b.text = entry.label
		b.theme_type_variation = "NavButton"
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.button_group = group
		b.add_theme_font_size_override("font_size", 15)
		if entry.has("script"):
			b.pressed.connect(show_screen.bind(entry.id))
		else:
			b.disabled = true
			b.tooltip_text = "Coming soon"
		_nav_buttons[entry.id] = b
		v.add_child(b)
	return side
