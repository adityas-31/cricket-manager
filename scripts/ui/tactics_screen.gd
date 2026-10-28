extends ScrollContainer
## Tactics, FM-style, all on one page: the XI in batting order with a role per batter, the
## reserves, a selection check, the bowling plan and the instructions every match starts with.
##
## Drag and drop does the selection: drag XI rows up and down to change the batting order,
## drag a reserve onto an XI player to swap them (or into the XI's empty space when it's
## short), and drag an XI player onto the reserves to drop them. Pick/Drop buttons do the same.
## Changes apply at once, even mid-match: reordering changes who comes in next.
##
## On a match day the club comes here first (Continue then reads "Start Match"). During a
## match the XI is locked (the match holds a state for each player) but the batting order,
## roles and bowling plan still apply at once; Continue reads "Back to Match".

var app: Node

var _page: VBoxContainer
var _next_match: Label
var _xi: VBoxContainer
var _reserves: VBoxContainer
var _check: VBoxContainer
var _plan: VBoxContainer
var _defaults: VBoxContainer


func title() -> String:
	return "Tactics"


func subtitle() -> String:
	if app.match_in_progress():
		return "%s  ·  Match in progress: the XI is locked; order, roles and plan apply now" % app.club.name
	if app.season.user_match_pending():
		return "%s  ·  Pick the XI and plan for today's match, then press Start Match" % app.club.name
	return "%s  ·  Selection, batting order, roles and bowling plan" % app.club.name


func continue_label() -> String:
	return "Back to Match" if app.match_in_progress() else app.default_continue_label()


func on_continue() -> void:
	if app.match_in_progress():
		app.show_screen("match")
	else:
		app.advance()


func on_shown() -> void:
	_build_next_match()
	_build_xi()
	_build_reserves()
	_build_check()
	_build_plan()
	_build_defaults()


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_page = VBoxContainer.new()
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page.add_theme_constant_override("separation", 12)
	add_child(_page)

	_next_match = UIKit.label("", 15)
	_next_match.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_page.add_child(_next_match)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	_page.add_child(h)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 12)
	h.add_child(left)
	var xi_card := UIKit.card("Playing XI  ·  Batting Order")
	xi_card.set_drag_forwarding(Callable(), _can_drop_on_xi.bind(-1), _drop_on_xi.bind(-1))
	left.add_child(xi_card)
	_xi = UIKit.content(xi_card)
	var check_card := UIKit.card("Selection Check")
	left.add_child(check_card)
	_check = UIKit.content(check_card)
	var defaults_card := UIKit.card("Match Instructions")
	left.add_child(defaults_card)
	_defaults = UIKit.content(defaults_card)

	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 680
	right.add_theme_constant_override("separation", 12)
	h.add_child(right)
	var reserves_card := UIKit.card("Reserves")
	reserves_card.set_drag_forwarding(Callable(), _can_drop_on_reserves, _drop_on_reserves)
	right.add_child(reserves_card)
	_reserves = UIKit.content(reserves_card)
	var plan_card := UIKit.card("Bowling Plan")
	right.add_child(plan_card)
	_plan = UIKit.content(plan_card)


# --- next match -------------------------------------------------------------------

func _build_next_match() -> void:
	var s: Season = app.season
	if app.match_in_progress():
		_next_match.visible = true
		_next_match.text = "Match in progress. The XI can't change until it's over; drag rows to change who bats next, and set roles and the bowling plan."
		_next_match.add_theme_color_override("font_color", UIKit.WARNING)
		return
	var f: Dictionary = s.user_fixture_today() if s.user_match_pending() else s.next_user_fixture()
	_next_match.visible = not f.is_empty()
	if f.is_empty():
		return
	var when := "Today" if f.day == s.day else s.date_text(f.day)
	_next_match.text = "%s:  %s v %s  ·  %s  ·  at %s, %s pitch" % [when, f.home.name, f.away.name, s.stage_text(f),
		f.home.name, str(f.home.home_pitch).capitalize()]
	_next_match.add_theme_color_override("font_color", UIKit.WARNING if f.day == s.day else UIKit.TEXT_DIM)


# --- XI and batting order -----------------------------------------------------------

