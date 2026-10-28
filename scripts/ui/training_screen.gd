extends ScrollContainer
## Training: the team's focus and intensity for the days between matches, each player's own
## focus, and the latest training report. See Training for what the settings do.

var app: Node

var _plan: VBoxContainer
var _report: VBoxContainer
var _players: VBoxContainer


func title() -> String:
	return "Training"


func subtitle() -> String:
	var s: Season = app.season
	return "%s  ·  %s focus, %s intensity" % [app.club.name, s.training.focus, str(s.training.intensity).to_lower()]


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var h := HBoxContainer.new()
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_theme_constant_override("separation", 14)
	add_child(h)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 520
	left.add_theme_constant_override("separation", 12)
	h.add_child(left)
	var plan_card := UIKit.card("Team Training")
	left.add_child(plan_card)
	_plan = UIKit.content(plan_card)
	var report_card := UIKit.card("Latest Report")
	left.add_child(report_card)
	_report = UIKit.content(report_card)
	var players_card := UIKit.card("Individual Focus")
	players_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(players_card)
	_players = UIKit.content(players_card)


func on_shown() -> void:
	_build_plan()
	_build_report()
	_build_players()


func _build_plan() -> void:
	var s: Season = app.season
	UIKit.clear(_plan)
	_plan.add_child(UIKit.label("FOCUS", 11, UIKit.TEXT_DIM))
	_plan.add_child(_choices(Training.FOCUSES.keys(), s.training.focus, func(f): _set_plan("focus", f)))
	_plan.add_child(UIKit.wrapped(Training.FOCUS_HELP[s.training.focus], 13))
	_plan.add_child(UIKit.label("INTENSITY", 11, UIKit.TEXT_DIM))
	_plan.add_child(_choices(Training.INTENSITIES.keys(), s.training.intensity, func(i): _set_plan("intensity", i)))
	_plan.add_child(UIKit.wrapped(Training.INTENSITY_HELP[s.training.intensity], 13))
	_plan.add_child(UIKit.wrapped("Training runs on the days between your matches. Younger players improve the most; tired players are likelier to get hurt in hard sessions."))


func _build_report() -> void:
	var s: Season = app.season
	UIKit.clear(_report)
	var text := Training.summary(s.last_training, s)
	_report.add_child(UIKit.wrapped(text if text != "" else "No training since the game was loaded. Reports also go to the Inbox.", 13,
		UIKit.TEXT if text != "" else UIKit.TEXT_DIM))


func _build_players() -> void:
	var s: Season = app.season
	var team: CricketTeam = app.club
	UIKit.clear(_players)
	_players.add_child(UIKit.grid_header([["Player", 0], ["Age", 40], ["Growth", 64], ["Cond", 50], ["Form", 44],
		["Last", 56], ["Focus", 130]]))
	var squad := team.squad.duplicate()
	squad.sort_custom(func(a, b): return a.age < b.age)
	var gains: Dictionary = s.last_training.get("gains", {})
	for i in squad.size():
		var p: CricketPlayer = squad[i]
		var h := UIKit.grid_row(i)
		var name_text: String = p.name + ("  (XI)" if p in team.players else "")
		h.add_child(UIKit.grid_cell(name_text, 0, UIKit.NEGATIVE if s.is_injured(p) else UIKit.TEXT))
		h.add_child(UIKit.grid_cell(str(p.age), 40, UIKit.TEXT_DIM, true))
		var factor := Training.age_factor(p.age)
		h.add_child(UIKit.grid_cell("High" if factor >= 0.8 else ("Some" if factor >= 0.4 else "Little"), 64,
			UIKit.POSITIVE if factor >= 0.8 else UIKit.TEXT_DIM, true, 13))
		var cond: float = s.condition[p]
		h.add_child(UIKit.grid_cell("%d%%" % roundi(cond), 50, UIKit.condition_colour(cond), true))
		var form := UIKit.form_rating(s.form[p])
		h.add_child(UIKit.grid_cell(form.text, 44, form.colour, true))
		h.add_child(UIKit.grid_cell("+%.2f" % gains[p] if gains.has(p) else "", 56, UIKit.TEXT_DIM, true, 13))
		var picker := OptionButton.new()
		picker.custom_minimum_size.x = 130
		picker.add_theme_font_size_override("font_size", 13)
		for f in Training.INDIVIDUAL:
			picker.add_item("Team (%s)" % s.training.focus if f == "Team" else f)
		picker.selected = Training.INDIVIDUAL.find(s.training_focus.get(p, "Team"))
		picker.item_selected.connect(func(idx):
			var f: String = Training.INDIVIDUAL[idx]
			if f == "Team":
				s.training_focus.erase(p)
			else:
				s.training_focus[p] = f
			GameLog.event("training_focus", {"player": p.name, "focus": f}))
		h.add_child(picker)
		_players.add_child(h.get_parent())
	_players.add_child(UIKit.wrapped("Growth: how much a player still gains from training at their age. Last: attribute points gained in the latest block."))


func _set_plan(key: String, value: String) -> void:
	app.season.training[key] = value
	GameLog.event("training_plan", app.season.training.duplicate())
	on_shown()
	app.refresh_header()


func _choices(options: Array, current: String, pick: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for o in options:
		var b := Button.new()
		b.text = o
		b.toggle_mode = true
		b.button_pressed = o == current
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(pick.bind(o))
		row.add_child(b)
	return row
