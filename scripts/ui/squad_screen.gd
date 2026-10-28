extends HBoxContainer
## Squad: FM-style player list with colour-coded ratings, and a profile of the selected player.

var app: Node

var _list: VBoxContainer
var _profile: VBoxContainer
var _selected := 0


func title() -> String:
	return "Squad"


func subtitle() -> String:
	var s: Season = app.season
	var injured: int = app.club.squad.filter(func(p): return s.is_injured(p)).size()
	return "%s  ·  %d players  ·  %d injured" % [app.club.name, app.club.squad.size(), injured]


## The XI in batting order, then reserves.
func _players() -> Array:
	var team: CricketTeam = app.club
	return team.players + team.reserves()


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	var list_card := UIKit.card("Players")
	list_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(list_card)
	_list = UIKit.content(list_card)

	var profile_card := UIKit.card("Player Profile")
	profile_card.custom_minimum_size.x = 400
	add_child(profile_card)
	_profile = UIKit.content(profile_card)


func on_shown() -> void:
	_rebuild()


func _rebuild() -> void:
	UIKit.clear(_list)
	var columns := [
		{"title": "Name", "width": 0},
		{"title": "Status", "width": 96},
		{"title": "Bat", "width": 40, "align": "center"},
		{"title": "Bowl", "width": 40, "align": "center"},
		{"title": "Cond", "width": 50, "align": "right"},
		{"title": "Form", "width": 44, "align": "right"},
		{"title": "Apps", "width": 40, "align": "right"},
		{"title": "Runs", "width": 44, "align": "right"},
		{"title": "Wkts", "width": 40, "align": "right"},
		{"title": "Av Rat", "width": 54, "align": "right"},
	]
	var s: Season = app.season
	var rows := []
	for p: CricketPlayer in _players():
		var st: Dictionary = s.stats[p]
		var avg := s.average_rating(p)
		var status := {"text": "Playing XI", "colour": UIKit.POSITIVE} if p in app.club.players else {"text": "Reserve", "colour": UIKit.TEXT_DIM}
		if s.is_injured(p):
			status = {"text": "Injured %dd" % s.injury_days(p), "colour": UIKit.NEGATIVE}
		rows.append([
			p.name + ("  †" if p.is_keeper() else ""),
			status,
			_rating(p.batting_rating()),
			_rating(p.bowling_rating()),
			{"text": "%d%%" % roundi(s.condition[p]), "colour": UIKit.condition_colour(s.condition[p])},
			UIKit.form_rating(s.form[p]),
			"%d" % st.apps,
			"%d" % st.runs,
			"%d" % st.wickets,
			{"text": "%.2f" % avg if st.apps > 0 else "-", "colour": UIKit.POSITIVE if avg >= 7.5 else UIKit.TEXT},
		])
	_list.add_child(UIKit.table(columns, rows, _select, _selected))
	_show_profile(_players()[_selected])


func _select(index: int) -> void:
	_selected = index
	_rebuild()


func _show_profile(p: CricketPlayer) -> void:
	UIKit.clear(_profile)
	_profile.add_child(UIKit.label(p.name, 22))
	var s0: Season = app.season
	_profile.add_child(UIKit.label("%s  ·  %s  ·  age %d  ·  %s, %s a year until %d" % [_role_name(p), p.style_name(), p.age,
		Transfers.money(Transfers.value(p, s0)), Transfers.money(s0.contracts[p].wage), s0.contracts[p].until], 13, UIKit.TEXT_DIM))

	var groups := GridContainer.new()
	groups.columns = 2
	groups.add_theme_constant_override("h_separation", 26)
	groups.add_theme_constant_override("v_separation", 16)
	_profile.add_child(groups)
	for group in CricketPlayer.ATTRIBUTES:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 3)
		box.custom_minimum_size.x = 180
		box.add_child(UIKit.label(group.to_upper(), 11, UIKit.TEXT_DIM))
		for attr in CricketPlayer.ATTRIBUTES[group]:
			var v := p.a(attr)
			box.add_child(UIKit.stat_row(attr.capitalize(), "%d" % roundi(v), UIKit.attr_colour(v)))
		groups.add_child(box)

	var s: Season = app.season
	var st: Dictionary = s.stats[p]
	var season := VBoxContainer.new()
	season.add_theme_constant_override("separation", 3)
	season.add_child(UIKit.label("SEASON", 11, UIKit.TEXT_DIM))
	season.add_child(UIKit.stat_row("Appearances", "%d" % st.apps))
	season.add_child(UIKit.stat_row("Average rating", "%.2f" % s.average_rating(p) if st.apps > 0 else "-"))
	season.add_child(UIKit.stat_row("Runs (avg, SR)", "%d (%.1f, %.0f)" % [st.runs, s.batting_average(p), st.runs * 100.0 / maxf(st.balls, 1.0)]))
	season.add_child(UIKit.stat_row("High score", "%d%s" % [st.hs, "*" if st.hs_not_out else ""]))
	season.add_child(UIKit.stat_row("Wickets (econ)", "%d (%.2f)" % [st.wickets, st.bowl_runs * 6.0 / maxf(st.bowl_balls, 1.0)]))
	season.add_child(UIKit.stat_row("Catches", "%d" % st.catches))
	season.add_child(UIKit.meter("Condition", s.condition[p] / 100.0, UIKit.condition_colour(s.condition[p]), "%d%%" % roundi(s.condition[p])))
	var form_cell := UIKit.form_rating(s.form[p])
	season.add_child(UIKit.meter("Form", s.form[p] / 100.0, form_cell.colour, form_cell.text))
	if s.is_injured(p):
		season.add_child(UIKit.label("Injured: fit again in %d days" % s.injury_days(p), 13, UIKit.NEGATIVE))
	_profile.add_child(season)


func _role_name(p: CricketPlayer) -> String:
	return str(CricketPlayer.Role.keys()[p.role]).capitalize()


func _rating(v: float) -> Dictionary:
	return {"text": "%d" % roundi(v), "colour": UIKit.attr_colour(v)}