func _build_xi() -> void:
	var team: CricketTeam = app.club
	var s: Season = app.season
	var locked: bool = app.match_in_progress()
	UIKit.clear(_xi)
	_xi.add_child(_header([["#", 22], ["", 16], ["Player", 0], ["Bat", 36], ["Bowl", 38], ["Cond", 46], ["Form", 40],
		["Status", 84], ["Role", 140], ["", 56]]))
	for i in team.players.size():
		var p: CricketPlayer = team.players[i]
		var h := _row(i)
		h.add_child(_cell(str(i + 1), 22, UIKit.TEXT_DIM))
		h.add_child(_cell("≡", 16, UIKit.TEXT_DIM, true))
		_player_cells(h, p, s)
		h.add_child(_role_picker(Tactics.BAT_ROLES, Tactics.bat_role(team, p), func(role): team.bat_roles[p] = role))
		var drop := _action_button("Drop", locked, _drop.bind(p))
		if locked:
			drop.tooltip_text = "The XI is locked during a match"
		h.add_child(drop)
		var row: Control = h.get_parent()
		row.tooltip_text = "Drag to change the batting order" + ("" if locked else ", or onto Reserves to drop")
		row.set_drag_forwarding(_drag_data.bind(row, p, "xi"), _can_drop_on_xi.bind(i), _drop_on_xi.bind(i))
		_xi.add_child(row)
	if team.players.size() < CricketTeam.XI_SIZE:
		_xi.add_child(_hint("%d of %d picked: drag a reserve here." % [team.players.size(), CricketTeam.XI_SIZE]))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	var suggest := Button.new()
	suggest.text = "Suggest Roles"
	suggest.tooltip_text = "Give every batter the role that suits their attributes and place in the order"
	suggest.pressed.connect(func():
		Tactics.suggest_batting(team)
		_build_xi())
	actions.add_child(suggest)
	var tip := _hint("Drag rows to reorder. Hover a role for what it does.")
	tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # a wrapping label in a row needs room, or it wraps every letter
	tip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	actions.add_child(tip)
	_xi.add_child(actions)


func _build_reserves() -> void:
	var team: CricketTeam = app.club
	var s: Season = app.season
	UIKit.clear(_reserves)
	_reserves.add_child(_header([["", 16], ["Player", 0], ["Bat", 36], ["Bowl", 38], ["Cond", 46], ["Form", 40],
		["Status", 84], ["", 56]]))
	var bench := team.reserves()
	bench.sort_custom(func(a, b): return maxf(a.batting_rating(), a.bowling_rating()) > maxf(b.batting_rating(), b.bowling_rating()))
	var full := team.players.size() >= CricketTeam.XI_SIZE
	var locked: bool = app.match_in_progress()
	for i in bench.size():
		var p: CricketPlayer = bench[i]
		var h := _row(i)
		h.add_child(_cell("" if locked else "≡", 16, UIKit.TEXT_DIM, true))
		_player_cells(h, p, s)
		var pick := _action_button("Pick", locked or full or s.is_injured(p), _pick.bind(p, -1))
		if locked:
			pick.tooltip_text = "The XI is locked during a match"
		elif full:
			pick.tooltip_text = "XI full: drag onto an XI player to swap"
		h.add_child(pick)
		var row: Control = h.get_parent()
		row.tooltip_text = "Injured" if s.is_injured(p) else ("The XI is locked during a match" if locked else "Drag onto an XI player to swap them")
		if not s.is_injured(p) and not locked:
			row.set_drag_forwarding(_drag_data.bind(row, p, "reserve"), _can_drop_on_reserves, _drop_on_reserves)
		_reserves.add_child(row)


func _build_check() -> void:
	var team: CricketTeam = app.club
	var s: Season = app.season
	UIKit.clear(_check)
	var problems := Selection.issues(team, s)
	if problems.is_empty():
		_check.add_child(UIKit.label("The XI is ready", 14, UIKit.POSITIVE))
	for line in problems:
		var serious: bool = not line.contains("tired")
		_check.add_child(UIKit.label(("✕  " if serious else "!  ") + line, 13, UIKit.NEGATIVE if serious else UIKit.WARNING))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	var auto := Button.new()
	auto.text = "Auto Select"
	auto.disabled = app.match_in_progress()
	auto.tooltip_text = "The XI is locked during a match" if auto.disabled else "Let the assistant pick the strongest fit XI now"
	auto.pressed.connect(func():
		Selection.auto_select(team, s)
		GameLog.event("selection", {"action": "auto_select", "xi": team.players.map(func(x): return x.name)})
		on_shown())
	actions.add_child(auto)
	var assistant := CheckBox.new()
	assistant.text = "Assistant picks the XI before every match"
	assistant.button_pressed = team.assistant_selects
	assistant.toggled.connect(func(on): team.assistant_selects = on)
	actions.add_child(assistant)
	_check.add_child(actions)
	_check.add_child(_hint("Injured players in your XI are replaced automatically at the start. Tired players bowl and field worse and get injured more often."))


