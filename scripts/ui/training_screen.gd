extends ScrollContainer
## Training: a calendar of the days before the club's next match (two sessions a day, set by
## hand or from a template), each player's own focus, and the latest training report. The
## block runs when the calendar moves on past those days. See Training for what sessions do.

var app: Node

var _calendar: VBoxContainer
var _report: VBoxContainer
var _players: VBoxContainer
var _guide: VBoxContainer


func title() -> String:
	return "Training"


func subtitle() -> String:
	var days := Training.block(app.season)
	var when := "no training days before the next match" if days.is_empty() else "%d training days before the next match" % (days[1] - days[0] + 1)
	return "%s  ·  %s template  ·  %s" % [app.club.name, app.season.training_template, when]


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var h := HBoxContainer.new()
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_theme_constant_override("separation", 14)
	add_child(h)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 12)
	h.add_child(left)
	var calendar_card := UIKit.card("Training Calendar")
	left.add_child(calendar_card)
	_calendar = UIKit.content(calendar_card)
	var report_card := UIKit.card("Latest Report")
	left.add_child(report_card)
	_report = UIKit.content(report_card)
	var guide_card := UIKit.card("Sessions")
	left.add_child(guide_card)
	_guide = UIKit.content(guide_card)
	var players_card := UIKit.card("Individual Focus")
	players_card.custom_minimum_size.x = 700
	h.add_child(players_card)
	_players = UIKit.content(players_card)


func on_shown() -> void:
	_build_calendar()
	_build_report()
	_build_guide()
	_build_players()


func _build_calendar() -> void:
	var s: Season = app.season
	UIKit.clear(_calendar)
	_calendar.add_child(UIKit.label("TEMPLATE", 11, UIKit.TEXT_DIM))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for t in Training.TEMPLATES:
		var b := Button.new()
		b.text = t
		b.toggle_mode = true
		b.button_pressed = t == s.training_template
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 13)
		b.tooltip_text = Training.TEMPLATE_HELP[t]
		b.pressed.connect(_set_template.bind(t))
		row.add_child(b)
	_calendar.add_child(row)
	_calendar.add_child(UIKit.wrapped("%s The morning after a match is Recovery and the afternoon before one is Match prep unless you change them." %
		Training.TEMPLATE_HELP[s.training_template]))

	var days := Training.block(s)
	if days.is_empty():
		_calendar.add_child(UIKit.label("No training days before the next match.", 14, UIKit.TEXT_DIM))
		return
	_calendar.add_child(UIKit.grid_header([["Day", 150], ["", 0], ["Morning", 170], ["Afternoon", 170], ["", 64]]))
	for d in range(days[0], days[1] + 1):
		var h := UIKit.grid_row(d - days[0])
		h.add_child(UIKit.grid_cell(s.date_text(d), 150))
		h.add_child(UIKit.grid_cell(_day_note(d), 0, UIKit.TEXT_DIM, false, 13))
		var sessions := Training.sessions_for(s, d)
		for slot in 2:
			h.add_child(_session_picker(d, slot, sessions))
		var custom: bool = s.training_plan.has(d)
		h.add_child(UIKit.small_button("Reset", _reset_day.bind(d), not custom, 64))
		_calendar.add_child(h.get_parent())
	var next_day: int = days[1] + 1
	var next: Array = s.fixtures.filter(func(f): return f.day == next_day and s.involves(f, s.club))
	if not next.is_empty():
		_calendar.add_child(UIKit.label("%s: %s v %s" % [s.date_text(next_day), next[0].home.name, next[0].away.name], 13, UIKit.WARNING))
	_calendar.add_child(UIKit.wrapped("Training runs as the calendar moves on to the match."))


func _day_note(d: int) -> String:
	var s: Season = app.season
	var notes := []
	for f in s.fixtures:
		if s.involves(f, s.club) and f.day == d - 1:
			notes.append("Day after match")
		if s.involves(f, s.club) and f.day == d + 1:
			notes.append("Day before match")
	return ", ".join(notes)


func _session_picker(d: int, slot: int, sessions: Array) -> OptionButton:
	var o := OptionButton.new()
	o.custom_minimum_size.x = 170
	o.add_theme_font_size_override("font_size", 13)
	var names := Training.SESSIONS.keys()
	for i in names.size():
		o.add_item(names[i])
		o.set_item_tooltip(i, Training.SESSIONS[names[i]].desc)
	o.selected = names.find(sessions[slot])
	o.tooltip_text = Training.SESSIONS[sessions[slot]].desc
	o.item_selected.connect(func(i):
		var plan: Array = sessions.duplicate()
		plan[slot] = names[i]
		app.season.training_plan[d] = plan
		GameLog.event("training_day", {"day": app.season.date_text(d), "sessions": plan})
		_build_calendar())
	return o


func _reset_day(d: int) -> void:
	app.season.training_plan.erase(d)
	_build_calendar()


func _set_template(t: String) -> void:
	app.season.training_template = t
	GameLog.event("training_plan", {"template": t})
	_build_calendar()
	app.refresh_header()


func _build_report() -> void:
	var s: Season = app.season
	UIKit.clear(_report)
	var text := Training.summary(s.last_training, s)
	if text == "":
		_report.add_child(UIKit.wrapped("No training since the game was loaded. Reports also go to the Inbox.", 13))
		return
	_report.add_child(UIKit.wrapped(text, 13, UIKit.TEXT))
	for day in s.last_training.days:
		_report.add_child(UIKit.stat_row(s.date_text(day.day), " / ".join(day.sessions)))


func _build_guide() -> void:
	UIKit.clear(_guide)
	_guide.add_child(UIKit.grid_header([["Session", 130], ["Load", 50], ["Works on", 0]]))
	var i := 0
	for name in Training.SESSIONS:
		var info: Dictionary = Training.SESSIONS[name]
		var h := UIKit.grid_row(i)
		h.add_child(UIKit.grid_cell(name, 130))
		var load: float = info.load
		h.add_child(UIKit.grid_cell("%+.1f" % -load if load != 0.0 else "0", 50,
			UIKit.POSITIVE if load < 0.0 else (UIKit.WARNING if load >= 2.5 else UIKit.TEXT_DIM), true, 13))
		var desc := UIKit.grid_cell(info.desc, 0, UIKit.TEXT_DIM, false, 13)
		desc.clip_text = false
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		h.add_child(desc)
		_guide.add_child(h.get_parent())
		i += 1
	_guide.add_child(UIKit.wrapped("Load: condition per session (positive helps recovery). Players also recover %d%% a day, like every club's." % roundi(Season.RECOVERY_PER_DAY)))


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
			picker.add_item("As scheduled" if f == "Team" else f)
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
	_players.add_child(UIKit.wrapped("Growth: how much a player still gains from training at their age. Last: attribute points gained in the latest block. Focus: a player's own focus replaces the skill sessions' work (Recovery, Rest and Match prep stay the same)."))
