extends VBoxContainer
## Tactics, FM-style. Selection: pick the XI from the squad (or let the assistant do it),
## with injury and fitness warnings. Roles & Plan: the batting order with a role per batter,
## the bowling plan, and the instructions every match starts with. Changes apply at once,
## even mid-match: reordering changes who comes in next.

const VIEWS := ["Selection", "Roles & Plan"]

var app: Node

var _views := {}
var _xi: VBoxContainer
var _reserves: VBoxContainer
var _check: VBoxContainer
var _order: VBoxContainer
var _plan: VBoxContainer
var _defaults: VBoxContainer


func title() -> String:
	return "Tactics"


func subtitle() -> String:
	return "%s  ·  Selection, roles and bowling plan" % app.club.name


func on_shown() -> void:
	_build_selection()
	_build_order()
	_build_plan()
	_build_defaults()


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	add_child(UIKit.sub_nav(VIEWS, _show_view))
	var stack := Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(stack)
	_views[VIEWS[0]] = _build_selection_view()
	_views[VIEWS[1]] = _build_plan_view()
	for v in _views.values():
		v.set_anchors_preset(Control.PRESET_FULL_RECT)
		stack.add_child(v)
	_show_view(VIEWS[0])


func _show_view(view: String) -> void:
	for key in _views:
		_views[key].visible = key == view
	if is_inside_tree() and app:
		on_shown()


func _build_selection_view() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 12)
	h.add_child(left)
	var xi_card := UIKit.card("Playing XI")
	left.add_child(xi_card)
	_xi = UIKit.content(xi_card)
	var check_card := UIKit.card("Selection Check")
	check_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(check_card)
	_check = UIKit.content(check_card)
	var reserves_card := UIKit.card("Reserves")
	reserves_card.custom_minimum_size.x = 560
	h.add_child(reserves_card)
	_reserves = UIKit.content(reserves_card)
	return h


func _build_plan_view() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 12)
	h.add_child(left)
	var order_card := UIKit.card("Batting Order")
	left.add_child(order_card)
	_order = UIKit.content(order_card)
	left.add_child(_role_guide())

	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 590
	right.add_theme_constant_override("separation", 12)
	h.add_child(right)
	var plan_card := UIKit.card("Bowling Plan")
	right.add_child(plan_card)
	_plan = UIKit.content(plan_card)
	var defaults_card := UIKit.card("Match Instructions")
	defaults_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(defaults_card)
	_defaults = UIKit.content(defaults_card)
	return h


# --- selection -------------------------------------------------------------------

func _build_selection() -> void:
	var team: CricketTeam = app.club
	var s: Season = app.season

	UIKit.clear(_xi)
	_xi.add_child(_header([["#", 22], ["Player", 0], ["Bat", 36], ["Bowl", 38], ["Cond", 46], ["Form", 40], ["Status", 84], ["", 64]]))
	for i in team.players.size():
		var p: CricketPlayer = team.players[i]
		var h := _row(i)
		h.add_child(_cell(str(i + 1), 22, UIKit.TEXT_DIM))
		_player_cells(h, p, s)
		h.add_child(_action_button("Drop", false, func():
			team.players.erase(p)
			on_shown()))
		_xi.add_child(h.get_parent())

	UIKit.clear(_reserves)
	_reserves.add_child(_header([["Player", 0], ["Bat", 36], ["Bowl", 38], ["Cond", 46], ["Form", 40], ["Status", 84], ["", 64]]))
	var bench := team.reserves()
	bench.sort_custom(func(a, b): return maxf(a.batting_rating(), a.bowling_rating()) > maxf(b.batting_rating(), b.bowling_rating()))
	var full := team.players.size() >= CricketTeam.XI_SIZE
	for i in bench.size():
		var p: CricketPlayer = bench[i]
		var h := _row(i)
		_player_cells(h, p, s)
		var pick := _action_button("Pick", full or s.is_injured(p), func():
			team.players.append(p)
			on_shown())
		if full:
			pick.tooltip_text = "Drop someone from the XI first"
		h.add_child(pick)
		_reserves.add_child(h.get_parent())
	_reserves.add_child(_hint("New picks bat at the bottom of the order; rearrange them under Roles & Plan."))

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
	auto.tooltip_text = "Let the assistant pick the strongest fit XI now"
	auto.pressed.connect(func():
		Selection.auto_select(team, s)
		on_shown())
	actions.add_child(auto)
	var assistant := CheckBox.new()
	assistant.text = "Assistant picks the XI before every match"
	assistant.button_pressed = team.assistant_selects
	assistant.toggled.connect(func(on): team.assistant_selects = on)
	actions.add_child(assistant)
	_check.add_child(actions)
	_check.add_child(_hint("Injured players in your XI are replaced automatically at kick-off. Tired players bowl and field worse and get injured more often."))


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


func _action_button(text: String, disabled: bool, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = disabled
	b.custom_minimum_size.x = 64
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(action)
	return b


func _build_order() -> void:
	UIKit.clear(_order)
	var team: CricketTeam = app.club
	_order.add_child(_header([["#", 22], ["Player", 0], ["Tech", 40], ["Pow", 40], ["Agg", 40], ["Role", 150], ["", 76]]))
	for i in team.players.size():
		var p: CricketPlayer = team.players[i]
		var h := _row(i)
		h.add_child(_cell(str(i + 1), 22, UIKit.TEXT_DIM))
		h.add_child(_cell(p.name + ("  †" if p.is_keeper() else ""), 0))
		for attr in ["technique", "power", "aggression"]:
			h.add_child(_cell("%d" % roundi(p.a(attr)), 40, UIKit.attr_colour(p.a(attr)), true))
		h.add_child(_role_picker(Tactics.BAT_ROLES, Tactics.bat_role(team, p), func(role): team.bat_roles[p] = role))
		var up := _small_button("▲", i == 0, _move.bind(i, -1))
		var down := _small_button("▼", i == team.players.size() - 1, _move.bind(i, 1))
		h.add_child(up)
		h.add_child(down)
		_order.add_child(h.get_parent())
	var actions := HBoxContainer.new()
	var suggest := Button.new()
	suggest.text = "Suggest Roles"
	suggest.pressed.connect(func():
		Tactics.suggest_batting(team)
		_build_order())
	actions.add_child(suggest)
	_order.add_child(actions)


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


func _move(index: int, step: int) -> void:
	var players: Array = app.club.players
	var other := index + step
	var p = players[index]
	players[index] = players[other]
	players[other] = p
	_build_order()


# --- widgets -----------------------------------------------------------------

func _role_guide() -> Control:
	var c := UIKit.card("Batting Roles")
	var body := UIKit.content(c)
	for role in Tactics.BAT_ROLES:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		var name_label := UIKit.label(role, 13)
		name_label.custom_minimum_size.x = 110
		h.add_child(name_label)
		var desc := _hint(Tactics.BAT_ROLES[role].desc)
		desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(desc)
		body.add_child(h)
	return c


## A table-style row; returns its HBox (the PanelContainer is its parent).
func _row(index: int) -> HBoxContainer:
	return UIKit.grid_row(index)


func _header(columns: Array) -> Control:
	return UIKit.grid_header(columns)


func _cell(text: String, width: float, colour := UIKit.TEXT, centred := false, size := 14) -> Label:
	return UIKit.grid_cell(text, width, colour, centred, size)


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


func _small_button(text: String, disabled: bool, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = disabled
	b.custom_minimum_size = Vector2(34, 0)
	b.add_theme_font_size_override("font_size", 11)
	b.pressed.connect(action)
	return b


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