func _player_cells(h: HBoxContainer, p: CricketPlayer, s: Season) -> void:
	var name_cell := _cell(p.name + ("  †" if p.is_keeper() else ""), 0)
	name_cell.tooltip_text = "%s  ·  %s" % [str(CricketPlayer.Role.keys()[p.role]).capitalize(), p.style_name()]
	name_cell.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(name_cell)
	h.add_child(_cell("%d" % roundi(p.batting_rating()), 36, UIKit.attr_colour(p.batting_rating()), true))
	h.add_child(_cell("%d" % roundi(p.bowling_rating()), 38, UIKit.attr_colour(p.bowling_rating()), true))
	var cond: float = s.condition[p]
	h.add_child(_cell("%d%%" % roundi(cond), 46, UIKit.condition_colour(cond), true))
	var form := UIKit.form_rating(s.form[p])
	h.add_child(_cell(form.text, 40, form.colour, true))
	var status := ""
	var colour := UIKit.TEXT_DIM
	if s.is_injured(p):
		status = "Injured %dd" % s.injury_days(p)
		colour = UIKit.NEGATIVE
	elif cond < Selection.TIRED:
		status = "Tired"
		colour = UIKit.WARNING
	h.add_child(_cell(status, 84, colour, false, 13))


# --- selection changes (buttons and drag and drop) -----------------------------------

func _drop(p: CricketPlayer) -> void:
	if app.match_in_progress():
		return
	app.club.players.erase(p)
	GameLog.event("selection", {"action": "drop", "player": p.name})
	on_shown()


## Adds a reserve to the XI at a batting position (-1: the bottom).
func _pick(p: CricketPlayer, at: int) -> void:
	var players: Array = app.club.players
	if players.size() >= CricketTeam.XI_SIZE or app.match_in_progress():
		return
	players.insert(players.size() if at < 0 else mini(at, players.size()), p)
	GameLog.event("selection", {"action": "pick", "player": p.name})
	on_shown()


## A reserve takes an XI player's place in the batting order.
func _swap(reserve: CricketPlayer, out: CricketPlayer) -> void:
	if app.match_in_progress():
		return
	var players: Array = app.club.players
	players[players.find(out)] = reserve
	GameLog.event("selection", {"action": "swap", "player": reserve.name, "for": out.name})
	on_shown()


## Moves an XI player to another batting position.
func _move_to(from: int, to: int) -> void:
	var players: Array = app.club.players
	if from == to or from < 0 or from >= players.size():
		return
	var p = players.pop_at(from)
	players.insert(clampi(to, 0, players.size()), p)
	GameLog.event("selection", {"action": "reorder", "player": p.name, "position": players.find(p) + 1})
	on_shown()


func _move(index: int, step: int) -> void:
	_move_to(index, index + step)


func _drag_data(_at: Vector2, row: Control, p: CricketPlayer, from: String) -> Variant:
	var preview := PanelContainer.new()
	preview.add_theme_stylebox_override("panel", UIKit.flat(app.club.colour.darkened(0.2), 4, 12, 6))
	preview.add_child(UIKit.label(p.name, 14, Color.WHITE))
	row.set_drag_preview(preview)
	return {"player": p, "from": from}


## index: the XI row dropped on, or -1 for the XI card's empty space.
func _can_drop_on_xi(_at: Vector2, data: Variant, index: int) -> bool:
	if typeof(data) != TYPE_DICTIONARY or not data.has("from"):
		return false
	if data.from == "xi":
		return true
	return not app.match_in_progress() and (index >= 0 or app.club.players.size() < CricketTeam.XI_SIZE)


func _drop_on_xi(_at: Vector2, data: Variant, index: int) -> void:
	var players: Array = app.club.players
	if data.from == "xi":
		_move_to(players.find(data.player), players.size() - 1 if index < 0 else index)
	elif index >= 0 and players.size() >= CricketTeam.XI_SIZE:
		_swap(data.player, players[index])
	else:
		_pick(data.player, index)


func _can_drop_on_reserves(_at: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.get("from", "") == "xi" and not app.match_in_progress()


func _drop_on_reserves(_at: Vector2, data: Variant) -> void:
	_drop(data.player)


# --- bowling plan and instructions ---------------------------------------------------

func _build_plan() -> void:
	UIKit.clear(_plan)
	var team: CricketTeam = app.club
	var bowlers := team.squad.filter(func(p): return not p.is_keeper() and (p in team.players or Selection.is_bowling_option(p)))
	bowlers.sort_custom(func(a, b): return a.bowling_rating() > b.bowling_rating())
	_plan.add_child(_header([["Bowler", 0], ["Type", 104], ["Bowl", 38], ["Acc", 34], ["Var", 34], ["Sta", 34], ["Role", 140]]))
	for i in bowlers.size():
		var p: CricketPlayer = bowlers[i]
		var h := _row(i)
		var in_xi: bool = p in team.players
		h.add_child(_cell(p.name + ("" if in_xi else "  (res)"), 0, UIKit.TEXT if in_xi else UIKit.TEXT_DIM))
		h.add_child(_cell(p.style_name(), 104, UIKit.TEXT_DIM))
		h.add_child(_cell("%d" % roundi(p.bowling_rating()), 38, UIKit.attr_colour(p.bowling_rating()), true))
		for attr in ["accuracy", "variation", "stamina"]:
			h.add_child(_cell("%d" % roundi(p.a(attr)), 34, UIKit.attr_colour(p.a(attr)), true))
		h.add_child(_role_picker(Tactics.BOWL_ROLES, Tactics.bowl_role(team, p), func(role): team.bowl_roles[p] = role))
		_plan.add_child(h.get_parent())
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	var suggest := Button.new()
	suggest.text = "Suggest Plan"
	suggest.pressed.connect(func():
		Tactics.suggest_bowling(team)
		_build_plan())
	var clear := Button.new()
	clear.text = "All Auto"
	clear.pressed.connect(func():
		team.bowl_roles.clear()
		_build_plan())
	actions.add_child(suggest)
	actions.add_child(clear)
	_plan.add_child(actions)
	_plan.add_child(_hint("Roles pull a bowler towards their phase; the captain still rests tired bowlers and keeps to the over limits. Hover a role for details."))


func _build_defaults() -> void:
	UIKit.clear(_defaults)
	var team: CricketTeam = app.club
	_defaults.add_child(UIKit.label("BATTING APPROACH", 11, UIKit.TEXT_DIM))
	var bat_row := HBoxContainer.new()
	bat_row.add_theme_constant_override("separation", 4)
	for i in MatchEngine.BAT_APPROACHES.size():
		bat_row.add_child(_toggle(MatchEngine.BAT_APPROACHES[i], team.default_bat_approach == i,
			func(): team.default_bat_approach = i))
	_defaults.add_child(bat_row)
	_defaults.add_child(UIKit.label("BOWLING APPROACH", 11, UIKit.TEXT_DIM))
	var bowl_row := HBoxContainer.new()
	bowl_row.add_theme_constant_override("separation", 4)
	bowl_row.add_child(_toggle("Auto", team.default_bowl_approach == MatchEngine.BOWL_AUTO,
		func(): team.default_bowl_approach = MatchEngine.BOWL_AUTO))
	for i in MatchEngine.BOWL_APPROACHES.size():
		bowl_row.add_child(_toggle(MatchEngine.BOWL_APPROACHES[i], team.default_bowl_approach == i,
			func(): team.default_bowl_approach = i))
	_defaults.add_child(bowl_row)
	_defaults.add_child(_hint("New matches start with these. Change them during a match from the Instructions card on Match Day."))


# --- widgets -----------------------------------------------------------------

## A table-style row; returns its HBox (the PanelContainer is its parent).
func _row(index: int) -> HBoxContainer:
	return UIKit.grid_row(index)


func _header(columns: Array) -> Control:
	return UIKit.grid_header(columns)


func _cell(text: String, width: float, colour := UIKit.TEXT, centred := false, size := 14) -> Label:
	return UIKit.grid_cell(text, width, colour, centred, size)


func _action_button(text: String, disabled: bool, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = disabled
	b.custom_minimum_size.x = 56
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(action)
	return b


func _role_picker(roles: Dictionary, current: String, apply: Callable) -> OptionButton:
	var o := OptionButton.new()
	o.custom_minimum_size.x = 140
	o.add_theme_font_size_override("font_size", 13)
	var keys := roles.keys()
	for i in keys.size():
		o.add_item(keys[i])
		o.set_item_tooltip(i, roles[keys[i]].desc)
	o.selected = keys.find(current)
	o.tooltip_text = roles[current].desc
	o.item_selected.connect(func(i):
		apply.call(keys[i])
		o.tooltip_text = roles[keys[i]].desc)
	return o


func _toggle(text: String, active: bool, apply: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_pressed = active
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(func():
		apply.call()
		_build_defaults())
	return b


func _hint(text: String) -> Label:
	var l := UIKit.label(text, 12, UIKit.TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l
